#####################################################################
#
#  OpenBib::Record::Title.pm
#
#  Titel
#
#  Dieses File ist (C) 2007-2016 Oliver Flimm <flimm@openbib.org>
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

use Cache::Memcached::Fast;
use Benchmark ':hireswallclock';
use Business::ISBN;
use DBIx::Class::ResultClass::HashRefInflator;
use DBI;
use Digest::MD5;
use Encode 'decode_utf8';
use HTML::Entities;
use HTML::Strip;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use SOAP::Lite;
use Storable qw(freeze thaw);
use XML::LibXML;
use YAML ();

use OpenBib::Catalog::Factory;
use OpenBib::Config;
use OpenBib::Config::File;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Conv::Config;
use OpenBib::Index::Document;
use OpenBib::Schema::Catalog;
use OpenBib::Schema::Enrichment;
use OpenBib::Schema::DBI;
use OpenBib::ILS::Factory;
use OpenBib::L10N;
use OpenBib::Normalizer;
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

use base 'OpenBib::Record';

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $id        = exists $arg_ref->{id}
        ? $arg_ref->{id}             : undef;

    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}       : undef;

    my $locations = exists $arg_ref->{locations}
        ? $arg_ref->{locations}      : undef;

    my $date      = exists $arg_ref->{date}
        ? $arg_ref->{date}           : undef;

    my $listid    = exists $arg_ref->{listid}
        ? $arg_ref->{listid}         : undef;

    my $comment   = exists $arg_ref->{comment}
        ? $arg_ref->{comment}        : undef;

    my $config     = exists $arg_ref->{config}
        ? $arg_ref->{config}         : OpenBib::Config->new();
    
    my $sessionID  = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}      : undef;

    my $normalizer = exists $arg_ref->{normalizer}
    ? $arg_ref->{normalizer}         : OpenBib::Normalizer->new;
    

    my $generic_attributes = exists $arg_ref->{generic_attributes}
        ? $arg_ref->{generic_attributes}   : {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Creating Title-Object");
    
    my $self = { };

    bless ($self, $class);

    $self->{_config}          = $config;

    if ($normalizer){
	$self->{_normalizer}  =  $normalizer;
    }
    
    $logger->debug("Stage 1");
    
    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);
    
    $self->{client}        = $ua;

    my $dbinfotable        = OpenBib::Config::DatabaseInfoTable->new;

    $self->{dbinfo}        = $dbinfotable->{dbinfo};
    
    if (defined $database){
        $self->{database} = $database;
    }

    if (defined $locations){
        $self->set_locations($locations);
    }

    if (defined $id){
        $self->{id}       = $id;
    }

    if (defined $sessionID){
        $self->{sessionID} = $sessionID;
    }
    
    if (defined $date){
        $self->{date}     = $date;
    }

    if (defined $comment){
        $self->{comment}  = $comment;
    }
    
    if (defined $listid){
        $self->{listid}   = $listid;
    }

    if (defined $generic_attributes){
        $self->{generic_attributes}   = $generic_attributes;
    }

    if (defined $id && defined $database){
        $logger->debug("Title-Record-Object created with id $id in database $database");
    }

    $logger->debug("Object created");
    
    return $self;
}

sub get_config {
    my $self = shift;

    return $self->{_config};
}

sub load_full_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    # (Re-)Initialisierung
    delete $self->{_fields}         if (exists $self->{_fields});
    delete $self->{_holding}        if (exists $self->{_holding});
    delete $self->{_circulation}    if (exists $self->{_circulation});

    my $fields_ref   = {};

    $self->{id      }        = $id;

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    unless (defined $self->{id} && defined $self->{database}){
        ($self->{_fields},$self->{_holding},$self->{_circulation})=({},(),[]);

        $logger->error("Incomplete Record-Information Id: ".((defined $self->{id})?$self->{id}:'none')." Database: ".((defined $self->{database})?$self->{database}:'none'));
        return $self;
    }
        
    my $memc_key = "record:title:full:$self->{database}:$self->{id}";

    my $record;

    if ($config->{memc} && length ($memc_key) < 250 ){
      $record = $config->{memc}->get($memc_key);

      if ($logger->is_debug){
          $logger->debug("Got record from memcached: ".YAML::Dump($record));
      }

      if (defined $record->{fields} && defined $record->{holdings} && defined $record->{locations}){
          $self->set_fields($record->{fields});
          $self->set_holding($record->{holdings});
	  $self->set_locations($record->{locations});
          
          if ($config->{benchmark}) {
              $btime=new Benchmark;
              $timeall=timediff($btime,$atime);
              $logger->info("Total time for fetching fields/holdings from memcached is ".timestr($timeall));
          }
          
          return $self;
      }
    }
    
    my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $self->{database}, sessionID => $self->{sessionID}, config => $config });
    
    $record = $catalog->load_full_title_record({id => $id});
    
    if ($logger->is_debug){
        $logger->debug("Zurueck ".YAML::Dump($record->get_fields));
    }

    my $fields          = $record->get_fields;
    my $holdings        = $record->get_holding;
    my $same_records    = $record->get_same_records;
    my $similar_records = $record->get_similar_records;
    my $related_records = $record->get_related_records;


    $logger->debug("Setting data from Backend");
    
    # Location aus 4230 setzen    
    my $locations_ref = [];

    foreach my $item_ref (@{$fields->{'T4230'}}){
	push @{$locations_ref}, $item_ref->{content};
    }

    $self->set_locations($locations_ref);
    $self->set_fields($fields);
    $self->set_holding($holdings);
    $self->set_same_records($same_records);
    $self->set_related_records($related_records);
    $self->set_similar_records($similar_records);

    if ($config->{memc}){
        $config->{memc}->set($memc_key,{ fields => $fields, holdings => $holdings, locations => $locations_ref },$config->{memcached_expiration}{'record:title:full'});
        $logger->debug("Fetch record from db and store in memcached");
    }
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for is ".timestr($timeall));
    }

    $logger->debug("Full record loaded");

    return $self;
}

sub load_brief_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    # (Re-)Initialisierung
    delete $self->{_fields}       if (exists $self->{_fields});
    delete $self->{_holding}        if (exists $self->{_holding});
    delete $self->{_circulation}    if (exists $self->{_circulation});

    my $record_exists = 0;

    my $fields_ref   = {};

    $self->{id      }        = $id;

    unless (defined $self->{id} && defined $self->{database}){
        ($self->{_fields},$self->{_holding},$self->{_circulation})=({},(),[]);

        $logger->error("Incomplete Record-Information Id: ".((defined $self->{id})?$self->{id}:'none')." Database: ".((defined $self->{database})?$self->{database}:'none'));
        return $self;
    }

    my ($atime,$btime,$timeall)=(0,0,0);
    
    if ($config->{benchmark}) {
        $atime  = new Benchmark;
    }

    my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $self->{database}});
    
    my $record = $catalog->load_brief_title_record({id => $id});

    $fields_ref         = $record->get_fields;
    $record_exists      = $record->record_exists;

    # Titel-ID und zugehoerige Datenbank setzen

    $fields_ref->{id      } = $id;
    $fields_ref->{database} = $self->{database};

    # Location aus 4230 setzen
    
    my $locations_ref = [];

    foreach my $item_ref (@{$fields_ref->{'T4230'}}){
	push @{$locations_ref}, $item_ref->{content};
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        my $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung der gesamten Informationen         : ist ".timestr($timeall));
    }

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($fields_ref));
    }

    ($self->{_fields},$self->{_locations},$self->{_exists},$self->{_type})=($fields_ref,$locations_ref,$record_exists,'brief');

    return $self;
}

