####################################################################
#
#  OpenBib::Index::Backend::ElasticSearch
#
#  Dieses File ist (C) 2013-2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Index::Backend::ElasticSearch;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Search::Elasticsearch;
use Storable;
use String::Tokenizer;
use YAML ();

use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Common::Util;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

use base qw(OpenBib::Index);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database         = exists $arg_ref->{database}
        ? $arg_ref->{database}                      : undef;

    my $indextype        = exists $arg_ref->{index_type}
        ? $arg_ref->{index_type}                    : 'readonly';

    my $createindex      = exists $arg_ref->{create_index}
        ? $arg_ref->{create_index}                  : undef;

    my $indexname        = exists $arg_ref->{indexname}
        ? $arg_ref->{indexname}                     : undef;
    
    my $self = { };

    bless ($self, $class);

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    $self->{config} = $config;
    
    unless ($database){
        $logger->error("No database argument given");
        return $self;
    }
    
    if ($database){
        $self->{_database}      = $database;

        {   # get locationid and save to object
            my $locationid = $config->get_locationid_of_database($database);
            my $locationid_norm =  OpenBib::Common::Util::normalize({ content => $locationid});
            $locationid_norm=~s/\W/_/g;
            $self->{_locationid}      = $locationid;
            $self->{_locationid_norm} = $locationid_norm;
        }

	$indexname=($indexname)?$indexname:$database;
    }

    $logger->debug("Creating elasticsearch DB-Object for database $self->{_database}");
    
    eval {
	my $es = Search::Elasticsearch->new(
	    userinfo   => $config->{elasticsearch}{userinfo},
	    cxn_pool   => $config->{elasticsearch}{cxn_pool},    # default 'Sniff'
	    nodes      => $config->{elasticsearch}{nodes},       # default '127.0.0.1:9200'
	    );
	
	my $result;

	if ($createindex){
	    if ($es->indices->exists( index => $indexname )){
		$result = $es->indices->delete( index => $indexname );
	    }
	    
	    $result = $es->indices->create(
		index    => $indexname,
		);
	    $result = $es->indices->put_mapping(
		index => $indexname,
		body => {
		    properties => $config->{elasticsearch_index_mappings}{properties},
		}	
		);
	    
	}
	

	my $bulk = $es->bulk_helper(
	    index => $indexname,
	    );

	$self->{_backend} = $es;
	$self->{_index} = $bulk;
    };
    
    if ($@) {
        $logger->error("Database: $self->{_database} - :".$@);
        return $self;
    }        
        
    # Backend Specific Attributes
    
    return $self;
}

sub get_backend {
    my $self         = shift;

    return $self->{_backend};
}

sub drop_index {
    my $self         = shift;
    my $indexname    = shift;

    return unless ($indexname);

    my $es = $self->get_backend;
    
    if ($es->indices->exists( index => $indexname )){
	$es->indices->delete( index => $indexname );
    }

    return $self;    
}

sub get_aliased_index {
    my $self         = shift;
    my $aliasname    = shift;

    return unless ($aliasname);

    my $index_ref;

    eval {
	$index_ref = $self->get_backend->indices->get_alias(
	    name    => $aliasname
	    );    
    };
    
    my $indexname = "${aliasname}_a";

    # Ersten Indexnamen nehmen
    if (defined $index_ref && %$index_ref){
	foreach my $index (keys %$index_ref){
	    $indexname = $index;
	    last;
	}
    }

    
    
    return $indexname;
}

sub drop_alias {
    my $self         = shift;
    my $aliasname    = shift;
    my $indexname    = shift;

    return unless ($aliasname);

    my $result;
    
    eval {
	$result = $self->get_backend->indices->delete_alias(
	    name => $aliasname,
	    index => $indexname,
	    );
    };
    
    return $result;
}

sub create_alias {
    my $self         = shift;
    my $aliasname    = shift;
    my $indexname    = shift;

    return unless ($aliasname || $indexname);

    my $result;

    eval {
	$result = $self->get_backend->indices->put_alias(
	    name  => $aliasname,
	    index => $indexname,
	    );
    };
    
    return $result;
}

