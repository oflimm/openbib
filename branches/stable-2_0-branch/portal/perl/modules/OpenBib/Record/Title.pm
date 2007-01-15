#####################################################################
#
#  OpenBib::Record::Title.pm
#
#  Titel
#
#  Dieses File ist (C) 2007 Oliver Flimm <flimm@openbib.org>
#
#  Dieses Programm ist freie Software. Sie koennen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es wuenschen) jeder spaeteren Version.
#
#  Die Veroeffentlichung dieses Programms erfolgt in der
#  Hoffnung, dass es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEWAEHRLEISTUNG - sogar ohne die implizite Gewaehrleistung
#  der MARKTREIFE oder der EIGNUNG FUER EINEN BESTIMMTEN ZWECK.
#  Details finden Sie in der GNU General Public License.
#
#  Sie sollten eine Kopie der GNU General Public License zusammen
#  mit diesem Programm erhalten haben. Falls nicht, schreiben Sie
#  an die Free Software Foundation, Inc., 675 Mass Ave, Cambridge,
#  MA 02139, USA.
#
#####################################################################

package OpenBib::Record::Title;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Reload;
use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;
use Storable;
use YAML ();

use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Search::Util;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}       : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $self = { };

    bless ($self, $class);

    $self->{config}         = $config;
    $self->{targetdbinfo}   = $self->{config}->get_targetdbinfo();
    $self->{targetcircinfo} = $self->{config}->get_targetcircinfo();

    if (defined $database){
        $self->{database} = $database;

        $self->{dbh}
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
    }

    $logger->debug("Title-Record-Object created: ".YAML::Dump($self));
    return $self;
}