sub enrich_content {
    my ($self, $arg_ref) = @_;

    my $profilename = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}        : '';
    
    my $viewname = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}        : '';

    my $normalizer    = exists $arg_ref->{normalizer}
    ? $arg_ref->{normalizer}          :
	($self->{_normalizer})?$self->{_normalizer}:OpenBib::Normalizer->new;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;


    my ($atime,$btime,$timeall);
        
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    if (!exists $self->{enrich_schema}){
        $self->connectEnrichmentDB;
        if ($logger->is_debug){            
            $self->{enrich_schema}->storage->debug(1);
        }
    }

    return $self unless ($self->{database} && $self->{id});
    
    # ISBNs aus Anreicherungsdatenbank als subquery
    my $this_isbns = $self->{enrich_schema}->resultset('AllTitleByIsbn')->search_rs(
        { 
            dbname  => $self->{database},
            titleid => $self->{id},
        },
        {
            columns  => ['isbn'],
            group_by => ['isbn'],
        }
    );
    
    my $bibkey    = $self->get_field({field => 'T5050', mult => 1})  if ($self->has_field('T5050'));
    
    my @issn_refs = ();
    push @issn_refs, @{$self->get_field({field => 'T0543'})} if ($self->has_field('T0543'));                                           
    
    if ($logger->is_debug){
        $logger->debug("Enrichment ISSN's ".YAML::Dump(\@issn_refs));
    }
    
    my %seen_content = ();            
    
    my $mult_map_ref = {};
    
    if ($this_isbns){
        my @filter_databases = ($profilename)?$config->get_profiledbs($profilename):
            ($viewname)?$config->get_viewdbs($viewname):();


        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen vor Normdaten ".timestr($timeall));
        }

        if ($logger->is_debug){
            $logger->debug("Filtern Profile: $profilename / View: $viewname nach Datenbanken ".YAML::Dump(\@filter_databases));
        }
                
        # Anreicherung der Normdaten
        {
            # DBI "select distinct category,content from normdata where isbn=? order by category,indicator";
            my $enriched_contents = $self->{enrich_schema}->resultset('EnrichedContentByIsbn')->search_rs(
                {
                    isbn    => { -in => $this_isbns->as_query },
                },
                {
                    group_by => ['isbn','field','content','origin','subfield'],
                    order_by => ['field','content'],
                    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );
            
            while (my $item = $enriched_contents->next) {
                my $field      = "E".sprintf "%04d",$item->{field};
                my $subfield   =                    $item->{subfield};
                my $content    =                    $item->{content};
                
                if ($seen_content{$content}) {
                    next;
                }
                else {
                    $seen_content{$content} = 1;
                }
                my $mult = ++$mult_map_ref->{$field};
                $self->set_field({
                    field      => $field,
                    subfield   => $subfield,
                    mult       => $mult,
                    content    => $content,
                });
            }
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen / inkl Normdaten ist ".timestr($timeall));
        }
        
    }
    elsif ($bibkey){
        # DBI "select category,content from normdata where isbn=? order by category,indicator";
        my $enriched_contents = $self->{enrich_schema}->resultset('EnrichedContentByBibkey')->search_rs(
            {
                bibkey => $bibkey,
            },
            {                        
                group_by => ['field','content','bibkey','origin','subfield'],
                order_by => ['field','content'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        while (my $item = $enriched_contents->next) {
            my $field      = "E".sprintf "%04d",$item->{field};
            my $subfield   =                    $item->{subfield};
            my $content    =                    $item->{content};
            
            if ($seen_content{$content}) {
                next;
            }
            else {
                $seen_content{$content} = 1;
            }                    
            
            my $mult = ++$mult_map_ref->{$field};
            
            $self->set_field({
                field      => $field,
                subfield   => $subfield,
                mult       => $mult,
                content    => $content,
            });
        }
    }
    elsif (@issn_refs){
        my @issn_refs_tmp = ();
        # Normierung
        
        foreach my $issn_ref (@issn_refs){
            my $thisissn = $issn_ref->{content};
            
            push @issn_refs_tmp, $normalizer->normalize({
                field => 'T0543',
                content  => $thisissn,
            });
            
        }
        
        # Dubletten Bereinigen
        my %seen_issns = ();
        
        @issn_refs = grep { ! $seen_issns{$_} ++ } @issn_refs_tmp;
        
        if ($logger->is_debug){
            $logger->debug("ISSN: ".YAML::Dump(\@issn_refs));
        }
        
        # DBI "select category,content from normdata where isbn=? order by category,indicator"
        my $enriched_contents = $self->{enrich_schema}->resultset('EnrichedContentByIssn')->search_rs(
            {
                issn => \@issn_refs,
            },
            {                        
                group_by => ['field','content','issn','origin','subfield'],
                order_by => ['field','content'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        while (my $item = $enriched_contents->next) {
            my $field      = "E".sprintf "%04d",$item->{field};
            my $subfield   =                    $item->{subfield};
            my $content    =                    $item->{content};
            
            if ($seen_content{$content}) {
                next;
            } else {
                $seen_content{$content} = 1;
            }                    
            
            my $mult = ++$mult_map_ref->{$field};
            
            $self->set_field({
                field      => $field,
                subfield   => $subfield,
                mult       => $mult,
                content    => $content,
            });
        }
    }

    # Anreicherung mit spezifischer Titel-ID und Datenbank

    {
	my $enriched_contents = $self->{enrich_schema}->resultset('EnrichedContentByTitle')->search_rs(
            {
                dbname  => $self->{database},
		titleid => $self->{id},
            },
            {                        
                group_by => ['field','content','dbname','titleid','origin','subfield'],
                order_by => ['field','content'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
	    );
        
        while (my $item = $enriched_contents->next) {
            my $field      = "E".sprintf "%04d",$item->{field};
            my $subfield   =                    $item->{subfield};
            my $content    =                    $item->{content};
            
            if ($seen_content{$content}) {
                next;
            } else {
                $seen_content{$content} = 1;
            }                    
            
            my $mult = ++$mult_map_ref->{$field};
            
            $self->set_field({
                field      => $field,
                subfield   => $subfield,
                mult       => $mult,
                content    => $content,
            });
        }
    }
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    return;
}

sub enrich_related_records {
    my ($self, $arg_ref) = @_;

    my $profilename = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}           : '';

    my $orgunitname = exists $arg_ref->{orgunitname}
        ? $arg_ref->{orgunitname}        : '';
    
    my $viewname = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}              : '';

    my $locations_ref = exists $arg_ref->{locations}
        ? $arg_ref->{locations}             : [];
    
    my $blacklisted_locations_ref = exists $arg_ref->{blacklisted_locations}
        ? $arg_ref->{blacklisted_locations} : [];

    my $num      = exists $arg_ref->{num}
        ? $arg_ref->{num}                : 20;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    my ($atime,$btime,$timeall);
        
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $locationdigest = "";

    if (@$locations_ref){
	my $md5digest=Digest::MD5->new();
	
	$md5digest->add(join('', sort @$locations_ref));
			
	$locationdigest=$md5digest->hexdigest;
    }
    
    # my $memc_key = "record:title:enrich_related:$locationdigest:$profilename:$viewname:$num:$self->{database}:$self->{id}";
    
    # if ($config->{memc}){
    #     my $related_recordlist = $self->get_related_records;
        
    #     my $cached_records = $config->{memc}->get($memc_key);

    #     if ($cached_records){
    # 	    if ($logger->is_debug){
    # 		$logger->debug("Got related records for key $memc_key from memcached ".YAML::Dump($cached_records));
    # 	    }
	                
    #         if ($config->{benchmark}) {
    #             my $btime=new Benchmark;
    #             my $timeall=timediff($btime,$atime);
    #             $logger->info("Zeit fuer das Holen der gecacheten Informationen ist ".timestr($timeall));
    #         }

    #         $related_recordlist->from_serialized_reference($cached_records);

    #         if ($config->{benchmark}) {
    #             $btime=new Benchmark;
    #             $timeall=timediff($btime,$atime);
    #             $logger->info("Zeit fuer : Bestimmung von cached Enrich-Informationen ist ".timestr($timeall));
    #             undef $atime;
    #             undef $btime;
    #             undef $timeall;
    #         }
     
    #         $self->set_related_records($related_recordlist);

    #         return $self;
    #     }
    # }
    
    
    if (!exists $self->{enrich_schema}){
        $self->connectEnrichmentDB;
        if ($logger->is_debug){            
            $self->{enrich_schema}->storage->debug(1);
        }
    }

    my @filter_databases = ($orgunitname && $profilename)?$config->get_orgunitdbs($profilename,$orgunitname):($profilename)?$config->get_profiledbs($profilename):($viewname)?$config->get_viewdbs($viewname):();
        
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen vor Normdaten ".timestr($timeall));
    }

    return $self unless ($self->{database} && $self->{id});
    
    # ISBNs aus Anreicherungsdatenbank als subquery
    my $this_isbns = $self->{enrich_schema}->resultset('AllTitleByIsbn')->search_rs(
        { 
            dbname  => $self->{database},
            titleid => $self->{id},
        },
        {
            columns  => ['isbn'],
            group_by => ['isbn'],
        }
    );
    
    
    # Anreichern mit thematisch verbundenen Titeln (z.B. via Wikipedia) im gleichen Katalog(!)
    {
        my $ctime;
        my $dtime;
        if ($config->{benchmark}) {
            $ctime=new Benchmark;
        }
        
        my $related_recordlist = $self->get_related_records;
        
        if ($logger->is_debug){
            $logger->debug("Related records via backend ".YAML::Dump($related_recordlist));
        }
        
        my $titles_found_ref = {}; # Ein Titel kann ueber verschiedenen ISBNs erreicht werden. Das laesst sich nicht trivial via SQL loesen, daher haendisch                    
        # Finde abstrakte ids fuer Wikipedia-Artikel, in denen die ISBNs des Titels genannt sind
	my $related_ids = $self->{enrich_schema}->resultset('WikiarticleByIsbn')->search_rs(
	    {
		isbn    => { -in => $this_isbns->as_query },
	    },
	    {
		columns => ['article'],
		group_by => ['article'],
	    }
	    );
        
        if ($logger->is_debug){                        
            $logger->debug("Found ".($related_ids->count)." related ids");
        }
	
	# Finde alle thematisch zusammenhaengende ISBNs, die in den gefundenen Wikipedia-Artikeln (ueber die abstrakte ID) referenziert werden unter Auslassung der ISBNs des aktuellen Titelsatzes
	my $related_isbns = $self->{enrich_schema}->resultset('WikiarticleByIsbn')->search_rs(
	    {
		isbn      => { -not_in => $this_isbns->as_query },
		article   => { -in => $related_ids->as_query },
	    },
	    {
		columns => ['isbn'],
		group_by => ['isbn'],
	    }
	    );
        
        if ($logger->is_debug){            
            $logger->debug("Found ".($related_isbns->count)." isbns");
        }
        
        my $where_ref = {
            isbn    => { -in => $related_isbns->as_query },
        };

	# Filtern nach Standortmarkierungen
	if (@$locations_ref){
            $where_ref = {
                isbn      => { -in => $related_isbns->as_query },
                location  => { -in => $locations_ref },
            };
	}

	# Filtern nach Katalogen
        if (@filter_databases){
            $where_ref = {
                isbn    => { -in => $related_isbns->as_query },
                dbname  => { -in => \@filter_databases },
            };
        }

        if (@$blacklisted_locations_ref){
            $where_ref->{location} = { -not_in => @$blacklisted_locations_ref
            };
        }       
        
        my $titles = $self->{enrich_schema}->resultset('AllTitleByIsbn')->search_rs(
            $where_ref,
            {
		select   => ['dbname','location','titleid','titlecache','isbn'],
                group_by => ['dbname','location','titleid','titlecache','isbn'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );

	if ($logger->is_debug){
	    $logger->debug(YAML::Dump($where_ref));
	}

	my $count = 1;
	
        while (my $titleitem = $titles->next) {
            my $id         = $titleitem->{titleid};
            my $database   = $titleitem->{dbname};
            my $location   = $titleitem->{location};
            my $titlecache = $titleitem->{titlecache};

            next if (defined $titles_found_ref->{"$database:$id"});
            
            my $ctime;
            my $dtime;
            if ($config->{benchmark}) {
                $ctime=new Benchmark;
            }

	    my $new_record;

            if ($titlecache){
                $new_record = new OpenBib::Record::Title({ id => $id, database => $database, config => $config })->set_fields_from_json($titlecache);
            }
            else {
                $new_record = new OpenBib::Record::Title({ id => $id, database => $database, config => $config })->load_brief_record();
            }
	    
	    $new_record->set_locations([$location]);
	    $related_recordlist->add($new_record);
            
            if ($config->{benchmark}) {
                $dtime=new Benchmark;
                $timeall=timediff($dtime,$ctime);
                    $logger->info("Zeit fuer : Bestimmung von Kurztitel-Information des Titels ist ".timestr($timeall));
            }
            
            $titles_found_ref->{"$database:$id"} = 1;

	    last if ($count >= $num);
	    $count++;
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen / inkl Normdaten/Same Titles/Similar Titles/Related Titles w/o load_brief_records ist ".timestr($timeall));
        }

        # if ($config->{memc}){
        #     my $related_records_ref = $related_recordlist->to_serialized_reference;
        #     $logger->debug("Storing ".YAML::Dump($related_records_ref));
        #     $config->{memc}->set($memc_key,$related_records_ref,$config->{memcached_expiration}{'record:title:enrich_related'});
        # }
        
        $self->set_related_records($related_recordlist);

    }
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    return $self;
}

sub enrich_similar_records_old {
    my ($self, $arg_ref) = @_;

    my $profilename = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}        : undef;
    
    my $viewname = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    my ($atime,$btime,$timeall);
        
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    if (!exists $self->{enrich_schema}){
        $self->connectEnrichmentDB;
        if ($logger->is_debug){            
            $self->{enrich_schema}->storage->debug(1);
        }
    }

    my @filter_databases = ($profilename)?$config->get_profiledbs($profilename):
        ($viewname)?$config->get_viewdbs($viewname):();

    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen vor Normdaten ".timestr($timeall));
    }

    return $self unless ($self->{database} && $self->{id});
    
    # ISBNs aus Anreicherungsdatenbank als subquery
    my $this_isbns = $self->{enrich_schema}->resultset('AllTitleByIsbn')->search_rs(
        { 
            dbname  => $self->{database},
            titleid => $self->{id},
        },
        {
            columns  => ['isbn'],
            group_by => ['isbn'],
        }
    );
    
    
    # Anreicherung mit 'aehnlichen' (=andere Auflage, Sprache) Titeln aus allen Katalogen
    {
        my $similar_recordlist = $self->get_similar_records;
        
        if ($logger->is_debug){
            $logger->debug("Similar records via backend ".YAML::Dump($similar_recordlist));
        }   
        
        # Alle Werke zu gegebenen ISBNs bestimmen
        my $works = $self->{enrich_schema}->resultset('WorkByIsbn')->search_rs(
            {
                isbn    => { -in => $this_isbns->as_query },
            },
            {
                columns => ['workid'],
                group_by => ['workid'],
            }
        );
        
        my $similar_isbns = $self->{enrich_schema}->resultset('WorkByIsbn')->search_rs(
            {
                isbn      => { -not_in => $this_isbns->as_query },
                workid    => { -in => $works->as_query },
            },
            {
                columns => ['isbn'],
                group_by => ['isbn'],
            }
        );
            
        my $where_ref = {
            isbn    => { -in => $similar_isbns->as_query },
        };
        
        if (@filter_databases){
            $where_ref = {
                isbn    => { -in => $similar_isbns->as_query },                            
                dbname => \@filter_databases,
            };
        }
        
        my $titles = $self->{enrich_schema}->resultset('AllTitleByIsbn')->search_rs(
            $where_ref,
            {
                group_by => ['dbname','isbn','location','tstamp','titleid','titlecache'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        while (my $titleitem = $titles->next) {
            my $id         = $titleitem->{titleid};
            my $database   = $titleitem->{dbname};
            my $location   = $titleitem->{location};
            my $titlecache = $titleitem->{titlecache};
            
            $logger->debug("Found Title with id $id in database $database");

	    my $new_record;

            if ($titlecache){
                $new_record = new OpenBib::Record::Title({ id => $id, database => $database, config => $config })->set_fields_from_json($titlecache);
            }
            else {
                $new_record = new OpenBib::Record::Title({ id => $id, database => $database, config => $config })->load_brief_record();
            }
	    
	    $new_record->set_locations([$location]);
	    $similar_recordlist->add($new_record);
	    
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen / inkl Normdaten/Same Titles/Similar Titles w/o load_brief_records ist ".timestr($timeall));
        }
        
        $self->set_similar_records($similar_recordlist);
    }
        
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen / inkl Normdaten/Same Titles/Similar Titles ist ".timestr($timeall));
    }

    return $self;
}

sub enrich_similar_records {
    my ($self, $arg_ref) = @_;

    my $profilename = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}        : '';

    my $orgunitname = exists $arg_ref->{orgunitname}
        ? $arg_ref->{orgunitname}        : '';
    
    my $viewname = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}        : '';

    my $blacklisted_locations_ref = exists $arg_ref->{blacklisted_locations}
        ? $arg_ref->{blacklisted_locations} : [];
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    my ($atime,$btime,$timeall);
        
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $memc_key = "record:title:enrich_similar:$profilename:$viewname:$self->{database}:$self->{id}";
    
    if ($config->{memc} && length ($memc_key) < 250 ){
        my $similar_recordlist = $self->get_similar_records;
        
        my $cached_records = $config->{memc}->get($memc_key);

        if ($cached_records){

	    if ($logger->is_debug){
		$logger->debug("Got similar records for key $memc_key from memcached: ".YAML::Dump($cached_records));
	    }
	
            if ($config->{benchmark}) {
                my $btime=new Benchmark;
                my $timeall=timediff($btime,$atime);
                $logger->info("Zeit fuer das Holen der gecacheten Informationen ist ".timestr($timeall));
            }

            $similar_recordlist->from_serialized_reference($cached_records);

            if ($config->{benchmark}) {
                $btime=new Benchmark;
                $timeall=timediff($btime,$atime);
                $logger->info("Zeit fuer : Bestimmung von cached Enrich-Informationen ist ".timestr($timeall));
                undef $atime;
                undef $btime;
                undef $timeall;
            }

            $self->set_similar_records($similar_recordlist);

            return $self;
        }
    }
    
    if (!exists $self->{enrich_schema}){
        $self->connectEnrichmentDB;
        if ($logger->is_debug){            
            $self->{enrich_schema}->storage->debug(1);
        }
    }

    my @filter_databases = ($orgunitname && $profilename)?$config->get_orgunitdbs($profilename,$orgunitname):($profilename)?$config->get_profiledbs($profilename):($viewname)?$config->get_viewdbs($viewname):();

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen vor Normdaten ".timestr($timeall));
    }

    return $self unless ($self->{database} && $self->{id});
    
    # Workkeys aus Anreicherungsdatenbank als subquery
    my $this_workkeys = $self->{enrich_schema}->resultset('AllTitleByWorkkey')->search_rs(
        { 
            dbname  => $self->{database},
            titleid => $self->{id},
        },
        {
            columns  => ['workkey'],
            group_by => ['workkey'],
        }
    );
    
    my $this_edition = $self->{enrich_schema}->resultset('AllTitleByWorkkey')->search_rs(
        { 
            dbname  => $self->{database},
            titleid => $self->{id},
        },
        {
            columns  => ['edition'],
            group_by => ['edition'],
        }
    )->first;

    my $edition = '0001';
    
    if ($this_edition){
        $edition = $this_edition->edition;
    }
    
    # Anreicherung mit 'aehnlichen' (=andere Auflage, Sprache) Titeln aus allen Katalogen
    {
        my $similar_recordlist = $self->get_similar_records;
        
        if ($logger->is_debug){
            $logger->debug("Similar records via backend ".YAML::Dump($similar_recordlist));
        }   
        
        my $where_ref = {
            workkey    => { -in => $this_workkeys->as_query },
            edition    => { '!=' => $edition },
        };
        
        if (@filter_databases){
            $where_ref = {
                workkey    => { -in => $this_workkeys->as_query },
                edition    => { '!=' => $edition },
                dbname     => \@filter_databases,
            };
        }

        if (@$blacklisted_locations_ref){
            $where_ref->{location} = { -not_in => @$blacklisted_locations_ref
            };
        }       
        
        my $titles = $self->{enrich_schema}->resultset('AllTitleByWorkkey')->search_rs(
            $where_ref,
            {
                order_by => ['edition DESC'],
                group_by => ['id','dbname','workkey','edition','location','tstamp','titleid','titlecache'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );

        my $have_title_ref = {};
        while (my $titleitem = $titles->next) {
            my $id         = $titleitem->{titleid};
            my $database   = $titleitem->{dbname};
            my $location   = $titleitem->{location};
            my $titlecache = $titleitem->{titlecache};

            next if (defined $have_title_ref->{"$database:$id"});
            
            $logger->debug("Found Title with location $location and id $id in database $database");
            
	    my $new_record;

            if ($titlecache){
                $new_record = new OpenBib::Record::Title({ id => $id, database => $database, config => $config })->set_fields_from_json($titlecache);
            }
            else {
                $new_record = new OpenBib::Record::Title({ id => $id, database => $database, config => $config })->load_brief_record();
            }
            
	    $new_record->set_locations([$location]);
	    $similar_recordlist->add($new_record);

            $have_title_ref->{"$database:$id"} = 1;
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen / inkl Normdaten/Same Titles/Similar Titles w/o load_brief_records ist ".timestr($timeall));
        }

        if ($config->{memc}){
            my $similar_records_ref = $similar_recordlist->to_serialized_reference;
	    if ($logger->is_debug){
		$logger->debug("Storing ".YAML::Dump($similar_records_ref));
	    }
	    
            $config->{memc}->set($memc_key,$similar_records_ref,$config->{memcached_expiration}{'record:title:enrich_similar'});
        }

        $self->set_similar_records($similar_recordlist);
    }
        
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen / inkl Normdaten/Same Titles/Similar Titles ist ".timestr($timeall));
    }

    return $self;
}

sub enrich_same_records {
    my ($self, $arg_ref) = @_;

    my $profilename = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}        : '';

    my $orgunitname = exists $arg_ref->{orgunitname}
        ? $arg_ref->{orgunitname}        : '';
    
    my $viewname = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}        : '';

    my $blacklisted_locations_ref = exists $arg_ref->{blacklisted_locations}
        ? $arg_ref->{blacklisted_locations} : [];
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    my ($atime,$btime,$timeall);
        
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $memc_key = "record:title:enrich_same:$profilename:$viewname:$self->{database}:$self->{id}";
    
    if ($config->{memc} && length ($memc_key) < 250 ){
        my $same_recordlist = $self->get_same_records;

        my $cached_records = $config->{memc}->get($memc_key);

        if ($cached_records){

	    if ($logger->is_debug){
		$logger->debug("Got same records for key $memc_key from memcached: ".YAML::Dump($cached_records));
	    }
	
            if ($config->{benchmark}) {
                my $btime=new Benchmark;
                my $timeall=timediff($btime,$atime);
                $logger->info("Zeit fuer das Holen der gecacheten Informationen ist ".timestr($timeall));
            }

            $same_recordlist->from_serialized_reference($cached_records);

            if ($config->{benchmark}) {
                $btime=new Benchmark;
                $timeall=timediff($btime,$atime);
                $logger->info("Zeit fuer : Bestimmung von cached Enrich-Informationen ist ".timestr($timeall));
                undef $atime;
                undef $btime;
                undef $timeall;
            }

            $self->set_same_records($same_recordlist);

            return $self;
        }
    }
    else {
        $logger->debug("No memcached available");
    }
    
    if (!exists $self->{enrich_schema}){
        $self->connectEnrichmentDB;
        if ($logger->is_debug){            
            $self->{enrich_schema}->storage->debug(1);
        }
    }

    my @filter_databases = ($orgunitname && $profilename)?$config->get_orgunitdbs($profilename,$orgunitname):($profilename)?$config->get_profiledbs($profilename):($viewname)?$config->get_viewdbs($viewname):();
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen vor Normdaten ".timestr($timeall));
    }

    return $self unless ($self->{database} && $self->{id});
    
    # ISBNs aus Anreicherungsdatenbank als subquery
    my $this_isbns = $self->{enrich_schema}->resultset('AllTitleByIsbn')->search_rs(
        { 
            dbname  => $self->{database},
            titleid => $self->{id},
        },
        {
            columns  => ['isbn'],
            group_by => ['isbn'],
        }
    );
    
    # Anreicherung mit 'gleichen' (=gleiche ISBN) Titeln aus anderen Katalogen
    {
        # Same Records via Backend sind Grundlage.               
        my $same_recordlist = $self->get_same_records;
        
        if ($logger->is_debug){
            $logger->debug("Same records via backend ".YAML::Dump($same_recordlist));
        }
        
        my $where_ref = {
            isbn    => { -in => $this_isbns->as_query },
            titleid => {'!=' => $self->{id} },
            dbname  => {'!=' => $self->{database}}
        };
            
        if (@filter_databases){
            $where_ref = {
                isbn    => { -in => $this_isbns->as_query },
                titleid => {'!=' => $self->{id} },
                -and => [
                    {
                        dbname  => {'!=' => $self->{database}}
                    },
                    {
                        dbname => \@filter_databases,
                    },
                ]
            };
        }

        if (@$blacklisted_locations_ref){
            $where_ref->{location} = { -not_in => @$blacklisted_locations_ref
            };
        }       
        
        # DBI: "select distinct id,dbname from all_isbn where isbn=? and dbname != ? and id != ?";
        my $same_titles = $self->{enrich_schema}->resultset('AllTitleByIsbn')->search_rs(
            $where_ref,
            {
                group_by => ['titleid','dbname','location','isbn','tstamp','titlecache'],
                result_class => 'DBIx::Class::ResultClass::HashRefInflator',
            }
        );
        
        if ($logger->is_debug){            
            $logger->debug("Found ".($same_titles->count)." records");
        }

        my $have_title_ref = {};

        while (my $item = $same_titles->next) {
            my $id         = $item->{titleid};
            my $database   = $item->{dbname};
            my $location   = $item->{location};
            my $titlecache = $item->{titlecache};

            next if (defined $have_title_ref->{"$database:$id:$location"});

	    my $new_record;

            if ($titlecache){
                $new_record = new OpenBib::Record::Title({ id => $id, database => $database, config => $config })->set_fields_from_json($titlecache);
            }
            else {
                $new_record = new OpenBib::Record::Title({ id => $id, database => $database, config => $config })->load_brief_record();
            }

	    $new_record->set_locations([$location]);
	    $same_recordlist->add($new_record);

            $have_title_ref->{"$database:$id:$location"} = 1;
        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen / inkl Normdaten/Same Titles w/o load_brief_records ist ".timestr($timeall));
        }

        if ($config->{memc}){
            my $same_records_ref = $same_recordlist->to_serialized_reference;
	    
	    if ($logger->is_debug){
		$logger->debug("Storing ".YAML::Dump($same_records_ref));
	    }
	    
            $config->{memc}->set($memc_key,$same_records_ref,$config->{memcached_expiration}{'record:title:enrich_same'});
        }
        
        $self->set_same_records($same_recordlist);
    }
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : Bestimmung von Enrich-Informationen / inkl Normdaten/Same Titles ist ".timestr($timeall));
    }

    return $self;
}

