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

my ($url,$format,$from,$until,$set);

&GetOptions(
    "format=s"   => \$format,
    "url=s"      => \$url,
    "from=s"     => \$from,
    "until=s"    => \$until,
    "set=s"      => \$set,
);


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

if (!$format){
    $format = "oai_dc";
}

my $filename = "pool-${format}-${from}_to_${until}.xml";
$filename=~s/\s+/_/g;

open(OUT,">:raw",$filename);

my $h = new HTTP::OAI::Harvester(baseURL=>$iurl);

my $response = $h->repository($h->Identify);
if( $response->is_error ) {
  print "Error requesting Identify:\n",
    $response->code . " " . $response->message, "\n";
  exit;
}
if ($set){
    $response = $h->ListRecords(
        metadataPrefix => $format,
        from           => $from, # '2001-01-29T15:27:51Z',
        until          => $until, #'2003-01-29T15:27:51Z',
        set            => $set
    );
}
else {
    $response = $h->ListRecords(
        metadataPrefix => $format,
        from           => $from, # '2001-01-29T15:27:51Z',
        until          => $until, #'2003-01-29T15:27:51Z',
    );
}Z'
			       );

if( $response->is_error ) {
  die("Error harvesting: " . $response->message . "\n");
}

$response =while( my $rec = $response->next ) {
    print OUT "<record>\n";
    print OUTit();
}

print "<?xml version = '1.0' encoding = 'UTF-8'?>\n";
print "<oairesponse>\n";
while( my $recif ($rec->is_deleted){
        print OUT " <is_deleted>1</is_deleted>\n";
    }
    else {
        eval {
            my $metadata_string = $rec->metadata->dom->toString;
            $metadata_string=~s/^<\?xml.*?>//;
            print OUT $metadata_string,"\n";
        };
    }
    
    print OUT "</record>\n";
}

close(OUT);
