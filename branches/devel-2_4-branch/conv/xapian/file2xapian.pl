#!/usr/bin/perl

#####################################################################
#
#  file2xapian.pl
#
#  Dieses File ist (C) 2007 Oliver Flimm <flimm@openbib.org>
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
    $ENV{XAPIAN_PREFER_FLINT}    = '1';
    $ENV{XAPIAN_FLUSH_THRESHOLD} = '200000';
}

use Benchmark ':hireswallclock';
use DB_File;
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use MLDBM qw(DB_File Storable);
use Storable ();
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian;
use String::Tokenizer;
use YAML::Syck;
use OpenBib::Config;
use OpenBib::Common::Util;

my ($database,$help,$logfile,$withfields,$withsorting,$withpositions);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
            "with-fields"     => \$withfields,
            "with-sorting"    => \$withsorting,
            "with-positions"  => \$withpositions,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/file2xapian.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, LOGFILE, Screen
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

if (!$database){
  $logger->fatal("Kein Pool mit --database= ausgewaehlt");
  exit;
}

my $FLINT_BTREE_MAX_KEY_LEN = 80;
my $DRILLDOWN_MAX_KEY_LEN   = 100;

my %normdata                = ();

tie %normdata,                'MLDBM', "./normdata.db"
    or die "Could not tie normdata.\n";

$logger->info("### POOL $database");

my %xapian_idmapping;

tie %xapian_idmapping, 'DB_File', $config->{'autoconv_dir'}."/pools/$database/xapian_idmapping.db";

open(TITLISTITEM, "<:utf8","titlistitem.mysql" ) || die "TITLISTITEM konnte nicht geoeffnet werden";

my $dbbasedir=$config->{xapian_index_base_path};

my $thisdbpath="$dbbasedir/$database";
if (! -d "$thisdbpath"){
    mkdir "$thisdbpath";
}

$logger->info("Loeschung des alten Index fuer Datenbank $database");

system("rm -f $thisdbpath/*");

$logger->info("Aufbau eines neuen  Index fuer Datenbank $database");

my $db = Search::Xapian::WritableDatabase->new( $thisdbpath, Search::Xapian::DB_CREATE_OR_OVERWRITE ) || die "Couldn't open/create Xapian DB $!\n";

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

my $tokenizer = String::Tokenizer->new();

$logger->info("Migration der Titelsaetze");