sub load_circulation {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config        = $self->get_config;

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $memc_key = "record:title:circulation:$self->{database}:$self->{id}";
    
    if ($config->{memc} && length ($memc_key) < 250 ){
        my $circulation_ref = $config->{memc}->get($memc_key);
                
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time for is ".timestr($timeall));
        }

        if ($circulation_ref){
	    if ($logger->is_debug){
		$logger->debug("Got circulation for key $memc_key from memcached: ".YAML::Dump($circulation_ref));
	    }
	    
            $self->set_circulation($circulation_ref);

            return $self;
        }
    }

    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($circinfotable->{circinfo}));
    }
    
    # Ausleihinformationen der Exemplare

    my $circulation_ref = [];


    # Bei einer Ausleihbibliothek haben - falls Exemplarinformationen
    # in den Ausleihdaten vorhanden sind -- diese Vorrange ueber die
    # titelbasierten Exemplardaten
    
    # Anreichern mit Bibliotheksinformationen
    if ($circinfotable->has_circinfo($self->{database}) && defined $circinfotable->get($self->{database})->{circ}) {
	
	my $ils = OpenBib::ILS::Factory->create_ils({ database => $self->{database} });
	
	my $mediastatus_ref = $ils->get_mediastatus($self->{id});

	if ($logger->is_debug){
	    $logger->debug("Result: ".YAML::Dump($mediastatus_ref));
	}

	if (defined $mediastatus_ref->{error}){
	    $self->set_circulation_error($mediastatus_ref);
	    $self->set_circulation($circulation_ref);
	    return $self;
	}
	
	if (defined $mediastatus_ref->{items} && @{$mediastatus_ref->{items}}){
            for (my $i=0; $i < scalar(@{$mediastatus_ref->{items}}); $i++) {
		my $department     = $mediastatus_ref->{items}[$i]{department}{content};
		my $department_id  = $mediastatus_ref->{items}[$i]{department}{id};
#		my $department_url = $mediastatus_ref->{items}[$i]{department}{href};

		my $storage            = $mediastatus_ref->{items}[$i]{storage}{content};

		my $storage_id         = $mediastatus_ref->{items}[$i]{storage}{id};
		
		my $barcode            = $mediastatus_ref->{items}[$i]{barcode};
		
		my $boundcollection    = $mediastatus_ref->{items}[$i]{boundcollection};
		my $remark             = $mediastatus_ref->{items}[$i]{remark}; # z.B. Exemplarfussnote wie "Sachgruppe 22"

		my $availability_ref   = $mediastatus_ref->{items}[$i]{available};
		my $unavailability_ref = $mediastatus_ref->{items}[$i]{unavailable};

		# Valid values: lent|missing|loan|order|presence
		my $availability     = $self->get_availability($availability_ref,$unavailability_ref);

		# unknown should not be returned, so have to log response
		if ($availability eq "unknown"){

		    if ($logger->is_error){
			$logger->error("Ausleihstatus konnte nicht bestimmt werden. Daten: ".YAML::Dump($mediastatus_ref->{items}[$i]{debug}));
		    }
		}
		
		my $location_mark    = $mediastatus_ref->{items}[$i]{label};
		my $holdingid         = $mediastatus_ref->{items}[$i]{id};

		my $this_item_ref = {
		    # Legacy
		    Zweigstelle    => $department_id,
		    Signatur       => $location_mark,
		    Standort       => $department." / ".$storage,

		    # ILS analog DAIA
		    department     => $department,
		    department_id  => $department_id,
#		    department_url => $department_url,
		    location_mark  => $location_mark,
		    storage        => $storage,
		    storage_id     => $storage_id,
		    availability   => $availability,
		    availability_info   => $availability_ref,
		    unavailability_info => $unavailability_ref,
		    holdingid           => $holdingid,
		    boundcollection     => $boundcollection,
		    remark              => $remark,
		    barcode             => $barcode,
		};

		push @$circulation_ref, $this_item_ref;
            }
	}
    }

    if ($config->{memc}){
        $logger->debug("Fetch circulation from db and store in memcached");
        $config->{memc}->set($memc_key,$circulation_ref,$config->{memcached_expiration}{'record:title:circulation'});
    }
    

    $self->set_circulation($circulation_ref);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for is ".timestr($timeall));
    }

    return $self;
}

sub load_olwsviewer {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config        = $self->get_config;

    my $olwsconfig = ($config->get('olws')->{$self->{'database'}})?$config->get('olws')->{$self->{'database'}}:undef;

    my $circcheckurl  = (defined $olwsconfig)?$olwsconfig->{circwsurl}:"";
    my $circdb        = (defined $olwsconfig)?$olwsconfig->{circdb}:"";

    # Anreicherung mit OLWS-Daten
    if ($circdb && $circcheckurl){
        if ($logger->is_debug){                        
            $logger->debug("Endpoint: ".$circcheckurl);
        }
        
        my $soapresult;
        eval {
            my $soap = SOAP::Lite
                -> uri("urn:/Viewer")
                    -> proxy($circcheckurl);
            
            my $result = $soap->get_item_info(
                SOAP::Data->name(parameter  =>\SOAP::Data->value(
                    SOAP::Data->name(collection => $circdb)->type('string'),
                    SOAP::Data->name(item       => $id)->type('string'))));
            
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
    
    return $self;
}

sub save_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $config = $self->get_config;

    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    if ($id){
        my $record_exists = $self->get_schema->resultset('Title')->search(
            {
                'me.id' => $id,
            },
        )->count;

        # Wenn noch nicht da, dann eintragen,
        if (!$record_exists){

            $logger->debug("Record doesn't exist. Creating.");
            
            my $fields_ref = $self->{_fields};
            
            # Primaeren Normdatensatz erstellen und schreiben

            my $create_ref = {
                id => $id,
            };
            my $create_tstamp = "1970-01-01 12:00:00";
            
            if (defined $fields_ref->{'0002'} && defined $fields_ref->{'0002'}[0]) {
                $create_tstamp = $fields_ref->{'0002'}[0]{content};
                if ($create_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
                    $create_tstamp=$3."-".$2."-".$1." 12:00:00";
                }
                $create_ref->{tstamp_create} = $create_tstamp;
            }
        
            my $update_tstamp = "1970-01-01 12:00:00";
        
            if (exists $fields_ref->{'0003'} && exists $fields_ref->{'0003'}[0]) {
                $update_tstamp = $fields_ref->{'0003'}[0]{content};
                if ($update_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
                    $update_tstamp=$3."-".$2."-".$1." 12:00:00";
                }
                $create_ref->{tstamp_update} = $update_tstamp;
            }

            $self->get_schema->resultset('Title')->create($create_ref);
        }

        my $record = $self->get_schema->resultset('Title')->single(
            {
                'me.id' => $id,
            },
        );

        $record->title_fields->delete;
        
        # Ausgabe der Anzahl verkuepfter Titel
        my $titcount = $self->get_number_of_titles;
        
        push @{$self->{fields}{P5000}}, {
            content => $titcount,
        };

        $logger->debug("Populating new fields.");

        my $fields_ref = $self->get_fields;

        my $title_fields_ref = [];

        foreach my $field (keys %$fields_ref){
            foreach my $content_ref (@{$fields_ref->{$field}}){
                $content_ref->{titleid} = $id;
                $content_ref->{field}   = $field;
                push @$title_fields_ref, $content_ref;
            }
        }
        
        $record->title_fields->populate($title_fields_ref);
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Benoetigte Zeit ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }

    }
    # sonst komplett neu anlegen inkl. ID
    else {
        # Derzeit koennen keine Titel ohne bereits festgelegte ID aufgenommen werden.
        # Hierzu wird zukuenftig eine Kombination aus Trigger und Sequenztabelle noetig, mit der zusaetzlichen Problematik,
        # dass die Titel-ID als Textfeld definiert ist. Hier koennen nur Numerische IDs darin verwendet werden, da sonst kein
        # Hochzaehlen moeglich ist.
    }

    $logger->debug("Record with ID $id saved to database $self->{database}");
    return $self;
}

sub delete_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $config = $self->get_config;

    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    # DBI "select category,content,indicator from title where id = ?";
    my $title = $self->get_schema->resultset('Title')->search(
        {
            'me.id' => $id,
        },
    );

    $title->title_fields->delete;
    $title->title_people->delete;

    $logger->debug("Deleted title $self->{id} in database $self->{database}");
    
    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer Titleenbestimmung ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    return $self;
}

sub is_brief {
    my ($self)=@_;

    return ($self->{_type} eq "brief")?1:0;
}

sub is_full {
    my ($self)=@_;

    return ($self->{_type} eq "full")?1:0;
}

sub get_locations {
    my ($self)=@_;

    return $self->{_locations}
}

sub set_locations {
    my ($self,$location_ref)=@_;

    $self->{_locations} = $location_ref;

    return;
}

sub add_location {
    my ($self,$location)=@_;

    push @{$self->{_locations}}, $location;

    return $self;
}

sub get_holding {
    my ($self)=@_;

    return $self->{_holding}
}

sub set_holding {
    my ($self,$holding_ref)=@_;

    $self->{_holding} = $holding_ref;

    return;
}

sub get_locationmark_of_media {
    my ($self,$medianumber,$msg) = @_;

    my $logger = get_logger();

    $logger->debug("Getting locationmark for $medianumber");

    my $location_mark = "";

    foreach my $holding_ref (@{$self->get_holdings}){
	next unless (defined $holding_ref->{'X0010'} && $holding_ref->{'X0010'} eq $medianumber);
	$location_mark = $holding_ref->{'X0014'};
	last;
    }

    $logger->debug("Got locationmark $location_mark");
    
    return $location_mark;
}

sub set_generic_attributes {
    my ($self,$attributes_ref)=@_;

    $self->{generic_attributes} = $attributes_ref;

    return;
}

sub get_generic_attributes {
    my ($self)=@_;

    return $self->{generic_attributes};
}

sub set_fields {
    my ($self,$fields_ref)=@_;

    $self->{_fields} = $fields_ref;

    return;
}

sub get_circulation {
    my ($self)=@_;

    return $self->{_circulation}
}

sub set_circulation {
    my ($self,$circulation_ref)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    if ($logger->is_debug){
        $logger->debug("Setting Circulation: ".YAML::Dump($circulation_ref));
    }
    
    $self->{_circulation} = $circulation_ref;

    return;
}

sub set_circulation_error {
    my ($self,$error_ref)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    if ($logger->is_debug){
        $logger->debug("Setting Circulation Error: ".YAML::Dump($error_ref));
    }
    
    $self->{_circulation_error} = $error_ref;

    return;
}

sub has_circulation_error {
    my ($self)=@_;

    return (defined $self->{_circulation_error} && %{$self->{_circulation_error}} )?1:0;
}

sub get_circulation_error {
    my ($self)=@_;

    return (defined $self->{_circulation_error} && %{$self->{_circulation_error}} )?$self->{_circulation_error}:undef;
}

sub set_same_records {
    my ($self,$recordlist)=@_;

    $self->{_same_records} = $recordlist;

    return $self;
}

sub has_same_records {
    my ($self)=@_;

    return ($self->{_same_records}->get_size())?1:0;
}

sub get_same_records {
    my ($self)=@_;

    unless (defined $self->{_same_records}){
        $self->{_same_records}    = OpenBib::RecordList::Title->new();
    }
    
    return $self->{_same_records};
}

sub get_similar_records {
    my ($self)=@_;

    unless (defined $self->{_similar_records}){
        $self->{_similar_records}    = OpenBib::RecordList::Title->new();
    }

    return $self->{_similar_records}
}

sub set_similar_records {
    my ($self,$recordlist)=@_;

    $self->{_similar_records} = $recordlist;

    return $self;
}

sub get_related_records {
    my ($self)=@_;

    unless (defined $self->{_related_records}){
        $self->{_related_records}    = OpenBib::RecordList::Title->new();
    }

    return $self->{_related_records}
}

sub set_related_records {
    my ($self,$recordlist)=@_;

    $self->{_related_records} = $recordlist;
    
    return $self;
}

