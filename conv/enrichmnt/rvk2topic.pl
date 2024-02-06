#!/usr/bin/perl
#####################################################################
#
#  rvk2topics.pl
#
#  Erzeugung von Anreicherungsdaten mit Themengebieten anhand von
#  bestehenden Anreicherungdaten mit RVKs aus den BVB Open Data Dumps
#  fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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

use JSON::XS;

use OpenBib::User;

my $user = OpenBib::User->new;

my $rvk_topic_mapping_ref = {};

foreach my $topic_ref (@{$user->get_topics}){
    foreach my $classification (@{$user->get_classifications_of_topic({ topicid => $topic_ref->{id}, type => 'rvk'})}){
        $rvk_topic_mapping_ref->{$classification} = $topic_ref->{id};
    }
}

my $count = 1;

while (<>){
    my $enrich_ref = decode_json $_;

    $enrich_ref->{field} = 4102;
    $enrich_ref->{subfield} = 'a';
    my ($rvkbase) = $enrich_ref->{content} =~m/^([A-Z][A-Z])/;

    next unless (defined $rvkbase && defined $rvk_topic_mapping_ref->{$rvkbase});

    $enrich_ref->{content} = $rvk_topic_mapping_ref->{$rvkbase};

    print encode_json $enrich_ref, "\n";

    if ($count % 10000 == 0){
	print STDERR "$count records processed";
    }
    
    $count++
}

print STDERR "$count records processed";
