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
use Benchmark ':hireswallclock';
use DBIx::Class::ResultClass::HashRefInflator;
use JSON::XS;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Conv::Config;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Schema::Catalog;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Classification;
use OpenBib::Record::Subject;
use OpenBib::RecordList::Title;
use OpenBib::User;
use OpenBib::Statistics;

sub new {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Set defaults
    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}         : undef;

    my $id              = exists $arg_ref->{id}
        ? $arg_ref->{id}               : undef;

    my $self = { };

    bless ($self, $class);

    $self->{database} = $database;
    $self->{id}       = $id;
    
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

    my $recordlist = new OpenBib::RecordList::Title();

    eval {
        my $titles = $self->{schema}->resultset('Title')->search_rs(
            undef,
            {
                order_by => ['tstamp_create DESC'],
                rows     => $limit,
            }
        );
        
        while (my $title = $titles->next){
            $logger->debug("Adding Title ".$title->id);
            $recordlist->add(new OpenBib::Record::Title({ database => $self->{database} , id => $title->id, date => $title->tstamp_create}));
        }
    };
        
    if ($@){
        $logger->fatal($@);
    }
    
    return $recordlist;
}

sub get_recent_titles_of_person {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}               : undef;

    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $recordlist = new OpenBib::RecordList::Title();

    eval {
        my $titles = $self->{schema}->resultset('Title')->search_rs(
            {
                'title_people.personid' => $id,
            },
            {
                join     => ['title_people'],
                order_by => ['me.tstamp_create DESC'],
                rows     => $limit,
            }
        );

        while (my $title = $titles->next){
            $logger->debug("Adding Title ".$title->id);
            $recordlist->add(new OpenBib::Record::Title({ database => $self->{database} , id => $title->id, date => $title->tstamp_create}));
        }
    };

    if ($@){
        $logger->fatal($@);
    }
    
    return $recordlist;
}

sub get_recent_titles_of_corporatebody {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}               : undef;

    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $recordlist = new OpenBib::RecordList::Title();

    eval {
        my $titles = $self->{schema}->resultset('Title')->search_rs(
            {
                'title_corporatebodies.corporatebodyid' => $id,
            },
            {
                join     => ['title_corporatebodies'],
                order_by => ['me.tstamp_create DESC'],
                rows     => $limit,
            }
        );
        
        while (my $title = $titles->next){
            $logger->debug("Adding Title ".$title->id);
            $recordlist->add(new OpenBib::Record::Title({ database => $self->{database} , id => $title->id, date => $title->tstamp_create}));
        }
    };
        
    if ($@){
        $logger->fatal($@);
    }
    
    return $recordlist;
}

sub get_recent_titles_of_classification {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}               : undef;

    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $recordlist = new OpenBib::RecordList::Title();

    eval {
        my $titles = $self->{schema}->resultset('Title')->search_rs(
            {
                'title_classifications.classificationid' => $id,
            },
            {
                join     => ['title_classifications'],
                order_by => ['me.tstamp_create DESC'],
                rows     => $limit,
            }
        );
        
        while (my $title = $titles->next){
            $logger->debug("Adding Title ".$title->id);
            $recordlist->add(new OpenBib::Record::Title({ database => $self->{database} , id => $title->id, date => $title->tstamp_create}));
        }
    };
        
    if ($@){
        $logger->fatal($@);
    }
    
    return $recordlist;
}

sub get_recent_titles_of_subject {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}               : undef;

    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $recordlist = new OpenBib::RecordList::Title();

    eval {
        my $titles = $self->{schema}->resultset('Title')->search_rs(
            {
                'title_subjects.subjectid' => $id,
            },
            {
                join     => ['title_subjects'],
                order_by => ['me.tstamp_create DESC'],
                rows     => $limit,
            }
        );
        
        while (my $title = $titles->next){
            $logger->debug("Adding Title ".$title->id);
            $recordlist->add(new OpenBib::Record::Title({ database => $self->{database} , id => $title->id, date => $title->tstamp_create}));
        }
    };
        
    if ($@){
        $logger->fatal($@);
    }
    
    return $recordlist;
}