sub set_fields_from_storable {
    my ($self,$storable_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # (Re-)Initialisierung
    delete $self->{_exists}        if (exists $self->{_exists});
    delete $self->{_fields}        if (exists $self->{_fields});
    delete $self->{_holding}       if (exists $self->{_holding});
    delete $self->{_circulation}   if (exists $self->{_circulation});

    if ($logger->is_debug){
        $logger->debug("Got :".YAML::Dump($storable_ref));
    }

    if (defined $storable_ref->{locations}){
	$self->{_locations} = $storable_ref->{locations};
	$storable_ref->{locations} = [];
	delete $storable_ref->{locations};
    }

    if (defined $storable_ref->{id}){
	delete $storable_ref->{id};
    }

    if (defined $storable_ref->{database}){
	delete $storable_ref->{database};
    }
    
    $self->{_fields} = $storable_ref;
    $self->{_type} = 'brief';
    
    return $self;
}

sub set_fields_from_json {
    my ($self,$json_string)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # (Re-)Initialisierung
    delete $self->{_exists}         if (exists $self->{_exists});
    delete $self->{_fields}         if (exists $self->{_fields});
    delete $self->{_holding}        if (exists $self->{_holding});
    delete $self->{_circulation}    if (exists $self->{_circulation});

    my $json_ref = {};

    eval {
#        $json_ref = JSON::XS::decode_json decode_utf8($json_string);
        $json_ref = JSON::XS::decode_json $json_string;
    };
    
    if ($@){
        $logger->error("Can't decode JSON string $json_string");
    }
    else {
        $self->{_fields} = $json_ref;
        $self->{_type} = 'brief';
    }

    return $self;
}

sub set_record_from_json {
    my ($self,$json_string)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # (Re-)Initialisierung
    delete $self->{_exists}         if (exists $self->{_exists});
    delete $self->{_fields}         if (exists $self->{_fields});
    delete $self->{_holding}        if (exists $self->{_holding});
    delete $self->{_circulation}    if (exists $self->{_circulation});

    my $json_ref = {};

    eval {
#        $json_ref = JSON::XS::decode_json decode_utf8($json_string);
        $json_ref = JSON::XS::decode_json $json_string;
    };
        
    if ($@){
        $logger->error("Can't decode JSON string $json_string");
    }
    else {
        $self->{_fields}  = $json_ref->{fields};
	$self->{id}       = $json_ref->{id};
	$self->{database} = $json_ref->{database};
    }

    return $self;
}

sub to_bibkey {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $normalizer = $self->{_normalizer};
    
    my $bibkey_record_ref = {
        'T0100' => $self->{_fields}->{'T0100'},
        'T0101' => $self->{_fields}->{'T0101'},
        'T0331' => $self->{_fields}->{'T0331'},
        'T0425' => $self->{_fields}->{'T0425'},
    };

    return ($self->has_field('T5050'))?$self->get_field({field => 'T5050', mult => 1}):$normalizer->gen_bibkey({ fields => $bibkey_record_ref});
}

sub to_normalized_isbn13 {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $normalizer = $self->{_normalizer};
    
    my $thisisbn = ($self->has_field("T0540"))?$self->{_fields}{"T0540"}[0]{content}:"";

    $logger->debug("ISBN: $thisisbn");

    # Normierung auf ISBN13

    my $isbn     = Business::ISBN->new($thisisbn);
    
    if (defined $isbn && $isbn->is_valid){
        $thisisbn = $isbn->as_isbn13->as_string;
    }
    
    $thisisbn = $normalizer->normalize({
        field => 'T0540',
        content  => $thisisbn,
    });
    
    return $thisisbn;
}

sub get_sortfields {
    my ($self) = @_;

    my $normalizer = $self->{_normalizer};
    
    my $person_field = $self->get_field({ field => 'PC0001' });
    my $title_field  = $self->get_field({ field => 'T0331' });
    my $year_field   = $self->get_field({ field => 'T0425' });

    if (!defined $year_field->[0]{content}){
        $year_field   = $self->get_field({ field => 'T0424' });
    }

    my $srt_person = $normalizer->normalize({
        content => $person_field->[0]{content}
    });
    
    my $srt_title  =  $normalizer->normalize({
        content => $title_field->[0]{content},
        field   => 'T0331',
    });
    
    my $srt_year   =  $normalizer->normalize({
        content => $year_field->[0]{content},
        field   => 'T0425',
        type    => 'integer',
    });

    return {
        person => $srt_person,
        title  => $srt_title,
        year   => $srt_year,
    }
}

sub to_endnote {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $fields_ref = $self->to_abstract_fields();

    # https://www1.citavi.com/sub/manual-citaviweb/de/index.html?importing_an_endnote_tagged_file.html
    
    my $endnote_category_map_ref = {
        'source_journal' => '%J',    # Journal containing the article
        'source_volume'  => '%V',    # Volume 
        'authors'   => '%A',   # Author
        'editors'   => '%E',   # Editor of book containing article
        'corp'      => '%A',   # Corporate Author
        'creator'   => '%E',   # Corporate Creator
        'title'     => '%T',   # Title of the article or book
        'series'    => '%S',   # Title of the serie
        'T0519'     => '%R',   # Report, paper, or thesis type
        'volume'    => '%N',   # Number with volume
        'pages'     => '%P',   # Page number(s)
        'publisher' => '%I',   # Issuer. This is the publisher
        'place'     => '%C',   # City where published. This is the publishers address
        'year'      => '%D',   # Date of publication
        'keywords'  => '%K',   # Keywords used by refer to help locate the reference
        'isbn'      => '%@',   # Abstract. This is not normally printed in a reference
        'issn'      => '%@',   # Abstract. This is not normally printed in a reference
        'abstract'  => '%X',   # Abstract. This is not normally printed in a reference
        'pages'     => '%Z',   # Pages in the entire document. Tib reserves this for special use
        'edition'   => '%7',   # Edition
#        ''         => '%Y',   # Series Editor
#        ''         => '%L',   # Label used to number references when the -k flag of refer is used
#        ''         => '%O',   # Other information which is printed after the reference
#        ''         => '%W',   # Where the item can be found (physical location of item)
    };

    my $endnote_ref=[];

    my $type_ref = {
	'book' => 'Book',
	    'article' => 'Journal Article',
	    
    };

    # Typ
    if (defined $fields_ref->{'type'} && defined $type_ref->{$fields_ref->{'type'}} && $type_ref->{$fields_ref->{'type'}}){
	push @{$endnote_ref}, '%0 '.$type_ref->{$fields_ref->{'type'}}; 
    }
    
    # Titelkategorien
    foreach my $category (keys %{$endnote_category_map_ref}) {
        if (defined $fields_ref->{$category} && $fields_ref->{$category}) {
	    if ($category =~m/(authors|editors|corp|creator|keywords)/){
		foreach my $field_content (@{$fields_ref->{$category}}){
		    my $content = $endnote_category_map_ref->{$category}." ".$field_content;
		    push @{$endnote_ref}, $content;

		}
	    }
	    else {
                my $content = $endnote_category_map_ref->{$category}." ".$fields_ref->{$category};
		
                if ($category eq "title" && defined $fields_ref->{"titlesup"}){
                    $content.=" : ".$fields_ref->{"titlesup"};
                }
                
                push @{$endnote_ref}, $content;
            }
        }
    }

    # Urls

    if (defined $fields_ref->{'urls'}){
	foreach my $url_ref (@{$fields_ref->{'urls'}}){
	    next unless (defined $url_ref->{'url'});
	    my $content = '%U '.$url_ref->{'url'};
	    if ($url_ref->{'desc'}){
		$content.=" (".$url_ref->{desc}.")";
	    }
	    push @{$endnote_ref}, $content;
	}
    }
    
    # Exemplardaten
    my @holdingnormset = (defined $self->{_holding} && @{$self->{_holding}})?@{$self->{_holding}}:();

    if ($#holdingnormset > 0){
        foreach my $holding_ref (@holdingnormset){
            push @{$endnote_ref}, '%W '.$holding_ref->{"X4000"}{content}{full}." / ".$holding_ref->{"X0016"}{content}." / ".$holding_ref->{"X0014"}{content};
        }
    }
    
    return join("\n",@$endnote_ref);
}


sub to_bibsonomy_post {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $utf8               = exists $arg_ref->{utf8}
        ? $arg_ref->{utf8}               : 0;

    my $fields_ref = $self->to_abstract_fields();
    
    my $doc = XML::LibXML::Document->new();
    my $root = $doc->createElement('bibsonomy');
    $doc->setDocumentElement($root);
    my $post = $doc->createElement('post');
    $root->appendChild($post);
    my $bibtex = $doc->createElement('bibtex');

    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];

    if (defined $fields_ref->{authors} && @{$fields_ref->{authors}}){
	$authors_ref = $fields_ref->{authors};
    }

    if (defined $fields_ref->{editors} && @{$fields_ref->{editors}}){
	$editors_ref = $fields_ref->{editor};
    }
    
    my $author = join(' and ',@$authors_ref);
    my $editor = join(' and ',@$editors_ref);

    $author = utf2bibtex($author,$utf8);
    $editor = utf2bibtex($editor,$utf8);
    
    # Schlagworte
    my $keywords_ref=[];

    if (defined $fields_ref->{keywords} && @{$fields_ref->{keywords}}){
	$keywords_ref = $fields_ref->{keywords};
    }
    
    my $keyword = join(' ; ',@$keywords_ref);

    $keyword = utf2bibtex($keyword,$utf8);
    
    # Auflage
    my $edition   = (defined $fields_ref->{edition})?utf2bibtex($fields_ref->{edition},$utf8):'';

    # Verleger
    my $publisher = (defined $fields_ref->{publisher})?utf2bibtex($fields_ref->{publisher},$utf8):'';

    # Verlagsort
    my $place = (defined $fields_ref->{place})?utf2bibtex($fields_ref->{place},$utf8):'';

    # Titel
    my $title = (defined $fields_ref->{title})?utf2bibtex($fields_ref->{title},$utf8):'';

    # Zusatz zum Titel
    my $titlesup = (defined $fields_ref->{titlesup})?utf2bibtex($fields_ref->{titlesup},$utf8):'';

#    Folgende Erweiterung um titlesup ist nuetzlich, laeuft aber der
#    Bibkey-Bildung entgegen
#    if ($title && $titlesup){
#        $title = "$title : $titlesup";
#    }

    # Jahr
    my $year = (defined $fields_ref->{year})?utf2bibtex($fields_ref->{year},$utf8):'';

    # ISBN
    my $isbn = (defined $fields_ref->{isbn})?utf2bibtex($fields_ref->{isbn},$utf8):'';

    # ISSN
    my $issn = (defined $fields_ref->{issn})?utf2bibtex($fields_ref->{issn},$utf8):'';

    # Sprache
    my $language = (defined $fields_ref->{language})?utf2bibtex($fields_ref->{language},$utf8):'';

    # (1st) URL
    my $url = (defined $fields_ref->{urls})?utf2bibtex($fields_ref->{urls}[0]{url},$utf8):'';

    # Abstract
    my $abstract = (defined $fields_ref->{abstract})?utf2bibtex($fields_ref->{abstract},$utf8):'';

    # Pages
    my $pages = (defined $fields_ref->{pages})?utf2bibtex($fields_ref->{pages},$utf8):'';
    
    # Source Journal
    my $source_journal = (defined $fields_ref->{source_journal})?utf2bibtex($fields_ref->{source_journal},$utf8):'';

    # Source Volume
    my $source_volume = (defined $fields_ref->{source_volume})?utf2bibtex($fields_ref->{source_volume},$utf8):'';

    # Source Pages
    my $source_pages = (defined $fields_ref->{source_pages})?utf2bibtex($fields_ref->{source_pages},$utf8):'';

    # Source Year
    my $source_year = (defined $fields_ref->{source_year})?utf2bibtex($fields_ref->{source_year},$utf8):'';
    
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
    if ($place){
        $bibtex->setAttribute("address",$place);
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
    if ($url){
        $bibtex->setAttribute("url",$url);
    }
    if ($language){
        $bibtex->setAttribute("language",$language);
    }
    if ($abstract){
        $bibtex->setAttribute("abstract",$abstract);
    }

    if ($source_journal){
	# Journal
	$bibtex->setAttribute("journal",$source_journal);

        # Pages
        if ($source_pages){
	    $bibtex->setAttribute("pages",$source_pages);
        }

        # Volume
        if ($source_volume){
	    $bibtex->setAttribute("volume",$source_volume);
        }

        # Year
        if ($source_year){
	    $bibtex->setAttribute("year",$source_year);
        }	
    }
    else {
	if ($year){
	    $bibtex->setAttribute("year",$year);
	}
	if ($pages){
	    $bibtex->setAttribute("paes",$pages);
	}
    }
    
    my $identifier=substr($author,0,4).substr($title,0,4).$year;
    $identifier=~s/[^A-Za-z0-9]//g;

    $bibtex->setAttribute("bibtexKey",$identifier);

    if ($source_journal){
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

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $bibtex_ref=[];

    my $fields_ref = $self->to_abstract_fields();
    
    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];

    if ($logger->is_debug){
	$logger->debug("Fields: ".YAML::Dump($fields_ref));
    }

    if (defined $fields_ref->{authors} && @{$fields_ref->{authors}}){
	$authors_ref = $fields_ref->{authors};
    }

    if (defined $fields_ref->{editors} && @{$fields_ref->{editors}}){
	$editors_ref = $fields_ref->{editors};
    }

    my $author = join(' and ',@$authors_ref);
    my $editor = join(' and ',@$editors_ref);

    $author = utf2bibtex($author,$utf8);
    $editor = utf2bibtex($editor,$utf8);
    
    # Schlagworte
    my $keywords_ref=[];

    if (defined $fields_ref->{keywords} && @{$fields_ref->{keywords}}){
	$keywords_ref = $fields_ref->{keywords};
    }
    
    my $keyword = join(' ; ',@$keywords_ref);

    $keyword = utf2bibtex($keyword,$utf8);
    
    # Auflage
    my $edition   = (defined $fields_ref->{edition})?utf2bibtex($fields_ref->{edition},$utf8):'';

    # Verleger
    my $publisher = (defined $fields_ref->{publisher})?utf2bibtex($fields_ref->{publisher},$utf8):'';

    # Verlagsort
    my $place = (defined $fields_ref->{place})?utf2bibtex($fields_ref->{place},$utf8):'';

    # Titel
    my $title = (defined $fields_ref->{title})?utf2bibtex($fields_ref->{title},$utf8):'';

    # Zusatz zum Titel
    my $titlesup = (defined $fields_ref->{titlesup})?utf2bibtex($fields_ref->{titlesup},$utf8):'';

#    Folgende Erweiterung um titlesup ist nuetzlich, laeuft aber der
#    Bibkey-Bildung entgegen
#    if ($title && $titlesup){
#        $title = "$title : $titlesup";
#    }

    # Jahr
    my $year = (defined $fields_ref->{year})?utf2bibtex($fields_ref->{year},$utf8):'';

    # ISBN
    my $isbn = (defined $fields_ref->{isbn})?utf2bibtex($fields_ref->{isbn},$utf8):'';

    # ISSN
    my $issn = (defined $fields_ref->{issn})?utf2bibtex($fields_ref->{issn},$utf8):'';

    # Sprache
    my $language = (defined $fields_ref->{language})?utf2bibtex($fields_ref->{language},$utf8):'';

    # Volltext URL
    my $fulltext_url = (defined $fields_ref->{onlineurl})?utf2bibtex($fields_ref->{onlineurl},$utf8):'';
    
    # (1st) URL
    my $url = (defined $fields_ref->{urls})?utf2bibtex($fields_ref->{urls}[0]{url},$utf8):'';

    # Abstract
    my $abstract = (defined $fields_ref->{abstract})?utf2bibtex($fields_ref->{abstract},$utf8):'';

    # Pages
    my $pages = (defined $fields_ref->{pages})?utf2bibtex($fields_ref->{pages},$utf8):'';

    # DOI
    my $doi = (defined $fields_ref->{doi})?utf2bibtex($fields_ref->{doi},$utf8):'';

    # Note
    my $note = (defined $fields_ref->{note})?utf2bibtex($fields_ref->{note},$utf8):'';
    
    # Source Journal
    my $source_journal = (defined $fields_ref->{source_journal})?utf2bibtex($fields_ref->{source_journal},$utf8):'';

    # Source Volume
    my $source_volume = (defined $fields_ref->{source_volume})?utf2bibtex($fields_ref->{source_volume},$utf8):'';

    # Source Issue
    my $source_issue = (defined $fields_ref->{source_issue})?utf2bibtex($fields_ref->{source_issue},$utf8):'';
    
    # Source Pages
    my $source_pages = (defined $fields_ref->{source_pages})?utf2bibtex($fields_ref->{source_pages},$utf8):'';

    # Source Year
    my $source_year = (defined $fields_ref->{source_year})?utf2bibtex($fields_ref->{source_year},$utf8):'';
    
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
    if ($place){
        push @$bibtex_ref, "address   = \"$place\"";
    }
    if ($title){
        push @$bibtex_ref, "title     = \"$title\"";
    }
    if ($isbn){
        push @$bibtex_ref, "isbn      = \"$isbn\"";
    }
    if ($issn){
        push @$bibtex_ref, "issn      = \"$issn\"";
    }
    if ($doi){
        push @$bibtex_ref, "doi       = \"$doi\"";
    }
    if ($keyword){
        push @$bibtex_ref, "keywords  = \"$keyword\"";
    }
    if ($note){
        push @$bibtex_ref, "note      = \"$note\"";
    }
    if ($fulltext_url && !$doi){
        push @$bibtex_ref, "url       = \"$fulltext_url\"";
    }    
    elsif ($url){
        push @$bibtex_ref, "url       = \"$url\"";
    }
    if ($language){
        push @$bibtex_ref, "language  = \"$language\"";
    }
    if ($abstract){
        push @$bibtex_ref, "abstract  = \"$abstract\"";
    }

    if ($source_journal){
	# Journal
	push @$bibtex_ref, "journal   = \"$source_journal\"";

        # Pages
        if ($source_pages){
            push @$bibtex_ref, "pages     = \"$source_pages\"";
        }

        # Volume
        if ($source_volume){
            push @$bibtex_ref, "volume    = \"$source_volume\"";
        }

        # Issue
        if ($source_issue){
            push @$bibtex_ref, "number     = \"$source_issue\"";
        }
	
        # Year
        if ($source_year){
            push @$bibtex_ref, "year    = \"$source_year\"";
        }	
    }
    else {
	if ($year){
	    push @$bibtex_ref, "year      = \"$year\"";
	}
	if ($pages){
	    push @$bibtex_ref, "pages     = \"$pages\"";
	}
    }

    my $identifier=substr($author,0,4).substr($title,0,4).$year;
    $identifier=~s/[^A-Za-z0-9]//g;

    my $bibtex="";

    if ($source_journal){
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

sub to_harvard_citation {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $no_html               = exists $arg_ref->{no_html}
        ? $arg_ref->{no_html}             : 0;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $fields_ref = $self->to_abstract_fields();

    # Source: https://www.mendeley.com/guides/harvard-citation-guide
    
    my $citation = "";

    if (defined $fields_ref->{editors} && @{$fields_ref->{editors}}){
	if (@{$fields_ref->{editors}} >= 4){
	    $citation.=$fields_ref->{editors}[0]." et al";
	}
	else {
	    $citation.=join(', ', @{$fields_ref->{editors}});
	}
	$citation.=". (eds.)";
    }
    elsif (defined $fields_ref->{authors} && @{$fields_ref->{authors}}){
	if (@{$fields_ref->{authors}} >= 4){
	    $citation.=$fields_ref->{authors}[0]." et al";
	}
	else {
	    $citation.=join(', ', @{$fields_ref->{authors}});
	}
	$citation.=".";
    }
    else {
	    $citation.="Anonymus.";
    }

    if (defined $fields_ref->{type}){
    if ($fields_ref->{type} =~m/(book|periodical)/ ){
	if ($fields_ref->{availability} eq "online"){
	    if ($fields_ref->{year}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="(".$fields_ref->{year}.").";
	    }
	    if ($fields_ref->{title}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="<i>".$fields_ref->{title}."</i>.";
	    }
	    if ($fields_ref->{edition}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{edition}.".";
	    }
	    if ($fields_ref->{series}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="<i>".$fields_ref->{series}."</i> [online].";
	    }

	    if ($citation){
		$citation.=" ";
	    }
	    
	    $citation.="Available at: ";
	    
	    if ($fields_ref->{onlineurl}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{onlineurl};
	    }
	    elsif ($fields_ref->{doi}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{doi};
	    }
	}
	else {
	    if ($fields_ref->{year}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="(".$fields_ref->{year}.").";
	    }
	    if ($fields_ref->{title}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="<i>".$fields_ref->{title}."</i>.";
	    }
	    if ($fields_ref->{edition}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{edition}.".";
	    }
	    if ($fields_ref->{place}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{place}.":";
	    }
	    if ($fields_ref->{publisher}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{publisher};
	    }
	}
    }
    elsif ($fields_ref->{type} eq "article"){
	if ($fields_ref->{availability} eq "online"){
	    if ($fields_ref->{year}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="(".$fields_ref->{year}.")";
	    }
	    if ($fields_ref->{title}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="'".$fields_ref->{title}."',";
	    }
	    if ($fields_ref->{source_journal}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="<i>".$fields_ref->{source_journal}."</i>.";
	    }
	    if ($fields_ref->{source_volume}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{source_volume};
	    }
	    if ($fields_ref->{source_issue}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="(".$fields_ref->{source_issue}."),";
	    }
	    if ($fields_ref->{source_pages}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{source_pages}.".";
	    }

	    if ($citation){
		$citation.=" ";
	    }
	    
	    $citation.="Available at:";
	    
	    if ($fields_ref->{onlineurl}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{onlineurl};
	    }
	    elsif ($fields_ref->{doi}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{doi};
	    }
	}
	else {
	    if ($fields_ref->{year}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="(".$fields_ref->{year}.").";
	    }
	    if ($fields_ref->{title}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="'".$fields_ref->{title}."'.";
	    }
	    if ($fields_ref->{source_journal}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="<i>".$fields_ref->{source_journal}."</i>.";
	    }
	    if ($fields_ref->{source_volume}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{source_volume};
	    }
	    if ($fields_ref->{source_issue}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="(".$fields_ref->{source_issue}."),";
	    }
	    if ($fields_ref->{source_pages}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{source_pages}.".";
	    }
	}
    }
    }
    if ($no_html){
	my $hs = HTML::Strip->new();
	
	$citation = $hs->parse($citation);
    }

    $logger->debug("Harvard Citation: $citation");

    return $citation;
}

sub to_mla_citation {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $no_html               = exists $arg_ref->{no_html}
        ? $arg_ref->{no_html}             : 0;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $fields_ref = $self->to_abstract_fields();

    # Source: https://www.mendeley.com/guides/mla-citation-guide
    
    my $citation = "";

    if (defined $fields_ref->{authors} && @{$fields_ref->{authors}}){
	if (@{$fields_ref->{authors}} == 1){
	    $citation.=$fields_ref->{authors}[0];
	}
	elsif (@{$fields_ref->{authors}} == 2){
	    $citation.=$fields_ref->{authors}[0]; # first author
	    my ($surname,$forename) = split('\s*,\s*',$fields_ref->{authors}[1]); # 2nd author
	    $citation.=" and $forename $surname";
	}
	elsif (@{$fields_ref->{authors}} >= 3){
	    $citation.=$fields_ref->{authors}[0]." et al";
	}
    }

    if (defined $fields_ref->{editors} && @{$fields_ref->{editors}}){
	if (!$citation){
	    $citation.=$fields_ref->{editors}[0].", editor";
	}
    }

    $citation.="." if ($citation);

    if (defined $fields_ref->{type}){
	if ($fields_ref->{type} =~m/(book|periodical)/ ){
	    if ($fields_ref->{title}){
		my $title = $fields_ref->{title};
		#$title=~s/([\w']+)/\u\L$1/g;
		if ($citation){
		    $citation.=" ";
		}
		$citation.="<i>$title</i>.";
	    }
	    if ($fields_ref->{series}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{series};
		if ($fields_ref->{publisher} || $fields_ref->{year} || $fields_ref->{edition} || $fields_ref->{availability} eq "online"){
		    $citation.=",";
		}
	    }
	    if ($fields_ref->{edition}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{edition};
		if ($fields_ref->{publisher} || $fields_ref->{year}){
		    $citation.=",";
		}
	    }
	    if ($fields_ref->{availability} eq "online"){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="e-book";
		if ($fields_ref->{year} || $fields_ref->{publisher}){
		    $citation.=",";
		}
	    }
	    
	    if ($fields_ref->{publisher}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{publisher};
		if ($fields_ref->{year}){
		    $citation.=",";
		}
	    }
	    if ($fields_ref->{year}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{year}.".";
	    }
	}
	elsif ($fields_ref->{type} eq "article"){
	    if ($fields_ref->{title}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="\"".$fields_ref->{title}."\".";
	    }
	    if ($fields_ref->{source_journal}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="<i>".$fields_ref->{source_journal}."</i>";
		if ($fields_ref->{source_volume} || $fields_ref->{source_issue} || $fields_ref->{year} || $fields_ref->{source_pages}){
		    $citation.=",";
		}
	    }
	    if ($fields_ref->{source_volume}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="vol. ".$fields_ref->{source_volume};
		if ($fields_ref->{source_issue} || $fields_ref->{year} || $fields_ref->{source_pages}){
		    $citation.=",";
		}
	    }
	    if ($fields_ref->{source_issue}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="no. ".$fields_ref->{source_issue};
		if ($fields_ref->{year} || $fields_ref->{source_pages}){
		    $citation.=",";
		}
	    }
	    if ($fields_ref->{year}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{year};
		if ($fields_ref->{source_pages}){
		    $citation.=",";
		}
	    }
	    if ($fields_ref->{source_pages}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{source_pages};
	    }
	    
	    if ($citation){
		$citation.=".";
	    }
	    
	    if ($fields_ref->{availability} eq "online"){
		if ($fields_ref->{onlineurl}){
		    if ($citation){
			$citation.=" ";
		    }
		    $citation.=$fields_ref->{onlineurl};
		}
		elsif ($fields_ref->{doi}){
		    if ($citation){
			$citation.=" ";
		    }
		    $citation.=$fields_ref->{doi};
		}
		
		if ($citation){
		    $citation.=".";
		}
	    }
	}
    }

    if ($no_html){
	my $hs = HTML::Strip->new();
	
	$citation = $hs->parse($citation);
    }
    
    $logger->debug("MLA Citation: $citation");
    
    return $citation;
}

sub to_apa_citation {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $no_html               = exists $arg_ref->{no_html}
        ? $arg_ref->{no_html}             : 0;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $fields_ref = $self->to_abstract_fields();

    # Source: https://www.mendeley.com/guides/apa-citation-guide
    
    my $citation = "";

    if (defined $fields_ref->{editors} && @{$fields_ref->{editors}}){
	my @editors = @{$fields_ref->{editors}} ;
	if (@editors == 1){
	    $citation.=$fields_ref->{editors}[0];
	}
	elsif (@editors >= 1){
	    $editors[$#editors] = "&amp; ".$editors[$#editors]; 
	    $citation.=join(', ', @editors);
	}
	$citation.="(Ed.)";
    }
    elsif (defined $fields_ref->{authors} && @{$fields_ref->{authors}}){
	my @authors = @{$fields_ref->{authors}} ;
	if (@authors == 1){
	    $citation.=$fields_ref->{authors}[0];
	}
	elsif (@authors >= 1){
	    $authors[$#authors] = "&amp; ".$authors[$#authors]; 
	    $citation.=join(', ', @authors);
	}
    }

    $citation.="." if ($citation);

    if (defined $fields_ref->{type}){
	if ($fields_ref->{type} =~m/(book|periodical)/ ){
	    if ($fields_ref->{year}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="(".$fields_ref->{year}.").";
	    }
	    if ($fields_ref->{title}){
		my $title = $fields_ref->{title};
		#$title=~s/([\w']+)/\u\L$1/g;
		if ($citation){
		    $citation.=" ";
		}
		$citation.="<i>$title</i>";

		if ($fields_ref->{edition}){
		    if ($citation){
			$citation.=" ";
		    }
		    $citation.="(".$fields_ref->{edition}.")";
		}

		$citation.=".";
	    }

	    if ($fields_ref->{place}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{place};
		
		if ($fields_ref->{publisher}){
		    $citation.=":";
		}
	    }
	    if ($fields_ref->{publisher}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{publisher}.".";
	    }
	    
	    if ($fields_ref->{availability} eq "online"){
		if ($fields_ref->{onlineurl}){
		    if ($citation){
			$citation.=" ";
		    }
		    $citation.="Retrieved from ".$fields_ref->{onlineurl};
		}
		elsif ($fields_ref->{doi}){
		    if ($citation){
			$citation.=" ";
		    }
		    $citation.=$fields_ref->{doi};
		}
	    }	
	}
	elsif ($fields_ref->{type} eq "article"){
	    if ($fields_ref->{year}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="(".$fields_ref->{year}.").";
	    }
	    if ($fields_ref->{title}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{title}.".";
	    }
	    if ($fields_ref->{source_journal}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.="<i>".$fields_ref->{source_journal}."</i>";
		if ($fields_ref->{source_volume} || $fields_ref->{source_issue} || $fields_ref->{year} || $fields_ref->{source_pages}){
		    $citation.=",";
		}
	    }
	    if ($fields_ref->{source_volume}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{source_volume};
		if (!$fields_ref->{source_issue} && $fields_ref->{source_pages}){
		    $citation.=",";
		}
	    }
	    if ($fields_ref->{source_issue}){
		$citation.="(".$fields_ref->{source_issue}.")";
		if ($fields_ref->{source_pages}){
		    $citation.=",";
		}
	    }
	    if ($fields_ref->{source_pages}){
		if ($citation){
		    $citation.=" ";
		}
		$citation.=$fields_ref->{source_pages};
	    }

	    if ($citation){
		$citation.=".";
	    }
	    
	    if ($fields_ref->{availability} eq "online"){
		if ($fields_ref->{onlineurl}){
		    if ($citation){
			$citation.=" ";
		    }
		    $citation.="Retrieved from ".$fields_ref->{onlineurl};
		}
		elsif ($fields_ref->{doi}){
		    if ($citation){
			$citation.=" ";
		    }
		    $citation.=$fields_ref->{doi};
		}
	    }    
	}
    }

    if ($no_html){
	my $hs = HTML::Strip->new();
	
	$citation = $hs->parse($citation);
    }
    
    $logger->debug("APA Citation: $citation");
    
    return $citation;
}

sub to_isbd {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $no_html               = exists $arg_ref->{no_html}
        ? $arg_ref->{no_html}             : 0;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $fields_ref = $self->to_abstract_fields();

    # Source: https://wiki.fachbereich-aub.de/wiki/index.php/ISBD-Format
    
    my $isbd = "";

    # Erste Zeile
    my $line1="";
    if ($fields_ref->{title}){
	my $title = $fields_ref->{title};
	#$title=~s/([\w']+)/\u\L$1/g;
	$line1 = $title;
    }

    if ($fields_ref->{titlesup}){
	my $titlesup = $fields_ref->{titlesup};
	if ($line1){
	    $line1.=" : ";
	}
	$line1 .=$titlesup;
    }

    my @perscorp = ();
    if (defined $fields_ref->{authors} && @{$fields_ref->{authors}}){
	push @perscorp, @{$fields_ref->{authors}} ;
    }
    
    if (defined $fields_ref->{corp} && @{$fields_ref->{corp}}){
	push @perscorp, @{$fields_ref->{corp}} ;
    }
    
    if (defined $fields_ref->{editors} && @{$fields_ref->{editors}}){
	push @perscorp, @{$fields_ref->{editors}} ;
    }

    if (@perscorp){
	my $perscorp = join (', ',@perscorp);
	if ($line1){
	    $line1.=" / ";
	}
	$line1.="von $perscorp";
    }

    $isbd.="$line1. -\n" if ($line1); # Ende erste Zeile

    # Zweite Zeile

    my $line2 = "";
    
    if ($fields_ref->{edition}){
	$line2.=$fields_ref->{edition};
    }

    if ($fields_ref->{place}){
	if ($fields_ref->{edition}){
	    $line2.=". - "
	}
	$line2.=$fields_ref->{place};
    }

    if ($fields_ref->{publisher}){
	if ($fields_ref->{place}){
	    $line2.=" : ";
	}
	$line2.=$fields_ref->{publisher};
    }

    if ($fields_ref->{year}){
	if ($fields_ref->{publisher}){
	    $line2.=", ";
	}
	$line2.=$fields_ref->{year};
    }

    $isbd.="$line2. -\n" if ($line2); # Ende zweite Zeile

    # Dritte Zeile

    my $line3 = "";

    if ($fields_ref->{pages}){
	$line3.=$fields_ref->{pages};
    }

    if ($fields_ref->{source}){
	if ($line3){
	    $line3.=". - ";
	}
	if ($fields_ref->{source_journal}){
	    $line3.="(".$fields_ref->{source_journal};
	}

	if ($fields_ref->{source_volume}){
	    if ($fields_ref->{source_journal}){
		$line3.=" ; ";
	    }
	    $line3.=$fields_ref->{source_volume};
	}
	$line3.=")";

    }
    elsif ($fields_ref->{series}){
	if ($line3){
	    $line3.=". - ";
	}
	$line3.="(".$fields_ref->{series};
	if ($fields_ref->{series_volume}){
	    if ($fields_ref->{series}){
		$line3.=" ; ";
	    }
	    $line3.=$fields_ref->{series_volume};
	}
	$line3.=")";
    }

    $isbd.="$line3\n" if ($line3); # Ende dritte Zeile

    # Vierte Zeile fuer Fussnoten bleibt leer

    # Fuenfte Zeile
    
    my $line5 = "";

    if ($fields_ref->{isbn}){
	$line5.=$fields_ref->{isbn};
    }
    elsif ($fields_ref->{issn}){
	$line5.=$fields_ref->{issn};
    }
    
    $isbd.="$line5\n" if ($line5); # Ende fuenfte Zeile

    # Sechste Zeile
    
    my $line6 = "";

    if (@{$fields_ref->{urls}}){
	my @urls = ();
	foreach my $url_ref (@{$fields_ref->{urls}}){
	    my $url = $url_ref->{url};
	    $url.=" (".$url_ref->{desc}.")" if ($url_ref->{desc});
	    push @urls, $url;
	}
	$line6.="URL: ".join(' ; ',@urls);
    }
    
    $isbd.="$line6\n" if ($line6); # Ende sechste Zeile
    
    if ($no_html){
	my $hs = HTML::Strip->new();
	
	$isbd = $hs->parse($isbd);
    }
    
    $logger->debug("ISBD: $isbd");
    
    return $isbd;
}

sub to_abstract_fields {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $database = $self->{database};

    my $schema   = $self->{dbinfo}{schema}{$database} || '';

    if ($schema eq "mab2"){
	$logger->debug("Abstract fields from mab2");
	return $self->to_abstract_fields_mab2;
    }
    elsif ($schema eq "marc21"){
	$logger->debug("Abstract fields from marc21");	
	return $self->to_abstract_fields_marc21;
    }

    $logger->debug("Abstract fields: No schema available (DB: $database, Schema: $schema)");
    
    # Otherwise no data
    return {};
}

sub to_abstract_fields_mab2 {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $abstract_fields_ref = {};

    # Definition sprechender Feldnamen mit deren Inhalten
    #
    # authors[] : Verfasser 0100/0101
    # editors[] : Herausgeber anhand Supplement
    # corp[]    : Koerperschaften 0200
    # creator[] : Urheber 0201
    # keywords[]: Schlagworte
    # classifications[]: Klassifikationen
    # edition   : Auflage
    # publisher : Verlag
    # place     : Verlagsort
    # title     : Titel
    # titlesup  : Zusatz zum Sachtitel
    # year      : Erscheinungsjahr
    # isbn      : ISBN
    # issn      : ISSN
    # language  : Sprache
    # urls[]    : URLs
    # abstract  : Abstrakt
    #
    # source    : Quelle Gesamtangabe
    #
    # aufgesplittet in:
    #   source_pages   : Quelle Seitenangabe
    #   source_journal : Quelle Zeitschriftentitel
    #   source_volume  : Quelle Bandnr
    #   source_year    : Quelle Jahr
    #
    # pages     : Kollation
    # series    : Gesamttitelangabe (0451)
    # series_volume    : Band (0089 bzw. 0455)
    # edition   : Auflage
    # type      : Medientyp (article,book,periodical)
    
    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $category (qw/T0100 T0101/){
        next if (!exists $self->{_fields}->{$category});
        foreach my $part_ref (@{$self->{_fields}->{$category}}){
            if (defined $part_ref->{supplement} && $part_ref->{supplement} =~ /Hrsg/){
                push @$editors_ref, $part_ref->{content};
            }
            else {
                push @$authors_ref, $part_ref->{content};
            }
        }
    }

    $abstract_fields_ref->{authors} = $authors_ref;
    $abstract_fields_ref->{editors} = $editors_ref;

    # Urheber und Koerperschaften konstruieren
    my $corp_ref=[];
    my $creator_ref=[];
    foreach my $category (qw/T0200/){
        next if (!exists $self->{_fields}->{$category});
        foreach my $part_ref (@{$self->{_fields}->{$category}}){
	    push @$corp_ref, $part_ref->{content};
        }
    }

    foreach my $category (qw/T0201/){
        next if (!exists $self->{_fields}->{$category});
        foreach my $part_ref (@{$self->{_fields}->{$category}}){
	    push @$creator_ref, $part_ref->{content};
        }
    }

    $abstract_fields_ref->{corp} = $corp_ref;
    $abstract_fields_ref->{creator} = $creator_ref;
    
    # Schlagworte
    my $keywords_ref=[];
    foreach my $category (qw/T0710 T0902 T0907 T0912 T0917 T0922 T0927 T0932 T0937 T0942 T0947/){
        next if (!exists $self->{_fields}->{$category});
        foreach my $part_ref (@{$self->{_fields}->{$category}}){
            push @$keywords_ref, $part_ref->{content};
        }
    }

    $abstract_fields_ref->{keywords} = $keywords_ref;

    # Klassifikationen
    my $classifications_ref=[];
    foreach my $category (qw/T0700/){
        next if (!exists $self->{_fields}->{$category});
        foreach my $part_ref (@{$self->{_fields}->{$category}}){
            push @$classifications_ref, $part_ref->{content};
        }
    }
    
    $abstract_fields_ref->{classifications} = $classifications_ref;

    # Auflage
    $abstract_fields_ref->{edition} = (exists $self->{_fields}->{T0403})?$self->{_fields}->{T0403}[0]{content}:'';

    # Verleger
    $abstract_fields_ref->{publisher} = (exists $self->{_fields}->{T0412})?$self->{_fields}->{T0412}[0]{content}:'';

    # Verlagsort
    $abstract_fields_ref->{place} = (exists $self->{_fields}->{T0410})?$self->{_fields}->{T0410}[0]{content}:'';

    # Titel
    $abstract_fields_ref->{title} = (exists $self->{_fields}->{T0310})?$self->{_fields}->{T0310}[0]{content}:(exists $self->{_fields}->{T0331})?$self->{_fields}->{T0331}[0]{content}:'';

    # Zusatz zum Titel
    $abstract_fields_ref->{titlesup} = (exists $self->{_fields}->{T0335})?$self->{_fields}->{T0335}[0]{content}:'';
#    Folgende Erweiterung um titlesup ist nuetzlich, laeuft aber der
#    Bibkey-Bildung entgegen
#    if ($title && $titlesup){
#        $title = "$title : $titlesup";
#    }

    # Jahr
    $abstract_fields_ref->{year} = (exists $self->{_fields}->{T0424})?$self->{_fields}->{T0424}[0]{content}:(exists $self->{_fields}->{T0425})?$self->{_fields}->{T0425}[0]{content}:'';

    # ISBN
    $abstract_fields_ref->{isbn} = (exists $self->{_fields}->{T0540})?$self->{_fields}->{T0540}[0]{content}:'';

    # ISSN
    $abstract_fields_ref->{issn} = (exists $self->{_fields}->{T0543})?$self->{_fields}->{T0543}[0]{content}:(exists $self->{_fields}->{T0585})?$self->{_fields}->{T0585}[0]{content}:'';

    # Sprache
    $abstract_fields_ref->{language} = (exists $self->{_fields}->{T0015})?$self->{_fields}->{T0015}[0]{content}:
	(exists $self->{_fields}->{T0516})?$self->{_fields}->{T0516}[0]{content}:'';

    # Series
    $abstract_fields_ref->{series} = (exists $self->{_fields}->{T0451})?$self->{_fields}->{T0451}[0]{content}:'';

    # Band
    $abstract_fields_ref->{series_volume} = (exists $self->{_fields}->{T0089})?$self->{_fields}->{T0089}[0]{content}:(exists $self->{_fields}->{T0455})?$self->{_fields}->{T0455}[0]{content}:'';
    
    # Mediatyp
    $abstract_fields_ref->{type} = '';
    if ($abstract_fields_ref->{issn}){
	if (@{$abstract_fields_ref->{authors}}){
	    $abstract_fields_ref->{type} = 'article';
	}
	elsif ($abstract_fields_ref->{title}){
	    if ($abstract_fields_ref->{source}){
		$abstract_fields_ref->{type} = 'article';
	    }
	    else {
		$abstract_fields_ref->{type} = 'periodical';
	    }
	}
    }
    elsif ($abstract_fields_ref->{isbn}){
	if ($abstract_fields_ref->{title}){
	    $abstract_fields_ref->{type} = 'book';
	}
    }
    elsif ($abstract_fields_ref->{series}){
	if ($abstract_fields_ref->{title}){
	    $abstract_fields_ref->{type} = 'article';
	}
	else {
	    $abstract_fields_ref->{type} = 'magazine';
	}
    }
    elsif ($abstract_fields_ref->{title}){
	$abstract_fields_ref->{type} = 'book';
    }

    # Zugriffsart (online=Digital / E-Resource)
    $abstract_fields_ref->{availability} = (exists $self->{_fields}->{T4400})?$self->{_fields}->{T4400}[0]{content} :'';
    
    # URL
    my $urls_ref=[];
    foreach my $category (qw/T0662/){
        next if (!exists $self->{_fields}->{$category});
        foreach my $part_ref (@{$self->{_fields}->{$category}}){
	    my $thisdesc ="";
	    foreach my $descpart_ref (@{$self->{_fields}->{'T0663'}}){
		if ($part_ref->{'mult'} == $descpart_ref->{'mult'} ){
		    $thisdesc = $descpart_ref->{content};
		}
	    }

	    if ($thisdesc =~m/DOI/){
		$abstract_fields_ref->{onlineurl} = $part_ref->{content};
		$abstract_fields_ref->{doi} = $part_ref->{content};
		$abstract_fields_ref->{availability} = "online";
	    }
	    elsif ($thisdesc =~m/Volltext/){
		$abstract_fields_ref->{onlineurl} = $part_ref->{content};
		$abstract_fields_ref->{availability} = "online";
	    }
	    
	    push @$urls_ref, {
		url => $part_ref->{content},
		desc => $thisdesc,
	    };
        }
    }

    # Only one URL, so this must be digital...
    if (@$urls_ref == 1){
	$abstract_fields_ref->{onlineurl} = $urls_ref->[0]{url};	
    }

    $abstract_fields_ref->{urls} = $urls_ref;

    # Abstract
    $abstract_fields_ref->{abstract} = (exists $self->{_fields}->{T0750})?$self->{_fields}->{T0750}[0]{content}:'';

    # Source
    $abstract_fields_ref->{source} = (exists $self->{_fields}->{T0590})?$self->{_fields}->{T0590}[0]{content}:'';

    my $article_source = ($abstract_fields_ref->{source})?$abstract_fields_ref->{source}:$abstract_fields_ref->{series};

    # Information in T0596, else parse Source/Series Pages (e.g. EDS)
    if (exists $self->{_fields}->{T0596}){
	$abstract_fields_ref->{source_journal} = (exists $self->{_fields}->{T0376})?$self->{_fields}->{T0376}[0]{content}:$abstract_fields_ref->{series};
	
        foreach my $part_ref (@{$self->{_fields}->{T0596}}){
	    if    ($part_ref->{subfield} eq "b"){
		$abstract_fields_ref->{source_volume} = $part_ref->{content};
	    }
	    elsif    ($part_ref->{subfield} eq "s"){
		$abstract_fields_ref->{source_pages} = $part_ref->{content};
	    }
	    elsif    ($part_ref->{subfield} eq "h"){
		$abstract_fields_ref->{source_issue} = $part_ref->{content};
	    }
	}
    }
    elsif ($article_source){
	# Pages
        if ($article_source=~/ ; (S\. *\d+.*)$/){
	    $abstract_fields_ref->{source_pages} = $1;
        }
        elsif ($article_source=~/, (S\. *\d+.*)$/){
	    $abstract_fields_ref->{source_pages} = $1;
        }

        # Journal and/or Volume
        if ($article_source=~/^(.+?) ; (.*?) ; S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
	    $abstract_fields_ref->{source_journal} = $journal;
	    $abstract_fields_ref->{source_volume} = $2;
        }
        elsif ($article_source=~/^(.+?)\. (.*?), (\d\d\d\d), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;
            my $year    = $3;

            $journal =~ s/ \/ .*$//;
	    $abstract_fields_ref->{source_journal} = $journal;
	    $abstract_fields_ref->{source_volume} = $2;
	    $abstract_fields_ref->{source_year} = $3;

        }
        elsif ($article_source=~/^(.+?)\. (.*?), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
	    $abstract_fields_ref->{source_journal} = $journal;
	    $abstract_fields_ref->{source_volume} = $2;
        }
        elsif ($article_source=~/^(.+?) ; (.*?), S\. *\d+.*$/){
            my $journal = $1;
            my $volume  = $2;

            $journal =~ s/ \/ .*$//;
	    $abstract_fields_ref->{source_journal} = $journal;
	    $abstract_fields_ref->{source_volume} = $2;
        }
        elsif ($article_source=~/^(.*?) ; S\. *\d+.*$/){
            my $journal = $1;

            $journal =~ s/ \/ .*$//;
	    $abstract_fields_ref->{source_journal} = $journal;
        }
    }

    # Pages
    $abstract_fields_ref->{pages} = (exists $self->{_fields}->{T0433})?$self->{_fields}->{T0433}[0]{content}:'';

    # Edition
    $abstract_fields_ref->{edition} = (exists $self->{_fields}->{T0403})?$self->{_fields}->{T0403}[0]{content}:'';

    # Note
    $abstract_fields_ref->{note} = "";

    if (exists $self->{_fields}->{T0501}){
	my @notes = ();
	foreach my $note_ref (@{$self->{_fields}->{T0501}}){
	    push @notes, $note_ref->{content};
	}
	if (@notes){
	    $abstract_fields_ref->{note} = join('; ',@notes);
	}
    }
    
    if ($logger->is_debug){
	$logger->debug("Abstract Fields: ".YAML::Dump($abstract_fields_ref));
    }
    
    return $abstract_fields_ref;
}

sub to_abstract_fields_marc21 {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $abstract_fields_ref = {};

    # Definition sprechender Feldnamen mit deren Inhalten
    #
    # authors[] : Verfasser 0100/0101
    # editors[] : Herausgeber anhand Supplement
    # corp[]    : Koerperschaften 0200
    # creator[] : Urheber 0201
    # keywords[]: Schlagworte
    # classifications[]: Klassifikationen
    # edition   : Auflage
    # publisher : Verlag
    # place     : Verlagsort
    # title     : Titel
    # titlesup  : Zusatz zum Sachtitel
    # year      : Erscheinungsjahr
    # isbn      : ISBN
    # issn      : ISSN
    # language  : Sprache
    # urls[]    : URLs
    # abstract  : Abstrakt
    #
    # source    : Quelle Gesamtangabe
    #
    # aufgesplittet in:
    #   source_pages   : Quelle Seitenangabe
    #   source_journal : Quelle Zeitschriftentitel
    #   source_volume  : Quelle Bandnr
    #   source_year    : Quelle Jahr
    #
    # pages     : Kollation
    # series    : Gesamttitel
    # series_volume : Zaehlung Gesamttitel
    # edition   : Auflage
    # type      : Medientyp (article,book,periodical)

    my $field_ref = $self->to_custom_field_scheme_1;

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($field_ref));
    }
	
    # Verfasser und Herausgeber konstruieren
    my $authors_ref=[];
    my $editors_ref=[];
    foreach my $category (qw/T0100 T0700 T0900/){
        next if (!defined $field_ref->{$category});
        foreach my $part_ref (@{$field_ref->{$category}}){
            if (defined $part_ref->{e} && $part_ref->{e} =~ /Hrsg/){
                push @$editors_ref, $part_ref->{a} if (defined $part_ref->{a});
            }
            else{
                push @$authors_ref, $part_ref->{a} if (defined $part_ref->{a});
            }
        }
    }

    $abstract_fields_ref->{authors} = $authors_ref;
    $abstract_fields_ref->{editors} = $editors_ref;

    # Urheber und Koerperschaften konstruieren
    my $corp_ref=[];
    my $creator_ref=[];
    foreach my $category (qw/T0110 T0710/){
        next if (!defined $field_ref->{$category});
        foreach my $part_ref (@{$field_ref->{$category}}){
	    push @$corp_ref, $part_ref->{a} if (defined $part_ref->{a});
        }
    }

    foreach my $category (qw/T0910/){
        next if (!defined $field_ref->{$category});
        foreach my $part_ref (@{$field_ref->{$category}}){
	    push @$creator_ref, $part_ref->{a} if (defined $part_ref->{a});
        }
    }

    $abstract_fields_ref->{corp} = $corp_ref;
    $abstract_fields_ref->{creator} = $creator_ref;
    
    # Schlagworte
    my $keywords_ref=[];
    foreach my $category (qw/T0600 T0610 T0648 T0650 T0651 T0655 T0688/){
        next if (!defined $field_ref->{$category});
        foreach my $part_ref (@{$field_ref->{$category}}){
            push @$keywords_ref, $part_ref->{a} if (defined $part_ref->{a});
        }
    }

    $abstract_fields_ref->{keywords} = $keywords_ref;

    # Klassifikationen
    my $classifications_ref=[];
    foreach my $category (qw/T0050 T0082 T0084/){
        next if (!defined $field_ref->{$category});
        foreach my $part_ref (@{$field_ref->{$category}}){
            push @$classifications_ref, $part_ref->{a} if (defined $part_ref->{a});
        }
    }

    $abstract_fields_ref->{classifications} = $classifications_ref;
    
    # Auflage
    $abstract_fields_ref->{edition} = (defined $field_ref->{T0250}  && defined $field_ref->{T0250}[0]{a})?$field_ref->{T0250}[0]{a}:'';

    $abstract_fields_ref->{publisher} = (defined $field_ref->{T0264} && defined $field_ref->{T0264}[0]{b})?$field_ref->{T0264}[0]{b}:'';

    # Verlagsort
    $abstract_fields_ref->{place} = (defined $field_ref->{T0264} && defined $field_ref->{T0264}[0]{a})?$field_ref->{T0264}[0]{a}:'';

    # Titel
    $abstract_fields_ref->{title} = (defined $field_ref->{T0245} && defined $field_ref->{T0245}[0]{a})?$field_ref->{T0245}[0]{a}:'';

    # Zusatz zum Titel
    $abstract_fields_ref->{titlesup} = (defined $field_ref->{T0245} && defined $field_ref->{T0245}[0]{b})?$field_ref->{T0245}[0]{b}:'';
#    Folgende Erweiterung um titlesup ist nuetzlich, laeuft aber der
#    Bibkey-Bildung entgegen
#    if ($title && $titlesup){
#        $title = "$title : $titlesup";
#    }

    # Jahr
    $abstract_fields_ref->{year} = (defined $field_ref->{T0260} && defined $field_ref->{T0260}[0]{c})?$field_ref->{T0260}[0]{c}:(defined $field_ref->{T0264} && defined $field_ref->{T0264}[0]{c})?$field_ref->{T0264}[0]{c}:'';

    # ISBN
    $abstract_fields_ref->{isbn} = (defined $field_ref->{T0020} && defined $field_ref->{T0020}[0]{a})?$field_ref->{T0020}[0]{a}:'';

    # ISSN
    $abstract_fields_ref->{issn} = (defined $field_ref->{T0022} && defined $field_ref->{T0022}[0]{a})?$field_ref->{T0022}[0]{a}:'';

    # Sprache
    $abstract_fields_ref->{language} = (defined $field_ref->{T0041} && defined $field_ref->{T0041}[0]{a})?$field_ref->{T0041}[0]{a}:
	(defined $field_ref->{T0516})?$field_ref->{T0516}[0]{content}:'';

    # (1st) Series
    foreach my $category (qw/T0490 T0440/){
        next if (!defined $field_ref->{$category});
        foreach my $part_ref (@{$field_ref->{$category}}){
	    $abstract_fields_ref->{series} = $part_ref->{a} if (defined $part_ref->{a});
	    $abstract_fields_ref->{series_volume} = $part_ref->{v} if (defined $part_ref->{v});

	    last if (defined $abstract_fields_ref->{series});
	}
	last if (defined $abstract_fields_ref->{series});
    }
    
    # Mediatyp
    if ($abstract_fields_ref->{issn}){
	if (@{$abstract_fields_ref->{authors}}){
	    $abstract_fields_ref->{type} = 'article';
	}
	elsif ($abstract_fields_ref->{title}){
	    if ($abstract_fields_ref->{source}){
		$abstract_fields_ref->{type} = 'article';
	    }
	    else {
		$abstract_fields_ref->{type} = 'periodical';
	    }
	}
    }
    elsif ($abstract_fields_ref->{isbn}){
	if ($abstract_fields_ref->{title}){
	    $abstract_fields_ref->{type} = 'book';
	}
    }
    elsif ($abstract_fields_ref->{series}){
	if ($abstract_fields_ref->{title}){
	    $abstract_fields_ref->{type} = 'article';
	}
	else {
	    $abstract_fields_ref->{type} = 'magazine';
	}
    }
    elsif ($abstract_fields_ref->{title}){
	$abstract_fields_ref->{type} = 'book';
    }

    # Zugriffsart (online=Digital / E-Resource)
    $abstract_fields_ref->{availability} = (exists $field_ref->{T4400})?$field_ref->{T4400}[0]{content} :'';

    # Todo: Ab hier noch zu mappen!!! 20220509
	
    # URL
    my $urls_ref=[];
    foreach my $category (qw/T0856/){
        next if (!defined $field_ref->{$category});
        foreach my $part_ref (@{$field_ref->{$category}}){           	    
	    my $thisdesc = (defined $part_ref->{'3'})?$part_ref->{'3'}:(defined $part_ref->{z})?$part_ref->{z}:"";

	    if ($thisdesc =~m/DOI/){
		$abstract_fields_ref->{onlineurl} = $part_ref->{u};
		$abstract_fields_ref->{availability} = "online";
	    }
	    elsif ($thisdesc =~m/Volltext/){
		$abstract_fields_ref->{onlineurl} = $part_ref->{u};
		$abstract_fields_ref->{availability} = "online";
	    }
	    
	    push @$urls_ref, {
		url => $part_ref->{u},
		desc => $thisdesc,
	    };
        }
    }

    # Only one URL, so this must be digital...
    if (@$urls_ref == 1){
	$abstract_fields_ref->{onlineurl} = $urls_ref->[0]{url};	
    }

    $abstract_fields_ref->{urls} = $urls_ref;

    # Abstract
    $abstract_fields_ref->{abstract} = (defined $field_ref->{T0520} && defined $field_ref->{T0520}[0]{a})?$field_ref->{T0520}[0]{a}:'';

    # Source


    my $article_source = ($abstract_fields_ref->{source})?$abstract_fields_ref->{source}:$abstract_fields_ref->{series};

    if (defined $field_ref->{T0773}){
	foreach my $part_ref (@{$field_ref->{T0773}}){
	    $abstract_fields_ref->{source_journal} = $part_ref->{t} if (defined $part_ref->{t});
	    if (defined $part_ref->{g}){
		($abstract_fields_ref->{source_volume}) = $part_ref->{g} =~m/(Vol\. \d+)/;
		($abstract_fields_ref->{source_pages}) = $part_ref->{g} =~m/(p\. \d+-\d+)/; 
		($abstract_fields_ref->{source_issue}) = $part_ref->{g} =~m/(no\. \d+)/; 
	    }
	    
	    if (defined $part_ref->{d} && $part_ref->{d} =~m/\d\d\d\d/){
		($abstract_fields_ref->{source_year}) = $part_ref->{d} =~m/(\d\d\d\d)/;
	    }
	}
	if (defined $field_ref->{T0773}[0]{t}){
	    $abstract_fields_ref->{source} = $field_ref->{T0773}[0]{t};
	    if (defined $field_ref->{T0773}[0]{g}){
		$abstract_fields_ref->{source}.= ": ".$field_ref->{T0773}[0]{g};
	    }
	    if (defined $field_ref->{T0773}[0]{d}){
		$abstract_fields_ref->{source}.= " (".$field_ref->{T0773}[0]{d}.")";
	    }
	}
    }

    # Pages
    $abstract_fields_ref->{pages} = (exists $field_ref->{T0300})?$field_ref->{T0300}[0]{a}:'';

    # Edition
    $abstract_fields_ref->{edition} = (exists $field_ref->{T0250})?$field_ref->{T0250}[0]{a}:'';

    # # Cleanup fields from marc21 junk
    # foreach my $key (keys %{$abstract_fields_ref}){
    # 	$logger->debug("Ref $key:".(ref $abstract_fields_ref->{$key}));
    # 	$abstract_fields_ref->{$key} =~s{\s*[,:./]\s*$}{} if (ref $abstract_fields_ref->{$key} ne "ARRAY") ;
    # }
    
    if ($logger->is_debug){
	$logger->debug(YAML::Dump($abstract_fields_ref));
    }
    
    return $abstract_fields_ref;
}

sub to_custom_field_scheme_1 {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Umwandlung des ggf. z.B. bereits mit MARC21 (Sub)Feldern gefuellten Internformats
    # in ein besser in den Templates auswertbares Daten-Schema
    #
    # Multiple Subfeldinhalte werden mit Leerzeichen zusammengefasst
    #
    # Beispiel:

    # my $example_ref = {
    # 	# Key: T=Title + (MARC)Fieldno (4 stellig vorgenullt)
    # 	'T0100' => [	    
    # 	    {
    # 		# Mult-Feld
    # 		'mult' => 1, # erster Autor
    #           'ind'  => '11' # Indikator
    # 		    # Subfelder
    # 		    'a' => 'Morgan, John Pierpont',
    # 		    'd' => '1837-1913',
    # 		    'e' => 'collector',
    # 	    },
    # 	    {
    # 		# Mult-Feld
    # 		'mult' => 2, # Zweiter Autor
    #           'ind'  => '11' # Indikator
    # 		    # Subfelder
    # 		    'a' => 'Adams, Henry',
    # 		    'd' => '1838-1918',
    # 	    },
    # 	    ],
    # };
    
    my $field_scheme_ref = {};

    if (defined $self->{_fields}){
	if ($logger->is_debug){
	    $logger->debug("Source-Fields ". YAML::Dump($self->{_fields}));
	}

	my $field_mult_ref = {};
	
	foreach my $fieldname (keys %{$self->{_fields}}){
	    if ($fieldname !~ m/^[TPCNSX]C?\d+/){
		$field_scheme_ref->{$fieldname} = $self->{_fields}{$fieldname};
		next;
	    }
	    
	    my $tmp_scheme_ref = {};

	    if (defined $self->{_fields}{$fieldname}){
		foreach my $item_ref (@{$self->{_fields}{$fieldname}}){
		    $item_ref->{subfield} = "" unless (defined $item_ref->{subfield});
		    unless ($item_ref->{mult}){
			$item_ref->{mult} = (defined $field_mult_ref->{$fieldname})?$field_mult_ref->{$fieldname}++:1;
		    }

		    if (defined $item_ref->{mult} && defined $item_ref->{subfield} && $item_ref->{content}){
			$item_ref->{content} =~s{\s*[,:./]\s*$}{} if ($fieldname=~m/(T0245|T0250|T0264|T0300)/); # Cleanup MARC21 junk

			$tmp_scheme_ref->{$item_ref->{mult}}{'ind'} = $item_ref->{ind};
			
			if (!defined $tmp_scheme_ref->{$item_ref->{mult}}{$item_ref->{subfield}}){
			    $tmp_scheme_ref->{$item_ref->{mult}}{$item_ref->{subfield}} = $item_ref->{content};
			}
			else {
			    $tmp_scheme_ref->{$item_ref->{mult}}{$item_ref->{subfield}} = $tmp_scheme_ref->{$item_ref->{mult}}{$item_ref->{subfield}}." ".$item_ref->{content};
			}
		    }
		}
	    }

	    if ($logger->is_debug){
		$logger->debug("Interim-Fields 1". YAML::Dump($tmp_scheme_ref));
	    }
	    
	    foreach my $mult (sort keys %$tmp_scheme_ref){
		my $tmp2_scheme_ref = {
		    mult => $mult,
		};
		foreach my $subfield (keys %{$tmp_scheme_ref->{$mult}}){	    
		    $tmp2_scheme_ref->{$subfield} = $tmp_scheme_ref->{$mult}{$subfield};
		}

		if ($logger->is_debug){
		    $logger->debug("Interim-Fields 2". YAML::Dump($tmp2_scheme_ref));
		}

		push @{$field_scheme_ref->{$fieldname}}, $tmp2_scheme_ref;
	    }
	    
	}
    }

    if ($logger->is_debug){
	$logger->debug("Destination-Fields ". YAML::Dump($field_scheme_ref));
    }

    return $field_scheme_ref;
}

sub to_custom_field_scheme_2 {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Umwandlung des ggf. z.B. bereits mit MARC21 (Sub)Feldern gefuellten Internformats
    # in ein besser in den Templates auswertbares Daten-Schema
    #
    # Beispiel:

    # my $example_ref = {
    # 	# Key: T=Title + (MARC)Fieldno (4 stellig vorgenullt)
    # 	'T1943' => [	    
    # 	      {
    # 		# Mult-Feld
    # 		'mult' => 1, # Erstes Holding
    # 	        # Subfelder
    # 	        'z' => [
    #                    {
    #                       content => '[N=1]', # Luecken im Bestandsverlauf
    #                       ind     => ' 0',
    #                    },
    #                    {
    #                       content => 'vormals xyz', # Bemerkung
    #                       ind     => '30',
    #                    }
    #                  ],
    # 		 h' => [
    #                    {
    #                       content => 'AB123', # Signatur
    #                       ind     => '',
    #                    },
    #                  ],
    #         },
    # 	    ],
    # };
    
    my $field_scheme_ref = {};

    if (defined $self->{_fields}){
	if ($logger->is_debug){
	    $logger->debug("Source-Fields ". YAML::Dump($self->{_fields}));
	}

	my $field_mult_ref = {};
	
	foreach my $fieldname (keys %{$self->{_fields}}){
	    if ($fieldname !~ m/^[TPCNSX]C?\d+/){
		$field_scheme_ref->{$fieldname} = $self->{_fields}{$fieldname};
		next;
	    }
	    
	    my $tmp_scheme_ref = {};

	    if (defined $self->{_fields}{$fieldname}){
		foreach my $item_ref (@{$self->{_fields}{$fieldname}}){
		    $item_ref->{subfield} = "" unless (defined $item_ref->{subfield});
		    unless ($item_ref->{mult}){
			$item_ref->{mult} = (defined $field_mult_ref->{$fieldname})?$field_mult_ref->{$fieldname}++:1;
		    }

		    if (defined $item_ref->{mult} && defined $item_ref->{subfield} && $item_ref->{content}){
			$item_ref->{content} =~s{\s*[,:./]\s*$}{} if ($fieldname=~m/(T0245|T0250|T0264|T0300)/); # Cleanup MARC21 junk
			
			push @{$tmp_scheme_ref->{$item_ref->{mult}}{$item_ref->{subfield}}}, {
			    content => $item_ref->{content},
			    ind     => $item_ref->{ind},
			};
		    }
		}
	    }

	    if ($logger->is_debug){
		$logger->debug("Interim-Fields 1". YAML::Dump($tmp_scheme_ref));
	    }
	    
	    foreach my $mult (sort keys %$tmp_scheme_ref){
		my $tmp2_scheme_ref = {
		    mult => $mult,
		};
		foreach my $subfield (keys %{$tmp_scheme_ref->{$mult}}){	    
		    $tmp2_scheme_ref->{$subfield} = $tmp_scheme_ref->{$mult}{$subfield};
		}

		if ($logger->is_debug){
		    $logger->debug("Interim-Fields 2". YAML::Dump($tmp2_scheme_ref));
		}

		push @{$field_scheme_ref->{$fieldname}}, $tmp2_scheme_ref;
	    }
	    
	}
    }

    if ($logger->is_debug){
	$logger->debug("Destination-Fields ". YAML::Dump($field_scheme_ref));
    }

    return $field_scheme_ref;
}

sub to_tags {
    my ($self) = @_;

    my $normalizer = $self->{_normalizer};
    
    # Schlagworte
    my $keywords_ref=[];
    foreach my $category (qw/T0710 T0902 T0907 T0912 T0917 T0922 T0927 T0932 T0937 T0942 T0947/){
        next if (!exists $self->{_fields}->{$category});
        foreach my $part_ref (@{$self->{_fields}->{$category}}){
            foreach my $content_part (split('\s+',$part_ref->{content})){
                push @$keywords_ref, $normalizer->normalize({
                    strip_first_stopword => 1,
                    tagging              => 1,
                    content              => $content_part,
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

    return ($self->{_fields},$self->{_holding},$self->{_circulation});
}

sub to_hash {
    my ($self) = @_;
    
    my $hash_ref = {
        'id'          => $self->{id},
        'database'    => $self->{database},
        'fields'      => $self->{_fields},
        'locations'   => $self->{_locations},
        'items'       => $self->{_holding},
	 'circulation' => $self->{_circulation},
	 'generic_attributes' => $self->{generic_attributes},   
    };

    return $hash_ref;
}

sub from_hash {
    my ($self,$hash_ref)=@_;
    
    $self->set_id($hash_ref->{id});
    $self->set_database($hash_ref->{database});
    
    $self->set_fields($hash_ref->{fields});
    $self->set_holding($hash_ref->{items});
    $self->set_circulation($hash_ref->{circulation});
    $self->set_locations($hash_ref->{locations});
    $self->set_generic_attributes($hash_ref->{generic_attributes});
	
    return $self;
}
    

sub record_exists {
    my ($self) = @_;

    my @categories = grep { /^[PCTX]/ } keys %{$self->{_fields}};

    return 0 if (!@categories);
    
    my $record_exists = 0;
    
    foreach my $field (@categories){
	$record_exists = 1 if (@{$self->{_fields}{$field}});
    }
    
    return $record_exists;
}

sub set_record_exists {
    my ($self) = @_;

    $self->{_exists} = 1;

    return $self;
}

sub to_drilldown_term {
    my ($self,$term)=@_;

    my $config = $self->get_config;

    my $normalizer = $self->{_normalizer};
    
    $term = $normalizer->normalize({
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
    my ($self,$msg)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $record = $self->to_hash;

    # Anreicherung mit Feld-Bezeichnungen
    if (defined $msg){
        foreach my $fieldnumber (keys %{$record->{fields}}){
            my $effective_fieldnumber = $fieldnumber;
            my $mapping = $config->{'categorymapping'};
            if (defined $mapping->{$record->{database}}{$fieldnumber}){
                $effective_fieldnumber = $fieldnumber."-".$record->{database};
            }
                    
            foreach my $fieldcontent_ref (@{$record->{fields}->{$fieldnumber}}){
                $fieldcontent_ref->{description} = $msg->maketext($effective_fieldnumber);
            }
        }

        foreach my $item_ref (@{$record->{items}}){            
            foreach my $fieldnumber (keys %{$item_ref}){                
                next if ($fieldnumber eq "id");

                my $effective_fieldnumber = $fieldnumber;
                my $mapping = $config->{'categorymapping'};
                if (defined $mapping->{$record->{database}}{$fieldnumber}){
                    $effective_fieldnumber = $fieldnumber."-".$record->{database};
                }
                
                $item_ref->{$fieldnumber}->{description} = $msg->maketext($effective_fieldnumber);
            }
        }
    }

    my $contentstring = "";
    
    eval {
	$contentstring= JSON::XS->new->utf8->canonical->encode($record);
    };
    
    if ($@){
	if ($logger->is_error){
	    $logger->error("Canonical Encoding failed: ".YAML::Dump($record));
	}
    }
    
    return $contentstring; 
}

sub from_json {
    my ($self,$json)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    eval {
        my $json_ref = JSON::XS::decode_json $json;

        $self->from_hash($json_ref);
    };

    if ($@){
        $logger->error($@);
    }
        
    return $self;
}

sub set_status {
    my ($self,$status,$value) = @_;

    $self->{_status}{$status} = $value;

    return $self;
}

sub get_status {
    my ($self,$status) = @_;

    return 0 if (!defined $self->{_status} && !defined $self->{_status}{$status});
    
    return $self->{_status}{$status};
}

sub set_id {
    my ($self,$id) = @_;

    $self->{id}           = $id;
    $self->{_normset}{id} = $id;

    return $self;
}

sub set_database {
    my ($self,$database) = @_;

    $self->{database}           = $database;
    $self->{_normset}{database} = $database;

    return $self;
}

sub get_provenances_of_media {
    my ($self,$medianumber,$msg) = @_;

    my $logger = get_logger();

    my $database = $self->{database};

    my $schema   = $self->{dbinfo}{schema}{$database} || '';

    if ($schema eq "mab2"){
	$logger->debug("Provenances from mab2");
	return $self->get_provenances_of_media_mab2($medianumber,$msg);
    }
    elsif ($schema eq "marc21"){
	$logger->debug("Provenances from marc21");	
	return $self->get_provenances_of_media_marc21($medianumber,$msg);
    }

    return [];
}

sub get_provenances_of_media_mab2 {
    my ($self,$medianumber,$msg) = @_;

    my $logger = get_logger();

    $logger->debug("Getting provenances for $medianumber");
    
    my $config = $self->get_config;
    
    my $provenances_ref = [];

    return [] unless (defined $self->{_fields}{'T4309'});

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($self->get_fields));
    }

    foreach my $provenance_ref  (@{$self->get_provenances_mab2($msg)}){
	if ($provenance_ref->{'T4309'}[0]{content} eq $medianumber){
	    push @{$provenances_ref}, $provenance_ref;
	}
    }
        
    return $provenances_ref;
}

sub get_provenances_of_media_marc21 {
    my ($self,$medianumber,$msg) = @_;

    my $logger = get_logger();

    $logger->debug("Getting provenances for $medianumber");
    
    my $config = $self->get_config;
    
    my $provenances_ref = [];

    return [] unless (defined $self->{_fields}{'T4309'});

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($self->get_fields));
    }

    foreach my $provenance_ref  (@{$self->get_provenances_marc21($msg)}){
	if ($provenance_ref->{'T4309'}{'a'} eq $medianumber){
	    push @{$provenances_ref}, $provenance_ref;
	}
    }
        
    return $provenances_ref;
}

sub get_provenances {
    my ($self,$msg) = @_;

    my $logger = get_logger();

    my $database = $self->{database};

    my $schema   = $self->{dbinfo}{schema}{$database} || '';

    if ($schema eq "mab2"){
	$logger->debug("Provenances from mab2");
	return $self->get_provenances_mab2($msg);
    }
    elsif ($schema eq "marc21"){
	$logger->debug("Provenances from marc21");	
	return $self->get_provenances_marc21($msg);
    }

    return [];
}

sub get_provenances_mab2 {
    my ($self,$msg) = @_;

    my $logger = get_logger();

    my $config = $self->get_config;

    my $provenances_ref = [];

    return [] unless (defined $self->{_fields}{'T4309'});

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($self->get_fields));
    }
    
    foreach my $medianumber_ref (@{$self->{_fields}{'T4309'}}){
        my $mult = $medianumber_ref->{mult};

        my $this_provenance_ref = {};
        $this_provenance_ref->{'T4309'} = [ { mult => $mult, content => $medianumber_ref->{content}} ];
        foreach my $field ('T4306','T4307','T4308','T4310','T4311','T4312','T4313','T4314','T4315','T4316','T4317'){
            my $fields_ref = $self->get_field({ field => $field });
            next unless ($fields_ref);
            
            foreach my $field_ref (@{$fields_ref}){
		if ($logger->is_debug){
		    $logger->debug(YAML::Dump($field_ref));
		}
		
                if ($field_ref->{mult} eq $mult){
                        push @{$this_provenance_ref->{$field}}, $field_ref;
                    }
            }
        }

        # Anreicherung mit Feld-Bezeichnungen
        if (defined $msg){
            foreach my $fieldnumber (keys %{$this_provenance_ref}){
                my $effective_fieldnumber = $fieldnumber;
                my $mapping = $config->{'categorymapping'};
                if (defined $mapping->{$self->{database}}{$fieldnumber}){
                    $effective_fieldnumber = $fieldnumber."-".$self->{database};
                }
                
                foreach my $fieldcontent_ref (@{$this_provenance_ref->{$fieldnumber}}){
                    $fieldcontent_ref->{description} = $msg->maketext($effective_fieldnumber);
                }
            }
        }

        push @$provenances_ref, $this_provenance_ref;
    }
    
    return $provenances_ref;
}

sub get_provenances_marc21 {
    my ($self,$msg) = @_;

    my $logger = get_logger();

    my $config = $self->get_config;

    my $provenances_ref = [];

    return [] unless (defined $self->{_fields}{'T4309'});

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($self->get_fields));
    }

    my $field_ref = $self->to_custom_field_scheme_1;

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($field_ref));
    }

    my $tmp_fields_ref = {};
    foreach my $field ('T4306','T4307','T4308','T4309','T4310','T4311','T4312','T4313','T4314','T4315','T4316','T4317'){

	foreach my $subfield_ref (@{$field_ref->{$field}}){
	    $tmp_fields_ref->{$subfield_ref->{mult}}{$field} = $subfield_ref;
	}
    }

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($tmp_fields_ref));
    }

    foreach my $mult (sort keys %{$tmp_fields_ref}){
	push @{$provenances_ref}, $tmp_fields_ref->{$mult};
    }
    
    return $provenances_ref;
}


