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

#  print $dom->toString;

  # Author -> Verfasser

  my $authors=$dom->getElementsByTagName("dc:creator");

  for (my $i=0; $i < $authors->getLength; $i++){
    my $author=$authors->item($i)->getFirstChild();

    if ($author){
      $author=$author->getData();
    }
    print "AU==".$author."\n";
  }

  # Titel -> HST

  my $titles=$dom->getElementsByTagName("dc:title");

  for (my $i=0; $i < $titles->getLength; $i++){
    my $title=$titles->item($i)->getFirstChild();

    if ($title){
      $title=$title->getData();
      
      print "TI==$title\n" if ($i==0);
      print "WT==$title\n" if ($i>0);
    }
  }

  # Art -> HSFN

  my $types=$dom->getElementsByTagName("dc:type");

  for (my $i=0; $i < $types->getLength; $i++){
    my $type=$types->item($i)->getFirstChild();

    if ($type){
      $type=$type->getData();

      if ($type=~/Text.Thesis.Doctoral/){
	$type="Dissertation";
      }
      elsif ($type=~/Text.Thesis.Habilitation/){
	$type="Habilitation";
      }
      elsif ($cleantype=~/Text.Thesis.Doctoral.Abstract/){
	$type="Dissertations-Abstract";
      }
      
      print "HS==$type\n";
    }
  }


  # Subject -> Schlagwort

  my $subjects=$dom->getElementsByTagName("dc:subject");

  for (my $i=0; $i < $subjects->getLength; $i++){
    my $subject=$subjects->item($i)->getFirstChild();

    if ($subject){
      $subject=$subject->getData();

      print "SW==$subject\n" if ($subject && $subject ne "no entry");
    }
  }

  # Jahr -> Erscheinungsjahr

  my $ejahre=$dom->getElementsByTagName("dc:date");

  for (my $i=0; $i < $ejahre->getLength; $i++){
    my $ejahr=$ejahre->item($i)->getFirstChild();

    if ($ejahr){
      $ejahr=$ejahr->getData();
      
      print "EJ==$ejahr\n";
    }
  }

  # URL -> URL

  my $urls=$dom->getElementsByTagName("dc:identifier");

  for (my $i=0; $i < $urls->getLength; $i++){
    my $url=$urls->item($i)->getFirstChild();

    if ($url){
      $url=$url->getData();

      print "UR==$url\n" if ($url =~/http/);
    }
  }

  # Abstract -> Abstract

  my $abstracts=$dom->getElementsByTagName("dc:description");
  
  for (my $i=0; $i < $abstracts->getLength; $i++){
    my $abstract=$abstracts->item($i)->getFirstChild();

    if ($abstract){
      $abstract=$abstract->getData();

      $abstract=~s/&lt;(\S{1,5})&gt;/<$1>/g;
      $abstract=~s/&amp;(\S{1,8});/&$1;/g;
      $abstract=~s/\n/<br>/g;
      $abstract=~s/^Zusammenfassung<br>//g;
      $abstract=~s/^Summary<br>//g;
      $abstract=~s/\|/&#124;/g;
      
      print "AB==$abstract\n";
    }
  }

  print "\n";

}

