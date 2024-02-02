#!/usr/bin/perl
#####################################################################
#
#  rvkxml2yaml.pl
#
#  Umwandeln der RVK im XML-Format in YAML
#
#  Dieses File ist (C) 2024 Oliver Flimm <flimm@openbib.org>
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
no warnings 'redefine';
use utf8;

use File::Slurper 'read_binary';
use XML::LibXML;
use XML::LibXML::XPathContext;

use YAML::Syck;

$YAML::Syck::SingleQuote = 1;
$YAML::Syck::ImplicitTyping  = 1;
$YAML::Syck::ImplicitUnicode = 1;

# XML-Inputfile from
# https://rvk.uni-regensburg.de/regensburger-verbundklassifikation-online/rvk-download

my $inputfile = $ARGV[0];

our $rvk_ref = {};

my $xmlcontent = read_binary($inputfile);

our $parser = XML::LibXML->new();
my $tree = $parser->parse_string($xmlcontent);
my $root = $tree->getDocumentElement;

foreach my $node ($root->findnodes('/classification_scheme/node')) {
    my $notation   = $node->getAttribute('notation');
    my $benennung  = $node->getAttribute('benennung');

    $rvk_ref->{description}{$notation} = $benennung;

    process_children($node,$notation);
}
    
open(OUT,">:utf8","./rvk_complete.yml");
print OUT YAML::Syck::Dump($rvk_ref);
close(OUT);

sub process_children {
    my $basenode = shift;
    my $basenotation = shift;

    foreach my $node ($basenode->findnodes('children/node')) {    
	my $notation   = $node->getAttribute ('notation');
	my $benennung  = $node->getAttribute ('benennung');
	
	$rvk_ref->{description}{$notation} = $benennung;

	push @{$rvk_ref->{hierarchy}{$basenotation}}, $notation;

	process_children($node,$notation);
    }

    return;
}