sub get_id {
    my ($self) = @_;

    return $self->{id};
}

sub get_database {
    my ($self) = @_;

    return $self->{database};
}

sub set_from_psgi_request {
    my ($self,$r) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $query = $r;

    my $set_categories_ref = [];

    foreach my $category_arg ($query->param){
        next unless ($category_arg=~m/^[TX]\d\d\d\d/); 

        if ($query->param($category_arg)){
            if ($category_arg=~m/^T/){
                $self->set_field({ field => $category_arg, subfield => '', mult => 1, content => $query->param($category_arg) });
            }
            elsif ($category_arg=~m/^X/){
                $self->set_holding_field({ field => $category_arg, subfield => '', mult => 1, content => $query->param($category_arg) });
            }
        } 
    } 

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($self->{_fields}));
    }
    
    return $self;
}

# sub store {
#     my ($self,$arg_ref) = @_;

#     # Set defaults
#     my $dbh               = exists $arg_ref->{dbh}
#         ? $arg_ref->{dbh}               : undef;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     my $config = OpenBib::Config->new;

#     my $is_new = (exists $self->{id})?1:0;

#     my $local_dbh = 0;
#     if (!defined $dbh){
#         # Kein Spooling von DB-Handles!
#         $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
#             or $logger->error_die($DBI::errstr);
#         $local_dbh = 1;
#     }

