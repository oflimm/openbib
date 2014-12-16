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

foreach my $topic_ref (@{$user->get_topics}){
    foreach my $classification (@{$user->get_classifications_of_topic({ topicid => $topic_ref->{id}, type => 'rvk'})}){
        $rvk_topic_mapping_ref->{$classification} = $topic_ref->{id};
    }
    foreach my $classification (@{$user->get_classifications_of_topic({ topicid => $topic_ref->{id}, type => 'bk'})}){
        $bk_topic_mapping_ref->{$classification} = $topic_ref->{id};
    }
}

my %classificationid2topicid = ();

open(CLASSIFICATION,"zcat meta.classification.gz|");

while (<CLASSIFICATION>){
    my $classification_ref = decode_json $_;
    
    my $classification = $classification_ref->{'fields'}{'0800'}[0]{content};

    if ($classification =~/^([A-Z][A-Z]) \d+/){ # RVK
        if (defined $rvk_topic_mapping_ref->{$1}){
            $classificationid2topicid{$classification_ref->{id}} = $rvk_topic_mapping_ref->{$1};
        }
    }
}

close(CLASSIFICATION);

while (<>){
    my $title_ref = decode_json $_;

    my @topicids = ();
    
    if (defined $title_ref->{'fields'}{'0700'}){
        foreach my $classification_ref (@{$title_ref->{'fields'}{'0700'}}){
            my $classificationid = $classification_ref->{id};

            if ($classificationid2topicid{$classification_ref->{id}}){
                push @topicids, $classificationid2topicid{$classification_ref->{id}};
            }
        }
    }

    my $mult = 1;
    foreach my $topicid (@topicids){
        push @{$title_ref->{'fields'}{'4102'}}, {
            subfield => '',
            content  => $topicid,
            mult     => $mult++,
        }
    }

    print encode_json $title_ref, "\n";
}