sub get_full_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @normset=();

    my $normset_ref={};

    $normset_ref->{id      } = $id;
    $normset_ref->{database} = $self->{database};

    # Titelkategorien
    {

        my ($atime,$btime,$timeall)=(0,0,0);

        if ($self->{config}->{benchmark}) {
            $atime=new Benchmark;
        }

        my $reqstring="select * from tit where id = ?";
        my $request=$self->{dbh}->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($self->{id}) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $category  = "T".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $content   =        decode_utf8($res->{content  });

            push @{$normset_ref->{$category}}, {
                indicator => $indicator,
                content   => $content,
            };
        }
        $request->finish();

        if ($self->{config}->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }

    # Verknuepfte Normdaten
    {
        my ($atime,$btime,$timeall)=(0,0,0);

        if ($self->{config}->{benchmark}) {
            $atime=new Benchmark;
        }

        my $reqstring="select category,targetid,targettype,supplement from conn where sourceid=? and sourcetype=1 and targettype IN (2,3,4,5)";
        my $request=$self->{dbh}->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($self->{id}) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $category   = "T".sprintf "%04d",$res->{category };
            my $targetid   =        decode_utf8($res->{targetid  });
            my $targettype =                    $res->{targettype};
            my $supplement =        decode_utf8($res->{supplement});

	    # Korrektes UTF-8 Encoding Flag wird in get_*_ans_*
	    # vorgenommen

            my $content    =
                ($targettype == 2 )?OpenBib::Record::Person->new({database=>$self->{database}})->get_name({id=>$targetid})->name_as_string():
                ($targettype == 3 )?OpenBib::Record::CorporateBody->new({database=>$self->{database}})->get_name({id=>$targetid})->name_as_string():
                ($targettype == 4 )?OpenBib::Record::Subject->new({database=>$self->{database}})->get_name({id=>$targetid})->name_as_string():
                ($targettype == 5 )?OpenBib::Record::Classification->new({database=>$self->{database}})->get_name({id=>$targetid})->name_as_string():'Error';

            push @{$normset_ref->{$category}}, {
                id         => $targetid,
                content    => $content,
                supplement => $supplement,
            };
        }
        $request->finish();

        if ($self->{config}->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }

    # Verknuepfte Titel
    {
        my ($atime,$btime,$timeall)=(0,0,0);

        my $reqstring;
        my $request;
        my $res;
        
        # Unterordnungen
        if ($self->{config}->{benchmark}) {
            $atime=new Benchmark;
        }

        $reqstring="select count(distinct targetid) as conncount from conn where sourceid=? and sourcetype=1 and targettype=1";
        $request=$self->{dbh}->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($self->{id}) or $logger->error("Request: $reqstring - ".$DBI::errstr);

        $res=$request->fetchrow_hashref;

        if ($res->{conncount} > 0){
            push @{$normset_ref->{T5001}}, {
                content => $res->{conncount},
            };
        }
        
        if ($self->{config}->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }

        # Ueberordnungen
        if ($self->{config}->{benchmark}) {
            $atime=new Benchmark;
        }

        $reqstring="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=1";
        $request=$self->{dbh}->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($self->{id}) or $logger->error("Request: $reqstring - ".$DBI::errstr);

        $res=$request->fetchrow_hashref;

        if ($res->{conncount} > 0){
            push @{$normset_ref->{T5002}}, {
                content => $res->{conncount},
            };
        }
        
        if ($self->{config}->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }


        $request->finish();
    }

    # Exemplardaten
    my @mexnormset=();
    {

        my $reqstring="select distinct targetid from conn where sourceid= ? and sourcetype=1 and targettype=6";
        my $request=$self->{dbh}->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($self->{id}) or $logger->error("Request: $reqstring - ".$DBI::errstr);

        my @verknmex=();
        while (my $res=$request->fetchrow_hashref){
            push @verknmex, decode_utf8($res->{targetid});
        }
        $request->finish();

        if ($#verknmex >= 0) {
            foreach my $mexsatz (@verknmex) {
                push @mexnormset, _get_mex_set_by_idn({
                    mexidn             => $mexsatz,
                });
            }
        }

    }

    # Ausleihinformationen der Exemplare
    my @circexemplarliste = ();
    {
        my $circexlist=undef;

        if (exists $self->{targetcircinfo}->{$self->{database}}{circ}) {

            my $circid=(exists $normset_ref->{'T0001'}[0]{content} && $normset_ref->{'T0001'}[0]{content} > 0 && $normset_ref->{'T0001'}[0]{content} != $self->{id} )?$normset_ref->{'T0001'}[0]{content}:$self->{id};

            $logger->debug("Katkey: $self->{id} - Circ-ID: $circid");

            my $soap = SOAP::Lite
                -> uri("urn:/MediaStatus")
                    -> proxy($self->{targetcircinfo}->{$self->{database}}{circcheckurl});
            my $result = $soap->get_mediastatus(
                $circid,$self->{targetcircinfo}->{$self->{database}}{circdb});
            
            unless ($result->fault) {
                $circexlist=$result->result;
            }
            else {
                $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
            }
        }
        
        # Bei einer Ausleihbibliothek haben - falls Exemplarinformationen
        # in den Ausleihdaten vorhanden sind -- diese Vorrange ueber die
        # titelbasierten Exemplardaten
        
        if (defined($circexlist)) {
            @circexemplarliste = @{$circexlist};
        }
        
        if (exists $self->{targetcircinfo}->{$self->{database}}{circ}
                && $#circexemplarliste >= 0) {
            for (my $i=0; $i <= $#circexemplarliste; $i++) {
                
                my $bibliothek="-";
                my $sigel=$self->{targetdbinfo}->{dbases}{$self->{database}};
                
                if (length($sigel)>0) {
                    if (exists $self->{targetdbinfo}->{sigel}{$sigel}) {
                        $bibliothek=$self->{targetdbinfo}->{sigel}{$sigel};
                    }
                    else {
                        $bibliothek="($sigel)";
                    }
                }
                else {
                    if (exists $self->{targetdbinfo}->{sigel}{$self->{targetdbinfo}->{dbases}{$self->{database}}}) {
                        $bibliothek=$self->{targetdbinfo}->{sigel}{
                            $self->{targetdbinfo}->{dbases}{$self->{database}}};
                    }
                }
                
                my $bibinfourl=$self->{targetdbinfo}->{bibinfo}{
                    $self->{targetdbinfo}->{dbases}{$self->{database}}};
                
                # Zusammensetzung von Signatur und Exemplar
                $circexemplarliste[$i]{'Signatur'}   = $circexemplarliste[$i]{'Signatur'}.$circexemplarliste[$i]{'Exemplar'};
                $circexemplarliste[$i]{'Bibliothek'} = $bibliothek;
                $circexemplarliste[$i]{'Bibinfourl'} = $bibinfourl;
                $circexemplarliste[$i]{'Ausleihurl'} = $self->{targetcircinfo}->{$self->{database}}{circurl};
            }
        }
        else {
            @circexemplarliste=();
        }
    }

    # Anreicherung mit zentralen Enrichmentdaten
    {
        my ($atime,$btime,$timeall);
        
        if ($self->{config}->{benchmark}) {
            $atime=new Benchmark;
        }
        
        # Verbindung zur SQL-Datenbank herstellen
        my $enrichdbh
            = DBI->connect("DBI:$self->{config}->{dbimodule}:dbname=$self->{config}->{enrichmntdbname};host=$self->{config}->{enrichmntdbhost};port=$self->{config}->{enrichmntdbport}", $self->{config}->{enrichmntdbuser}, $self->{config}->{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);
        
        foreach my $isbn_ref (@{$normset_ref->{T0540}}){

            my $isbn=$isbn_ref->{content};
            
            $isbn =~s/ //g;
            $isbn =~s/-//g;
            $isbn=~s/([A-Z])/\l$1/g;
                        
            my $reqstring="select category,content from normdata where isbn=? order by category,indicator";
            my $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
            
            while (my $res=$request->fetchrow_hashref) {
                my $category   = "T".sprintf "%04d",$res->{category };
                my $content    =        decode_utf8($res->{content});
                
                push @{$normset_ref->{$category}}, {
                    content    => $content,
                };
            }
            $request->finish();
            $logger->debug("Enrich: $isbn -> $reqstring");
        }
        
        $enrichdbh->disconnect();

        if ($self->{config}->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von Enrich-Normdateninformationen ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }


    }

    ($self->{normset},$self->{mexset},$self->{circset})=($normset_ref,\@mexnormset,\@circexemplarliste);
}