#     if ($is_new){

#     # Titelkategorien
#     {
#         # Neue ID bestimmen
#         my $request = $dbh->prepare("select max(id)+1 as nextid from title");
#         $request->execute();
#         my $result=$request->fetchrow_hashref;

#         $self->set_id($result->{nextid});

#         # Kategorien eintragen
#         my ($atime,$btime,$timeall)=(0,0,0);
        
#         if ($config->{benchmark}) {
#             $atime=new Benchmark;
#         }
        
#         my $reqstring="insert into title (id,category,indicator,content) values(?,?,?,?)";
#         $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);

#         foreach my $category (keys %{$self->{_fields}}){
#             $category=~s/^T//;

#             # Hierarchieverknuepfung
#             if ($category eq "0004"){
#                 my $reqstring2 = "insert into conn (category,sourceid,sourcetype,targetid,targettype) values ('0004',?,1,?,1);where targetid=? and sourcetype=1 and targettype=1";
#                 my $request2 = $dbh->prepare($reqstring2);
#                 foreach my $item (@{$self->{_fields}->{$category}}){
#                     $request2->execute($item->{content},$self->{id});
#                 }
#                 $request2->finish;
#             }
#             # oder 'normale' Kategorie
#             else {
#                 foreach my $item (@{$self->{_fields}->{$category}}){
#                     $request->execute($self->{id},$category,$item->{indicator},$item->{content});
#                 }
#             }
#         }
        