sub get_index {
    my $self         = shift;

    return $self->{_index};
}

sub set_stopper {
    my $self         = shift;

    # my $config = $self->{config};
    
    # my $stopwordfile = shift || $config->{stopword_filename};

    # my $stopword_ref={};
    
    # if (-e $stopwordfile){
    #     open(SW,$stopwordfile);
    #     while (my $stopword=<SW>){
    #         chomp $stopword ;
    #         $stopword = OpenBib::Common::Util::normalize({
    #             content  => $stopword,
    #         });
            
    #         $stopword_ref->{$stopword}=1;
    #     }
    #     close(SW);
    # }

    # my $stopwords = join(' ',keys %$stopword_ref);
    
    # $self->{_stopper} = ...

    return $self;
}

sub have_stopper {
    my $self = shift;

    if (defined $self->{_stopper}){
        return 1;
    }
   
    return 0;
}

sub get_stopper {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($self->have_stopper){
        return $self->{_stopper};
    }

    $logger->fatal("No stopper defined");
    
    return undef;
}

sub set_termgenerator {
    my $self = shift;

#    $self->{_tg} = new Search::Xapian::TermGenerator();
#    $self->{_tg}->set_stopper($self->get_stopper);

    return $self;
}

sub have_termgenerator {
    my $self = shift;

    if (defined $self->{_tg}){
        return 1;
    }
   
    return 0;
}

sub get_termgenerator {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($self->have_termgenerator){
        return $self->{_tg};
    }

    $logger->fatal("No termgenerator defined");
    
    return undef;
}