sub load_full_title_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config        = OpenBib::Config->instance;
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    my $title_record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });

    eval {
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
                    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );
            
            while (my $item = $title_fields->next){
                my $field    = "T".sprintf "%04d",$item->{thisfield};
                my $subfield =                    $item->{thissubfield};
                my $mult     =                    $item->{thismult};
                my $content  =                    $item->{thiscontent};
                
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
                    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );

            if ($title_persons){
                my $mult = 1;
                while (my $item = $title_persons->next){
                    my $field      = "T".sprintf "%04d",$item->{thisfield};
                    my $personid   =                    $item->{thispersonid};
                    my $supplement =                    $item->{thissupplement};
                    
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
                    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );

            if ($title_corporatebodies){
                my $mult = 1;        
                while (my $item = $title_corporatebodies->next){
                    my $field             = "T".sprintf "%04d",$item->{thisfield};
                    my $corporatebodyid   =                    $item->{thiscorporatebodyid};
                    my $supplement        =                    $item->{thissupplement};
                    
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
                    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );

            if ($title_subjects){
                my $mult = 1;
                while (my $item = $title_subjects->next){
                    my $field             = "T".sprintf "%04d",$item->{thisfield};
                    my $subjectid         =                    $item->{thissubjectid};
                    my $supplement        =                    $item->{thissupplement};
                    
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
                    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );

            if ($title_classifications){
                my $mult = 1;
                while (my $item = $title_classifications->next){
                    my $field             = "T".sprintf "%04d",$item->{thisfield};
                    my $classificationid  =                    $item->{thisclassificationid};
                    my $supplement        =                    $item->{thissupplement};
                    
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
        }
        
        # Verknuepfte Titel
        {
            my ($atime,$btime,$timeall)=(0,0,0);
            
            my $request;
            my $res;
            
            # Unterordnungen
            # Super wird durch meta2sql.pl im Kontext der Anreicherung mit
            # Informationen der uebergeordneten Titelaufnahme erzeugt.

#             if ($config->{benchmark}) {
#                 $atime=new Benchmark;
#             }
            
#             my @sub = $self->get_connected_titles({ type => 'sub', id => $id });
            
#             if (@sub){
                
#                 $title_record->set_field({                
#                     field      => 'T5001',
#                     content    => scalar(@sub),
#                     subfield   => '',
#                     mult       => 1,
#                 });
                
#                 my $mult = 1;
#                 foreach my $id (@sub){
#                     $title_record->set_field({
#                         field      => 'T5003',
#                         content    => $id,
#                         subfield   => '',
#                         mult       => $mult,
#                     });
                    
#                     $mult++;
#                 }
#             }
            
#             if ($config->{benchmark}) {
#                 $btime=new Benchmark;
#                 $timeall=timediff($btime,$atime);
#                 $logger->info("Zeit fuer  ist ".timestr($timeall));
#             }
            
            # Ueberordnungen
            # Super wird durch meta2sql.pl im Kontext der Anreicherung mit
            # Informationen der uebergeordneten Titelaufnahme erzeugt.
            
            if ($config->{benchmark}) {
                $atime=new Benchmark;
            }


            my @super = $self->get_connected_titles({ type => 'super', id => $id });
            
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
            
            my $title_holdings = $self->{schema}->resultset('TitleHolding')->search(
                {
                    'titleid' => $id,
                },
                {
                    select   => ['holdingid'],
                    as       => ['thisholdingid'],
                    group_by => ['holdingid'], # = distinct holdingid
                    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );
            
            while (my $item = $title_holdings->next()){
                my $holdingid =                    $item->{thisholdingid};

                $logger->debug("Got holdingid $holdingid for titleid $id");

                push @$holding_ref, $self->_get_holding({
                    id             => $holdingid,
                });
            }
        }
        
        $logger->debug(YAML::Dump($title_record->get_fields));
        $title_record->set_holding($holding_ref);
    };

    if ($@){
        $logger->fatal($@);
    }
    
    return $title_record;
}

sub load_brief_title_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $title_record = new OpenBib::Record::Title({ database => $self->{database}, id => $id });
    
    eval {
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
            $title_record->set_fields_from_json($record->titlecache);
            $record_exists = 1;
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            my $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung der gesamten Informationen         : ist ".timestr($timeall));
        }
    };

    if ($@){
        $logger->fatal($@);
    }
    
    return $title_record;
}

sub load_conv_config {
    my $self = shift;

    if ($self->{database}){
        $self->{_conv_config} = new OpenBib::Conv::Config({dbname => $self->{database}});
    }

    return $self;
}

sub get_conv_config {
    my $self = shift;

    return $self->{_conv_config};
}

sub create_index_document {
    my ($self,$titleid) = @_;

    return $self unless ($self->{database} && $titleid);

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $index_doc = OpenBib::Index::Document->new({ database => $self->{database}, id => $titleid });

    my $thisyear = `date +"%Y"`;

    my $record = $self->load_full_title_record({ id => $titleid });

    my $conv_config = $self->get_conv_config;
    
    # 1) Data bestimmen und setzen
    
    my $statistics = new OpenBib::Statistics;
    my $user       = new OpenBib::User;

    my $popularity = $statistics->{schema}->resultset('Titleusage')->search(
        {
            dbname  => $self->{database},
            origin  => 1,
            id      => $titleid,
        }
    )->count;
    
    if (exists $self->{_conv_config}->{'listitemcat'}{popularity}) {

    }
    
    $index_doc->add_index('popularity',1, $popularity);
    
    my $tags_ref = [];
    {
        my $tags = $user->{schema}->resultset('TitTag')->search(
            {
                'me.dbname' => $self->{database},
                'me.titleid' => $titleid,
            },
            {
                select => ['tagid.name','tagid.id'],
                as     => ['thistagname','thistagid'],
                join => ['tagid'],
            }
        );

        foreach my $tag ($tags->all){
            my $tagname = $tag->get_column('thistagname');
            my $tagid   = $tag->get_column('thistagid');

            push @$tags_ref, { tag => $tagname, id => $tagid };
        }
        
        if (exists $self->{_conv_config}->{'listitemcat'}{tags}) {

        }
    }

    my $litlists_ref = [];
    
    {
        my $litlists = $user->{schema}->resultset('Litlist')->search(
            {
                'litlistitems.dbname' => $self->{database},
                'litlistitems.titleid' => $titleid,
            },
            {
                select => ['me.title','me.id'],
                as     => ['thislitlisttitle','thislitlistid'],
                join => ['litlistitems'],
            }
        );
        
        foreach my $litlist ($litlists->all){
            my $litlisttitle = $litlist->get_column('thislitlisttitle');
            my $litlistid    = $litlist->get_column('thislitlistid');
            
            push @{$litlists_ref}, { title => $litlisttitle, id => $litlistid };
            
        }
    }

    foreach my $field (keys %{$self->{_conv_config}->{'listitemcat'}}){
        if ($field eq "popularity" && $popularity){
            $index_doc->set_data('popularity',$popularity) if ($popularity);
        }
        elsif ($field eq "tags"){
            $index_doc->add_data('tag',$tags_ref);
        }
        elsif ($field eq "litlists"){
            $index_doc->add_data('litlist',$litlists_ref);
        }
        elsif ($record->has_field("T".$field)){
            foreach my $item_ref (@{$record->get_field({field => "T".$field})}){
                $index_doc->add_data("T".$field, $item_ref);
            }
        }
    }

    my @personcorporatebody = ();
    
    # Inhalte aus Normdaten (Personen, Schlagworte, usw.) hinzufuegen
    {
        # Verfasser/Personen
        foreach my $field ('0100','0101','0102','0103','1800') {
            # Anreicherung mit Informationen der Ueberordnung

            if ($record->has_field("T5005")) {
                eval {
                    foreach my $super (@{$record->get_field({field => "T5005"})}){
                        my $super_ref = decode_json $super->{content};

                        if (defined $super_ref->{$field}) {
                            # Anreichern der Titelinformationen
                            foreach my $item_ref (@{$super_ref->{$field}}) {
                                $record->set_field({field => "T$field", content => $item_ref->{content}, id => $item_ref->{id}});
                            }
                        }

                    }
                };

                if ($@){
                    $logger->error($@);
                }
            }
            
            if ($record->has_field("T".$field)) {
                foreach my $item_ref (@{$record->get_field({ field => "T".$field })}) {
                    push @personcorporatebody, $item_ref->{content};

                    if ($item_ref->{id}){
                        my $person = new OpenBib::Record::Person({ database => $self->{database}, id => $item_ref->{id} })->load_full_record;

                        $index_doc->add_index('personid',1, ['id',$item_ref->{id}]);

                        foreach my $normdata_field (keys %{$person->get_fields}){
                            $normdata_field=~s/^.//;
                            foreach my $normdataitem_ref (@{$person->get_field({ field => "P".$normdata_field})}) {
                                if (exists $conv_config->{inverted_person}{$normdata_field}->{index}) {
                                    foreach my $searchfield (keys %{$conv_config->{inverted_person}{$normdata_field}->{index}}) {
                                        my $weight = $conv_config->{inverted_person}{$normdata_field}->{index}{$searchfield};
                                        $index_doc->add_index($searchfield,$weight, ["P$normdata_field",$normdataitem_ref->{content}]);
                                    }
                                }
                            }
                        }       
                    }
                    else {
                    }
                    
                }
            }
        }

        #Koerperschaften/Urheber
        foreach my $field ('0200','0201','1802') {
            if ($record->has_field("T".$field)) {
                foreach my $item_ref (@{$record->get_field({ field => "T".$field })}) {
                    push @personcorporatebody, $item_ref->{content};
                    
                    if ($item_ref->{id}){
                        my $corporatebody = new OpenBib::Record::CorporateBody({ database => $self->{database}, id => $item_ref->{id} })->load_full_record;

                        $index_doc->add_index('corporatebodyid',1, ['id',$item_ref->{id}]);
                        
                        foreach my $normdata_field (keys %{$corporatebody->get_fields}){
                            $normdata_field=~s/^.//;
                            foreach my $normdataitem_ref (@{$corporatebody->get_field({ field => "C".$normdata_field})}) {
                                if (exists $conv_config->{inverted_corporatebody}{$normdata_field}->{index}) {
                                    foreach my $searchfield (keys %{$conv_config->{inverted_corporatebody}{$normdata_field}->{index}}) {
                                        my $weight = $conv_config->{inverted_corporatebody}{$normdata_field}->{index}{$searchfield};
                                        $index_doc->add_index($searchfield,$weight, ["C$normdata_field",$normdataitem_ref->{content}]);
                                    }
                                }
                            }
                        }       
                    }
                    else {
                    }
                    
                }
            }
        }

        # Klassifikation
        foreach my $field ('0700') {
            if ($record->has_field("T".$field)) {
                foreach my $item_ref (@{$record->get_field({ field => "T".$field })}) {
                    if ($item_ref->{id}){
                        my $classification = new OpenBib::Record::Classification({ database => $self->{database}, id => $item_ref->{id} })->load_full_record;

                        $index_doc->add_index('classificationid',1, ['id',$item_ref->{id}]);
                        
                        foreach my $normdata_field (keys %{$classification->get_fields}){
                            $normdata_field=~s/^.//;
                            foreach my $normdataitem_ref (@{$classification->get_field({ field => "N".$normdata_field})}) {
                                if (exists $conv_config->{inverted_classification}{$normdata_field}->{index}) {
                                    foreach my $searchfield (keys %{$conv_config->{inverted_classification}{$normdata_field}->{index}}) {
                                        my $weight = $conv_config->{inverted_classification}{$normdata_field}->{index}{$searchfield};
                                        $index_doc->add_index($searchfield,$weight, ["N$normdata_field",$normdataitem_ref->{content}]);
                                    }
                                }
                            }
                        }       
                    }
                    else {
                    }
                    
                }
            }
        }

        # Schlagworte
        foreach my $field ('0710','0902','0907','0912','0917','0922','0927','0932','0937','0942','0947') {
            if ($record->has_field("T".$field)) {
                foreach my $item_ref (@{$record->get_field({ field => "T".$field })}) {
                    if ($item_ref->{id}){
                        my $subject = new OpenBib::Record::Subject({ database => $self->{database}, id => $item_ref->{id} })->load_full_record;

                        $index_doc->add_index('subjectid',1, ['id',$item_ref->{id}]);
                        
                        foreach my $normdata_field (keys %{$subject->get_fields}){
                            $normdata_field=~s/^.//;
                            foreach my $normdataitem_ref (@{$subject->get_field({ field => "S".$normdata_field})}) {
                                if (exists $conv_config->{inverted_subject}{$normdata_field}->{index}) {
                                    foreach my $searchfield (keys %{$conv_config->{inverted_subject}{$normdata_field}->{index}}) {
                                        my $weight = $conv_config->{inverted_subject}{$normdata_field}->{index}{$searchfield};
                                        $index_doc->add_index($searchfield,$weight, ["S$normdata_field",$normdataitem_ref->{content}]);
                                    }
                                }
                            }
                        }       
                    }
                    else {
                    }
                    
                }
            }
        }

        # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung
        $index_doc->add_data('PC0001', {
            content   => join(" ; ",@personcorporatebody),
        });        

        # Suchmaschineneintraege mit den Tags, Literaturlisten und Standard-Titelkategorien fuellen
        foreach my $field (keys %{$conv_config->{inverted_title}}){
            # a) Indexierung in der Suchmaschine
            if (exists $conv_config->{inverted_title}{$field}->{index}){
                
                my $flag_isbn = 0;
                # Wird dieses Feld als ISBN genutzt, dann zusaetzlicher Inhalt
                foreach my $searchfield (keys %{$conv_config->{inverted_title}{$field}->{index}}) {
                    if ($searchfield eq "isbn"){
                        $flag_isbn=1;
                    }
                }
                
                foreach my $searchfield (keys %{$conv_config->{inverted_title}{$field}->{index}}) {
                    my $weight = $conv_config->{inverted_title}{$field}->{index}{$searchfield};
                    next unless ($record->has_field("T".$field));

                    foreach my $item_ref (@{$record->get_field({ field => "T".$field })}) {
                        next unless $item_ref->{content};
                        
                        $index_doc->add_index($searchfield,$weight, ["T$field",$item_ref->{content}]);
                        
                        # Wird diese Kategorie als isbn verwendet?
                        if ($flag_isbn) {
                            # Alternative ISBN zur Rechercheanreicherung erzeugen
                            my $isbn = Business::ISBN->new($item_ref->{content});
                            
                            if (defined $isbn && $isbn->is_valid) {
                                my $isbnXX;
                                if (!$isbn->prefix) { # ISBN10 haben kein Prefix
                                    $isbnXX = $isbn->as_isbn13;
                                } else {
                                    $isbnXX = $isbn->as_isbn10;
                                }
                                
                                if (defined $isbnXX) {
                                    my $enriched_isbn = $isbnXX->as_string;
                                    
                                    $enriched_isbn = lc($enriched_isbn);
                                    $enriched_isbn=~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8$9$10$11$12$13/g;
                                    $enriched_isbn=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8$9$10/g;
                                    
                                    $index_doc->add_index($searchfield,$weight, ["T$field",$enriched_isbn]);
                                }
                            }
                        }
                    }
                }
            }

            # b) Facetten in der Suchmaschine
            if (exists $conv_config->{inverted_title}{$field}->{facet}){
                foreach my $searchfield (keys %{$conv_config->{inverted_title}{$field}->{facet}}) {
                    if ($field eq "tag"){
                        foreach my $tag_ref (@$tags_ref){
                            $index_doc->add_facet("facet_$searchfield", $tag_ref->{tag});
                        }
                    }
                    elsif ($field eq "litlist"){
                        foreach my $litlist_ref (@$litlists_ref){
                            $index_doc->add_facet("facet_$searchfield", $litlist_ref->{title});
                        }
                    }            
                    else {
                        next unless ($record->has_field("T".$field));

                        foreach my $item_ref (@{$record->get_field({ field => "T".$field })}) {
                            $index_doc->add_facet("facet_$searchfield", $item_ref->{content}); 
                        }
                    }
                }
            }
        }
    }

    {
        foreach my $holding_ref (@{$record->get_holding}){
            foreach my $field (keys %{$holding_ref}) {
                next if ($field eq "id" || defined $conv_config->{blacklist_holding}{$field} );

                next unless ($holding_ref->{$field}{content});

                $field=~s/^.//;
                
                if (exists $conv_config->{inverted_holding}{$field}->{index}) {
                    foreach my $searchfield (keys %{$conv_config->{inverted_holding}{$field}->{index}}) {
                        my $weight = $conv_config->{inverted_holding}{$field}->{index}{$searchfield};
                        
                        $index_doc->add_index($searchfield, $weight, ["X$field",$holding_ref->{"X".$field}{content}]); # value is arrayref
                    }
                }
            }
        }
    }

    {
        # Jahreszahlen umwandeln
        if ($record->has_field('0425')) {
            foreach my $item_ref (@{$record->get_field({ field => '0425'})}){
                my $date = $item_ref->{content};
                
                if ($date =~/^(\d\d\d\d)\s*-\s*(\d\d\d\d)/) {
                    my $startyear = $1;
                    my $endyear   = $2;
                    
                    $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                    for (my $year=$startyear;$year<=$endyear; $year++) {
                        $logger->debug("Enriching year $year");
                        $index_doc->add_index('year',1, ['T0425',$year]);
                        $index_doc->add_index('freesearch',1, ['T0425',$year]);
                    }
                }
            }
        }
        
        # Bestandsverlauf in Jahreszahlen umwandeln
        foreach my $holding_ref (@{$record->get_holding}){
            if ((defined $holding_ref->{'1204'})) {        
                
                foreach my $date (split(";",$holding_ref->{'1204'}[0]{content})) {
                    if ($date =~/^.*?(\d\d\d\d)[^-]+?\s+-\s+.*?(\d\d\d\d)/) {
                        my $startyear = $1;
                        my $endyear   = $2;
                        
                        $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                        for (my $year=$startyear;$year<=$endyear; $year++) {
                            $logger->debug("Enriching year $year");
                            $index_doc->add_index('year',1, ['T0425',$year]);
                            $index_doc->add_index('freesearch',1, ['T0425',$year]);
                        }
                    }
                    elsif ($date =~/^.*?(\d\d\d\d)[^-]+?\s+-/) {
                        my $startyear = $1;
                        my $endyear   = $thisyear;
                        $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                        for (my $year=$startyear;$year<=$endyear;$year++) {
                            $logger->debug("Enriching year $year");
                            $index_doc->add_index('year',1, ['T0425',$year]);
                            $index_doc->add_index('freesearch',1, ['T0425',$year]);
                        }                
                    }
                    elsif ($date =~/(\d\d\d\d)/) {
                        $logger->debug("Not expanding $date, just adding year $1");
                        $logger->debug("Enriching year $1");
                        $index_doc->add_index('year',1, ['T0425',$1]);
                        $index_doc->add_index('freesearch',1, ['T0425',$1]);
                    }
                }
            }
        }
    }
    # Potentiell fehlender Titel fuer Index-Data zusammensetzen
    {
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
        if (!$record->has_field('T0331')) {
            # UnterFall 2.1:
            if ($record->has_field('T0089')) {
                $index_doc->add_data('T0331',{
                    content => $record->get_field({ field => 'T0089' })->[0]{content}
                });
            }
            # Unterfall 2.2:
            elsif ($record->has_field('0455')) {
                $index_doc->add_data('T0331',{
                    content => $record->get_field({ field => 'T0455' })->[0]{content}
                });
            }
            # Unterfall 2.3:
            elsif ($record->has_field('0451')) {
                $index_doc->add_data('T0331',{
                    content => $record->get_field({ field => 'T0451' })->[0]{content}
                });
            }
            # Unterfall 2.4:
            elsif ($record->has_field('1203')) {
                $index_doc->add_data('T0331',{
                    content => $record->get_field({ field => 'T1203' })->[0]{content}
                });
            }
            else {
                $index_doc->add_data('T0331',{
                    content => "Kein Titel vorhanden"
                });
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
        if ($record->has_field('0089')) {
            $index_doc->set_data('T5100', [
                {
                    content => $record->get_field({ field => 'T0089' })->[0]{content}
                }
            ]);
        }
        # Fall 2:
        elsif ($record->has_field('0455')) {
            $index_doc->set_data('T5100', [
                {
                    content => $record->get_field({ field => 'T0455' })->[0]{content}
                }
            ]);
        }
    }
    
    # Exemplardaten (X0014) immer!
    foreach my $holding_ref (@{$record->get_holding}){
        $index_doc->add_data('X0014', {
            content => $holding_ref->{"X0014"}{content},
        });
    }
    
    return $index_doc;
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
    
    my $fields_ref={};

    $fields_ref->{id}=$id;
    
    # Defaultwerte setzen
    $fields_ref->{X0005}{content}="-";
    $fields_ref->{X0014}{content}="-";
    $fields_ref->{X0016}{content}="-";
    $fields_ref->{X1204}{content}="-";
    $fields_ref->{X4000}{content}="-"; # Katalogname
    $fields_ref->{X4001}{content}="";  # Katalog-URL laut Admin
    
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
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    while (my $item = $holding_fields->next){
        my $field    = "X".sprintf "%04d",$item->{thisfield};
        my $subfield =                    $item->{thissubfield};
        my $mult     =                    $item->{thismult};
        my $content  =                    $item->{thiscontent};
        
        # Exemplar-Normdaten werden als nicht multipel angenommen
        # und dementsprechend vereinfacht in einer Datenstruktur
        # abgelegt
        $fields_ref->{$field} = {
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
    if (exists $fields_ref->{X3330}{content}) {
        $sigel=$fields_ref->{X3330}{content};
        if (exists $dbinfotable->{sigel}{$sigel}) {
            $fields_ref->{X4000}{content}=$dbinfotable->{sigel}{$sigel};
        }
        else {
            $fields_ref->{X4000}{content}= {
					     full  => "($sigel)",
					     short => "($sigel)",
					    };
        }
    }
    # sonst wird der Datenbankname zur Findung des Sigels herangezogen
    else {
        $sigel=$dbinfotable->{dbases}{$self->{database}};
        if (exists $dbinfotable->{sigel}{$sigel}) {
            $fields_ref->{X4000}{content}=$dbinfotable->{sigel}{$sigel};
        }
    }

    my $bibinfourl="";

    # Bestimmung der Bibinfo-Url
    if (exists $dbinfotable->{bibinfo}{$sigel}) {
        $fields_ref->{X4001}{content}=$dbinfotable->{bibinfo}{$sigel};
    }

    $logger->debug(YAML::Dump($fields_ref));
    
    return $fields_ref;
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

    return 0 unless ($self->{schema});

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

    return () unless ($self->{schema});

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
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',                
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
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',                
            }
        );
    }
    else {
        return undef;
    }

    my @titles = ();
    while (my $item = $titles->next){
        push @titles, $item->{thistitleid};
    }

    $logger->debug("Related title id's for type $type and id $id :".YAML::Dump(@titles));
    
    return @titles;
}

sub get_fields {
    my ($self)=@_;

    return $self->{_fields}
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

sub get_bibliographic_counters {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($title_count,$title_journalcount,$title_articlecount,$title_digitalcount,$person_count,$corporatebody_count,$classification_count,$subject_count,$holding_count)=
        (0,0,0,0,0,0,0,0,0);

    eval {
        $person_count = $self->{schema}->resultset('Person')->count;
        $corporatebody_count = $self->{schema}->resultset('Corporatebody')->count;
        $classification_count = $self->{schema}->resultset('Classification')->count;
        $subject_count = $self->{schema}->resultset('Subject')->count;
        $holding_count = $self->{schema}->resultset('Holding')->count;
        
	# Gesamt-Titelzahl bestimmen;
	$title_count = $self->{schema}->resultset('Title')->count;
	
	# Serien/Zeitschriften bestimmen
	# DBI "select count(distinct id) as rowcount from title where category=800 and content = 'Zeitschrift/Serie'"
	$title_journalcount = $self->{schema}->resultset('TitleField')->search(
	    {
		'field'                   => '4410',
		'content'                 => 'Zeitschrift/Serie',
	    },
	    {
		select   => ['titleid'],
		as       => ['thistitleid'], 
		group_by => ['titleid'], # via group_by und nicht via distinct (Performance)
		
	    }
	    )->count;
	
	# Aufsaetze bestimmen
	# DBI "select count(distinct id) as rowcount from title where category=800 and content = 'Aufsatz'"
	$title_articlecount = $self->{schema}->resultset('TitleField')->search(
	    {
		'field'                   => '4410',
		'content'                 => 'Aufsatz',
	    },
	    {
		select   => ['titleid'],
		as       => ['thistitleid'], 
		group_by => ['titleid'], # via group_by und nicht via distinct (Performance)
		
	    }
	    )->count;
	
	# E-Median bestimmen
	# DBI "select count(distinct id) as rowcount from title where category=800 and content = 'Digital'"
	$title_digitalcount = $self->{schema}->resultset('TitleField')->search(
	    {
		'field'                   => '4410',
		'content'                 => 'Digital',
	    },
	    {
		select   => ['titleid'],
		as       => ['thistitleid'], 
		group_by => ['titleid'], # via group_by und nicht via distinct (Performance)
		
	    }
        )->count;

    };

    if ($@){
        $logger->error($@);
    }

    return {
        person_count => $person_count,
        corporatebody_count => $corporatebody_count,
        classification_count => $classification_count,
        subject_count => $subject_count,
        holding_count => $holding_count,
        title_count => $title_count,
        title_journalcount => $title_journalcount,
        title_articlecount => $title_articlecount,
        title_digitalcount => $title_digitalcount,
    };
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
        return 0;
    }

    return 1;
}

1;
