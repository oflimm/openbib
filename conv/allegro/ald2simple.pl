#!/usr/bin/perl

#####################################################################
#
#  als2simple.pl
#
#  Filter, um Allegro-Daten in ein einfaches Format zu bringen, das
#  mit simple2meta.pl verarbeitet werden kann
#
#  Copyright 1997-2009 Oliver Flimm <flimm@openbib.org>
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

use utf8;

use Encode qw/decode encode/;

my @buffer        = ();
my $lastcategory = "";

while (my $line=<>){
    $line=~s/^.....//;
    $line=~s/ Û+ //;
    $line=~s/
$//;
    my 	@datensatz=split(" ",$line);

    foreach my $part (@datensatz){
        next if (length($part) <2 || $part=~/^\s*$/);
        
        substr($part,2,1)=":";
        print $part."\n";
    }
    print "9999:\n";
}
