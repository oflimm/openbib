#!/usr/bin/perl

#####################################################################
#
#  dump_titles2csv.pl
#
#  Dieses File ist (C) 2015-2016 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Catalog::Factory;
use JSON::XS qw/decode_json/;
use Encode qw(decode_utf8 encode_utf8);
use Getopt::Long;
use List::MoreUtils qw/ uniq /;
use Log::Log4perl qw(get_logger :levels);
use Text::CSV_XS;

my ($database,$help,$logfile,$outputfile);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
            "outputfile=s"    => \$outputfile,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/dump_titles2csv.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, LOGFILE, Screen
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

my $atime      = new Benchmark;

if (!$database){
  $logger->fatal("Kein Pool mit --database= ausgewaehlt");
  exit;
}

$logger->info("### POOL $database");

my $out;

open $out, ">:encoding(utf8)", $outputfile;

my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database});

my $outputcsv = Text::CSV_XS->new ({
    'eol'         => "\n",
    'sep_char'    => "\t",
});

my $out_ref = [];

push @{$out_ref}, ('id','tstamp_create','tstamp_update','Person/Körperschaft','AST','Titel','Zusatz','Auflage','Verlag','Jahr','Gesamttitel','Band','ISBN','ISSN','ZDBID','BibKey','WorkKey','Signatur','ISIL');

$outputcsv->print($out,$out_ref);

my $titles = $catalog->get_schema->resultset('Title');

my $count = 0;
while (my $title=$titles->next){
    $out_ref = [];    

    my $titlecache_ref = decode_json $title->titlecache;
    
    my @pers_korp  = ();
    my @ast        = ();
    my @titel      = ();
    my @zusatz     = ();
    my @auflage    = ();
    my @verlag     = ();
    my @jahr       = ();
    my @gt         = ();
    my @band       = ();
    my @isbn       = ();
    my @issn       = ();
    my @bibkey     = ();
    my @workkey    = ();
    my @signatur   = ();
    my @locations  = ();
    my @zdbids     = ();

    foreach my $item_ref (@{$titlecache_ref->{PC0001}}){
        push @pers_korp, cleanup_content($item_ref->{content});
    }
    foreach my $item_ref (@{$titlecache_ref->{T0310}}){
        push @ast, cleanup_content($item_ref->{content});
    }
    foreach my $item_ref (@{$titlecache_ref->{T0331}}){
        push @titel, cleanup_content($item_ref->{content});
    }
    foreach my $item_ref (@{$titlecache_ref->{T0335}}){
        push @zusatz, cleanup_content($item_ref->{content});
    }
    foreach my $item_ref (@{$titlecache_ref->{T0403}}){
        push @auflage, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$titlecache_ref->{T0089}}){
        push @band, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$titlecache_ref->{T0455}}){
        push @band, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$titlecache_ref->{T0540}}){
        push @isbn, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$titlecache_ref->{T0553}}){
        push @isbn, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$titlecache_ref->{T0543}}){
        push @issn, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$titlecache_ref->{T5050}}){
        push @bibkey, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$titlecache_ref->{T5055}}){
        push @workkey, cleanup_content($item_ref->{content});
    }
    
    if (defined $titlecache_ref->{T0424}){
        foreach my $item_ref (@{$titlecache_ref->{T0424}}){
            push @jahr, cleanup_content($item_ref->{content});
        }
    }
    elsif (defined $titlecache_ref->{T0425}){
        foreach my $item_ref (@{$titlecache_ref->{T0425}}){
            push @jahr, cleanup_content($item_ref->{content});
        }
    }
        
    foreach my $item_ref (@{$titlecache_ref->{T0451}}){
        push @gt, cleanup_content($item_ref->{content});
    }

    foreach my $item_ref (@{$titlecache_ref->{T0572}}){
        push @zdbids, cleanup_content($item_ref->{content});
    }
    
    foreach my $item_ref (@{$titlecache_ref->{X0014}}){
        push @signatur, cleanup_content($item_ref->{content});
    }

    foreach my $location (@{$titlecache_ref->{locations}}){
        push @locations, $location;
    }
        
    push @{$out_ref}, ($title->id,$title->tstamp_create,$title->tstamp_update,join(' ; ',@pers_korp),join(' ; ',@ast),join(' ; ',@titel),join(' ; ',@zusatz),join(' ; ',@auflage),join(' ; ',@verlag),join(' ; ',@jahr),join(' ; ',@gt),join(' ; ',uniq @band),join(' ; ',uniq @isbn),join(' ; ',uniq @issn),join(' ; ',uniq @zdbids),join(' ; ',uniq @bibkey),join(' ; ',uniq @workkey),join(' ; ',@signatur)),join(' ; ',uniq @locations);    

    $outputcsv->print($out,$out_ref);

    $count++;

    if ($count % 1000 == 0){
	$logger->info("$count done");
    }
    
}

close $out;

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");

sub cleanup_content {
    my $content = shift;

    $content=~s/&lt;/</g;
    $content=~s/&gt;/>/g;
    $content=~s/&amp;/&/g;
    return $content;
}

sub print_help {
    print << "ENDHELP";
dump_title2csv.pl - Datenbank-Dump in CSV-Datei der Kurzlisten-Kategorien

   Optionen:
   -help                 : Diese Informationsseite
       
   --outputfile          : CSV-Ausgabedatei
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
