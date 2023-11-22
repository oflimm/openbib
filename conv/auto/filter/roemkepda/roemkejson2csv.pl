#!/usr/bin/perl

#####################################################################
#
#  roemkejson2csv.pl
#
#  Dieses File ist (C) 2016 Oliver Flimm <flimm@openbib.org>
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

use File::Slurp;
use JSON::XS qw/decode_json/;
use Text::CSV_XS;

my $outputcsv = Text::CSV_XS->new ({
    'eol'         => "\n",
    'sep_char'    => "\t",
});

my $out;

open $out, ">:encoding(utf8)", $ARGV[1];

my $out_ref = [];

push @{$out_ref}, ('upi','identifier','title','person','publisher','publishingyear','price','availability','cover','linked_isbn');

$outputcsv->print($out,$out_ref);

my $json = read_file($ARGV[0]) ;

my $json_ref = decode_json($json);

foreach my $item_ref (@$json_ref){
    my $out_ref = [];
    $out_ref->[0] = $item_ref->{upi};
    $out_ref->[1] = $item_ref->{identifier};
    $out_ref->[2] = $item_ref->{title};
    $out_ref->[3] = $item_ref->{person};
    $out_ref->[4] = $item_ref->{publisher};
    $out_ref->[5] = $item_ref->{publishingyear};
    $out_ref->[6] = $item_ref->{price};
    $out_ref->[7] = $item_ref->{availability};
    $out_ref->[8] = $item_ref->{cover};
    $out_ref->[9] = $item_ref->{linked_isbn};

    $outputcsv->print($out,$out_ref);
}

close $out;
