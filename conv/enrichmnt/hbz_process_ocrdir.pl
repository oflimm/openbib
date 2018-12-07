#!/usr/bin/perl

#####################################################################
#
#  hbz_process_ocrdir.pl
#
#  Vorbereiten der Dateinamen der OCR-Inhaltsverzeichnisse
#  durch Normierung der Dateinamen auf 'HT122345456.txt'
#
#  Dieses File ist (C) 2018 Oliver Flimm <flimm@openbib.org>
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

use warnings;
use strict;
use utf8;

use File::Spec::Functions qw'no_upwards';
use File::Copy;

my $ocrdir = $ARGV[0];

$ocrdir=~s/\/$//;

if (!-d $ocrdir){
    print STDERR "$ocrdir existiert nicht!\n";
}

print "OCR-Dir: $ocrdir\n";

opendir my ($dh), $ocrdir;

for my $filename ( no_upwards sort readdir $dh) {
    my ($hbzid) = $filename =~m/^([[:alnum:]]+)_.+/;

    my $oldfilename = "$ocrdir/$filename";
    my $newfilename = "$ocrdir/$hbzid.txt";
    
    rename $oldfilename, $newfilename;
    print "$oldfilename -> $newfilename\n";
}

closedir $dh;