#         $request->finish();

#         if ($config->{benchmark}) {
#             $btime=new Benchmark;
#             $timeall=timediff($btime,$atime);
#             $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
#         }
#     }
    
# #     # Verknuepfte Normdaten
# #     {
# #         my ($atime,$btime,$timeall)=(0,0,0);
        
# #         if ($config->{benchmark}) {
# #             $atime=new Benchmark;
# #         }
        
# #         my $reqstring="select category,targetid,targettype,supplement from conn where sourceid=? and sourcetype=1 and targettype IN (2,3,4,5)";
# #         my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
# #         $request->execute($id) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
# #         while (my $res=$request->fetchrow_hashref) {
# #             my $category   = "T".sprintf "%04d",$res->{category };
# #             my $targetid   =        decode_utf8($res->{targetid  });
# #             my $targettype =                    $res->{targettype};
# #             my $supplement =        decode_utf8($res->{supplement});
            
# # 	    # Korrektes UTF-8 Encoding Flag wird in get_*_ans_*
# # 	    # vorgenommen
            
# #             my $recordclass    =
# #                 ($targettype == 2 )?"OpenBib::Record::Person":
# #                     ($targettype == 3 )?"OpenBib::Record::CorporateBody":
# #                         ($targettype == 4 )?"OpenBib::Record::Subject":
# #                             ($targettype == 5 )?"OpenBib::Record::Classification":undef;
            
