#!/usr/bin/perl

#####################################################################
#
#  file2solr.pl
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Config;
use OpenBib::Common::Util;

my ($database,$help,$logfile,$withfields);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
            "with-fields"     => \$withfields,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/file2solr.log';

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

my %normdata                = ();

tie %normdata,                'MLDBM', "./normdata.db"
    or die "Could not tie normdata.\n";

$logger->info("### POOL $database");

my %xapian_idmapping;

tie %xapian_idmapping, 'DB_File', $config->{'autoconv_dir'}."/pools/$database/xapian_idmapping.db";

my $count = 1;
my $solr_filename = "solr-".(sprintf "%010d", $count).".xml";
    
open(SEARCH,      "<:utf8","search.mysql"      ) || die "SEARCH konnte nicht geoeffnet werden";
open(TITLISTITEM, "<:utf8","titlistitem.mysql" ) || die "TITLISTITEM konnte nicht geoeffnet werden";
open(SOLR,        ">:utf8",$solr_filename )      || die "SOLR.XML konnte nicht geoeffnet werden";

my $dbbasedir=$config->{xapian_index_base_path};

my $thisdbpath="$dbbasedir/$database";
if (! -d "$thisdbpath"){
    mkdir "$thisdbpath";
}

$logger->info("Loeschung des alten Index fuer Datenbank $database");

system("rm -f $thisdbpath/*");

$logger->info("Aufbau eines neuen  Index fuer Datenbank $database");

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

print SOLR "<add>\n";

my $atime = new Benchmark;
{
    my $atime = new Benchmark;
    while (my $search=<SEARCH>, my $titlistitem=<TITLISTITEM>) {
        my ($s_id,$verf,$hst,$kor,$swt,$notation,$sign,$ejahrint,$ejahr,$gtquelle,$inhalt,$isbn,$issn,$artinh)=split("",$search);
        my ($t_id,$listitem)=split ("",$titlistitem);
        if ($s_id != $t_id) {
            $logger->fatal("Id's stimmen nicht ueberein ($s_id != $t_id)!");
            next;
        }

        my $doc_ref = {};

#        $doc_ref->{};
        print SOLR "<doc>\n";
        print SOLR "<field name=\"id\">$database:$s_id</field>\n";
        print SOLR "<field name=\"database\">$database</field>\n";
        print SOLR "<field name=\"verf_s\">$verf</field>\n" if ($verf);
        print SOLR "<field name=\"kor_s\">$kor</field>\n" if ($kor);
        print SOLR "<field name=\"hst_s\">$hst</field>\n" if ($hst);
        print SOLR "<field name=\"swt_s\">$swt</field>\n" if ($swt);
        print SOLR "<field name=\"notation_s\">$notation</field>\n" if ($notation);
        print SOLR "<field name=\"sign_s\">$sign</field>\n" if ($sign);
        print SOLR "<field name=\"gtquelle_s\">$gtquelle</field>\n" if ($gtquelle);
        print SOLR "<field name=\"inhalt_s\">$inhalt</field>\n" if ($inhalt);
#        print SOLR "<field name=\"artinh_s\">$artinh</field>\n" if ($artinh);
        print SOLR "<field name=\"isbn_s\">$isbn</field>\n" if ($isbn);
        print SOLR "<field name=\"issn_s\">$issn</field>\n" if ($issn);

        foreach my $verf (@{$normdata{$s_id}{verf}}){
            print SOLR "<field name=\"aut_facet\">$verf</field>\n";
        }

        foreach my $kor (@{$normdata{$s_id}{kor}}){
            print SOLR "<field name=\"kor_facet\">$kor</field>\n";
        }

        foreach my $spr (@{$normdata{$s_id}{spr}}){
            print SOLR "<field name=\"spr_facet\">$spr</field>\n";
            last;
        }

        foreach my $year (@{$normdata{$s_id}{year}}){
            print SOLR "<field name=\"year_facet\">$year</field>\n";
            last;
        }

        foreach my $notation (@{$normdata{$s_id}{notation}}){
            print SOLR "<field name=\"not_facet\">$notation</field>\n";
        }

        foreach my $swt (@{$normdata{$s_id}{swt}}){
            print SOLR "<field name=\"swt_facet\">$swt</field>\n";
        }

        foreach my $mart (@{$normdata{$s_id}{mart}}){
            print SOLR "<field name=\"mart_facet\">$mart</field>\n";
            last;
        }

        print SOLR "<field name=\"data\">$listitem</field>\n";

        print SOLR "</doc>\n";

        if ($count % 10000 == 0) {
            my $btime      = new Benchmark;
            my $timeall    = timediff($btime,$atime);
            my $resulttime = timestr($timeall,"nop");
            $resulttime    =~s/(\d+\.\d+) .*/$1/;
            $atime         = new Benchmark;
            $logger->info("$count Saetze indexiert in $resulttime Sekunden");

            print SOLR "</add>\n";

            $solr_filename = "solr-".(sprintf "%010d", $count).".xml";
            close(SOLR);

            open(SOLR,        ">:utf8",$solr_filename )      || die "SOLR.XML konnte nicht geoeffnet werden";
            print SOLR "<add>\n";

        } 
   
        $count++;
    }
    print SOLR "</add>\n";
}

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");

close(SEARCH);
close(TITLISTITEM);
close(SOLR);

sub print_help {
    print << "ENDHELP";
file2solr.pl - Aufbau eines Solr-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
