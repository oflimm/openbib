#!/usr/bin/perl

#####################################################################
#
#  extract.pl
#
#  Extraktion der MDZ-Titel
#
#  Dieses File ist (C) 2014 Oliver Flimm <flimm@openbib.org>
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

use warnings;
use strict; 
use utf8;

use Encode 'decode';

our $count = 0;

$/="</marc:record>";

while (my $chunk = <>){
    my ($record) = $chunk =~m/(<marc:record.+<\/marc:record>)/s;

    next if (!defined $record);
    if ($record=~m{http://www.mdz-nbn-resolving.de/urn/resolver.pl}){
        print $record,"\n";
    }

    $count++;

    if ($count % 1000 == 0){
        print STDERR "$count titles processd\n";
    }
}