sub create_document {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $document    = exists $arg_ref->{document}
        ? $arg_ref->{document}        : undef;

    my $withsorting = exists $arg_ref->{with_sorting}
        ? $arg_ref->{with_sorting}        : 1;

    my $withpositions = exists $arg_ref->{with_positions}
        ? $arg_ref->{with_positions}        : 1;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # We always need a stopper 
    if (!$self->have_stopper){
        $self->set_stopper;
    }

    # and a termgenerator (which in turn needs a stopper)
    if (!$self->have_termgenerator){
        $self->set_termgenerator;
    }
    
    my $config = $self->{config};

    my %normalize_cache = ();
    
    my $index_ref  = $document->get_index;
    my $record_ref = $document->get_data;

    my $id         = $record_ref->{id};
    my $thisdbname = $record_ref->{database};

    my $convconfig = OpenBib::Conv::Config->instance({dbname => $thisdbname});
    
    my $seen_token_ref = {};
    
    my $doc_ref = {_id => $id};

#    $self->{_tg}->set_document($doc_ref);
       
    # Katalogname des Satzes recherchierbar machen
    eval {
	push @{$doc_ref->{fdb}}, $thisdbname;
	push @{$doc_ref->{floc}}, $self->{_locationid_norm};
    };

    if ($@){
        $logger->error($@);
    }
    
    foreach my $searchfield (keys %{$config->{searchfield}}) {
        
        my $option_ref = (defined $config->{searchfield}{$searchfield}{option})?$config->{searchfield}{$searchfield}{option}:{};
        
        # IDs oder Integer
        if ($config->{searchfield}{$searchfield}{type} eq 'id' || $config->{searchfield}{$searchfield}{type} eq 'integer'){
            next if (! defined $index_ref->{$searchfield});
            
            $logger->debug("Processing Searchfield $searchfield for id $id and type ".$config->{searchfield}{$searchfield}{type});
            
            foreach my $weight (keys %{$index_ref->{$searchfield}}){
                # Naechstes, wenn keine ID
                foreach my $fields_ref (@{$index_ref->{$searchfield}{$weight}}){
                    my $field   = $fields_ref->[0];
                    my $content = $fields_ref->[1];

                    $logger->debug("Field: $field - Content: $content");

		    if ($config->{searchfield}{$searchfield}{type} eq "integer"){
			if ($self->can('filter_force_signed_year')){
			    $content = $self->filter_force_signed_year($content);
                        }
		    }
		    
                    next if (!$content);
                    
                    my $normalize_cache_id = "$field:".$config->{searchfield}{$searchfield}{type}.":".join(":",keys %$option_ref).":$content";
                    
                    my $normcontent = "";
                    
                    if (defined $normalize_cache{$normalize_cache_id}){
                        $normcontent = $normalize_cache{$normalize_cache_id};
                    }
                    else {
                        $normcontent = OpenBib::Common::Util::normalize({ field => $field, content => $content, option => $option_ref, type => $config->{searchfield}{$searchfield}{type} });
                        $normalize_cache{$normalize_cache_id} = $normcontent;
                    }
                    
                    next if (!$normcontent);
                        
                    $logger->debug("ID indexing searchfield $searchfield: $normcontent");

		    push @{$doc_ref->{$config->{searchfield}{$searchfield}{prefix}}}, $normcontent;

                }
            }
        }
        # Einzelne Worte (Fulltext)
        elsif ($config->{searchfield}{$searchfield}{type} eq 'ft'){
            # Tokenize
            next if (! exists $index_ref->{$searchfield});
            
            $logger->debug("Processing Searchfield $searchfield for id $id and type ".$config->{searchfield}{$searchfield}{type});
            
            foreach my $weight (keys %{$index_ref->{$searchfield}}){
                # Naechstes, wenn keine ID
                foreach my $fields_ref (@{$index_ref->{$searchfield}{$weight}}){
                    my $field   = $fields_ref->[0];
                    my $content = $fields_ref->[1];
                    
                    next if (!$content);
                                        
                    my $normalize_cache_id = "$field:".$config->{searchfield}{$searchfield}{type}.":".join(":",keys %$option_ref).":$content";
                    
                    my $normcontent = "";
                    
                    if (defined $normalize_cache{$normalize_cache_id}){
                        $normcontent = $normalize_cache{$normalize_cache_id};
                    }
                    else {
                        $normcontent = OpenBib::Common::Util::normalize({ field => $field, content => $content, option => $option_ref, type => $config->{searchfield}{$searchfield}{type} });
                        $normalize_cache{$normalize_cache_id} = $normcontent;
                    }
                    
                    next if (!$normcontent);
                    
                    $logger->debug("Fulltext indexing searchfield $searchfield: $normcontent");

		    push @{$doc_ref->{$config->{searchfield}{$searchfield}{prefix}}}, $normcontent;
		    
                    my $additionalcontent = "";
                    
                    if ($content=~m/(\w)-(\w)/){
                        $additionalcontent = $content;
                        $additionalcontent=~s/(\w)-(\w)/$1$2/g;
                    }
                    
                    if ($additionalcontent){
                        my $normalize_cache_id = "$field:".$config->{searchfield}{$searchfield}{type}.":".join(":",keys %$option_ref).":$additionalcontent";
                        
                        my $normcontent = "";
                        
                        if (defined $normalize_cache{$normalize_cache_id}){
                            $normcontent = $normalize_cache{$normalize_cache_id};
                        }
                        else {
                            $normcontent = OpenBib::Common::Util::normalize({ field => $field, content => $additionalcontent, option => $option_ref, type => $config->{searchfield}{$searchfield}{type} });
                            $normalize_cache{$normalize_cache_id} = $normcontent;
                        }
                        
                        next if (!$normcontent);
                        
                        $logger->debug("Fulltext indexing searchfield $searchfield: $normcontent");
			
			push @{$doc_ref->{$config->{searchfield}{$searchfield}{prefix}}}, $normcontent;
			       
		    }
                }
            }
        }
        # Zusammenhaengende Zeichenkette
        elsif ($config->{searchfield}{$searchfield}{type} eq 'string'){
            next if (!exists $index_ref->{$searchfield});
            
            $logger->debug("Processing Searchfield $searchfield for id $id and type ".$config->{searchfield}{$searchfield}{type});
            
            foreach my $weight (keys %{$index_ref->{$searchfield}}){
                my %seen_terms = ();
                my @unique_terms = @{$index_ref->{$searchfield}{$weight}}; #grep { ! defined $seen_terms{$_->[1]} || ! $seen_terms{$_->[1]} ++ } @{$index_ref->{$searchfield}{$weight}}; 
                
                
                foreach my $unique_term_ref (@unique_terms){
                    my $field       = $unique_term_ref->[0];
                    my $content     = $unique_term_ref->[1];
                    
                    $logger->debug("Processing string $content in field $searchfield");
                    
                    next if (!$content);
                    
                    my $normcontent = "";

                    my $normalize_cache_id = "$field:".$config->{searchfield}{$searchfield}{type}.":".join(":",keys %$option_ref).":$content";
                    
                    if (defined $normalize_cache{$normalize_cache_id}){
                        $normcontent = $normalize_cache{$normalize_cache_id};
                    }
                    else {
                        $normcontent = OpenBib::Common::Util::normalize({ field => $field, content => $content, option => $option_ref, type => $config->{searchfield}{$searchfield}{type} });
                        $normalize_cache{$normalize_cache_id} = $normcontent;
                    }
                    
                    next unless ($normcontent);

                    $logger->debug("String indexing searchfield $searchfield: $normcontent");

		    push @{$doc_ref->{$config->{searchfield}{$searchfield}{prefix}}}, $normcontent;

                    my $additionalcontent = "";
                    
                    if ($content=~m/(\w)-(\w)/){
                        $additionalcontent = $content;
                        $additionalcontent=~s/(\w)-(\w)/$1$2/g;
                    }
                    
                    if ($additionalcontent){
                        my $normcontent = "";
                        
                        my $normalize_cache_id = "$field:".$config->{searchfield}{$searchfield}{type}.":".join(":",keys %$option_ref).":$additionalcontent";
                        
                        if (defined $normalize_cache{$normalize_cache_id}){
                            $normcontent = $normalize_cache{$normalize_cache_id};
                        }
                        else {
                            $normcontent = OpenBib::Common::Util::normalize({ field => $field, content => $additionalcontent, option => $option_ref, type => $config->{searchfield}{$searchfield}{type} });
                            $normalize_cache{$normalize_cache_id} = $normcontent;
                        }
                        
                        next unless ($normcontent);
                        
                        $logger->debug("String indexing searchfield $searchfield: $normcontent");
			
			push @{$doc_ref->{$config->{searchfield}{$searchfield}{prefix}}}, $normcontent;
                    }
                }
            }
        }
    }
    
    # Facetten
    foreach my $type (keys %{$config->{facets}}){
        # Datenbankname

	push @{$doc_ref->{"facet_$type"}}, $self->{_database} if ($type eq "database" && $self->{_database});
	push @{$doc_ref->{"facet_$type"}}, $self->{_locationid} if ($type eq "location" && $self->{_locationid});

        next if (!defined $index_ref->{"facet_".$type});
        
        my %seen_terms = ();
        my @unique_terms = grep { defined $_ && ! $seen_terms{$_} ++ } @{$index_ref->{"facet_$type"}}; 

	push @{$doc_ref->{"facet_$type"}}, @unique_terms;
    }
    
    # Sortierung
    if ($withsorting){

        if ($logger->is_debug){
            $logger->debug("sorting_order: ".YAML::Dump($convconfig->get('sorting_order')));
            $logger->debug("sorting: ".YAML::Dump($convconfig->get('sorting')));
        }
        
        foreach my $field (@{$convconfig->get('sorting_order')}){
	    my ($basefield,$subfield) = ('','');

	    # Basefield:Subfield
	    if ($field =~m/^(.+?):(.)/){
		$basefield     = $1;
		$subfield      = $2;
	    }
	    # Sonst Feld
	    else {
		$basefield = $field;
	    }
	    
            next unless (defined $record_ref->{$basefield});
	    
            # Bibliogr. Feldinhalte mit Zeichenketten
            if ($convconfig->get('sorting')->{$field}->{type} eq "stringfield"){
		my $content = "";

		if ($subfield){
		    foreach my $item_ref (@{$record_ref->{$basefield}}){
			if ($item_ref->{subfield} eq $subfield){
			    $content = $item_ref->{content};
			    last;
			}
		    }
		}
		else {
		    $content = (defined $record_ref->{$field}[0]{content})?$record_ref->{$field}[0]{content}:"";
		}
		
                next unless ($content);
                
                if (defined $convconfig->get('sorting')->{$field}{filter}){
                    foreach my $filtername (@{$convconfig->get('sorting')->{$field}{filter}}){
                        if ($self->can($filtername)){
                            $content = $self->$filtername($content);
                        }
                    }
                }
                
                $content = OpenBib::Common::Util::normalize({
                    content   => $content,
                    type      => 'string',
							    });
                
                if ($content){
                    $logger->debug("Adding $content as sortvalue");
		    
		    push @{$doc_ref->{"sorting_".$convconfig->get('sorting')->{$field}{sortfield}}}, $content;
                }
            }
            # Bibliogr. Feldinhalte mit Integerwerten
            elsif ($convconfig->get('sorting')->{$field}->{type} eq "integerfield"){
		my $content = "";

		if ($subfield){
		    foreach my $item_ref (@{$record_ref->{$basefield}}){
			if ($item_ref->{subfield} eq $subfield){
			    $content = $item_ref->{content};
			    last;
			}
		    }
		}
		else {
		    $content = (defined $record_ref->{$field}[0]{content})?$record_ref->{$field}[0]{content}:"";
		}
		
                next unless ($content);
		
                if (defined $convconfig->get('sorting')->{$field}{filter}){
                    foreach my $filtername (@{$convconfig->get('sorting')->{$field}{filter}}){
                        if ($self->can($filtername)){
                            $content = $self->$filtername($content);
                        }
                    }
                }
		
                ($content) = $content=~m/^\D*?(-?\d+)/ if (defined $content);
                
                if ($content){
		    #                    $content = sprintf "%08d",$content;
                    $logger->debug("Adding $content as sortvalue");
		    
		    push @{$doc_ref->{"sorting_".$convconfig->get('sorting')->{$field}{sortfield}}}, $content;
		}
	    }
            # Integerwerte jenseits der bibliogr. Felder, also z.B. popularity
            elsif ($convconfig->get('sorting')->{$field}->{type} eq "integervalue"){

		my $content = 0 ;
                if (defined $record_ref->{$field}){
                    ($content) = $record_ref->{$field}=~m/^(-?\d+)/;
                }

                if ($content){
		    #                   $content = sprintf "%08d",$content;
                    $logger->debug("Adding $content as sortvalue");

		    push @{$doc_ref->{"sorting_".$convconfig->get('sorting')->{$field}{sortfield}}}, $content;
                }
            }
        }
    }
	       
    my $record = encode_json $record_ref;
	       
    $doc_ref->{listitem} = $record;		
    
    return $doc_ref;
}