sub _get_mex_set_by_idn {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $mexidn             = exists $arg_ref->{mexidn}
        ? $arg_ref->{mexidn}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $normset_ref={};
    
    # Defaultwerte setzen
    $normset_ref->{X0005}{content}="-";
    $normset_ref->{X0014}{content}="-";
    $normset_ref->{X0016}{content}="-";
    $normset_ref->{X1204}{content}="-";
    $normset_ref->{X4000}{content}="-";
    $normset_ref->{X4001}{content}="";

    my ($atime,$btime,$timeall);
    if ($self->{config}->{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest="select category,content,indicator from mex where id = ?";
    my $result=$self->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $result->execute($mexidn);

    while (my $res=$result->fetchrow_hashref){
        my $category  = "X".sprintf "%04d",$res->{category };
        my $indicator =        decode_utf8($res->{indicator});
        my $content   =        decode_utf8($res->{content  });
        
        # Exemplar-Normdaten werden als nicht multipel angenommen
        # und dementsprechend vereinfacht in einer Datenstruktur
        # abgelegt
        $normset_ref->{$category} = {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($self->{config}->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $sqlrequest : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    my $sigel      = "";
    # Bestimmung des Bibliotheksnamens
    # Ein im Exemplar-Datensatz gefundenes Sigel geht vor
    if (exists $normset_ref->{X3300}{content}) {
        $sigel=$normset_ref->{X3300}{content};
        if (exists $self->{targetdbinfo}->{sigel}{$sigel}) {
            $normset_ref->{X4000}{content}=$self->{targetdbinfo}->{sigel}{$sigel};
        }
        else {
            $normset_ref->{X4000}{content}= {
					     full  => "($sigel)",
					     short => "($sigel)",
					    };
        }
    }
    # sonst wird der Datenbankname zur Findung des Sigels herangezogen
    else {
        $sigel=$self->{targetdbinfo}->{dbases}{$self->{database}};
        if (exists $self->{targetdbinfo}->{sigel}{$sigel}) {
            $normset_ref->{X4000}{content}=$self->{targetdbinfo}->{sigel}{$sigel};
        }
    }

    my $bibinfourl="";

    # Bestimmung der Bibinfo-Url
    if (exists $self->{targetdbinfo}->{bibinfo}{$sigel}) {
        $normset_ref->{X4001}{content}=$self->{targetdbinfo}->{bibinfo}{$sigel};
    }

    return $normset_ref;
}

sub DESTROY {
    my $self = shift;
    $self->{dbh}->disconnect();

    return;
}

1;
