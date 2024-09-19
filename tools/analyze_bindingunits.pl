#!/usr/bin/perl
#####################################################################
#
#  analyze_bindingunits.pl
#
#  Auffinden ins Leere zeigender 773er Verweise auf Mediennummern,
#  die im exemplarfuehrenden Titel nicht (mehr) existieren.
#
#  Ausgabe geht nach STDERR
#
#  Dieses File ist (C) 2024 Oliver Flimm <flimm@ub.uni-koeln.de>
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

use JSON::XS qw/decode_json/;
use YAML;

# Erster Uebergabeparameter ist der Verzeichnispfad fuer die Titel-Exportdatei
# im JSON Metaformat ohne endenden /
my $inputdir = $ARGV[0];

$inputdir=($inputdir)?$inputdir:'/opt/openbib/autoconv/pools/uni';

my $be_ref = {};
my $be_titleid_ref = {};

print "Pass 1: Bindeeinheiten und Verknuepfungen zum exemplarfuehrenden Titel bestimmen\n";

open(TITLE,"zcat $inputdir/meta.title.gz |");
while (<TITLE>){
    my $title_ref  = decode_json $_;
    my $fields_ref = $title_ref->{fields};

    my $titleid    = $title_ref->{id};
    
    if (defined $fields_ref->{'0773'}){
	my $thisfield_ref = {};

	foreach my $item_ref (@{$fields_ref->{'0773'}}){
	    $thisfield_ref->{$item_ref->{mult}}{$item_ref->{subfield}} = $item_ref->{content} 
	}

	# Detect binding unit
	foreach my $mult (sort keys %{$thisfield_ref} ){
	    if (defined $thisfield_ref->{$mult}{p} && $thisfield_ref->{$mult}{p} eq "AngebundenAn"){
		
		my $g = $thisfield_ref->{$mult}{g};
		$g =~s/^no://;
		my @mnrs = split('\s*:\s*',$g);

		my %have_mnr = ();
		foreach my $mnr (@mnrs){
		    if (defined $have_mnr{$mnr} && $have_mnr{$mnr}){
			print STDERR "Fehler $titleid: Multipler Barcode $mnr\n";
		    }
		    $have_mnr{$mnr} = 1;
		    push @{$be_ref->{$thisfield_ref->{$mult}{w}}}, {
			barcode       => $mnr,
		        linking_mmsid => $titleid,
		    };
		}
	    }
	}
	
    }
}
close(TITLE);

print "Pass 2: Analyse des exemplarfuehrenden Titels\n";

open(TITLE,"zcat $inputdir/meta.title.gz |");
while (<TITLE>){
    my $title_ref = decode_json $_;
    my $fields_ref = $title_ref->{fields};

    my $titleid    = $title_ref->{id};

    next unless (defined $be_ref->{$titleid});

    # Items analysieren;
    my $barcode_ref = {};
    if (defined $fields_ref->{'1944'}){
	my $have_mnr = {};
	foreach my $item_ref (@{$fields_ref->{'1944'}}){
	    if ($item_ref->{subfield} eq "a"){
		$have_mnr->{$item_ref->{content}} = 1;
	    }
	}

	my $linkage_error = 0;
	foreach my $linkage_ref (@{$be_ref->{$titleid}}){
	    if (!defined $have_mnr->{$linkage_ref->{barcode}}){
		$linkage_error = 1;
		print STDERR "Fehler bei BE-Link ".$linkage_ref->{linking_mmsid}." (".$linkage_ref->{barcode}.") -> $titleid (".join(' ; ',keys %$have_mnr).")\n";
	    }
	    else {
		my $barcode = $linkage_ref->{barcode};
		foreach my $mnr (keys %{$have_mnr}){
		    if ($mnr=~m/$barcode\#/){
			    print STDERR "Moeglicher Fehler bei BE-Link ".$linkage_ref->{linking_mmsid}." (".$linkage_ref->{barcode}.") -> $titleid (".join(' ; ',keys %$have_mnr).") wegen Existenz von Signatur $mnr mit Hash #\n";
			    
		    }
		}
	    }
	}
    }
}
