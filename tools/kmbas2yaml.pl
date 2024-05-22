#!/usr/bin/perl
#####################################################################
#
#  kmbas2yaml.pl
#
#  Umwandeln der KMB Aufstellungssystematik im CSV-Format in YAML
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

use Text::CSV_XS;
use YAML::Syck;

$YAML::Syck::SingleQuote = 1;
$YAML::Syck::ImplicitTyping  = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $inputfile = $ARGV[0];

my $csv_options = {
    'eol' => "\n",
	'sep_char' => "\t",
	'quote_char' => '"',
  'escape_char' => '"',
};

my $inputencoding = "utf8";
    
our $kmbas_ref = {};

open my $in,   "<:encoding($inputencoding)",$inputfile;
#open my $in,   "<",$inputfile;

my $csv = Text::CSV_XS->new($csv_options);

my @cols = @{$csv->getline ($in)};
my $row = {};
$csv->bind_columns (\@{$row}{@cols});

my $data_ref = {};
my $parents_ref = {};

while ($csv->getline ($in)){
    my $id        = $row->{'ID'};
    my $notation  = $row->{'Systematik'};
    my $benennung = $row->{'Titel'};
    my $parentid  = $row->{'RefId'};
    my $ref       = $row->{'Ref'};    

    $notation =~s/^\s+//;
    $notation =~s/\s+$//;
    
    $data_ref->{$id} = {
	notation => $notation,
	benennung => $benennung,
	parentid => $parentid,
	ref => $ref,
    };

    next unless ($notation && $benennung);
    
    $kmbas_ref->{description}{$notation} = $benennung ;
    
    push @{$parents_ref->{$parentid}}, $id;
}

close $in;

foreach my $parentid (keys %{$parents_ref}){
    my $basenotation = $data_ref->{$parentid}{notation};

    foreach my $childid (@{$parents_ref->{$parentid}}){
	my $notation = $data_ref->{$childid}{notation};

	if ($basenotation && $notation){
	    push @{$kmbas_ref->{hierarchy}{$basenotation}}, $notation;
	}
    }
}

open(OUT,">:utf8","./kmbas.yml");
print OUT YAML::Syck::Dump($kmbas_ref);
close(OUT);
