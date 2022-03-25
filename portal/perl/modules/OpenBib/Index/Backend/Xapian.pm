#####################################################################
#
#  OpenBib::Index::Backend::Xapian
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Index::Backend::Xapian;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode qw/decode_utf8 encode_utf8/;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian;
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

    my $searchprofile    = exists $arg_ref->{searchprofile}
        ? $arg_ref->{searchprofile}                 : undef;

    my $indextype        = exists $arg_ref->{index_type}
        ? $arg_ref->{index_type}                    : 'readonly';

    my $createindex      = exists $arg_ref->{create_index}
        ? $arg_ref->{create_index}                  : undef;

    my $indexpath        = exists $arg_ref->{index_path}
        ? $arg_ref->{index_path}                     : undef;
    
    my $self = { };

    bless ($self, $class);

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    $self->{config} = $config;
    
    unless ($database || $searchprofile){
        $logger->error("No database or searchprofile argument given");
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
    }

    if ($searchprofile){
        $self->{_searchprofile}      = $searchprofile;
    }   

    $indexpath=($indexpath)?$indexpath:
    ($database)?$config->{xapian_index_base_path}."/".$database:
    ($searchprofile)?$config->{xapian_index_base_path}."/_searchprofile/".$searchprofile:'';
        
    $logger->debug("Creating Xapian DB-Object for database $self->{_database}");
    
    eval {
        if ($indextype eq "readwrite" && $createindex){
            $self->{_index}     = Search::Xapian::WritableDatabase->new( $indexpath, Search::Xapian::DB_CREATE_OR_OVERWRITE ) || die "Couldn't open/create Xapian DB $!\n";
        }
        elsif ($indextype eq "readwrite"){
            $self->{_index}     = Search::Xapian::WritableDatabase->new( $indexpath, Search::Xapian::DB_CREATE_OR_OPEN ) || die "Couldn't open Xapian DB $!\n";
        }
        elsif ($indextype eq "readonly"){
            $self->{_index}     = Search::Xapian::Database->new( $indexpath ) || die "Couldn't open Xapian DB $!\n";
        }
    };
    
    if ($@) {
        $logger->error("Database: $self->{_database} - :".$@);
        return $self;
    }        
        
    # Backend Specific Attributes
    
    return $self;
}

sub get_index {
    my $self         = shift;

    return $self->{_index};
}

