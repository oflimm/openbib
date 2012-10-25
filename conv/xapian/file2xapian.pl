#!/usr/bin/perl

#####################################################################
#
#  file2xapian.pl
#
#  Dieses File ist (C) 2007-2012 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;
use utf8;

BEGIN {
#    $ENV{XAPIAN_PREFER_CHERT}    = '1';
    $ENV{XAPIAN_FLUSH_THRESHOLD} = $ENV{XAPIAN_FLUSH_THRESHOLD} || '200000';
}

use Benchmark ':hireswallclock';
use DB_File;
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use MLDBM qw(DB_File Storable);
use Storable ();
use Getopt::Long;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian;
use YAML::Syck;
use OpenBib::Config;
use OpenBib::Common::Util;

my ($database,$help,$logfile,$withsorting,$withpositions,$loglevel,$indexpath);

&GetOptions(
    "indexpath=s"     => \$indexpath,
    "database=s"      => \$database,
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "with-sorting"    => \$withsorting,
    "with-positions"  => \$withpositions,
    "help"            => \$help
);

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/file2xapian.log';
$loglevel=($loglevel)?$loglevel:"INFO";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = new OpenBib::Config();

$indexpath=($indexpath)?$indexpath:$config->{xapian_index_base_path}."/".$database;

if (!$database){
  $logger->fatal("Kein Pool mit --database= ausgewaehlt");
  exit;
}

my $FLINT_BTREE_MAX_KEY_LEN = $config->{xapian_option}{max_key_length};

$logger->info("### POOL $database");

my %xapian_idmapping;

tie %xapian_idmapping, 'DB_File', $config->{'autoconv_dir'}."/pools/$database/xapian_idmapping.db";

open(SEARCHENGINE, "<:utf8","searchengine.json"  ) || die "SEARCHENGINE konnte nicht geoeffnet werden";

if (! -d "$indexpath"){
    mkdir "$indexpath";
}

$logger->info("Loeschung des alten Index fuer Datenbank $database");

system("rm $indexpath/*");

my $atime = new Benchmark;