my $atime = new Benchmark;
my $count = 1;
{
    my $atime = new Benchmark;
    while (my $titlistitem=<TITLISTITEM>) {
        my ($s_id,$listitem)=split ("",$titlistitem);

        my $seen_token_ref = {};
        
        my $doc=Search::Xapian::Document->new();

        # ID des Satzes recherchierbar machen
        $doc->add_term($config->{xapian_search_prefix}{'id'}.$s_id);

        # Katalogname des Satzes recherchierbar machen
        $doc->add_term($config->{xapian_search_prefix}{'fdb'}.$database);

        my $k = 0;

        $logger->debug("Available Data for id $s_id ".YAML::Dump(\$normdata{$s_id}));

        foreach my $searchfield (keys %{$config->{searchfield}}) {

            $logger->debug("Processing Searchfield $searchfield for id $s_id");
            # Einzelne Worte (Fulltext)
            if ($config->{searchfield}{$searchfield}{type} eq 'ft'){
                # Tokenize
                next if (! exists $normdata{$s_id}->{$searchfield});
                
                my $tokenstring = join(' ',@{$normdata{$s_id}->{$searchfield}});
                $tokenizer->tokenize($tokenstring);
                
                my $i = $tokenizer->iterator();

                my @saved_tokens=();
                while ($i->hasNextToken()) {
                    my $next = $i->nextToken();

                    # Naechstes, wenn kein Token
                    next if (!$next);
                    # Naechstes, wenn keine Zahl oder einstellig
                    # next if (length($next) < 2 && $next !~ /\d/);
                    # Naechstes, wenn Stopwort
                    next if (exists $config->{stopword_filename} && exists $stopword_ref->{$next});

                    my $fieldtoken=$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}}.$next;

                    # Begrenzung der keys auf FLINT_BTREE_MAX_KEY_LEN Zeichen
                    
                    $fieldtoken=(length($fieldtoken) > $FLINT_BTREE_MAX_KEY_LEN)?substr($fieldtoken,0,$FLINT_BTREE_MAX_KEY_LEN):$fieldtoken;

                    $doc->add_term($fieldtoken);
                    
                    if ($withpositions){
                        $doc->add_posting($fieldtoken,$k);
                        $k++;
                    }
                }
   	    }
            # Zusammenhaengende Zeichenkette
            elsif ($config->{searchfield}{$searchfield}{type} eq 'string'){
                next if (!exists $normdata{$s_id}->{$searchfield});
                
                my %seen_terms = ();
                my @unique_terms = grep { ! $seen_terms{$_} ++ } @{$normdata{$s_id}->{$searchfield}}; 
                
	        foreach my $unique_term (@unique_terms){
                    next unless ($unique_term);
                    
                    # Kategorie in Feld einfuegen            
                    my $field = OpenBib::Common::Util::grundform({
                        content   => $unique_term,
                        searchreq => 1,
                    });
                    
                    $field=~s/\W/_/g;
                    
                    $field=$config->{xapian_search_prefix}{$config->{searchfield}{$searchfield}{prefix}}.$field;
                    
                    # Begrenzung der keys auf FLINT_BTREE_MAX_KEY_LEN Zeichen
                    if (length($field) > $DRILLDOWN_MAX_KEY_LEN){
                        $field=substr($field,0,$DRILLDOWN_MAX_KEY_LEN);
                    }

                    $logger->debug("Added Stringvalue $field");
                    $doc->add_term($field);
	        }
   	    }
	}

        # Facetten
        foreach my $type (keys %{$config->{xapian_drilldown_value}}){
            # Datenbankname
            $doc->add_value($config->{xapian_drilldown_value}{$type},encode_utf8($database)) if ($type eq "db" && $database);
            
            next if (!exists $normdata{$s_id}->{"facet_".$type});

            my %seen_terms = ();
            my @unique_terms = grep { ! $seen_terms{$_} ++ } @{$normdata{$s_id}->{"facet_".$type}}; 

            my $multstring = join("\t",@unique_terms);

            $logger->debug("Adding to $type facet $multstring");
            $doc->add_value($config->{xapian_drilldown_value}{$type},encode_utf8($multstring)) if ($multstring);
        }

        # Sortierung
        if ($withsorting){
            my $sorting_ref = [
                {
                    # Verfasser/Koepeschaft
                    id         => $config->{xapian_sorttype_value}{'author'},
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
                    id         => $config->{xapian_sorttype_value}{'yearofpub'},
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
                    id         => $config->{xapian_sorttype_value}{'signature'},
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

            my $titlistitem_raw = pack "H*", $listitem;
            my $titlistitem_ref = Storable::thaw($titlistitem_raw);

#            $logger->debug(YAML::Dump($titlistitem_ref));
            
            foreach my $this_sorting_ref (@{$sorting_ref}){

                if ($this_sorting_ref->{type} eq "stringcategory"){
                    my $content = (exists $titlistitem_ref->{$this_sorting_ref->{category}}[0]{content})?$titlistitem_ref->{$this_sorting_ref->{category}}[0]{content}:"";
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
                    my $content = 0;
                    if (exists $titlistitem_ref->{$this_sorting_ref->{category}}[0]{content}){
                        ($content) = $titlistitem_ref->{$this_sorting_ref->{category}}[0]{content}=~m/^(\d+)/;
                    }
                    if ($content){
                        $content = sprintf "%08d", $content;
                        $logger->debug("Adding $content as sortvalue");
                        $doc->add_value($this_sorting_ref->{id},$content);
                    }
                }
                elsif ($this_sorting_ref->{type} eq "integervalue"){
                    my $content = 0 ;
                    if (exists $titlistitem_ref->{$this_sorting_ref->{category}}){
                        ($content) = $titlistitem_ref->{$this_sorting_ref->{category}}=~m/^(\d+)/;
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

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");

untie(%xapian_idmapping);

sub print_help {
    print << "ENDHELP";
file2xapian.pl - Datenbank-Konnektor zum Aufbau eines Xapian-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   -with-fields          : Aufbau von einzelnen Suchfeldern (nicht default)
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
