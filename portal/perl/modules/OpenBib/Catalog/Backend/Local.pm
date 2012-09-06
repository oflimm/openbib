#####################################################################
#
#  OpenBib::Catalog::Backend::Local
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Catalog::Backend::Local;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(OpenBib::Catalog);

use Business::ISBN;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use Storable ();

use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Schema::DBI;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Set defaults
    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}         : undef;
    
    my $self = { };

    bless ($self, $class);

    $self->{database} = $database;
    
    $self->connectDB($database);
    
    return $self;
}


sub get_recent_titles {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();


    my $titles = $self->{schema}->resultset('Title')->search_rs(
        undef,
        {
            order_by => ['tstamp_create DESC'],
            rows     => $limit,
        }
    );

    my $recordlist = new OpenBib::RecordList::Title();

    foreach my $title ($titles->all){
        $logger->debug("Adding Title ".$title->id);
        $recordlist->add(new OpenBib::Record::Title({ database => $self->{database} , id => $title->id, date => $title->tstamp_create}));
    }

    return $recordlist;
}

sub load_full_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config        = OpenBib::Config->instance;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    my $title_record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });
    
    my $normset_ref   = {};

    $self->{id}              = $id;
    $normset_ref->{id      } = $id;
    $normset_ref->{database} = $self->{database};

    unless (defined $self->{id} && defined $self->{database}){
        $logger->error("Incomplete Record-Information Id: ".((defined $self->{id})?$self->{id}:'none')." Database: ".((defined $self->{database})?$self->{database}:'none'));
        return $title_record;
    }

    # Titelkategorien
    {
        
        my ($atime,$btime,$timeall)=(0,0,0);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        # DBI: select * from title where id = ?
        my $title_fields = $self->{schema}->resultset('Title')->search(
            {
                'me.id' => $id,
            },
            {
                select => ['title_fields.field','title_fields.mult','title_fields.subfield','title_fields.content'],
                as     => ['thisfield','thismult','thissubfield','thiscontent'],
                join   => ['title_fields'],
            }
        );

        foreach my $item ($title_fields->all){
            my $field    = "T".sprintf "%04d",$item->get_column('thisfield');
            my $subfield =                    $item->get_column('thissubfield');
            my $mult     =                    $item->get_column('thismult');
            my $content  =                    $item->get_column('thiscontent');

            $title_record->set_field({
                field     => $field,
                mult      => $mult,
                subfield  => $subfield,
                content   => $content,
            });
        }

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer Bestimmung der Titeldaten ist ".timestr($timeall));
        }
    }
    
    # Verknuepfte Normdaten
    {
        my ($atime,$btime,$timeall)=(0,0,0);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        
        # Personen
        # DBI: select category,targetid,targettype,supplement from conn where sourceid=? and sourcetype=1 and targettype IN (2,3,4,5)
        my $title_persons = $self->{schema}->resultset('Title')->search(
            {
                'me.id' => $id,
            },
            {
                select => ['title_people.field','title_people.personid','title_people.supplement'],
                as     => ['thisfield','thispersonid','thissupplement'],
                join   => ['title_people'],
            }
        );

        my $mult = 1;
        foreach my $item ($title_persons->all){
            my $field      = "T".sprintf "%04d",$item->get_column('thisfield');
            my $personid   =                    $item->get_column('thispersonid');
            my $supplement =                    $item->get_column('thissupplement');

            my $record = OpenBib::Record::Person->new({database=>$self->{database}});
            $record->load_name({id=>$personid});
            my $content = $record->name_as_string;

            $title_record->set_field({                
                field      => $field,
                id         => $personid,
                content    => $content,
                supplement => $supplement,
                mult       => $mult,
            });

            $mult++;
        }

        # Koerperschaften
        # DBI: select category,targetid,targettype,supplement from conn where sourceid=? and sourcetype=1 and targettype IN (2,3,4,5)
        my $title_corporatebodies = $self->{schema}->resultset('Title')->search(
            {
                'me.id' => $id,
            },
            {
                select => ['title_corporatebodies.field','title_corporatebodies.corporatebodyid','title_corporatebodies.supplement'],
                as     => ['thisfield','thiscorporatebodyid','thissupplement'],
                join   => ['title_corporatebodies'],
            }
        );

        $mult = 1;        
        foreach my $item ($title_corporatebodies->all){
            my $field             = "T".sprintf "%04d",$item->get_column('thisfield');
            my $corporatebodyid   =                    $item->get_column('thiscorporatebodyid');
            my $supplement        =                    $item->get_column('thissupplement');

            my $record = OpenBib::Record::CorporateBody->new({database=>$self->{database}});
            $record->load_name({id=>$corporatebodyid});
            my $content = $record->name_as_string;

            $title_record->set_field({                
                field      => $field,
                id         => $corporatebodyid,
                content    => $content,
                supplement => $supplement,
                mult       => $mult,
            });

            $mult++;
        }

        # Schlagworte
        # DBI: select category,targetid,targettype,supplement from conn where sourceid=? and sourcetype=1 and targettype IN (2,3,4,5)
        my $title_subjects = $self->{schema}->resultset('Title')->search(
            {
                'me.id' => $id,
            },
            {
                select => ['title_subjects.field','title_subjects.subjectid','title_subjects.supplement'],
                as     => ['thisfield','thissubjectid','thissupplement'],
                join   => ['title_subjects'],
            }
        );

        $mult = 1;
        foreach my $item ($title_subjects->all){
            my $field             = "T".sprintf "%04d",$item->get_column('thisfield');
            my $subjectid         =                    $item->get_column('thissubjectid');
            my $supplement        =                    $item->get_column('thissupplement');

            my $record = OpenBib::Record::Subject->new({database=>$self->{database}});
            $record->load_name({id=>$subjectid});
            my $content = $record->name_as_string;

            $title_record->set_field({                
                field      => $field,
                id         => $subjectid,
                content    => $content,
                supplement => $supplement,
                mult       => $mult,
            });

            $mult++;
        }

        # Klassifikationen
        # DBI: select category,targetid,targettype,supplement from conn where sourceid=? and sourcetype=1 and targettype IN (2,3,4,5)
        my $title_classifications = $self->{schema}->resultset('Title')->search(
            {
                'me.id' => $id,
            },
            {
                select => ['title_classifications.field','title_classifications.classificationid','title_classifications.supplement'],
                as     => ['thisfield','thisclassificationid','thissupplement'],
                join   => ['title_classifications'],
            }
        );

        $mult = 1;
        foreach my $item ($title_classifications->all){
            my $field             = "T".sprintf "%04d",$item->get_column('thisfield');
            my $classificationid  =                    $item->get_column('thisclassificationid');
            my $supplement        =                    $item->get_column('thissupplement');

            my $record = OpenBib::Record::Classification->new({database=>$self->{database}});
            $record->load_name({id=>$classificationid});
            my $content = $record->name_as_string;

            $title_record->set_field({                
                field      => $field,
                id         => $classificationid,
                content    => $content,
                supplement => $supplement,
                mult       => $mult,
            });

            $mult++;
        }

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer Bestimmung der verknuepften Normdaten : ist ".timestr($timeall));
        }
    }
    
    # Verknuepfte Titel
    {
        my ($atime,$btime,$timeall)=(0,0,0);
        
        my $request;
        my $res;
        
        # Unterordnungen
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        my @sub = $self->get_connected_titles({ type => 'sub' });

        if (@sub){

            $title_record->set_field({                
                field      => 'T5001',
                content    => scalar(@sub),
                subfield   => '',
                mult       => 1,
            });

            my $mult = 1;
            foreach my $id (@sub){
                $title_record->set_field({                
                    field      => 'T5003',
                    content    => $id,
                    subfield   => '',
                    mult       => $mult,
                });

                $mult++;
            }
        }

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer  ist ".timestr($timeall));
        }

        # Ueberordnungen
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        my @super = $self->get_connected_titles({ type => 'super' });

        if (@super){
            $title_record->set_field({                
                field      => 'T5002',
                content    => scalar(@super),
                subfield   => '',
                mult       => 1,
            });

            my $mult = 1;
            foreach my $id (@super){
                $title_record->set_field({                
                    field      => 'T5004',
                    content    => $id,
                    subfield   => '',
                    mult       => $mult,
                });

                $mult++;
            }
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit ist ".timestr($timeall));
        }

    }

    # Exemplardaten
    my $holding_ref=[];
    {
        
        # DBI: "select distinct targetid from conn where sourceid= ? and sourcetype=1 and targettype=6";

        my $title_holdings = $self->{schema}->resultset('Title')->search(
            {
                'me.id' => $id,
            },
            {
                select   => ['title_holdings.holdingid'],
                as       => ['thisholdingid'],
                group_by => ['title_holdings.holdingid'], # = distinct holdingid
                join     => ['title_holdings'],
            }
        );

        foreach my $item ($title_holdings->all){
            my $holdingid =                    $item->get_column('thisholdingid');

            push @$holding_ref, $self->_get_holding({
                id             => $holdingid,
            });
        }
    }

    # Ausleihinformationen der Exemplare
    my $circulation_ref = [];
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
            $circulation_ref = $circexlist;
        }

        # Anreichern mit Bibliotheksinformationen
        if (exists $circinfotable->{$self->{database}}{circ}
                && @{$circulation_ref}) {
            for (my $i=0; $i < scalar(@{$circulation_ref}); $i++) {
                
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
                
                $circulation_ref->[$i]{'Bibliothek'} = $bibliothek;
                $circulation_ref->[$i]{'Bibinfourl'} = $bibinfourl;
                $circulation_ref->[$i]{'Ausleihurl'} = $circinfotable->{$self->{database}}{circurl};
            }
        }
        else {
            $circulation_ref=[];
        }
    }

    $title_record->set_holding($holding_ref);
    $title_record->set_circulation($circulation_ref);

    return $title_record;
}