sub set_stopper {
    my $self         = shift;

    my $config = $self->{config};
    
    my $stopwordfile = shift || $config->{stopword_filename};

    my $stopword_ref={};
    
    if (-e $stopwordfile){
        open(SW,$stopwordfile);
        while (my $stopword=<SW>){
            chomp $stopword ;
            $stopword = OpenBib::Common::Util::normalize({
                content  => $stopword,
            });
            
            $stopword_ref->{$stopword}=1;
        }
        close(SW);
    }

    my $stopwords = join(' ',keys %$stopword_ref);
    
    $self->{_stopper} = new Search::Xapian::SimpleStopper($stopwords);

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

    $self->{_tg} = new Search::Xapian::TermGenerator();
    $self->{_tg}->set_stopper($self->get_stopper);

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

    my $FLINT_BTREE_MAX_KEY_LEN = $config->{xapian_option}{max_key_length};

    my %normalize_cache = ();
    
    my $index_ref  = $document->get_index;
    my $record_ref = $document->get_data;

    my $id         = $record_ref->{id};
    my $thisdbname = $record_ref->{database};

    my $convconfig = OpenBib::Conv::Config->instance({dbname => $thisdbname});
    
    my $seen_token_ref = {};
    
    my $doc = Search::Xapian::Document->new();
    
    $self->{_tg}->set_document($doc);
       
    # Katalogname des Satzes recherchierbar machen
    eval {
        $doc->add_term($config->{xapian_search}{'fdb'}{prefix}.$thisdbname);
        $doc->add_term($config->{xapian_search}{'floc'}{prefix}.$self->{_locationid_norm});
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
                    # IDs haben keine Position

                    $normcontent = $config->{xapian_search}{$config->{searchfield}{$searchfield}{prefix}}{prefix}.$normcontent;
                    
                    $logger->debug("Term: $normcontent");

                    # Begrenzung der keys auf DRILLDOWN_MAX_KEY_LEN Zeichen
                    my $normcontent_octet = encode_utf8($normcontent); 
                    $normcontent=(length($normcontent_octet) > $FLINT_BTREE_MAX_KEY_LEN)?substr($normcontent_octet,0,$FLINT_BTREE_MAX_KEY_LEN):$normcontent;

                    eval {
                        $doc->add_term($normcontent);
                    };
                    
                    if ($@){
                        $logger->error($@);
                    }
                    
                    # $self->{_tg}->index_text_without_positions($normcontent,$weight,$config->{xapian_search}{$config->{searchfield}{$searchfield}{prefix}}{prefix});
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

                    eval {
                        if ($withpositions){
                            $self->{_tg}->index_text($normcontent,$weight,$config->{xapian_search}{$config->{searchfield}{$searchfield}{prefix}}{prefix});
                        }
                        else {
                            $self->{_tg}->index_text_without_positions($normcontent,$weight,$config->{xapian_search}{$config->{searchfield}{$searchfield}{prefix}}{prefix});
                        }
                    };
                    
                    if ($@){
                        $logger->error($@);
                    }

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

                        eval {
                            if ($withpositions){
                                $self->{_tg}->index_text($normcontent,$weight,$config->{xapian_search}{$config->{searchfield}{$searchfield}{prefix}}{prefix});
                            }
                            else {
                                $self->{_tg}->index_text_without_positions($normcontent,$weight,$config->{xapian_search}{$config->{searchfield}{$searchfield}{prefix}}{prefix});
                            }
                        };
                        
                        if ($@){
                            $logger->error($@);
                        }                        
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
                    
                    $normcontent=$config->{xapian_search}{$config->{searchfield}{$searchfield}{prefix}}{prefix}.$normcontent;
                    
                    # Begrenzung der keys auf DRILLDOWN_MAX_KEY_LEN Zeichen
                    my $normcontent_octet = encode_utf8($normcontent); 
                    $normcontent=(length($normcontent_octet) > $FLINT_BTREE_MAX_KEY_LEN)?substr($normcontent_octet,0,$FLINT_BTREE_MAX_KEY_LEN):$normcontent;
                    
                    $logger->debug("String indexing searchfield $searchfield: $normcontent");

                    eval {
                        $doc->add_term($normcontent);
                    };
                    
                    if ($@){
                        $logger->error($@);
                    }

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
                        
                        $normcontent=$config->{xapian_search}{$config->{searchfield}{$searchfield}{prefix}}{prefix}.$normcontent;
                        
                        # Begrenzung der keys auf DRILLDOWN_MAX_KEY_LEN Zeichen
                        my $normcontent_octet = encode_utf8($normcontent); 
                        $normcontent=(length($normcontent_octet) > $FLINT_BTREE_MAX_KEY_LEN)?substr($normcontent_octet,0,$FLINT_BTREE_MAX_KEY_LEN):$normcontent;
                        
                        $logger->debug("String indexing searchfield $searchfield: $normcontent");

                        eval {
                            $doc->add_term($normcontent);
                        };
                        
                        if ($@){
                            $logger->error($@);
                        }
                    }
                }
            }
        }
    }
    
    # Facetten
    foreach my $type (keys %{$config->{xapian_facet_value}}){
        # Datenbankname

        eval {
            $doc->add_value($config->{xapian_facet_value}{$type},encode_utf8($self->{_database})) if ($type eq "database" && $self->{_database});
            $doc->add_value($config->{xapian_facet_value}{$type},encode_utf8($self->{_locationid})) if ($type eq "location" && $self->{_locationid});
        };
        
        if ($@){
            $logger->error($@);
        }

        next if (!defined $index_ref->{"facet_".$type});
        
        my %seen_terms = ();
        my @unique_terms = grep { defined $_ && ! $seen_terms{$_} ++ } @{$index_ref->{"facet_".$type}}; 
        
        my $multstring = join("\t",@unique_terms);
        
        $logger->debug("Adding to $type facet $multstring");
        eval {
            $doc->add_value($config->{xapian_facet_value}{$type},encode_utf8($multstring)) if ($multstring);
        };
        
        if ($@){
            $logger->error($@);
        }
    }

    foreach my $field (keys %{$config->{'xapian_collapse_value'}}){
	next if (!defined $index_ref->{"collapse_".$field});

        my %seen_terms = ();
        my @unique_terms = grep { defined $_ && ! $seen_terms{$_} ++ } @{$index_ref->{"collapse_".$field}}; 
	
	my $collapsestring = (defined $unique_terms[0])?$unique_terms[0]:'';
	
	$logger->debug("Adding to $field collapse $collapsestring");
	eval {
	    $doc->add_value($config->{xapian_collapse_value}{$field},encode_utf8($collapsestring)) if ($collapsestring);
	};
	
	if ($@){
	    $logger->error($@);
	}
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
                    eval {
                        $doc->add_value($config->{xapian_sorttype_value}{$convconfig->get('sorting')->{$field}{sortfield}},$content);
                    };
                    
                    if ($@){
                        $logger->error($@);
                    }
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

                    eval {
                        $doc->add_value($config->{xapian_sorttype_value}{$convconfig->get('sorting')->{$field}{sortfield}},Search::Xapian::sortable_serialise($content));
                    };
                    
                    if ($@){
                        $logger->error($@);
                    }
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

                    eval {
                        $doc->add_value($config->{xapian_sorttype_value}{$convconfig->get('sorting')->{$field}{sortfield}},Search::Xapian::sortable_serialise($content));
                    };
                    
                    if ($@){
                        $logger->error($@);
                    }
                }
            }
        }
    }
    
    my $record = encode_json $record_ref;

    eval {
        $doc->set_data($record);
    };
    
    if ($@){
        $logger->error($@);
    }
 
    return $doc;
}

sub create_record {
    my ($self,$doc) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    eval {
        my $docid = $self->get_index->add_document($doc);
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
    ($string) = $string=~m/^\D*(-?\d\D?\d\D?\d\D?\d)/;
    $string=~s/[^-0-9]//g if (defined $string);
    
    return $string;
}

sub filter_strip_nonsortable_word {
    my ($self, $string) = @_;
    $string=~s/^¬\w+¬?\s+//; # Mit Nichtsortierzeichen gekennzeichnetes Wort ausfiltern;
    return $string;
}

1;

