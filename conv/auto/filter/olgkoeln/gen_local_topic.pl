#!/usr/bin/perl
#####################################################################
#
#  gen_local_topic.pl
#
#  Themengebiet im lokalen Katalog anhand bestehender Systematik-
#  Normdaten bestimmen
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
use YAML;

my $user = OpenBib::User->new;

my $rvk_topic_mapping_ref = {};
my $bk_topic_mapping_ref  = {};
my $ddc_topic_mapping_ref = {};

foreach my $topic_ref (@{$user->get_topics}){
    foreach my $classification (@{$user->get_classifications_of_topic({ topicid => $topic_ref->{id}, type => 'rvk'})}){
        $rvk_topic_mapping_ref->{$classification} = $topic_ref->{id};
    }
    foreach my $classification (@{$user->get_classifications_of_topic({ topicid => $topic_ref->{id}, type => 'bk'})}){
        $bk_topic_mapping_ref->{$classification} = $topic_ref->{id};
    }
    foreach my $classification (@{$user->get_classifications_of_topic({ topicid => $topic_ref->{id}, type => 'ddc'})}){
        $ddc_topic_mapping_ref->{$classification} = $topic_ref->{id};
    }
}

while (<>){
    my $title_ref = decode_json $_;

    my @topicids = ();

    # DDC in 082$a
    if (defined $title_ref->{'fields'}{'0082'}){
	foreach my $item_ref (@{$title_ref->{'fields'}{'0082'}}){
	    if (defined $item_ref->{'subfield'} && $item_ref->{'subfield'} eq "a"){
		my $ddc = $item_ref->{'content'};
		
		push @topicids, $ddc_topic_mapping_ref->{$ddc};
	    }
	}
    }

    # RVK in 084$a mit 084$2 = 'rvk'
    if (defined $title_ref->{'fields'}{'0084'}){
	# Umorganisieren nach Mult-Gruppe
	my $field_084_ref = {};
	
	foreach my $item_ref (@{$title_ref->{'fields'}{'0084'}}){
	    $field_084_ref->{$item_ref->{mult}}{$item_ref->{subfield}} = $item_ref->{content}; 
	}

	foreach my $mult (sort keys %{$field_084_ref}){
	    if (defined $field_084_ref->{$mult}{'2'} && $field_084_ref->{$mult}{'2'} =~m/^rvk$/ && defined $field_084_ref->{$mult}{'a'}){
		if ($field_084_ref->{$mult}{'a'} =~m/^([A-Z][A-Z]) \d+/){
		    my $rvk = $1;

		    push @topicids, $rvk_topic_mapping_ref->{$rvk};
		}
	    }
	}
    }

    my $mult = 1;
    my $topics_seen_ref = {};
    foreach my $topicid (@topicids){
	if (defined $topicid && !defined $topics_seen_ref->{$topicid}){
	    push @{$title_ref->{'fields'}{'4102'}}, {
		subfield => '',
		content  => $topicid,
		mult     => $mult++,
	    };
	    $topics_seen_ref->{$topicid} = 1;
	}
    }

    print encode_json $title_ref, "\n";
}
