#####################################################################
#
#  OpenBib::Record::Title.pm
#
#  Titel
#
#  Dieses File ist (C) 2007-2010 Oliver Flimm <flimm@openbib.org>
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

use Apache2::Reload;
use Benchmark ':hireswallclock';
use Business::ISBN;
use DBI;
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::BibSonomy;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Database::DBI;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::User;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $id        = exists $arg_ref->{id}
        ? $arg_ref->{id}             : undef;

    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}       : undef;

    my $date      = exists $arg_ref->{date}
        ? $arg_ref->{date}           : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    if (defined $database){
        $self->{database} = $database;
    }

    if (defined $id){
        $self->{id}       = $id;
    }

    if (defined $date){
        $self->{date}     = $date;
    }

    $logger->debug("Title-Record-Object created: ".YAML::Dump($self));
    return $self;
}

sub load_full_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config        = OpenBib::Config->instance;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    # (Re-)Initialisierung
    delete $self->{_exists}        if (exists $self->{_exists});
    delete $self->{_normset}       if (exists $self->{_normset});
    delete $self->{_mexset}        if (exists $self->{_mexset});
    delete $self->{_circset}       if (exists $self->{_circset});
    delete $self->{_brief_normset} if (exists $self->{_brief_normset});

    my $record_exists = 0;

    my $normset_ref   = {};

    $self->{id      }        = $id;
    $normset_ref->{id      } = $id;
    $normset_ref->{database} = $self->{database};

    unless (defined $self->{id} && defined $self->{database}){
        ($self->{_normset},$self->{_mexset},$self->{_circset},$self->{_exists})=({},(),[],$record_exists);

        $logger->error("Incomplete Record-Information Id: ".((defined $self->{id})?$self->{id}:'none')." Database: ".((defined $self->{database})?$self->{database}:'none'));
        return $self;
    }

    my $local_dbh = 0;
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
        $local_dbh = 1;
    }

    # Titelkategorien
    {
        
        my ($atime,$btime,$timeall)=(0,0,0);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        my $reqstring="select * from title where id = ?";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($id) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $category  = "T".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $content   =        decode_utf8($res->{content  });

            push @{$normset_ref->{$category}}, {
                indicator => $indicator,
                content   => $content,
            };

            $record_exists = 1 if (!$record_exists);
        }
        $request->finish();

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }
    
    # Verknuepfte Normdaten
    {
        my ($atime,$btime,$timeall)=(0,0,0);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        my $reqstring="select category,targetid,targettype,supplement from conn where sourceid=? and sourcetype=1 and targettype IN (2,3,4,5)";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($id) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $category   = "T".sprintf "%04d",$res->{category };
            my $targetid   =        decode_utf8($res->{targetid  });
            my $targettype =                    $res->{targettype};
            my $supplement =        decode_utf8($res->{supplement});
            
	    # Korrektes UTF-8 Encoding Flag wird in get_*_ans_*
	    # vorgenommen
            
            my $recordclass    =
                ($targettype == 2 )?"OpenBib::Record::Person":
                    ($targettype == 3 )?"OpenBib::Record::CorporateBody":
                        ($targettype == 4 )?"OpenBib::Record::Subject":
                            ($targettype == 5 )?"OpenBib::Record::Classification":undef;
            
            my $content = "";
            if (defined $recordclass){
                my $record=$recordclass->new({database=>$self->{database}});
                $record->load_name({dbh => $dbh, id=>$targetid});
                $content=$record->name_as_string;
            }
            
            push @{$normset_ref->{$category}}, {
                id         => $targetid,
                content    => $content,
                supplement => $supplement,
            };
        }
        $request->finish();
        
        if ($config->{benchmark}) {
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
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        my $titcount = $self->get_number_of_titles({ type => 'sub' });

        if ($titcount > 0){
            push @{$normset_ref->{T5001}}, {
                content => $titcount,
            };
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }

        # Ueberordnungen
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        $titcount = $self->get_number_of_titles({ type => 'super' });

        if ($titcount > 0){
            push @{$normset_ref->{T5002}}, {
                content => $titcount,
            };
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }

    }

    # Exemplardaten
    my $mexnormset_ref=[];
    {
        
        my $reqstring="select distinct targetid from conn where sourceid= ? and sourcetype=1 and targettype=6";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($id) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        my @verknmex=();
        while (my $res=$request->fetchrow_hashref){
            push @verknmex, decode_utf8($res->{targetid});
        }
        $request->finish();
        
        if ($#verknmex >= 0) {
            foreach my $mexid (@verknmex) {
                push @$mexnormset_ref, $self->_get_mex_set_by_idn({
                    id             => $mexid,
                });
            }
        }

    }

    # Ausleihinformationen der Exemplare
    my @circexemplarliste = ();
    {
        my $circexlist=undef;

        if (exists $circinfotable->{$self->{database}}{circ}) {

            my $circid=(exists $normset_ref->{'T0001'}[0]{content} && $normset_ref->{'T0001'}[0]{content} > 0 && $normset_ref->{'T0001'}[0]{content} != $id )?$normset_ref->{'T0001'}[0]{content}:$id;

            $logger->debug("Katkey: $id - Circ-ID: $circid");

            eval {
                my $soap = SOAP::Lite
                    -> uri("urn:/MediaStatus")
                        -> proxy($circinfotable->{$self->{database}}{circcheckurl});
                my $result = $soap->get_mediastatus(
                SOAP::Data->name(parameter  =>\SOAP::Data->value(
                    SOAP::Data->name(katkey   => $circid)->type('string'),
                    SOAP::Data->name(database => $circinfotable->{$self->{database}}{circdb})->type('string'))));
                
                unless ($result->fault) {
                    $circexlist=$result->result;
                }
                else {
                    $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                }
            };

            if ($@){
                $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
	    }

        }
        
        # Bei einer Ausleihbibliothek haben - falls Exemplarinformationen
        # in den Ausleihdaten vorhanden sind -- diese Vorrange ueber die
        # titelbasierten Exemplardaten
        
        if (defined($circexlist)) {
            @circexemplarliste = @{$circexlist};
        }
        
        if (exists $circinfotable->{$self->{database}}{circ}
                && $#circexemplarliste >= 0) {
            for (my $i=0; $i <= $#circexemplarliste; $i++) {
                
                my $bibliothek="-";
                my $sigel=$dbinfotable->{dbases}{$self->{database}};
                
                if (length($sigel)>0) {
                    if (exists $dbinfotable->{sigel}{$sigel}) {
                        $bibliothek=$dbinfotable->{sigel}{$sigel};
                    }
                    else {
                        $bibliothek="($sigel)";
                    }
                }
                else {
                    if (exists $dbinfotable->{sigel}{$dbinfotable->{dbases}{$self->{database}}}) {
                        $bibliothek=$dbinfotable->{sigel}{
                            $dbinfotable->{dbases}{$self->{database}}};
                    }
                }
                
                my $bibinfourl=$dbinfotable->{bibinfo}{
                    $dbinfotable->{dbases}{$self->{database}}};
                
                $circexemplarliste[$i]{'Bibliothek'} = $bibliothek;
                $circexemplarliste[$i]{'Bibinfourl'} = $bibinfourl;
                $circexemplarliste[$i]{'Ausleihurl'} = $circinfotable->{$self->{database}}{circurl};
            }
        }
        else {
            @circexemplarliste=();
        }
    }

    # Anreicherung mit zentralen Enrichmentdaten
    {
        my ($atime,$btime,$timeall);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        # Verbindung zur SQL-Datenbank herstellen
        my $enrichdbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my @isbn_refs = ();
        push @isbn_refs, @{$normset_ref->{T0540}} if (exists $normset_ref->{T0540});
        push @isbn_refs, @{$normset_ref->{T0553}} if (exists $normset_ref->{T0553});

        my $bibkey    = $normset_ref->{T5050}[0]{content};

        my @issn_refs = ();
        push @issn_refs, @{$normset_ref->{T0543}} if (exists $normset_ref->{T0543});
        
        $logger->debug("Enrichment ISBN's ".YAML::Dump(\@isbn_refs));
        $logger->debug("Enrichment ISSN's ".YAML::Dump(\@issn_refs));
        
        if (@isbn_refs){
            my @isbn_refs_tmp = ();
            # Normierung auf ISBN-13

            foreach my $isbn_ref (@isbn_refs){
                my $thisisbn = $isbn_ref->{content};

                # Alternative ISBN zur Rechercheanrei
                my $isbn     = Business::ISBN->new($thisisbn);

                if (defined $isbn && $isbn->is_valid){
                    $thisisbn = $isbn->as_isbn13->as_string;
                }

                push @isbn_refs_tmp, OpenBib::Common::Util::grundform({
                    category => '0540',
                    content  => $thisisbn,
                });

            }

            # Dubletten Bereinigen
            my %seen_isbns = ();
            
            @isbn_refs = grep { ! $seen_isbns{$_} ++ } @isbn_refs_tmp;

            $logger->debug(YAML::Dump(\@isbn_refs));

            my %seen_content = ();            
            foreach my $isbn (@isbn_refs){
                my $reqstring="select distinct category,content from normdata where isbn=? order by category,indicator";
                my $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
                $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
                
                # Anreicherung der Normdaten
                while (my $res=$request->fetchrow_hashref) {
                    my $category   = "E".sprintf "%04d",$res->{category };
                    my $content    =        decode_utf8($res->{content});

                    if ($seen_content{$content}){
                        next;
                    }
                    else {
                        $seen_content{$content} = 1;
                    }                    
                    
                    push @{$normset_ref->{$category}}, {
                        content    => $content,
                    };
                }
                
                # Anreicherung mit 'gleichen' (=gleiche ISBN) Titeln aus anderen Katalogen
                my $same_recordlist = new OpenBib::RecordList::Title();
                
                $reqstring="select distinct id,dbname from all_isbn where isbn=? and dbname != ? and id != ?";
                $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
                $request->execute($isbn,$self->{database},$self->{id}) or $logger->error("Request: $reqstring - ".$DBI::errstr);
                
                while (my $res=$request->fetchrow_hashref) {
                    my $id         = $res->{id};
                    my $database   = $res->{dbname};
                    
                    $same_recordlist->add(new OpenBib::Record::Title({ id => $id, database => $database}));
                }
                
                $self->{_same_records} = $same_recordlist;
                
                # Anreicherung mit 'aehnlichen' (=andere Auflage, Sprache) Titeln aus allen Katalogen
                my $similar_recordlist = new OpenBib::RecordList::Title();
                
                $reqstring="select isbn from similar_isbn where match (isbn) against (?)";
                $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
                $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
                
                my $similar_isbn_ref = {};
                while (my $res=$request->fetchrow_hashref) {
                    my $similarisbnstring = $res->{isbn};
                    foreach my $similarisbn (split(':',$similarisbnstring)){
                        $similar_isbn_ref->{$similarisbn}=1 if ($similarisbn ne $isbn);
                    }
                }
                
                my @similar_args = keys %$similar_isbn_ref;
                
                if (@similar_args){
                    my $in_select_string = join(',',map {'?'} @similar_args);
                    
                    $logger->debug("InSelect $in_select_string");
                    
                    $reqstring="select distinct id,dbname from all_isbn where isbn in ($in_select_string) order by dbname";
                    
                    $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
                    $request->execute(@similar_args) or $logger->error("Request: $reqstring - ".$DBI::errstr);
                    
                    while (my $res=$request->fetchrow_hashref) {
                        my $id         = $res->{id};
                        my $database   = $res->{dbname};
                        
                        $similar_recordlist->add(new OpenBib::Record::Title({ id => $id, database => $database}));
                    }
                    
                }
                    
                $similar_recordlist->load_brief_records;
                
                $self->{_similar_records} = $similar_recordlist;
                
                $request->finish();
                $logger->debug("Enrich: $isbn -> $reqstring");
            }
        }
        elsif ($bibkey){
            my $reqstring="select category,content from normdata where isbn=? order by category,indicator";
            my $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($bibkey) or $logger->error("Request: $reqstring - ".$DBI::errstr);
            
            # Anreicherung der Normdaten
            while (my $res=$request->fetchrow_hashref) {
                my $category   = "E".sprintf "%04d",$res->{category };
                my $content    =        decode_utf8($res->{content});
                
                push @{$normset_ref->{$category}}, {
                    content    => $content,
                };
            }            
        }
        elsif (@issn_refs){
            my @issn_refs_tmp = ();
            # Normierung

            foreach my $issn_ref (@issn_refs){
                my $thisissn = $issn_ref->{content};

                push @issn_refs_tmp, OpenBib::Common::Util::grundform({
                    category => '0543',
                    content  => $thisissn,
                });

            }

            # Dubletten Bereinigen
            my %seen_issns = ();
            
            @issn_refs = grep { ! $seen_issns{$_} ++ } @issn_refs_tmp;

            $logger->debug("ISSN: ".YAML::Dump(\@issn_refs));
           
            foreach my $issn (@issn_refs){
                my $reqstring="select category,content from normdata where isbn=? order by category,indicator";
                my $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
                $request->execute($issn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
                
                # Anreicherung der Normdaten
                while (my $res=$request->fetchrow_hashref) {
                    my $category   = "E".sprintf "%04d",$res->{category };
                    my $content    =        decode_utf8($res->{content});
                    
                    push @{$normset_ref->{$category}}, {
                        content    => $content,
                    };
                }
                
                $request->finish();
                $logger->debug("Enrich: $issn -> $reqstring");
            }

        }
        $enrichdbh->disconnect();

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }
    }

    $dbh->disconnect() if ($local_dbh);
    
    $logger->debug(YAML::Dump($normset_ref));
    ($self->{_normset},$self->{_mexset},$self->{_circset},$self->{_exists})=($normset_ref,$mexnormset_ref,\@circexemplarliste,$record_exists);

    return $self;
}

