#!/usr/bin/perl

#####################################################################
#
#  harvestOAI.pl
#
#  Abzug eines OAI-Repositories
#
#  Dieses File ist (C) 2003-2004 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;

use OAI2::Harvester;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

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

while( my $rec = $response->next ) {
  if( $rec->is_error ) {
    die $rec->message;
  }

  my $md=$rec->metadata();

  my $doc = new XML::DOM::Document();
  my $dom = $md->toDOM($doc); # Clone internal XML

  # Author -> Verfasser

  my $authors=$dom->getElementsByTagName("dc:creator");

  for (my $i=0; $i < $authors->getLength; $i++){
    my $author=$authors->item($i);

    $cleanauthor=$author->toString;
    $cleanauthor=~s/<.+?>//g;
    print "AU==$cleanauthor\n" if ($cleanauthor);
  }

  # Titel -> HST

  my $titles=$dom->getElementsByTagName("dc:title");

  for (my $i=0; $i < $titles->getLength; $i++){
    my $title=$titles->item($i);

    $cleantitle=$title->toString;
    $cleantitle=~s/<.+?>//g;

    print "TI==$cleantitle\n" if ($i==0);
    print "WT==$cleantitle\n" if ($i>0);
  }

  # Art -> HSFN

  my $types=$dom->getElementsByTagName("dc:type");

  for (my $i=0; $i < $types->getLength; $i++){
    my $type=$types->item($i);

    $cleantype=$type->toString;
    $cleantype=~s/<.+?>//g;

    if ($cleantype=~/Text.Thesis.Doctoral/){
      $cleantype="Dissertation";
    }
    elsif ($cleantype=~/Text.Thesis.Habilitation/){
      $cleantype="Habilitation";
    }
    elsif ($cleantype=~/Text.Thesis.Doctoral.Abstract/){
      $cleantype="Dissertations-Abstract";
    }

    print "HS==$cleantype\n";
  }


  # Subject -> Schlagwort

  my $subjects=$dom->getElementsByTagName("dc:subject");

  for (my $i=0; $i < $subjects->getLength; $i++){
    my $subject=$subjects->item($i);

    $cleansubject=$subject->toString;
    $cleansubject=~s/<.+?>//g;
    print "SW==$cleansubject\n" if ($cleansubject && $cleansubject ne "no entry");

  }

  # Jahr -> Ercheinungsjahr

  my $ejahre=$dom->getElementsByTagName("dc:date");

  for (my $i=0; $i < $ejahre->getLength; $i++){
    my $ejahr=$ejahre->item($i);

    $cleanejahr=$ejahr->toString;
    $cleanejahr=~s/<.+?>//g;

    print "EJ==$cleanejahr\n";
  }

  # URL -> URL

  my $urls=$dom->getElementsByTagName("dc:identifier");

  for (my $i=0; $i < $urls->getLength; $i++){
    my $url=$urls->item($i);

    $cleanurl=$url->toString;
    $cleanurl=~s/<.+?>//g;

    print "UR==$cleanurl\n" if ($cleanurl =~/http/);
  }

  print "\n";
}

