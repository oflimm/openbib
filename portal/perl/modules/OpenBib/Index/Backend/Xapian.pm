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

use Apache2::Reload;
use Apache2::Request ();
use Benchmark ':hireswallclock';
use Encode qw/decode_utf8 encode_utf8/;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian;
use Storable;
use String::Tokenizer;
use YAML ();

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::QueryOptions;

use base qw(OpenBib::Search);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database         = exists $arg_ref->{database}
        ? $arg_ref->{database}                      : undef;

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

    my $config = OpenBib::Config->instance;

    if ($database){
        $self->{_database}      = $database;

        {   # get locationid and save to object
            my $locationid = $config->get_locationid_of_database($database);
            my $locationid_norm =  OpenBib::Common::Util::normalize({ content => $locationid});
            $locationid_norm=~s/\W/_/g;
            $self->{_locationid}      = $locationid;
            $self->{_locationid_norm} = $locationid_norm;
        }

        $indexpath=($indexpath)?$indexpath:$config->{xapian_index_base_path}."/".$database;
        
        $logger->debug("Creating Xapian DB-Object for database $self->{_database}");

        eval {
            if ($indextype eq "readwrite" && $createindex){
                $self->{_index}     = Search::Xapian::WritableDatabase->new( $indexpath, Search::Xapian::DB_CREATE_OR_OVERWRITE ) || die "Couldn't open/create Xapian DB $!\n";
            }
            elsif ($indextype eq "readwrite"){
                $self->{_index}     = Search::Xapian::WritableDatabase->new( $indexpath ) || die "Couldn't open Xapian DB $!\n";
            }
            elsif ($indextype eq "readonly"){
                $self->{_index}     = Search::Xapian::Database->new( $indexpath ) || die "Couldn't open Xapian DB $!\n";
            }
        };
        
        if ($@) {
            $logger->error("Database: $self->{_database} - :".$@);
            return;
        }        
    }
    else {
        $logger->error("No database argument given");
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

    my $config = OpenBib::Config->instance;
    
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
    my $document_ref = exists $arg_ref->{document}
        ? $arg_ref->{document}        : undef;

    my $withsorting = exists $arg_ref->{with_sorting}
        ? $arg_ref->{with_sorting}        : undef;

    my $withpositions = exists $arg_ref->{with_positions}
        ? $arg_ref->{with_positions}        : undef;

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
    
    my $config = OpenBib::Config->instance;

    my $FLINT_BTREE_MAX_KEY_LEN = $config->{xapian_option}{max_key_length};

    my %normalize_cache = ();
    
    my $index_ref  = $document_ref->{index};
    my $record_ref = $document_ref->{record};
    
    my $id         = $record_ref->{id};
    my $thisdbname = $record_ref->{database};
    
    my $seen_token_ref = {};
    
    my $doc=Search::Xapian::Document->new();
    
    $self->{_tg}->set_document($doc);
    
    # ID des Satzes recherchierbar machen
    $doc->add_term($config->{xapian_search_prefix}{'id'}.$id);
    
    # Katalogname des Satzes recherchierbar machen
    $doc->add_term($config->{xapian_search_prefix}{'fdb'}.$thisdbname);
    $doc->add_term($config->{xapian_search_prefix}{'floc'}.$self->{_locationid_norm});
    
    foreach my $searchfield (keys %{$config->{searchfield}}) {
        
        my $option_ref = (defined $config->{searchfield}{$searchfield}{option})?$config->{searchfield}{$searchfield}{option}:{};
        
        # IDs oder Integer
        if ($config->{searchfield}{$searchfield}{type} eq 'id' || $config->{searchfield}{$searchfield}{type} eq 'integer'){
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
                    # IDs haben keine Position
                    $self->{_tg}->index_text_without_positions($normcontent,$weight,$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}})
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
                    
                    if ($withpositions){
                        $self->{_tg}->index_text($normcontent,$weight,$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}})
                    }
                    else {
                        $self->{_tg}->index_text_without_positions($normcontent,$weight,$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}})
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
                    my $unique_term = $unique_term_ref->[1];
                    
                    $logger->debug("Processing string $unique_term in field $searchfield");
                    
                    next if (!$unique_term);
                    
                    my $normalize_cache_id = "$field:".$config->{searchfield}{$searchfield}{type}.":".join(":",keys %$option_ref).":$unique_term";
                    
                    if (defined $normalize_cache{$normalize_cache_id}){
                        $unique_term = $normalize_cache{$normalize_cache_id};
                    }
                    else {
                        $unique_term = OpenBib::Common::Util::normalize({ field => $field, content => $unique_term, option => $option_ref, type => $config->{searchfield}{$searchfield}{type} });
                        $normalize_cache{$normalize_cache_id} = $unique_term;
                    }
                    
                    next unless ($unique_term);
                    
                    $unique_term=$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}}.$unique_term;
                    
                    # Begrenzung der keys auf DRILLDOWN_MAX_KEY_LEN Zeichen
                    my $unique_term_octet = encode_utf8($unique_term); 
                    $unique_term=(length($unique_term_octet) > $FLINT_BTREE_MAX_KEY_LEN)?substr($unique_term_octet,0,$FLINT_BTREE_MAX_KEY_LEN):$unique_term;
                    
                    $logger->debug("String indexing searchfield $searchfield: $unique_term");
                    
                    $doc->add_term($unique_term);
                }
            }
        }
    }
    
    # Facetten
    foreach my $type (keys %{$config->{xapian_drilldown_value}}){
        # Datenbankname
        $doc->add_value($config->{xapian_drilldown_value}{$type},encode_utf8($self->{_database})) if ($type eq "database" && $self->{_database});
        $doc->add_value($config->{xapian_drilldown_value}{$type},encode_utf8($self->{_locationid})) if ($type eq "location" && $self->{_locationid});
        
        next if (!defined $index_ref->{"facet_".$type});
        
        my %seen_terms = ();
        my @unique_terms = grep { defined $_ && ! $seen_terms{$_} ++ } @{$index_ref->{"facet_".$type}}; 
        
        my $multstring = join("\t",@unique_terms);
        
        $logger->debug("Adding to $type facet $multstring");
        $doc->add_value($config->{xapian_drilldown_value}{$type},encode_utf8($multstring)) if ($multstring);
    }
    
    # Sortierung
    if ($withsorting){
        my $sorting_ref = [
            {
                # Verfasser/Koepeschaft
                id         => $config->{xapian_sorttype_value}{'person'},
                category   => 'PC0001',
                type       => 'stringcategory',
            },
            {
                # Titel
                id         => $config->{xapian_sorttype_value}{'title'},
                category   => 'T0331',
                type       => 'stringcategory',
                filter     => sub {
                    my $string=shift;
                    $string=~s/^¬\w+¬?\s+//; # Mit Nichtsortierzeichen gekennzeichnetes Wort ausfiltern;
                    return $string;
                },
            },
            {
                # Zaehlung
                id         => $config->{xapian_sorttype_value}{'order'},
                category   => 'T5100',
                type       => 'integercategory',
            },
            {
                # Jahr
                id         => $config->{xapian_sorttype_value}{'year'},
                category   => 'T0425',
                type       => 'integercategory',
            },
            {
                # Verlag
                id         => $config->{xapian_sorttype_value}{'publisher'},
                category   => 'T0412',
                type       => 'stringcategory',
            },
            {
                # Signatur
                id         => $config->{xapian_sorttype_value}{'mark'},
                category   => 'X0014',
                type       => 'stringcategory',
            },
            {
                # Popularitaet
                id         => $config->{xapian_sorttype_value}{'popularity'},
                category   => 'popularity',
                type       => 'integervalue',
            },
            
        ];
        
        foreach my $this_sorting_ref (@{$sorting_ref}){
            
            if ($this_sorting_ref->{type} eq "stringcategory"){
                my $content = (exists $record_ref->{$this_sorting_ref->{category}}[0]{content})?$record_ref->{$this_sorting_ref->{category}}[0]{content}:"";
                next unless ($content);
                
                if (defined $this_sorting_ref->{filter}){
                    $content = &{$this_sorting_ref->{filter}}($content);
                }
                
                $content = OpenBib::Common::Util::normalize({
                    content   => $content,
                    type      => 'string',
                });
                
                if ($content){
                    $logger->debug("Adding $content as sortvalue");
                    $doc->add_value($this_sorting_ref->{id},$content);
                }
            }
            elsif ($this_sorting_ref->{type} eq "integercategory"){
                my $content = (exists $record_ref->{$this_sorting_ref->{category}}[0]{content})?$record_ref->{$this_sorting_ref->{category}}[0]{content}:0;
                        next unless ($content);
                
                ($content) = $content=~m/^\D*(\d+)/;
                
                if ($content){
                    $content = sprintf "%08d",$content;
                    $logger->debug("Adding $content as sortvalue");
                    $doc->add_value($this_sorting_ref->{id},$content);
                }
            }
            elsif ($this_sorting_ref->{type} eq "integervalue"){
                my $content = 0 ;
                if (exists $record_ref->{$this_sorting_ref->{category}}){
                    ($content) = $record_ref->{$this_sorting_ref->{category}}=~m/^(\d+)/;
                }
                if ($content){
                    $content = sprintf "%08d",$content;
                    $logger->debug("Adding $content as sortvalue");
                    $doc->add_value($this_sorting_ref->{id},$content);
                }
            }
        }
    }
    
    my $record = encode_json $record_ref;
    $doc->set_data($record);
           
    return $doc;
}

sub create_record {
    my ($self,$doc) = @_;

    my $docid = $self->get_index->add_document($doc);

    return $self;
}

sub update_record {
    my ($self,$key,$new_doc) = @_;

    $self->get_index->replace_document($key, $new_doc) ;
}

sub delete_record {
    my ($self,$key) = @_;

    $self->get_index->delete_document($key) ;
}


1;

