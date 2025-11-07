#!/usr/bin/perl
#####################################################################
#
#  ksta2yaml.pl
#
#  Umwandeln der Jahr/Ausgabenstruktur des KStA in YAML
#
#  Dieses File ist (C) 2025 Oliver Flimm <flimm@openbib.org>
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

use DBIx::Class::ResultClass::HashRefInflator;
use OpenBib::Config;
use OpenBib::Catalog;
use YAML::Syck;

$YAML::Syck::SingleQuote = 1;
$YAML::Syck::ImplicitTyping  = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $config  = new OpenBib::Config;
my $catalog = new OpenBib::Catalog({ database => 'ksta' });

our $ksta_ref = {};

my $data_ref = {};
my $parents_ref = {};

my $hierarchy = $catalog->get_schema->resultset('TitleField')->search_rs(
    {
	'field' => 662,
	    'mult' => 2,
    },
    {
	select   => ['content', {'count' => 'titleid'}],
	as       => ['thiscontent','titlecount'],
	group_by => ['content'],
	result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
    );

while (my $item = $hierarchy->next()){
    my $content   = $item->{'thiscontent'};
    my $count     = $item->{'titlecount'};

    if ($content =~m{KoelnerStadtAnzeiger_J_(\d\d\d\d)/KoelnerStadtAnzeiger_A_(\d+)-(\d+)-\d\d\d\d_N_(\d+)/}){
	my ($year,$day,$month,$number) = ($1,$2,$3,$4); 
	my $notation  = $year.".".$number;
	my $benennung = "$day.$month.$year";
	my $parentid  = $year;
	
	my $id = $notation;

	unless (defined $data_ref->{$year}){
	    $data_ref->{$year} = {
		notation  => $year,
		benennung => $year,
	    };
	}
	
	$data_ref->{$id} = {
	    notation  => $notation,
	    benennung => $benennung,
	    parentid  => $parentid,
	    number    => $number,
	};
	
	next unless ($notation && $benennung);
	
	$ksta_ref->{description}{$notation} = $benennung ;
	
	push @{$parents_ref->{$parentid}}, $id;
    }
}

foreach my $parentid (sort keys %{$parents_ref}){
    my $basenotation = $data_ref->{$parentid}{notation};

    foreach my $childid (sort by_number @{$parents_ref->{$parentid}}){
	my $notation = $data_ref->{$childid}{notation};

	if ($basenotation && $notation){
	    push @{$ksta_ref->{hierarchy}{$basenotation}}, $notation;
	}
    }
}

open(OUT,">:utf8","./ksta.yml");
print OUT YAML::Syck::Dump($ksta_ref);
close(OUT);

sub by_number {
    my ($number1) = $a =~m{^\d\d\d\d\.(\d+)$}; 
    my ($number2) = $b =~m{^\d\d\d\d\.(\d+)$}; 
    return $number1 <=> $number2;
}
