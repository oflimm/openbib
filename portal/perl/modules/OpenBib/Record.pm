#####################################################################
#
#  OpenBib::Record.pm
#
#  Basisklasse
#
#  Dieses File ist (C) 2012-2018 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Record;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Cache::Memcached::Fast;
use Compress::LZ4;
use DBI;
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use SOAP::Lite;
use Storable;
use URI::Escape;
use YAML ();

use OpenBib::API::HTTP::JOP;
use OpenBib::Config;
use OpenBib::Config::File;
use OpenBib::Schema::Catalog;
use OpenBib::Schema::Enrichment;
use OpenBib::Schema::Enrichment::Singleton;
use OpenBib::SearchQuery;

sub get_schema {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Getting Schema $self");
    
    if (defined $self->{schema}){
        $logger->debug("Reusing Schema $self");
        return $self->{schema};
    }

    $logger->debug("Creating new Schema $self");    
    
    $self->connectDB;
    
    return $self->{schema};
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config::File->instance;

    eval {
        # UTF8: {'pg_enable_utf8'    => 1}
        $self->{schema} = OpenBib::Schema::Catalog->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},$config->{dboptions}) or $logger->error_die($DBI::errstr);
#        $self->{schema} = OpenBib::Schema::Catalog->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);
    };
    
    if ($@){
        $logger->fatal("Unable to connect schema to database $self->{database}: DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}");
    }

    return;

}

sub disconnectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Try disconnecting from Catalog-DB $self");
    
    if (defined $self->{schema}){
        eval {
            $logger->debug("Disconnect from Catalog-DB now $self");
            $self->{schema}->storage->disconnect;
            delete $self->{schema};
        };

        if ($@){
            $logger->error($@);
        }
    }
    
    return;
}

sub disconnectEnrichmentDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Try disconnecting from Catalog-DB $self");
    
    if (defined $self->{enrich_schema}){
        eval {
            $logger->debug("Disconnect from Catalog-DB now $self");
            $self->{enrich_schema}->storage->disconnect;
            delete $self->{enrich_schema};
        };

        if ($@){
            $logger->error($@);
        }
    }
    
    return;
}

sub DESTROY {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Destroying Catalog-Object $self");

    if (defined $self->{schema}){
        $self->disconnectDB;
    }

    if (defined $self->{enrich_schema}){
        $self->disconnectEnrichmentDB;
    }
    
    if (defined $self->{memc}){
        $self->disconnectMemcached;
    }
    
    return;
}

