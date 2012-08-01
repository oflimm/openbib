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
    $ENV{XAPIAN_FLUSH_THRESHOLD} = '200000';
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
use String::Tokenizer;
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

open(TITLECACHE,   "<:utf8","title.dump" ) || die "TITLECACHE konnte nicht geoeffnet werden";
open(SEARCHENGINE, "<:utf8","searchengine.csv"  ) || die "SEARCHENGINE konnte nicht geoeffnet werden";

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
            $stopword = OpenBib::Common::Util::grundform({
                content  => $stopword,
            });
            
            $stopword_ref->{$stopword}=1;
        }
        close(SW);
    }

    my $stopwords = join(' ',keys %$stopword_ref);
    
    my $tokenizer = String::Tokenizer->new();
    
    $logger->info("Migration der Titelsaetze");
    
    my $count = 1;

    {
        my $tg = new Search::Xapian::TermGenerator();
        $tg->set_stopper(new Search::Xapian::SimpleStopper($stopwords));
        
        my $atime = new Benchmark;
        while (my $title_listitem=<TITLECACHE>, my $searchengine=<SEARCHENGINE>) {
            my ($s_id,$searchcontent)=split ("",$searchengine);
            my ($t_id,$tstamp_create,$tstamp_update,$listitem)=split ("",$title_listitem);
            
            if ($s_id ne $t_id) {
                $logger->fatal("Id's stimmen nicht ueberein ($s_id != $t_id)!");
                next;
            }
            
            my $searchcontent_ref = decode_json $searchcontent;
            
            my $seen_token_ref = {};
            
            my $doc=Search::Xapian::Document->new();
            $tg->set_document($doc);
            
            # ID des Satzes recherchierbar machen
            $doc->add_term($config->{xapian_search_prefix}{'id'}.$s_id);
            
            # Katalogname des Satzes recherchierbar machen
            $doc->add_term($config->{xapian_search_prefix}{'fdb'}.$database);
            
            my $k = 0;
            

            foreach my $searchfield (keys %{$config->{searchfield}}) {
                
                $logger->debug("Processing Searchfield $searchfield for id $s_id");

                # IDs
                if ($config->{searchfield}{$searchfield}{type} eq 'id'){
                    # Tokenize
                    next if (! exists $searchcontent_ref->{$searchfield});

                    foreach my $weight (keys %{$searchcontent_ref->{$searchfield}}){
                        # Naechstes, wenn keine ID
                        foreach my $content (@{$searchcontent_ref->{$searchfield}{$weight}}){
                            next if (!$content);
                            # IDs haben keine Position
                            $tg->index_text_without_positions($content,$weight,$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}})
                        }
                    }
                }
                # Einzelne Worte (Fulltext)
                elsif ($config->{searchfield}{$searchfield}{type} eq 'ft'){
                    # Tokenize
                    next if (! exists $searchcontent_ref->{$searchfield});

                    foreach my $weight (keys %{$searchcontent_ref->{$searchfield}}){
                        # Naechstes, wenn keine ID
                        foreach my $content (@{$searchcontent_ref->{$searchfield}{$weight}}){
                            next if (!$content);
                            if ($withpositions){
                                $tg->index_text($content,$weight,$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}})
                            }
                            else {
                                $tg->index_text_without_positions($content,$weight,$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}})
                            }
                        }
                    }
                }
                # Zusammenhaengende Zeichenkette
                elsif ($config->{searchfield}{$searchfield}{type} eq 'string'){
                    next if (!exists $searchcontent_ref->{$searchfield});
                    
                    foreach my $weight (keys %{$searchcontent_ref->{$searchfield}}){
                        my %seen_terms = ();
                        my @unique_terms = grep { ! $seen_terms{$_} ++ } @{$searchcontent_ref->{$searchfield}{$weight}}; 
                        
                        
                        foreach my $unique_term (@unique_terms){
                            next unless ($unique_term);
                            
                            if (exists $config->{searchfield}{$searchfield}{option}{string_first_stopword}){
                                $unique_term = OpenBib::Common::Stopwords::strip_first_stopword($unique_term);
                                $logger->debug("Stripped first stopword");
                                
                            }
                        
                            $unique_term=~s/\W/_/g;
                            
                            $unique_term=$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}}.$unique_term;
                        
                            # Begrenzung der keys auf DRILLDOWN_MAX_KEY_LEN Zeichen
                            my $unique_term_octet = encode_utf8($unique_term); 
                            $unique_term=(length($unique_term_octet) > $FLINT_BTREE_MAX_KEY_LEN)?substr($unique_term_octet,0,$FLINT_BTREE_MAX_KEY_LEN):$unique_term;
                            
                            $logger->debug("Added Stringvalue $unique_term");
                            $doc->add_term($unique_term);
                        }
                    }
                }
            }
            
            # Facetten
            foreach my $type (keys %{$config->{xapian_drilldown_value}}){
                # Datenbankname
                $doc->add_value($config->{xapian_drilldown_value}{$type},encode_utf8($database)) if ($type eq "db" && $database);
                
                next if (!defined $searchcontent_ref->{"facet_".$type});
                
                my %seen_terms = ();
                my @unique_terms = grep { defined $_ && ! $seen_terms{$_} ++ } @{$searchcontent_ref->{"facet_".$type}}; 
                
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
                
                my $title_listitem_ref;

                # Korrekturen fuer PostgreSQL rueckgaengig machen
                $listitem =~s/\\r/\r/g;
                $listitem =~s/\\\\/\\/g; # Escape Literal Backslash
                
                eval {
                     $title_listitem_ref = decode_json $listitem;
                };
                if ($@){
                     next;
                }
                
                foreach my $this_sorting_ref (@{$sorting_ref}){
                    
                    if ($this_sorting_ref->{type} eq "stringcategory"){
                        my $content = (exists $title_listitem_ref->{$this_sorting_ref->{category}}[0]{content})?$title_listitem_ref->{$this_sorting_ref->{category}}[0]{content}:"";
                        next unless ($content);
                        
                        $content = OpenBib::Common::Util::grundform({
                            content   => $content,
                        });
                        
                        if ($content){
                            $logger->debug("Adding $content as sortvalue");                        
                            $doc->add_value($this_sorting_ref->{id},$content);
                        }
                    }
                    elsif ($this_sorting_ref->{type} eq "integercategory"){
                        my $content = (exists $title_listitem_ref->{$this_sorting_ref->{category}}[0]{content})?$title_listitem_ref->{$this_sorting_ref->{category}}[0]{content}:0;
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
                        if (exists $title_listitem_ref->{$this_sorting_ref->{category}}){
                            ($content) = $title_listitem_ref->{$this_sorting_ref->{category}}=~m/^(\d+)/;
                        }
                        if ($content){
                            $content = sprintf "%08d",$content;
                            $logger->debug("Adding $content as sortvalue");
                            $doc->add_value($this_sorting_ref->{id},$content);
                        }
                    }
                }
            }
            
            $doc->set_data($listitem);
            
            my $docid=$db->add_document($doc);
            
            # Abspeichern des Mappings der SQL-ID zur Xapian-Doc-ID
            $xapian_idmapping{$s_id} = $docid;
            
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

close(TITLECACHE);
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
