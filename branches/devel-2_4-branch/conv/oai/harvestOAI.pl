#!/usr/bin/perl

#####################################################################
#
#  harvestOAI.pl
#
#  Abzug eines OAI-Repositories
#
#  Dieses File ist (C) 2003-2008 Oliver Flimm <flimm@openbib.org>
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

use utf8;

use Getopt::Long;

use OAI2::Harvester;

#binmode STDOUT, ':utf8';

&GetOptions("oaiurl=s" => \$oaiurl,
	    );

my $h = new OAI2::Harvester(-baseURL=>$oaiurl);

my $response = $h->repository($h->Identify);
if( $response->is_error ) {
  print "Error requesting Identify:\n",
    $response->code . " " . $response->message, "\n";
  exit;
}

$response = $h->ListIdentifiers(
				-metadataPrefix=>'oai_dc',
				#-from=>'2001-01-29T15:27:51Z',
				#-until=>'2003-01-29T15:27:51Z'
			       );

if( $response->is_error ) {
  die("Error harvesting: " . $response->message . "\n");
}

$response = $h->ListRecords(-metadataPrefix=>'oai_dc');
if( $response->is_error ) {
  print "Error: ", $response->code,
    " (", $response->message, ")\n";
  exit();
}

print "<?xml version = '1.0' encoding = 'UTF-8'?>\n";
print "<oairesponse>\n";
while( my $rec = $response->next ) {
    print "<record>\n";
    print " <id>".$rec->identifier."</id>\n";
    if( $rec->is_error ) {
        die $rec->message;
    }
    print $rec->metadata, "\n";
    print "</record>\n";
}
print "</oairesponse>\n";