sub load_brief_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $title_record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });

    # Titel-ID und zugehoerige Datenbank setzen

    $self->connectDB($self->{database});
    
    my ($atime,$btime,$timeall)=(0,0,0);
    
    if ($config->{benchmark}) {
        $atime  = new Benchmark;
    }

    $logger->debug("Getting cached brief title for id $id");
    
    # DBI: "select listitem from title_listitem where id = ?"
    my $record = $self->{schema}->resultset('Title')->single(
        {
            'id' => $id,
        },
    );

    my $record_exists = 0;
    
    if ($record){
        $title_record->set_normdata_from_json($record->titlecache);
        $record_exists = 1;
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        my $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung der gesamten Informationen         : ist ".timestr($timeall));
    }

    return $title_record;
}

sub _get_holding {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->instance;
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    
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

    # DBI "select category,content,indicator from holding where id = ?";
    my $holding_fields = $self->{schema}->resultset('Holding')->search(
        {
            'me.id' => $id,
        },
        {
            select => ['holding_fields.field','holding_fields.mult','holding_fields.subfield','holding_fields.content'],
            as     => ['thisfield','thismult','thissubfield','thiscontent'],
            join   => ['holding_fields'],
        }
    );
    
    foreach my $item ($holding_fields->all){
        my $field    = "X".sprintf "%04d",$item->get_column('thisfield');
        my $subfield =                    $item->get_column('thissubfield');
        my $mult     =                    $item->get_column('thismult');
        my $content  =                    $item->get_column('thiscontent');
        
        # Exemplar-Normdaten werden als nicht multipel angenommen
        # und dementsprechend vereinfacht in einer Datenstruktur
        # abgelegt
        $normset_ref->{$field} = {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };
        
    }
    
    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer die Bestimmung der Exemplardaten : ist ".timestr($timeall));
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

    $logger->debug(YAML::Dump($normset_ref));
    
    return $normset_ref;
}