sub connectEnrichmentDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = OpenBib::Config->new;
    
    if ($self->{'enrichmntdbsingleton'}){
        eval {        
            #            $self->{enrich_schema} = OpenBib::Schema::Enrichment::Singleton->connect("DBI:Pg:dbname=$self->{systemdbname};host=$self->{systemdbhost};port=$self->{systemdbport}", $self->{systemdbuser}, $self->{systemdbpasswd}) or $logger->error_die($DBI::errstr);
            $self->{enrich_schema} = OpenBib::Schema::Enrichment::Singleton->connect("DBI:Pg:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd},$config->{enrichmntdboptions}) or $logger->error_die($DBI::errstr);
            
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $config->{enrichmntdbname}");
        }
    }
    else {
        eval {
            # UTF8: {'pg_enable_utf8'    => 1}
            $self->{enrich_schema} = OpenBib::Schema::Enrichment->connect("DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd},$config->{enrichmntdboptions}) or $logger->error_die($DBI::errstr);
            # $self->{enrich_schema} = OpenBib::Schema::Enrichment->connect("DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $config->{enrichmntdbname}: DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}");
        }

    }
    
    return;
}

sub set_generic_attributes {
    my ($self,$arg_ref) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    foreach my $attribute (keys %$arg_ref){
        $self->{generic_attributes}{$attribute} = $arg_ref->{$attribute};     
    }    
    
    return $self;
}

sub get_generic_attributes {
    my ($self) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($logger->is_debug){
        $logger->debug("Got: ".YAML::Dump($self->{generic_attributes}));
    }   
    
    return $self->{generic_attributes};
}

sub get_id {
    my ($self)=@_;

    return (defined $self->{id})?$self->{id}:undef;
}

sub get_encoded_id {
    my ($self) = @_;

    return (defined $self->{id})?uri_escape($self->{id}):undef;    
}

sub get_database {
    my ($self)=@_;

    return (defined $self->{database})?$self->{database}:undef;
}

sub get_date {
    my ($self)=@_;

    return (defined $self->{date})?$self->{date}:undef;
}

sub get_fields {
    my ($self,$msg)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    # Anreicherung mit Feld-Bezeichnungen
    if (defined $msg){
        foreach my $fieldnumber (keys %{$self->{_fields}}){
            my $effective_fieldnumber = $fieldnumber;
            my $mapping = $config->{'categorymapping'};
            if (defined $mapping->{$self->{database}}{$fieldnumber}){
                $effective_fieldnumber = $fieldnumber."-".$self->{database};
            }
                    
            foreach my $fieldcontent_ref (@{$self->{_fields}->{$fieldnumber}}){
                $fieldcontent_ref->{description} = $msg->maketext($effective_fieldnumber);
            }
        }

        foreach my $item_ref (@{$self->{items}}){            
            foreach my $fieldnumber (keys %{$item_ref}){                
                next if ($fieldnumber eq "id");

                my $effective_fieldnumber = $fieldnumber;
                my $mapping = $config->{'categorymapping'};
                if (defined $mapping->{$self->{database}}{$fieldnumber}){
                    $effective_fieldnumber = $fieldnumber."-".$self->{database};
                }
                
                $item_ref->{$fieldnumber}->{description} = $msg->maketext($effective_fieldnumber);
            }
        }
    }
    
    return (defined $self->{_fields})?$self->{_fields}:{};
}

sub get_field {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $field            = exists $arg_ref->{field}
        ? $arg_ref->{field}               : undef;

    my $mult             = exists $arg_ref->{mult}
        ? $arg_ref->{mult}                : undef;

    if (!defined $self->{_fields} && !defined $self->{_fields}->{$field}){
        return;
    }
    
    if (defined $mult && $mult){
        foreach my $field_ref (@{$self->{_fields}->{$field}}){
            if (defined $field_ref->{mult} && $field_ref->{mult} == $mult){
                return $field_ref->{content};
            }
        }
    }
    else {
        return $self->{_fields}->{$field};
    }
}

sub has_field {
    my ($self,$field) = @_;

    return (defined $self->{_fields}->{$field})?1:0;
}

sub set_field {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $field          = exists $arg_ref->{field}
        ? $arg_ref->{field}            : undef;

    my $id             = exists $arg_ref->{id}
        ? $arg_ref->{id}               : undef;
    
    my $mult           = exists $arg_ref->{mult}
        ? $arg_ref->{mult}             : 1;

    my $subfield       = exists $arg_ref->{subfield}
        ? $arg_ref->{subfield}         : undef;

    my $ind            = exists $arg_ref->{ind}
        ? $arg_ref->{ind}              : undef;
    
    my $content        = exists $arg_ref->{content}
        ? $arg_ref->{content}          : undef;

    my $supplement     = exists $arg_ref->{supplement}
        ? $arg_ref->{supplement}       : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($id){
        push @{$self->{_fields}{$field}}, {
            mult       => $mult,
            id         => $id,
            content    => $content,
            supplement => $supplement,
        };
	$logger->debug("Set field $field with content $content and id $id");
    }
    else {
        push @{$self->{_fields}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
	    ind       => $ind,
            content   => $content,
        };
	$logger->debug("Set field $field with content $content");
    }

    return $self;
}

sub set_fields {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fields         = exists $arg_ref->{fields}
        ? $arg_ref->{fields}            : undef;

    if ($fields && ref $fields eq "HASH"){
        $self->{_fields} = $fields;
    }

    return $self;
}

# sub have_subfields {
#     my ($self,$content) = @_;

#     # ToDo: Analyse
    
#     return 0;
# }

# sub content_per_subfield {
#     my ($self,$content) = @_;

#     # ToDo: Analyse

#     my @content_per_subfield = ();
    
#     return @content_per_subfield;
# }

# sub to_bulkload_field_string {
#     my $self = shift;
    
#     my $bulkload_string ="";

#     foreach my $field (keys %{$self->{_normset}}){
#         foreach my $item_ref (@{$self->{_normset}{$field}}){
#             $bulkload_string.="$self->{id}$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{content}\n";
#         }
#     }

#     return $bulkload_string;
# }

# sub to_bulkload_normfield_string {
#     my ($self,$conv_config) = @_;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     my $bulkload_string ="";


#     my $type ="";
    
    
#     foreach my $field (keys %{$self->{_normset}}){
#         foreach my $item_ref (@{$self->{_normset}{$field}}){
#             my $contentnorm   = "";

#             if (defined $field && exists $conv_config->{inverted_person}->{$field}){
#                 $contentnorm = OpenBib::Common::Util::normalize({
#                     field => $field,
#                     content  => $content,
#                 });
#         }
        
        
#         if (exists $conv_config->{inverted_person}{$field}->{index}){
#             foreach my $searchfield (keys %{$conv_config->{inverted_person}{$field}->{index}}){
#                 my $weight = $conv_config->{inverted_person}{$field}->{index}{$searchfield};
                
#                 push @{$conv_config->{$type}{data}{$id}{$searchfield}{$weight}}, $contentnormtmp;
#             }
#         }
            
#             $bulkload_string.="$self->{id}$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{content}\n";
#         }
#     }

#     return $bulkload_string;


#     }

sub enrich_dbpedia {
    my ($self,$article)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $enrich_data_ref = {};

    if ($article){
	# Default-URI
	my $url = $config->get('dbpedia_base');
	
	$url.="${article}.json";
	
	$logger->debug("DBPedia-URL: $url ");
	
	my $ua = new LWP::UserAgent;
	$ua->agent("OpenBib/1.0");
	$ua->timeout(10);
	my $request = new HTTP::Request('GET', $url);
	my $response = $ua->request($request);
	
	my $content = $response->content;
	
	if ($content){
	    $logger->debug("DBpedia: Result for article $article: ".$content);
	    eval {
		$enrich_data_ref = JSON::XS::decode_json($content);
	    };
	    if ($@){
		$logger->error($@);
	    }
	}
    }

    return $enrich_data_ref;
}

sub enrich_unpaywall {
    my ($self,$doi)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $enrich_data_ref = {};

    if ($doi){

	if ($doi=~m{http.*?doi.org/(.+?)$}){
	    $doi = $1;
	}
    
	# Default-URI
	my $url  = $config->get('unpaywall_base');
	my $user = $config->get('unpaywall_user');
	
	$url.="${doi}?email=${user}";
	
	$logger->debug("UnPayWall-URL: $url ");
	
	my $ua = new LWP::UserAgent;
	$ua->agent("OpenBib/1.0");
	$ua->timeout(10);
	my $request = new HTTP::Request('GET', $url);
	my $response = $ua->request($request);
	
	my $content = $response->content;
	
	if ($content){
	    my $unpaywall_ref;
	    $logger->debug("UnPayWall: Result for DOI $doi: ".$content);
	    eval {
		$unpaywall_ref = JSON::XS::decode_json($content);

		my $best_oa_location_ref = $unpaywall_ref->{'best_oa_location'};
		my $results_ref          = $unpaywall_ref->{'results'};

		$enrich_data_ref->{'unpaywall_source'} = $unpaywall_ref;

		if ($logger->is_debug){
		    $logger->debug(YAML::Dump($unpaywall_ref));
		}

		my $besturl = "";
		if (defined $best_oa_location_ref){

		    if ($best_oa_location_ref->{'url_for_pdf'}){			
			$besturl = $best_oa_location_ref->{'url_for_pdf'};
		    }
		    elsif ($best_oa_location_ref->{'url_for_landing_page'}){
			$besturl = $best_oa_location_ref->{'url_for_landing_page'};
		    }
		    elsif ($best_oa_location_ref->{'url'}){
			$besturl = $best_oa_location_ref->{'url'};
		    }
		}

		if (!$besturl && ref($results_ref) eq "ARRAY"){
		    foreach my $result_ref (@$results_ref){
			if ($result_ref->{'free_fulltext_url'} && $result_ref->{'is_free_to_read'}){

			    $besturl = $result_ref->{'free_fulltext_url'};			
			    last;
			}
		    }
		}

		$enrich_data_ref->{'green_url'} = $besturl;

	    };
	    if ($@){
		$logger->error($@);
	    }
	}
    }

    return $enrich_data_ref;
}

sub enrich_jop {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $issn         = exists $arg_ref->{issn}
        ? $arg_ref->{issn}             : '';

    my $volume       = exists $arg_ref->{volume}
        ? $arg_ref->{volume}           : '';

    my $issue        = exists $arg_ref->{issue}
        ? $arg_ref->{issue}            : '';

    my $pages        = exists $arg_ref->{pages}
        ? $arg_ref->{pages}            : '';

    my $year         = exists $arg_ref->{year}
        ? $arg_ref->{year}             : '';

    my $title        = exists $arg_ref->{title}
        ? $arg_ref->{title}            : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $enrich_data_ref = {};

    if ($issn){
	my $jopquery = new OpenBib::SearchQuery;
	
	$jopquery->set_searchfield('issn',$issn) if ($issn);
	$jopquery->set_searchfield('volume',$volume) if ($volume);
	$jopquery->set_searchfield('issue',$issue) if ($issue);
	$jopquery->set_searchfield('pages',$pages) if ($pages);
	$jopquery->set_searchfield('date',$year) if ($year);
	
	if ($title){
	    $jopquery->set_searchfield('genre','article');
	}
	elsif ($volume){
	    $jopquery->set_searchfield('genre','article');
	}
	else {
	    $jopquery->set_searchfield('genre','journal');
	}
	
	# bibid set via portal.yml
	my $api = OpenBib::API::HTTP::JOP->new({ searchquery => $jopquery });
	
	my $search = $api->search();
	
	eval {
	    $enrich_data_ref = $search->get_search_resultlist;
	};

	if ($@){
	    $logger->error($@);
	}
    }
    
    return $enrich_data_ref;
}

sub get_client {
    my ($self) = @_;

    return $self->{client};
}

sub DESTROY {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (defined $self->{schema}){
        eval {
            $self->{schema}->storage->dbh->disconnect;
        };

        if ($@){
            $logger->error($@);
        }
    }

    if (defined $self->{enrich_schema}){
        eval {
#            $self->{enrich_schema}->sth->finish;
            $self->{enrich_schema}->storage->dbh->disconnect;
        };
        
        if ($@){
            $logger->error($@);
        }
    }

    return;
}

1