sub load_brief_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # (Re-)Initialisierung
    delete $self->{_exists}        if (exists $self->{_exists});
    delete $self->{_normset}       if (exists $self->{_normset});
    delete $self->{_mexset}        if (exists $self->{_mexset});
    delete $self->{_circset}       if (exists $self->{_circset});
    delete $self->{_brief_normset} if (exists $self->{_brief_normset});

    my $record_exists = 0;
    
    my $listitem_ref={};
    
    # Titel-ID und zugehoerige Datenbank setzen

    $self->{id    }           = $id;
    $listitem_ref->{id      } = $id;
    $listitem_ref->{database} = $self->{database};

    my $local_dbh = 0;
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
        $local_dbh = 1;
    }

    my ($atime,$btime,$timeall)=(0,0,0);
    
    if ($config->{benchmark}) {
        $atime  = new Benchmark;
    }

    if ($config->{use_titlistitem_table}) {
        $logger->debug("Getting cached titlistitem");
        
        # Bestimmung des Satzes
        my $request=$dbh->prepare("select listitem from title_listitem where id = ?") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        if (my $res=$request->fetchrow_hashref){
            my $titlistitem     = decode_utf8($res->{listitem});
            
            $logger->debug("Stored listitem: $titlistitem");

            my $titlistitem_ref;

            if ($config->{internal_serialize_type} eq "packed_storable"){
                $titlistitem_ref = Storable::thaw(pack "H*", $titlistitem);
            }
            elsif ($config->{internal_serialize_type} eq "json"){
                $titlistitem_ref = decode_json $titlistitem;
            }
            else {
                $titlistitem_ref = Storable::thaw(pack "H*", $titlistitem);
            }

            my %titlistitem = %{ $titlistitem_ref };
            
            $logger->debug("TitlistitemYAML: ".YAML::Dump(\%titlistitem));
            %$listitem_ref=(%$listitem_ref,%titlistitem);

            $record_exists = 1 if (!$record_exists);
        }
    }
    else {
        my ($atime,$btime,$timeall)=(0,0,0);
        
        if ($config->{benchmark}) {
            $atime  = new Benchmark;
        }

        # Bestimmung der Titelinformationen
        my $request=$dbh->prepare("select category,indicator,content from title where id = ? and category in (0310,0331,0403,0412,0424,0425,0451,0455,1203,0089)") or $logger->error($DBI::errstr);
        #    my $request=$dbh->prepare("select category,indicator,content from title where id = ? ") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $res=$request->fetchrow_hashref){
            my $category  = "T".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $content   =        decode_utf8($res->{content  });
            
            push @{$listitem_ref->{$category}}, {
                indicator => $indicator,
                content   => $content,
            };

            $record_exists = 1 if (!$record_exists);            
        }
        
        $logger->debug("Titel: ".YAML::Dump($listitem_ref));
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der Titelinformationen : ist ".timestr($timeall));
        }
        
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        # Bestimmung der Exemplarinformationen
        $request=$dbh->prepare("select holding.category,holding.indicator,holding.content from holding,conn where conn.sourceid = ? and conn.targetid=holding.id and conn.sourcetype=1 and conn.targettype=6 and holding.category=0014") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $res=$request->fetchrow_hashref){
            my $category  = "X".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $content   =        decode_utf8($res->{content  });
            
            push @{$listitem_ref->{$category}}, {
                indicator => $indicator,
                content   => $content,
            };
        }
        
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der Exemplarinformationen : ist ".timestr($timeall));
        }
        
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        my @autkor=();
        
        # Bestimmung der Verfasser, Personen
        #
        # Bemerkung zur Performance: Mit Profiling (Devel::SmallProf) wurde
        # festgestellt, dass die Bestimmung der Information ueber conn
        # und get_*_ans_by_idn durchschnittlich ungefaehr um den Faktor 30-50
        # schneller ist als ein join ueber conn und aut (!)
        $request=$dbh->prepare("select targetid,category,supplement from conn where sourceid=? and sourcetype=1 and targettype=2") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $res=$request->fetchrow_hashref){
            my $category  = "P".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $targetid  =        decode_utf8($res->{targetid});
            
            my $supplement="";
            if ($res->{supplement}){
                $supplement=" ".decode_utf8($res->{supplement});
            }

            my $content=OpenBib::Record::Person->new({database => $self->{database}})->load_name({dbh => $dbh, id => $targetid})->name_as_string.$supplement;

            # Kategorieweise Abspeichern
            push @{$listitem_ref->{$category}}, {
                id      => $targetid,
                type    => 'aut',
                content => $content,
            };
            
            # Gemeinsam Abspeichern
            push @autkor, $content;
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der Verfasserinformationen : ist ".timestr($timeall));
        }
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }    
        
        # Bestimmung der Urheber, Koerperschaften
        $request=$dbh->prepare("select targetid,category,supplement from conn where sourceid=? and sourcetype=1 and targettype=3") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $res=$request->fetchrow_hashref){
            my $category  = "C".sprintf "%04d",$res->{category };
            my $indicator =        decode_utf8($res->{indicator});
            my $targetid  =        decode_utf8($res->{targetid});
            
            my $supplement="";
            if ($res->{supplement}){
                $supplement.=" ".decode_utf8($res->{supplement});
            }

            my $content=OpenBib::Record::CorporateBody->new({database => $self->{database}})->load_name({dbh => $dbh, id => $targetid})->name_as_string.$supplement;
            
            # Kategorieweise Abspeichern
            push @{$listitem_ref->{$category}}, {
                id      => $targetid,
                type    => 'kor',
                content => $content,
            };
            
            # Gemeinsam Abspeichern
            push @autkor, $content;
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der Koerperschaftsinformationen : ist ".timestr($timeall));
        }
        
        # Zusammenfassen von autkor fuer die Sortierung
        
        push @{$listitem_ref->{'PC0001'}}, {
            content   => join(" ; ",@autkor),
        };
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }    
        
        
        $request->finish();
        
        $logger->debug("Vor Sonderbehandlung: ".YAML::Dump($listitem_ref));

        # Konzeptionelle Vorgehensweise fuer die korrekte Anzeige eines Titel in
        # der Kurztitelliste:
        #
        # 1. Fall: Es existiert ein HST
        #
        # Dann:
        #
        # Ist nichts zu tun
        #
        # 2. Fall: Es existiert kein HST(331)
        #
        # Dann:
        #
        # Unterfall 2.1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.3: Es existieren keine Bandzahlen, aber ein (erster)
        #                Gesamttitel(451)
        #
        # Dann: Verwende diesen GT
        #
        # Unterfall 2.4: Es existieren keine Bandzahlen, kein Gesamttitel(451),
        #                aber eine Zeitschriftensignatur(1203/USB-spezifisch)
        #
        # Dann: Verwende diese Zeitschriftensignatur
        #

        if (!exists $listitem_ref->{T0331}) {
            # UnterFall 2.1:
            if (exists $listitem_ref->{'T0089'}) {
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0089}[0]{content};
            }
            # Unterfall 2.2:
            elsif (exists $listitem_ref->{T0455}) {
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0455}[0]{content};
            }
            # Unterfall 2.3:
            elsif (exists $listitem_ref->{T0451}) {
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0451}[0]{content};
            }
            # Unterfall 2.4:
            elsif (exists $listitem_ref->{T1203}) {
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T1203}[0]{content};
            } else {
                $listitem_ref->{T0331}[0]{content}="Kein Titel vorhanden";
            }
        }

        # Bestimmung der Zaehlung

        # Fall 1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Setze diese Bandzahl
        #
        # Fall 2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Setze diese Bandzahl

        # Fall 1:
        if (exists $listitem_ref->{'T0089'}) {
            $listitem_ref->{T5100}= [
                {
                    content => $listitem_ref->{T0089}[0]{content}
                }
            ];
        }
        # Fall 2:
        elsif (exists $listitem_ref->{T0455}) {
            $listitem_ref->{T5100}= [
                {
                    content => $listitem_ref->{T0455}[0]{content}
                }
            ];
        }
                
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der HST-Ueberordnungsinformationen : ist ".timestr($timeall));
        }

        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }    
        
        # Bestimmung der Popularitaet des Titels
        $request=$dbh->prepare("select idcount from popularity where id=?") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $res=$request->fetchrow_hashref){
            $listitem_ref->{popularity} = $res->{idcount};
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der Popularitaetsinformation : ist ".timestr($timeall));
        }

    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        my $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung der gesamten Informationen         : ist ".timestr($timeall));
    }

    $dbh->disconnect() if ($local_dbh);
    
    $logger->debug(YAML::Dump($listitem_ref));

    ($self->{_brief_normset},$self->{_exists})=($listitem_ref,$record_exists);

    return $self;
}