sub get_number_of_titles {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type}              : 'sub'; # sub oder super

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Ausgabe der Anzahl verk"upfter Titel
    my $titlecount;
    if ($type eq "sub"){
        # DBI "select count(distinct targetid) as conncount from conn where sourceid=? and sourcetype=1 and targettype=1";
        $titlecount = $self->{schema}->resultset('TitleTitle')->search(
            {
                'me.source_titleid'            => $id,
            },
            {
                select   => ['target_titleid'],
                as       => ['thistitleid' ], 
                group_by => ['target_titleid'], # via group_by und nicht via distinct (Performance)
                
            }
        )->count;
    }
    elsif ($type eq "super"){
        # DBI "select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=1";
        $titlecount = $self->{schema}->resultset('TitleTitle')->search(
            {
                'me.target_titleid'                 => $id,
            },
            {
                select   => ['source_titleid'],
                as       => ['thistitleid'], 
                group_by => ['source_titleid'], # via group_by und nicht via distinct (Performance)
                
            }
        )->count;
    }
    
    return $titlecount,
}

sub get_connected_titles {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type}              : 'sub'; # sub oder super

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Ausgabe der Anzahl verk"upfter Titel

    my $titles;
    if ($type eq "sub"){
        # DBI "select distinct targetid as titleid from conn where sourceid=? and sourcetype=1 and targettype=1"
        $titles = $self->{schema}->resultset('TitleTitle')->search(
            {
                'me.source_titleid'            => $id,
            },
            {
                select   => ['target_titleid'],
                as       => ['thistitleid' ], 
                group_by => ['target_titleid'], # via group_by und nicht via distinct (Performance)
                
            }
        );
    }
    elsif ($type eq "super"){
        # DBI "select distinct sourceid as titleid from conn where targetid=? and sourcetype=1 and targettype=1";
        $titles = $self->{schema}->resultset('TitleTitle')->search(
            {
                'me.target_titleid'                 => $id,
            },
            {
                select   => ['source_titleid'],
                as       => ['thistitleid'], 
                group_by => ['source_titleid'], # via group_by und nicht via distinct (Performance)
                
            }
        );
    }
    else {
        return undef;
    }

    my @titles = ();
    foreach my $item ($titles->all){
        push @titles, $item->get_column('thistitleid');
    }
    
    return @titles;
}

sub get_fields {
    my ($self)=@_;

    return $self->{_normdata}
}

sub get_holding {
    my ($self)=@_;

    return $self->{_holding}
}

sub get_circulation {
    my ($self)=@_;

    return $self->{_circulation}
}

sub record_exists {
    my ($self) = @_;

    return $self->{_exists};
}

sub connectDB {
    my $self = shift;
    my $database = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    eval {
        # UTF8: {'pg_enable_utf8'    => 1} 
        $self->{schema} = OpenBib::Schema::Catalog->connect("DBI:Pg:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},{'pg_enable_utf8'    => 1 }) or $logger->error_die($DBI::errstr);
    };

    if ($@){
        $logger->fatal("Unable to connect schema to database $config->{dbname}: DBI:Pg:dbname=$config->{dbname};host=$config->{dbhost};port=$config->{dbport}");
    }

    return;

}

1;