# #             my $content = "";
# #             if (defined $recordclass){
# #                 my $record=$recordclass->new({database=>$self->{database}});
# #                 $record->load_name({dbh => $dbh, id=>$targetid});
# #                 $content=$record->name_as_string;
# #             }
            
# #             push @{$fields_ref->{$category}}, {
# #                 id         => $targetid,
# #                 content    => $content,
# #                 supplement => $supplement,
# #             };
# #         }
# #         $request->finish();
        
# #         if ($config->{benchmark}) {
# #             $btime=new Benchmark;
# #             $timeall=timediff($btime,$atime);
# #             $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
# #         }
#     }
#     else {
#         $self->_delete_from_rdbms;
#         $self->_delete_from_searchengine;
#     }
    
#     return $self;
# }

# sub _delete_from_rdbms {
#     my ($self,$arg_ref) = @_;
    
#     # Set defaults
#     my $dbh               = exists $arg_ref->{dbh}
#         ? $arg_ref->{dbh}               : undef;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     my $config = OpenBib::Config->new;

#     my $local_dbh = 0;
#     if (!defined $dbh){
#         # Kein Spooling von DB-Handles!
#         $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
#             or $logger->error_die($DBI::errstr);
#         $local_dbh = 1;
#     }

#     my $request = $dbh->prepare("delete from title where id=?");
#     $request->execute($self->get_id);
    
#     $request = $dbh->prepare("delete from conn where sourcetype=1 and sourceid=?");
#     $request->execute($self->get_id);
#     $request = $dbh->prepare("delete from titlelistitem where id=?");
#     $request->execute($self->get_id);
    
#     return $self;
# }

# sub _store_into_rdbms {
#     my ($self,$arg_ref) = @_;
    
#     # Set defaults
#     my $dbh               = exists $arg_ref->{dbh}
#         ? $arg_ref->{dbh}               : undef;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     my $config = OpenBib::Config->new;

#     my $local_dbh = 0;
#     if (!defined $dbh){
#         # Kein Spooling von DB-Handles!
#         $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
#             or $logger->error_die($DBI::errstr);
#         $local_dbh = 1;
#     }

#     my $request = $dbh->prepare("delete from title where id=?");
#     $request->execute($self->get_id);
    
#     $request = $dbh->prepare("delete from conn where sourcetype=1 and sourceid=?");
#     $request->execute($self->get_id);
#     $request = $dbh->prepare("delete from titlelistitem where id=?");
#     $request->execute($self->get_id);
    
#     return $self;
# }

# sub _delete_from_searchengine {
#     my $self = shift;

    
#     return $self;
# }

sub enrich_cdm {
    my ($self,$id,$url)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $enrich_data_ref = {};
    
    unless ($config->get('active_cdm')){
	$logger->debug("CDM support disabled");
	return $enrich_data_ref;
    }
    
    # Wenn kein URI, dann Default-URI
    $url = $config->{cdm_base}.$config->{cdm_path} unless ($url);

    $url.=$id;

    $logger->debug("CDM-URL: $url ");
    
    my $ua = new LWP::UserAgent;
    $ua->agent("OpenBib/1.0");
    $ua->timeout(10);
    my $request = new HTTP::Request('GET', $url);
    my $response = $ua->request($request);

    my $content = $response->content;

    if ($content){
        $content=~s/<!--.+?-->//g;
        $logger->debug("CDM: Result for ID $id: ".$content);
        eval {
           $enrich_data_ref = JSON::XS::decode_json($content);
        };
        if ($@){
           $logger->error($@);
        }
    }

    return $enrich_data_ref;
}

sub to_indexable_document {
    my $self = shift;
    my $database = shift;

    my $config      = $self->get_config;
    my $conv_config = new OpenBib::Conv::Config({dbname => $database});

    my $doc = new OpenBib::Index::Document({ database => $self->{_database}, id => $self->{_id} });
    
    my $titlecache_ref   = {}; # Inhalte fuer den Titel-Cache
    my $searchengine_ref = {}; # Inhalte fuer die Suchmaschinen

}

sub get_availability {
    my ($self,$availability_ref,$unavailability_ref) = @_;

    my $availability = "unknown";

    if (defined $availability_ref && @$availability_ref){
	foreach my $this_availability_ref (@$availability_ref){
	    $availability = $this_availability_ref->{service};
	}
    }

    if (defined $unavailability_ref && @$unavailability_ref){
	foreach my $this_unavailability_ref (@$unavailability_ref){
	    if ($this_unavailability_ref->{service} eq "loan"){
		$availability = "lent";		
		
		if (defined $this_unavailability_ref->{expected} && $this_unavailability_ref->{expected} eq "missing"){
		    $availability = "missing";
		}
		if (defined $this_unavailability_ref->{expected} && $this_unavailability_ref->{expected} eq "temporarily_unavailable"){
		    $availability = "temporarily_unavailable";
		}
	    }
	    elsif ($this_unavailability_ref->{service} eq "order"){
		$availability = "ordered";
	    }
	}
    }

    return $availability;
}

1;