sub get_normdata {
    my ($self)=@_;

    return $self->{_normset}
}

sub get_mexdata {
    my ($self)=@_;

    return $self->{_mexset}
}

sub get_circdata {
    my ($self)=@_;

    return $self->{_circset}
}

sub get_same_records {
    my ($self)=@_;

    return $self->{_same_records}
}

sub get_similar_records {
    my ($self)=@_;

    return $self->{_similar_records}
}

sub get_brief_normdata {
    my ($self)=@_;

    return $self->{_brief_normset}
}

sub is_brief_normdata {
    my ($self)=@_;

    return (exists $self->{_brief_normset})?1:0;
}

sub is_normdata {
    my ($self)=@_;

    return (exists $self->{_normset})?1:0;
}

sub set_brief_normdata_from_storable {
    my ($self,$storable_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # (Re-)Initialisierung
    delete $self->{_exists}        if (exists $self->{_exists});
    delete $self->{_normset}       if (exists $self->{_normset});
    delete $self->{_mexset}        if (exists $self->{_mexset});
    delete $self->{_circset}       if (exists $self->{_circset});
    delete $self->{_brief_normset} if (exists $self->{_brief_normset});

    $self->{_brief_normset} = $storable_ref;

    $logger->debug(YAML::Dump($self));    

    return $self;
}

sub print_to_handler {
    my ($self,$arg_ref)=@_;

    my $r                  = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}          : undef;
    my $representation     = exists $arg_ref->{representation}
        ? $arg_ref->{representation}     : undef;
    my $content_type       = exists $arg_ref->{content_type}
        ? $arg_ref->{content_type}       : 'text/html';
    my $view               = exists $arg_ref->{view}
        ? $arg_ref->{view}               : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config        = OpenBib::Config->instance;
    my $session       = OpenBib::Session->instance({ apreq => $r });
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    my $user          = OpenBib::User->instance({sessionID => $session->{ID}});
    my $searchquery   = OpenBib::SearchQuery->instance;
    my $query         = Apache2::Request->new($r);

    my $queryoptions  = OpenBib::QueryOptions->instance($query);
    
    my $stid          = $query->param('stid')              || '';
    my $callback      = $query->param('callback')  || '';
    my $lang          = $query->param('lang') || $queryoptions->get_option('l') || 'de';

    my $queryid    = $query->param('queryid')   || '';
    my $format     = $query->param('format')    || 'full';
    my $no_log     = $query->param('no_log')    || '';
    
    my $loginname     = $user->get_username();
    my $logintargetdb = $user->get_targetdb_of_session($session->{ID});

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
    
    my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation({
        session    => $session,
        database   => $self->{database},
        titidn     => $self->{id},
        view       => $view,
    });

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    my $poolname=$dbinfotable->{dbnames}{$self->{database}};

    if ($queryid){
        $searchquery->load({sessionID => $session->{ID}, queryid => $queryid});
    }

    # Literaturlisten finden

    my $litlists_ref = $user->get_litlists_of_tit({titid => $self->{id}, titdb => $self->{database}});

    # Anreicherung mit OLWS-Daten
    if (defined $query->param('olws') && $query->param('olws') eq "Viewer"){
        if (exists $circinfotable->{$self->{database}} && exists $circinfotable->{$self->{database}}{circcheckurl}){
            $logger->debug("Endpoint: ".$circinfotable->{$self->{database}}{circcheckurl});
            my $soapresult;
            eval {
                my $soap = SOAP::Lite
                    -> uri("urn:/Viewer")
                        -> proxy($circinfotable->{$self->{database}}{circcheckurl});
                
                my $result = $soap->get_item_info(
                    SOAP::Data->name(parameter  =>\SOAP::Data->value(
                        SOAP::Data->name(collection => $circinfotable->{$self->{database}}{circdb})->type('string'),
                        SOAP::Data->name(item       => $self->{id})->type('string'))));
                
                unless ($result->fault) {
                    $soapresult=$result->result;
                }
                else {
                    $logger->error("SOAP Viewer Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                }
            };
            
            if ($@){
                $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
            }
            
            $self->{olws}=$soapresult;
        }
    }

    # Dann Ausgabe des neuen Headers
    
    # TT-Data erzeugen
    my $ttdata={
        content_type   => $content_type,
        representation => $representation,

        view        => $view,
        stylesheet  => $stylesheet,
        database    => $self->{database}, # Zwingend wegen common/subtemplate
        dbinfo      => $dbinfotable,
        poolname    => $poolname,
        prevurl     => $prevurl,
        nexturl     => $nexturl,
        qopts       => $queryoptions->get_options,
        queryid     => $searchquery->get_id,
        sessionID   => $session->{ID},
        session     => $session,
        record      => $self,
        titidn      => $self->{id},

        format      => $format,
        
        # Wegen Template-Kompatabilitaet:
        normset     => $self->{_normset},
        mexnormset  => $self->{_mexset},
        circset     => $self->{_circset},

        searchquery => $searchquery,
        activefeed  => $config->get_activefeeds_of_db($self->{database}),

        loginname     => $loginname,
        logintargetdb => $logintargetdb,

        litlists          => $litlists_ref,
        highlightquery    => \&highlightquery,

        config      => $config,
        user        => $user,
        msg         => $msg,
    };

    $stid=~s/[^0-9]//g;
    my $templatename = ($stid)?"tt_resource_title_".$stid."_tname":"tt_resource_title_tname";
    
    OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

    # Log Event

    my $isbn;

    if (exists $self->{normset}->{T0540}[0]{content}){
        $isbn = $self->{normset}->{T0540}[0]{content};
        $isbn =~s/ //g;
        $isbn =~s/-//g;
        $isbn =~s/X/x/g;
    }

    if (!$no_log){
        $session->log_event({
            type      => 10,
            content   => {
                id       => $self->{id},
                database => $self->{database},
                isbn     => $isbn,
            },
            serialize => 1,
        });
    }
    
    return;
}

sub _get_mex_set_by_idn {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}               : undef;

    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->instance;
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    
    my $local_dbh = 0;
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
        or $logger->error_die($DBI::errstr);
        $local_dbh = 1;
    }
    
    my $normset_ref={};

    $normset_ref->{id}=$id;
    
    # Defaultwerte setzen
    $normset_ref->{X0005}{content}="-";
    $normset_ref->{X0014}{content}="-";
    $normset_ref->{X0016}{content}="-";
    $normset_ref->{X1204}{content}="-";
    $normset_ref->{X4000}{content}="-"; # Katalogname
    $normset_ref->{X4001}{content}="";  # Katalog-URL laut Admin
    
    my ($atime,$btime,$timeall);
    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest="select category,content,indicator from holding where id = ?";
    my $result=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $result->execute($id);

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

    if ($config->{benchmark}) {
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
    if (exists $normset_ref->{X3330}{content}) {
        $sigel=$normset_ref->{X3330}{content};
        if (exists $dbinfotable->{sigel}{$sigel}) {
            $normset_ref->{X4000}{content}=$dbinfotable->{sigel}{$sigel};
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
        $sigel=$dbinfotable->{dbases}{$self->{database}};
        if (exists $dbinfotable->{sigel}{$sigel}) {
            $normset_ref->{X4000}{content}=$dbinfotable->{sigel}{$sigel};
        }
    }

    my $bibinfourl="";

    # Bestimmung der Bibinfo-Url
    if (exists $dbinfotable->{bibinfo}{$sigel}) {
        $normset_ref->{X4001}{content}=$dbinfotable->{bibinfo}{$sigel};
    }

    $dbh->disconnect() if ($local_dbh);

    $logger->debug(YAML::Dump($normset_ref));
    
    return $normset_ref;
}

sub highlightquery {
    my ($searchquery,$content) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Highlight Query

    my $term_ref = $searchquery->get_searchterms();

    return $content if (scalar(@$term_ref) <= 0);

    $logger->debug("Terms: ".YAML::Dump($term_ref));

    my $terms = join("|", grep /^\w{3,}/ ,@$term_ref);

    return $content if (!$terms);
    
    $logger->debug("Term_ref: ".YAML::Dump($term_ref)."\nTerms: $terms");
    $logger->debug("Content vor: ".$content);
    
    $content=~s/\b($terms)/<span class="queryhighlight">$1<\/span>/ig unless ($content=~/http/);

    $logger->debug("Content nach: ".$content);

    return $content;
}

sub to_bibkey {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return OpenBib::Common::Util::gen_bibkey({ normdata => $self->{_normset}});
}

sub to_normalized_isbn13 {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $thisisbn = $self->{_normset}{"T0540"}[0]{content};

    $logger->debug("ISBN: $thisisbn");

    # Normierung auf ISBN13

    my $isbn     = Business::ISBN->new($thisisbn);
    
    if (defined $isbn && $isbn->is_valid){
        $thisisbn = $isbn->as_isbn13->as_string;
    }
    
    $thisisbn = OpenBib::Common::Util::grundform({
        category => '0540',
        content  => $thisisbn,
    });
    
    return $thisisbn;
}

sub to_endnote {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $endnote_category_map_ref = {
        'T0100' => '%A',    # Author
        'T0101' => '%A',    # Person
        'T0103' => '%A',    # Celebr. Person 
        'T0200' => '%C',    # Corporate Author
        'T0331' => '%T',    # Title of the article or book
        'T0451' => '%S',    # Title of the serie
        'T0590' => '%J',    # Journal containing the article
#        '3'     => '%B',    # Journal Title (refer: Book containing article)
        'T0519' => '%R',    # Report, paper, or thesis type
        'T0455' => '%V',    # Volume 
        'T0089' => '%N',    # Number with volume
#        '7'     => '%E',    # Editor of book containing article
#        '8'     => '%P',    # Page number(s)
        'T0412' => '%I',    # Issuer. This is the publisher
        'T0410' => '%C',    # City where published. This is the publishers address
        'T0425' => '%D',    # Date of publication
        'T0424' => '%D',    # Date of publication
#        '11'    => '%O',    # Other information which is printed after the reference
#        '12'    => '%K',    # Keywords used by refer to help locate the reference
#        '13'    => '%L',    # Label used to number references when the -k flag of refer is used
        'T0540' => '%X',    # Abstract. This is not normally printed in a reference
        'T0543' => '%X',    # Abstract. This is not normally printed in a reference
        'T0750' => '%X',    # Abstract. This is not normally printed in a reference
#        '15'    => '%W',    # Where the item can be found (physical location of item)
        'T0433' => '%Z',    # Pages in the entire document. Tib reserves this for special use
        'T0403' => '%7',    # Edition
#        '17'    => '%Y',    # Series Editor
    };

    my $endnote_ref=[];

    # Titelkategorien
    foreach my $category (keys %{$endnote_category_map_ref}) {
        if (exists $self->{_normset}{$category}) {
            foreach my $content_ref (@{$self->{_normset}{$category}}){                
                my $content = $endnote_category_map_ref->{$category}." ".$content_ref->{content};
                
                if ($category eq "T0331" && exists $self->{_normset}{"T0335"}){
                    $content.=" : ".$self->{_normset}{"T0335"}[0]{content};
                }
                
                push @{$endnote_ref}, $content;
            }
        }
    }

    # Exemplardaten
    my @mexnormset = @{$self->{_mexset}};

    if ($#mexnormset > 0){
        foreach my $mex_ref (@mexnormset){
            push @{$endnote_ref}, '%W '.$mex_ref->{"X4000"}{content}{full}." / ".$mex_ref->{"X0016"}{content}." / ".$mex_ref->{"X0014"}{content};
        }
    }
    
    return join("\n",@$endnote_ref);
}


sub to_bibsonomy_post {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $utf8               = exists $arg_ref->{utf8}
        ? $arg_ref->{utf8}               : 0;

    my $doc = XML::LibXML::Document->new();
    my $root = $doc->createElement('bibsonomy');
    $doc->setDocumentElement($root);
    my $post = $doc->createElement('post');
    $root->appendChild($post);
    my $bibtex = $doc->createElement('bibtex');
    
    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $category (qw/T0100 T0101/){
        next if (!exists $self->{_normset}->{$category});
        foreach my $part_ref (@{$self->{_normset}->{$category}}){
            if ($part_ref->{supplement} =~ /Hrsg/){
                push @$editors_ref, utf2bibtex($part_ref->{content},$utf8);
            }
            else {
                push @$authors_ref, utf2bibtex($part_ref->{content},$utf8);
            }
        }
    }
    my $author = join(' and ',@$authors_ref);
    my $editor = join(' and ',@$editors_ref);

    # Schlagworte
    my $keywords_ref=[];
    foreach my $category (qw/T0710 T0902 T0907 T0912 T0917 T0922 T0927 T0932 T0937 T0942 T0947/){
        next if (!exists $self->{_normset}->{$category});
        foreach my $part_ref (@{$self->{_normset}->{$category}}){
            push @$keywords_ref, utf2bibtex($part_ref->{content},$utf8);
        }
    }
    my $keyword = join(' ; ',@$keywords_ref);
    
    # Auflage
    my $edition   = (exists $self->{_normset}->{T0403})?utf2bibtex($self->{_normset}->{T0403}[0]{content},$utf8):'';

    # Verleger
    my $publisher = (exists $self->{_normset}->{T0412})?utf2bibtex($self->{_normset}->{T0412}[0]{content},$utf8):'';

    # Verlagsort
    my $address   = (exists $self->{_normset}->{T0410})?utf2bibtex($self->{_normset}->{T0410}[0]{content},$utf8):'';

    # Titel
    my $title     = (exists $self->{_normset}->{T0331})?utf2bibtex($self->{_normset}->{T0331}[0]{content},$utf8):'';

    # Zusatz zum Titel
    my $titlesup  = (exists $self->{_normset}->{T0335})?utf2bibtex($self->{_normset}->{T0335}[0]{content},$utf8):'';

    #    Folgende Erweiterung um titlesup ist nuetzlich, laeuft aber der
    #    Bibkey-Bildung entgegen

#    if ($title && $titlesup){
#        $title = "$title : $titlesup";
#    }

    # Jahr
    my $year      = (exists $self->{_normset}->{T0425})?utf2bibtex($self->{_normset}->{T0425}[0]{content},$utf8):'';

    # ISBN
    my $isbn      = (exists $self->{_normset}->{T0540})?utf2bibtex($self->{_normset}->{T0540}[0]{content},$utf8):'';

    # ISSN
    my $issn      = (exists $self->{_normset}->{T0543})?utf2bibtex($self->{_normset}->{T0543}[0]{content},$utf8):'';

    # Sprache
    my $language  = (exists $self->{_normset}->{T0516})?utf2bibtex($self->{_normset}->{T0516}[0]{content},$utf8):'';

    # Abstract
    my $abstract  = (exists $self->{_normset}->{T0750})?utf2bibtex($self->{_normset}->{T0750}[0]{content},$utf8):'';

    # Origin
    my $origin    = (exists $self->{_normset}->{T0590})?utf2bibtex($self->{_normset}->{T0590}[0]{content},$utf8):'';

    if ($author){
        $bibtex->setAttribute("author",$author);
    }
    if ($editor){
        $bibtex->setAttribute("editor",$editor);
    }
    if ($edition){
        $bibtex->setAttribute("edition",$edition);
    }
    if ($publisher){
        $bibtex->setAttribute("publisher",$publisher);
    }
    if ($address){
        $bibtex->setAttribute("address",$address);
    }
    if ($title){
        $bibtex->setAttribute("title",$title);
    }
    if ($year){
        $bibtex->setAttribute("year",$year);
    }
    if ($isbn){
        $bibtex->setAttribute("misc",'ISBN = {'.$isbn.'}');
    }
    if ($issn){
        $bibtex->setAttribute("misc",'ISSN = {'.$issn.'}');
    }
    if ($keyword){
        $bibtex->setAttribute("keywords",$keyword);
    }
    if ($language){
        $bibtex->setAttribute("language",$language);
    }
    if ($abstract){
        $bibtex->setAttribute("abstract",$abstract);
    }

    if ($origin){
        # Pages
        if ($origin=~/ ; (S\. *\d+.*)$/){
            $bibtex->setAttribute("pages",$1);
        }
        elsif ($origin=~/, (S\. *\d+.*)$/){
            $bibtex->setAttribute("pages",$1);
        }

        # Journal and/or Volume
        if ($origin=~/^(.+?) ; (.*?) ; S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            $bibtex->setAttribute("journal",$journal);
            $bibtex->setAttribute("volume",$volume);
        }
        elsif ($origin=~/^(.+?)\. (.*?), (\d\d\d\d), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;
            my $year    = $3;

            $journal =~ s/ \/ .*$//;
            $bibtex->setAttribute("journal",$journal);
            $bibtex->setAttribute("volume",$volume);
        }
        elsif ($origin=~/^(.+?)\. (.*?), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            $bibtex->setAttribute("journal",$journal);
            $bibtex->setAttribute("volume",$volume);
        }
        elsif ($origin=~/^(.+?) ; (.*?), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            $bibtex->setAttribute("journal",$journal);
            $bibtex->setAttribute("volume",$volume);
        }
        elsif ($origin=~/^(.*?) ; S\. *\d+.*$/){
            my $journal = $1;

            $journal =~ s/ \/ .*$//;
            $bibtex->setAttribute("journal",$journal);
        }
    }

    my $identifier=substr($author,0,4).substr($title,0,4).$year;
    $identifier=~s/[^A-Za-z0-9]//g;

    $bibtex->setAttribute("bibtexKey",$identifier);

    if ($origin){
        $bibtex->setAttribute("entrytype",'article');
    }
    elsif ($isbn){
        $bibtex->setAttribute("entrytype",'book');
    }
    else {
        $bibtex->setAttribute("entrytype",'book');
    }

    $post->appendChild($bibtex);
    
    return $doc->toString();
}

sub to_bibtex {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $utf8               = exists $arg_ref->{utf8}
        ? $arg_ref->{utf8}               : 0;

    my $bibtex_ref=[];

    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $category (qw/T0100 T0101/){
        next if (!exists $self->{_normset}->{$category});
        foreach my $part_ref (@{$self->{_normset}->{$category}}){
            if ($part_ref->{supplement} =~ /Hrsg/){
                push @$editors_ref, utf2bibtex($part_ref->{content},$utf8);
            }
            else {
                push @$authors_ref, utf2bibtex($part_ref->{content},$utf8);
            }
        }
    }
    my $author = join(' and ',@$authors_ref);
    my $editor = join(' and ',@$editors_ref);

    # Schlagworte
    my $keywords_ref=[];
    foreach my $category (qw/T0710 T0902 T0907 T0912 T0917 T0922 T0927 T0932 T0937 T0942 T0947/){
        next if (!exists $self->{_normset}->{$category});
        foreach my $part_ref (@{$self->{_normset}->{$category}}){
            push @$keywords_ref, utf2bibtex($part_ref->{content},$utf8);
        }
    }
    my $keyword = join(' ; ',@$keywords_ref);
    
    # Auflage
    my $edition   = (exists $self->{_normset}->{T0403})?utf2bibtex($self->{_normset}->{T0403}[0]{content},$utf8):'';

    # Verleger
    my $publisher = (exists $self->{_normset}->{T0412})?utf2bibtex($self->{_normset}->{T0412}[0]{content},$utf8):'';

    # Verlagsort
    my $address   = (exists $self->{_normset}->{T0410})?utf2bibtex($self->{_normset}->{T0410}[0]{content},$utf8):'';

    # Titel
    my $title     = (exists $self->{_normset}->{T0331})?utf2bibtex($self->{_normset}->{T0331}[0]{content},$utf8):'';

    # Zusatz zum Titel
    my $titlesup  = (exists $self->{_normset}->{T0335})?utf2bibtex($self->{_normset}->{T0335}[0]{content},$utf8):'';
#    Folgende Erweiterung um titlesup ist nuetzlich, laeuft aber der
#    Bibkey-Bildung entgegen
#    if ($title && $titlesup){
#        $title = "$title : $titlesup";
#    }

    # Jahr
    my $year      = (exists $self->{_normset}->{T0425})?utf2bibtex($self->{_normset}->{T0425}[0]{content},$utf8):'';

    # ISBN
    my $isbn      = (exists $self->{_normset}->{T0540})?utf2bibtex($self->{_normset}->{T0540}[0]{content},$utf8):'';

    # ISSN
    my $issn      = (exists $self->{_normset}->{T0543})?utf2bibtex($self->{_normset}->{T0543}[0]{content},$utf8):'';

    # Sprache
    my $language  = (exists $self->{_normset}->{T0516})?utf2bibtex($self->{_normset}->{T0516}[0]{content},$utf8):'';

    # Abstract
    my $abstract  = (exists $self->{_normset}->{T0750})?utf2bibtex($self->{_normset}->{T0750}[0]{content},$utf8):'';

    # Origin
    my $origin    = (exists $self->{_normset}->{T0590})?utf2bibtex($self->{_normset}->{T0590}[0]{content},$utf8):'';

    if ($author){
        push @$bibtex_ref, "author    = \"$author\"";
    }
    if ($editor){
        push @$bibtex_ref, "editor    = \"$editor\"";
    }
    if ($edition){
        push @$bibtex_ref, "edition   = \"$edition\"";
    }
    if ($publisher){
        push @$bibtex_ref, "publisher = \"$publisher\"";
    }
    if ($address){
        push @$bibtex_ref, "address   = \"$address\"";
    }
    if ($title){
        push @$bibtex_ref, "title     = \"$title\"";
    }
    if ($year){
        push @$bibtex_ref, "year      = \"$year\"";
    }
    if ($isbn){
        push @$bibtex_ref, "ISBN      = \"$isbn\"";
    }
    if ($issn){
        push @$bibtex_ref, "ISSN      = \"$issn\"";
    }
    if ($keyword){
        push @$bibtex_ref, "keywords  = \"$keyword\"";
    }
    if ($language){
        push @$bibtex_ref, "language  = \"$language\"";
    }
    if ($abstract){
        push @$bibtex_ref, "abstract  = \"$abstract\"";
    }

    if ($origin){
        # Pages
        if ($origin=~/ ; (S\. *\d+.*)$/){
            push @$bibtex_ref, "pages     = \"$1\"";
        }
        elsif ($origin=~/, (S\. *\d+.*)$/){
            push @$bibtex_ref, "pages     = \"$1\"";
        }

        # Journal and/or Volume
        if ($origin=~/^(.+?) ; (.*?) ; S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.+?)\. (.*?), (\d\d\d\d), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;
            my $year    = $3;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.+?)\. (.*?), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.+?) ; (.*?), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
            push @$bibtex_ref, "volume    = \"$volume\"";
        }
        elsif ($origin=~/^(.*?) ; S\. *\d+.*$/){
            my $journal = $1;

            $journal =~ s/ \/ .*$//;
            push @$bibtex_ref, "journal   = \"$journal\"";
        }
    }

    my $identifier=substr($author,0,4).substr($title,0,4).$year;
    $identifier=~s/[^A-Za-z0-9]//g;

    my $bibtex="";

    if ($origin){
        unshift @$bibtex_ref, "\@article {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }
    elsif ($isbn){
        unshift @$bibtex_ref, "\@book {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }
    else {
        unshift @$bibtex_ref, "\@book {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }

    
    return $bibtex;
}

sub to_tags {
    my ($self) = @_;

    # Schlagworte
    my $keywords_ref=[];
    foreach my $category (qw/T0710 T0902 T0907 T0912 T0917 T0922 T0927 T0932 T0937 T0942 T0947/){
        next if (!exists $self->{_normset}->{$category});
        foreach my $part_ref (@{$self->{_normset}->{$category}}){
            foreach my $content_part (split('\s+',$part_ref->{content})){
                push @$keywords_ref, OpenBib::Common::Util::grundform({
                    tagging => 1,
                    content => $content_part,
                });
            }
        }
    }
    my $keyword = join(' ',@$keywords_ref);

    return $keyword;
}

sub utf2bibtex {
    my ($string,$utf8)=@_;

    return "" if (!defined $string);
    
    # {} werden von BibTeX verwendet und haben in den Originalinhalten
    # nichts zu suchen
    $string=~s/\{//g;
    $string=~s/\}//g;
    # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
    $string=~s/[^-+\p{Alphabetic}0-9\n\/&;#: '()@<>\\,.="^*[]]//g;
    $string=~s/&lt;/</g;
    $string=~s/&gt;/>/g;
    $string=~s/&amp;/&/g;

    # Wenn utf8 ausgegeben werden soll, dann sind wir hier fertig
    return $string if ($utf8);

    # ... ansonsten muessen weitere Sonderzeichen umgesetzt werden.
    $string=~s/&#172;//g;
    $string=~s/&#228;/{\\"a}/g;
    $string=~s/&#252;/{\\"u}/g;
    $string=~s/&#246;/{\\"o}/g;
    $string=~s/&#223;/{\\"s}/g;
    $string=~s/&#214;/{\\"O}/g;
    $string=~s/&#220;/{\\"U}/g;
    $string=~s/&#196;/{\\"A}/g;
    $string=~s/&auml;/{\\"a}/g;
    $string=~s/&ouml;/{\\"o}/g;
    $string=~s/&uuml;/{\\"u}/g;
    $string=~s/&Auml;/{\\"A}/g;
    $string=~s/&Ouml;/{\\"O}/g;
    $string=~s/&Uuml;/{\\"U}/g;
    $string=~s/&szlig;/{\\"s}/g;
    $string=~s/ä/{\\"a}/g;
    $string=~s/ö/{\\"o}/g;
    $string=~s/ü/{\\"u}/g;
    $string=~s/Ä/{\\"A}/g;
    $string=~s/Ö/{\\"O}/g;
    $string=~s/Ü/{\\"U}/g;
    $string=~s/ß/{\\ss}/g;

    return $string;
}

sub to_rawdata {
    my ($self) = @_;

    if (exists $self->{_brief_normset}){
        return $self->{_brief_normset};
    }
    else {
        return ($self->{_normset},$self->{_mexset},$self->{_circset});
    }
}

sub get_category {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $category            = exists $arg_ref->{category}
        ? $arg_ref->{category}               : undef;

    my $indicator           = exists $arg_ref->{indicator}
        ? $arg_ref->{indicator}              : undef;


    if (exists $self->{_brief_normset}){
        return $self->{_brief_normset}->{$category}->[$indicator-1]->{content};
    }
    else {
        return $self->{_normset}->{$category}->[$indicator-1]->{content};
    }
}

sub get_number_of_titles {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type}              : 'sub'; # sub oder super

    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $local_dbh = 0;
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
        $local_dbh = 1;
    }
    
    my $sqlrequest;

    # Ausgabe der Anzahl verk"upfter Titel

    if ($type eq "sub"){
        $sqlrequest="select count(distinct targetid) as conncount from conn where sourceid=? and sourcetype=1 and targettype=1";
    }
    elsif ($type eq "super"){
        $sqlrequest="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=1";
    }
    else {
        return undef;
    }
    
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($id);
    my $res=$request->fetchrow_hashref;
    
    return $res->{conncount},
}

sub record_exists {
    my ($self) = @_;

    return $self->{_exists};
}

sub to_drilldown_term {
    my ($self,$term)=@_;

    my $config = OpenBib::Config->instance;

    $term = OpenBib::Common::Util::grundform({
        content   => $term,
        searchreq => 1,
    });

    $term=~s/\W/_/g;

    if (length($term) > $config->{xapian_option}{max_key_length}){
        $term=substr($term,0,$config->{xapian_option}{max_key_length}-2); # 2 wegen Prefix
    }

    return $term;
}

sub to_json {
    my ($self)=@_;

    my $title_ref = {
        'metadata'    => $self->{_normset},
        'items'       => $self->{_mexset},
        'circulation' => $self->{_circset},
    };

    return encode_json $title_ref;
}

sub set_id {
    my ($self,$id) = @_;

    $self->{id} = $id;

    return $self;
}

sub set_database {
    my ($self,$database) = @_;

    $self->{database} = $database;

    return $self;
}


sub set_category {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $category          = exists $arg_ref->{category}
        ? $arg_ref->{category}          : undef;

    my $indicator         = exists $arg_ref->{indicator}
        ? $arg_ref->{indicator}         : undef;

    my $content            = exists $arg_ref->{content}
        ? $arg_ref->{content}           : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    push @{$self->{_normset}{$category}}, {
        indicator => $indicator,
        content   => $content,
    };

    return $self;
}

1;