{    
    $logger->info("Aufbau eines neuen temporaeren Index fuer Datenbank $database");
    
    my $db = Search::Xapian::WritableDatabase->new( $indexpath, Search::Xapian::DB_CREATE_OR_OVERWRITE ) || die "Couldn't open/create Xapian DB $!\n";
    
    my $stopword_ref={};
    
    if (exists $config->{stopword_filename}){
        open(SW,$config->{stopword_filename});
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
    
    $logger->info("Migration der Titelsaetze");
    
    my $count = 1;

    {
        my $tg = new Search::Xapian::TermGenerator();
        $tg->set_stopper(new Search::Xapian::SimpleStopper($stopwords));
        
        my $atime = new Benchmark;
        while (my $searchengine=<SEARCHENGINE>) {
            my $searchengine_ref = decode_json $searchengine;

	    my %normalize_cache = ();
            
            my $index_ref  = $searchengine_ref->{index};
            my $record_ref = $searchengine_ref->{record};

            my $id         = $record_ref->{id};
            my $thisdbname = $record_ref->{database};
            
            my $seen_token_ref = {};
            
            my $doc=Search::Xapian::Document->new();
            $tg->set_document($doc);
            
            # ID des Satzes recherchierbar machen
            $doc->add_term($config->{xapian_search_prefix}{'id'}.$id);
            
            # Katalogname des Satzes recherchierbar machen
            $doc->add_term($config->{xapian_search_prefix}{'fdb'}.$thisdbname);
            
            foreach my $searchfield (keys %{$config->{searchfield}}) {
                
		my $option_ref = (defined $config->{searchfield}{$searchfield}{option})?$config->{searchfield}{$searchfield}{option}:{};

                $logger->debug("Processing Searchfield $searchfield for id $id");

                # IDs
                if ($config->{searchfield}{$searchfield}{type} eq 'id'){
                    # Tokenize
                    next if (! exists $index_ref->{$searchfield});

                    foreach my $weight (keys %{$index_ref->{$searchfield}}){
                        # Naechstes, wenn keine ID
                        foreach my $fields_ref (@{$index_ref->{$searchfield}{$weight}}){
			    my $field   = $fields_ref->[0];
			    my $content = $fields_ref->[1];

                            next if (!$content);

			    my $normalize_cache_id = "$field:".join(":",keys %$option_ref).":$content";

			    my $normcontent = "";

			    if (defined $normalize_cache{$normalize_cache_id}){
				$normcontent = $normalize_cache{$normalize_cache_id};
			    }
			    else {
				$normcontent = OpenBib::Common::Util::normalize({ field => $field, content => $content, option => $option_ref });
				$normalize_cache{$normalize_cache_id} = $normcontent;
			    }
                            
                            next if (!$normcontent);
                            # IDs haben keine Position
                            $tg->index_text_without_positions($normcontent,$weight,$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}})
                        }
                    }
                }
                # Einzelne Worte (Fulltext)
                elsif ($config->{searchfield}{$searchfield}{type} eq 'ft'){
                    # Tokenize
                    next if (! exists $index_ref->{$searchfield});

                    foreach my $weight (keys %{$index_ref->{$searchfield}}){
                        # Naechstes, wenn keine ID
                        foreach my $fields_ref (@{$index_ref->{$searchfield}{$weight}}){
			    my $field   = $fields_ref->[0];
			    my $content = $fields_ref->[1];
			    
                            next if (!$content);

			    my $normalize_cache_id = "$field:".join(":",keys %$option_ref).":$content";

			    my $normcontent = "";

			    if (defined $normalize_cache{$normalize_cache_id}){
				$normcontent = $normalize_cache{$normalize_cache_id};
			    }
			    else {
				$normcontent = OpenBib::Common::Util::normalize({ field => $field, content => $content, option => $option_ref });
				$normalize_cache{$normalize_cache_id} = $normcontent;
			    }

                            next if (!$normcontent);

                            $logger->debug("Fulltext indexing searchfield $searchfield: $normcontent");
                            
                            if ($withpositions){
                                $tg->index_text($normcontent,$weight,$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}})
                            }
                            else {
                                $tg->index_text_without_positions($normcontent,$weight,$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}})
                            }
                        }
                    }
                }
                # Zusammenhaengende Zeichenkette
                elsif ($config->{searchfield}{$searchfield}{type} eq 'string'){
                    next if (!exists $index_ref->{$searchfield});
                    
                    foreach my $weight (keys %{$index_ref->{$searchfield}}){
                        my %seen_terms = ();
                        my @unique_terms = @{$index_ref->{$searchfield}{$weight}}; #grep { ! defined $seen_terms{$_->[1]} || ! $seen_terms{$_->[1]} ++ } @{$index_ref->{$searchfield}{$weight}}; 
                        
                        
                        foreach my $unique_term_ref (@unique_terms){
			    my $field       = $unique_term_ref->[0];
			    my $unique_term = $unique_term_ref->[1];

                            next if (!$unique_term);

			    my $normalize_cache_id = "$field:".join(":",keys %$option_ref).":$unique_term";

			    if (defined $normalize_cache{$normalize_cache_id}){
				$unique_term = $normalize_cache{$normalize_cache_id};
			    }
			    else {
				$unique_term = OpenBib::Common::Util::normalize({ field => $field, content => $unique_term, option => $option_ref });
				$normalize_cache{$normalize_cache_id} = $unique_term;
			    }

                            next unless ($unique_term);
                            
#                             if (exists $config->{searchfield}{$searchfield}{option}{string_first_stopword}){
#                                 $unique_term = OpenBib::Common::Stopwords::strip_first_stopword($unique_term);
#                                 $logger->debug("Stripped first stopword");
                                
#                             }
                        
                            $unique_term=~s/\W/_/g;
                            
                            
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
                $doc->add_value($config->{xapian_drilldown_value}{$type},encode_utf8($database)) if ($type eq "db" && $database);
                
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
                        });
                        
                        if ($content){
                            $logger->debug("Adding $content as sortvalue");
                            $doc->add_value($this_sorting_ref->{id},$content);
                        }
                    }
                    elsif ($this_sorting_ref->{type} eq "integercategory"){
                        my $content = (exists $record_ref->{$this_sorting_ref->{category}}[0]{content})?$record_ref->{$this_sorting_ref->{category}}[0]{content}:0;
                        next unless ($content);

                        ($content) = $content=~m/^(\d+)/;
                        
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
            
            my $docid=$db->add_document($doc);
            
            # Abspeichern des Mappings der SQL-ID zur Xapian-Doc-ID
            $xapian_idmapping{$id} = $docid;
            
            if ($count % 1000 == 0) {
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                $atime         = new Benchmark;
                $logger->info("$count Saetze indexiert in $resulttime Sekunden");
            }
            
            $count++;
        }
    }
    
}

close(SEARCHENGINE);

untie(%xapian_idmapping);


my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");

sub print_help {
    print << "ENDHELP";
file2xapian.pl - Datenbank-Konnektor zum Aufbau eines Xapian-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   -with-fields          : Integration von einzelnen Suchfeldern (nicht default)
   -with-sorting         : Integration von Sortierungsinformationen (nicht default)
   -with-positions       : Integration von Positionsinformationen(nicht default)
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