sub create_record {
    my ($self,$doc) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $id = $doc->{_id};
    delete $doc->{_id};
    
    eval {
	$self->get_index->index(
	    {
		_id    => $id,
		source => $doc,
	    }
	    ) if (defined $id && defined $doc);
    };
    
    if ($@){
        $logger->error($@);
    }

    return $self;
}

sub update_record {
    my ($self,$id,$new_doc) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->{config};

    $logger->error("Not implemented yet!");

    return $self;
    
    my $key = $config->{xapian_search}{id}{prefix}.$id;

    eval {
        $self->get_index->replace_document_by_term($key, $new_doc) ;
    };
    
    if ($@){
        $logger->error($@);
    }

    return $self;
}

sub delete_record {
    my ($self,$id) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->{config};

    $logger->error("Not implemented yet!");

    return $self;
    
    my $key = $config->{xapian_search}{id}{prefix}.$id;

    eval {
        $self->get_index->delete_document_by_term($key);
    };
    
    if ($@){
        $logger->error($@);
    }

    return $self;
}


sub filter_force_signed_year {
    my ($self, $string) = @_;
    $string=~s/[^-0-9]//g if (defined $string);
    ($string) = $string=~m/(-?\d\d\d\d)/;
    
    return $string;
}

sub filter_strip_nonsortable_word {
    my ($self, $string) = @_;
    $string=~s/^¬\w+¬?\s+//; # Mit Nichtsortierzeichen gekennzeichnetes Wort ausfiltern;
    return $string;
}

1;

