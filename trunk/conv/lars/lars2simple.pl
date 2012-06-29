#!/usr/bin/perl

#####################################################################
#
#  lars2simple.pl
#
#  Filter, um Lars-Daten in ein einfaches Format zu bringen, das
#  mit simple2meta.pl verarbeitet werden kann
#
#  Copyright 2004-2009 Oliver Flimm <flimm@openbib.org>
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
    $line=~s/\r$//;
    chop $line;

#    $line=decode("cp1252",$line);
    
    my $category = substr($line,0,4);

    if (length($line) == 0 && @buffer){
        push @buffer, "9999:";

        foreach my $bufline (@buffer){
            $bufline=~s/#C#1#500\.//g;
            $bufline=~s//\; /g;
            $bufline=~s/Verlag ú//g;

            next if ($bufline=~/ID==XXX/);
            print $bufline."\n";
        }

        @buffer = ();
    }

    if ($line=~/^    /){
        my ($thisline)=$line=~m/^    (.+)/s;

        my $lastline=pop @buffer;

        # Schlagworte stehen pro Zeile
        if ($lastcategory eq "SW=="){
            push @buffer, $lastline;
            push @buffer, $thisline;
        }
        # Orte und Signaturen werden zusammengefasst
        elsif (($lastcategory eq "OR==")||($lastcategory eq "SI==")){
            push @buffer, "$lastline ; $thisline";
        }
        # Sonst wird Inhalt hintereinander gehaengt
        else {
            push @buffer, "$lastline$thisline";
        }
    }
    elsif (length($line) > 0){
        push @buffer, $line;
        $lastcategory=$category;
    }

}

if (@buffer){
    push @buffer, "9999:";
    
    foreach my $bufline (@buffer){
        $bufline=~s/#C#1#500\.//g;
        $bufline=~s//\; /g;
        
        next if ($bufline=~/ID==XXX/);
        print $bufline."\n";
    }
}

