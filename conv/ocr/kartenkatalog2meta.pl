#!/usr/bin/perl
#####################################################################
#
#  kartenkatalog2meta.pl
#
#  Konvertierung von digitalisierten Katalogkarten per tesseract OCR
#  in das Einlade-Metaformat
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
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

use 5.008001;

use utf8;
use warnings;
use strict;

use Encode 'decode';
use File::Find;
use File::Slurp;
use Getopt::Long;
use JSON::XS;
use Encode qw /decode_utf8/;

our ($inputdir,$lang);

&GetOptions(
    "inputdir=s" => \$inputdir,
    "lang=s"     => \$lang,
    );

if (!$inputdir){
    print << "HELP";
kartenkatalog2meta.pl - Aufrufsyntax

    kartenkatalog2meta.pl --inputdir=xxx --lang=deu+heb

    WICHTIG: Es muss der Absolute Pfad als inputdir uebergeben werden beginnend mit /
HELP
exit;
}

my $mediatype_ref = {};
open (TITLE,     ,"| gzip > meta.title.gz");
$| = 1;

sub process_file {
    return unless ($File::Find::dir=~/normal/);
    return unless ($File::Find::name=~/.gif$/);

    my $filename = $_;

    my ($id) = $filename =~m/^(.+)\.gif$/; 

    my ($basedir) = $id =~m/^(\d\d\d[a-z])/;
    my ($subdir)  = $id =~m/^(\d\d\d[a-z]\d\d\d)/;
    
    my $title_ref = {
        'fields' => {},
    };
    
    my $multcount_ref = {};

    $title_ref->{id} = $id;

    my $cmd = "/usr/bin/tesseract -l $lang $File::Find::name stdout|";

    print "Executing $cmd\n";

    my $current_dir = `pwd`;
    
    open(TESS, "/usr/bin/tesseract -l $lang $File::Find::name stdout|");

    my $ocrtext = "";

    while(<TESS>){
	$ocrtext.=decode_utf8($_);
    }

    # OCR-Text as-is abspeichern
    # Optimierung per Regexp spaeter ueber Import-Filter 
    
    close(TESS);

    # OCR-Text wird Abstract
    {
	my $mult = ++$multcount_ref->{'0750'};
	
	push @{$title_ref->{fields}{'0750'}}, {
	    mult     => $mult,
	    subfield => '',
	    content  => $ocrtext,
	};
    }

    # Thumbnail-Pfad
    {
	my $mult = ++$multcount_ref->{'0662'};
	
	push @{$title_ref->{fields}{'0662'}}, {
	    mult     => $mult,
	    subfield => '',
	    content  => "$basedir/normal/$subdir/$filename",
	};
    }
    
    # Thumbnail-Pfad
    {
	my $mult = ++$multcount_ref->{'2662'};
	
	push @{$title_ref->{fields}{'2662'}}, {
	    mult     => $mult,
	    subfield => '',
	    content  => "$basedir/vorschau/$subdir/$filename",
	};
    }
    
    
    print TITLE encode_json $title_ref, "\n";

}

find(\&process_file, $inputdir);

close(TITLE);
