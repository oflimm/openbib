#!/usr/bin/perl

#####################################################################
#
#  harvestOAI.pl
#
#  Abzug eines OAI-Repositories
#
#  Dieses File ist (C) 2003-2013 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

use warnings;
use strict;

use utf8;

use Getopt::Long;
use HTTP::OAI;
use YAML;
use Log::Log4perl qw(get_logger :levels);

my ($url,$format,$from,$until,$set,$loglevel,$all);

&GetOptions(
    "format=s"   => \$format,
    "url=s"      => \$url,
    "all"        => \$all,
    "from=s"     => \$from,
    "until=s"    => \$until,
    "set=s"      => \$set,
    "loglevel=s" => \$loglevel,
);

my $logfile = '/var/log/openbib/harvestoai.log';

$loglevel=($loglevel)?$loglevel:'INFO';

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

$logger->info("Starting harvesting from url $url");

if (!$from){
    # Scannen der bisher geharvesteten Dateien

    foreach my $this_filename (<pool-*.xml>) {
        my ($this_format,$this_from,$this_to)=$this_filename=~m/^pool-(.*?)-(\d\d\d\d.+?Z)_to_(\d\d\d\d.+?Z).xml$/;
        $format=$this_format unless ($format);
        $from = $this_to;
    }
    
    if (!$from){
        $from = "1970-01-01T12:00:00Z";
    }
}

my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $dst) = localtime();
$mon += 1;
$year += 1900;

if (!$until){
    $until = sprintf "%4d-%02d-%02dT%02d:%02d:%02dZ",$year,$mon,$mday,$hour,$min,$sec;
}

if ($all){
    $logger->info("Harvesting all");
}
else {
    $logger->info("Timespan from $from until $until");
}

if (!$format){
    $format = "oai_dc";
}

$logger->info("Using format: $format");

my $filename = "pool-${format}-${from}_to_${until}.xml";
$filename=~s/\s+/_/g;

open(OUT,">:raw",$filename);

my $h = new HTTP::OAI::Harvester(baseURL=>$url);

my $response = $h->repository($h->Identify);
if( $response->is_error ) {
  print "Error requesting Identify:\n",
    $response->code . " " . $response->message, "\n";
  exit;
}
if ($set){
    $logger->info("Using set: $set");

    if ($all){
        $response = $h->ListRecords(
            metadataPrefix => $format,
            set            => $set
        );
    }
    else {
        $response = $h->ListRecords(
            metadataPrefix => $format,
            from           => $from, # '2001-01-29T15:27:51Z',
            until          => $until, #'2003-01-29T15:27:51Z',
            set            => $set
        );
    }
    
}
else {
    if ($all){        
        $response = $h->ListRecords(
            metadataPrefix => $format
        );
    }
    else {
        $response = $h->ListRecords(
            metadataPrefix => $format,
            from           => $from, # '2001-01-29T15:27:51Z',
            until          => $until, #'2003-01-29T15:27:51Z',
        );
    }
}

if( $response->is_error ) {
    $logger->error_die("Error: ", $response->code,
                       " (", $response->message, ")");
}

while( my $rec = $response->next ) {
    if( $rec->is_error ) {
        $logger->error($rec->message);
        next;
    }

    print OUT "<record>\n";

    eval {
        my $header_string = $rec->header->dom->toString;
        $header_string=~s/^<\?xml.*?>//;

        print OUT " $header_string \n";
    };
    if ($rec->is_deleted){
        print OUT " <is_deleted>1</is_deleted>\n";
    }
    else {
        eval {
            my $metadata_string = $rec->metadata->dom->toString;
            $metadata_string=~s/^<\?xml.*?>//;
            print OUT $metadata_string,"\n";
        };
    }

    my $about_string = $rec->{about}[0]->dom->toString;
    
    if ($about_string){
        $about_string=~s/^<\?xml.*?>//;
        
        print OUT " $about_string \n";
    }


    print OUT "</record>\n";
}

close(OUT);
