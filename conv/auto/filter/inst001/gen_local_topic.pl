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

open(CLASSIFICATION,"meta.classification");

while (<CLASSIFICATION>){
    my $classification_ref = decode_json $_;
    
    my $classification = $classification_ref->{'fields'}{'0800'}[0]{content};

    if ($classification =~/^(\d\d)\.\d\d$/){ # BK
        if (defined $bk_topic_mapping_ref->{$1}){
            $classificationid2topicid{$classification_ref->{id}} = $bk_topic_mapping_ref->{$1};
        }
    }
    else { # Alt-Notationen
        my $topicid = altnot2topicid($classification);

        if ($topicid){
            $classificationid2topicid{$classification_ref->{id}} = $topicid;
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

    if (defined $title_ref->{'fields'}{'1701'}){
        foreach my $item_ref (@{$title_ref->{'fields'}{'1701'}}){
            my $classification = $item_ref->{content};

            if ($classification =~/^([A-Z][A-Z]) \d+/){ # RVK
                my $rvk = $1;
                if (defined $rvk_topic_mapping_ref->{$rvk}){
                    push @topicids, $rvk_topic_mapping_ref->{$rvk};
                }
            }
        }
    }
    
    my $mult = 1;
    my $topics_seen_ref = {};
    foreach my $topicid (@topicids){        
        push @{$title_ref->{'fields'}{'4102'}}, {
            subfield => '',
            content  => $topicid,
            mult     => $mult++,
        } unless (defined $topics_seen_ref->{$topicid});
        $topics_seen_ref->{$topicid} = 1;
    }

    print encode_json $title_ref, "\n";
}

sub altnot2topicid {
    my $content = shift;

    my $topicid;

    if ($content =~/^A2[qrstu]/){ # Information und Dokumentation
        return 15;
    }
    
    if ($content =~/^A1[0-1]$|^A1[0-1][.a-zA-Z]/){ # Wissenschaft und Kultur Allgemein
        return 18;
    }

    if ($content =~/^A1[7-9]$|^1[7-9][.a-zA-Z]/){ # Information und Dokumentation
        return 15;
    }
    
    if ($content =~/^A[23][0-9]$|^A[23][0-9][.a-zA-Z]|^HA14$|^HA14[.a-zA-Z]/){ # Kommunikationswissenschaft
        return 15;
    }

    if ($content =~/^A4[0-1]$|^A4[0-1][.a-zA-Z]/){ # Kommunikationswissenschaft
        return 15;
    }

    if ($content =~/^A[1-3]$|^A[1-3][.a-zA-Z]/){ # Allgemeines
        return 18;
    }

    if ($content =~/^A[4-9]$|^A[4-9][.a-zA-Z]/){ # Wissenschaft und Kultur Allgemein
        return 18;
    }

    if ($content =~/^Ph\d/){ # Philosophie
        return 10;
    }

    if ($content =~/^Th\d|^RG\d/){ # Theologie
        return 16;
    }

    if ($content =~/^G49|^G50/){ # 
        return 20;
    }
    
    if ($content =~/^G\d/){ # Geschichte 
        return 2;
    }

    if ($content =~/^L[ABDEFGCHJKLMNOPQ]\d/){ # diverse Sprach und Literaturwissenschaft 
        return 7;
    }

    if ($content =~/^Ku\d/){ # Kunstwissenschaft
        return 13;
    }

    if ($content =~/^KTh\d/){ # Theater/Film 
        return 14;
    }

    if ($content =~/^KM\d/){ # Musik 
        return 14;
    }

    if ($content =~/^T[1-9]$|^T[1-9][.a-zA-Z]|^T10$|^T10[.a-zA-Z]/){ # Naturwissenschaften allgemein 
        return 19;
    }

    if ($content =~/^T1[1-9]$|^T1[1-9][.a-zA-Z]|^T2[0-7]$|^T2[0-7][.a-zA-Z]/){ # Mathematik
        return 4;
    }
        
    if ($content =~/^T3[0-9]$|^T3[0-9][.a-zA-Z]|^4[0-6]$|^4[0-6][.a-zA-Z]/){ # Physik
        return 1;
    }

    if ($content =~/^T4[89]$|^T4[89][.a-zA-Z]|^T5[0-9]$|^T5[0-9][.a-zA-Z]|^T6[0-6]$|^T6[0-6][.a-zA-Z]/){ # Chemie 
        return 1;
    }

    if ($content =~/^E\d|^T7[4-9]$|^T7[4-9][.a-zA-Z]|^T8[0-9]$|^T8[0-9][.a-zA-Z]|^T90$|^T90[.a-zA-Z]/){ # Geowissenschaften 
        return 19;
    }

    if ($content =~/^T29$|^T29[.a-zA-Z]/){ # Astronomie 
        return 1;
    }

    if ($content =~/^T166$|^T166[.a-zA-Z]/){ # Tiermedizin 
        return 6;
    }
    
    if ($content =~/^T9[1-9]$|^T9[1-9][.a-zA-Z]|^T1[0-5][0-9]$|^T1[0-5][0-9][.a-zA-Z]|^T16[0-9]$|^T16[0-9][.a-zA-Z]/){ # Biologie 
        return 1;
    }

    if ($content =~/^HN\d/){ # Umweltforschung, Umweltschutz 
        return 19;
    }

    if ($content =~/^L\d/){ # Land und Forstwirtschaft 
        return 5;
    }

    if ($content =~/^H31/){ # Hauswirtschaft
        return 5;
    }
    
    if ($content =~/^N\d|^U1$|^U1[.a-zA-Z]|^U1[1-35-7]$|^U1[1-35-7][.a-zA-Z]|^U2[01]$|^U2[01][.a-zA-Z]/){ # Diverse Technik 
        return 9;
    }

    if ($content =~/^D\d/){ # Informatik
        return 15;
    }
    

    if ($content =~/^H[ABCDEFLOA]\d/){ # Diverse Sozialwissenschaften 
        return 8;
    }

    if ($content =~/^E\d/){ # Geographie 
        return 19;
    }

    if ($content =~/^HP\d/){ # Raumordnung im Staedtebau 
        return 9;
    }

    if ($content =~/^Sp\d/){ # Sport, Freizeit, Erholung
        return 17;
    }

    if ($content =~/^Ps\d/){ # Psychologie 
        return 11;
    }

    if ($content =~/^HH51.9/){ # Sozialpaedagogik 
        return 8;
    }

    if ($content =~/^Pa8/){ # Bildungswesen 
        return 12;
    }

    if ($content =~/^Pa\d/){ # Paedagogik 
        return 12;
    }

    if ($content =~/^[HJMPORSQ]\d/){ # Diverse Wirtschaftswissenschaften
        return 5;
    }

    if ($content =~/^F\d|^FG\d/){ # Recht 
        return 3;
    }

    if ($content =~/^Pol\d/){ # Politologie 
        return 8;
    }

    if ($content =~/^KW\d/){ # Archaeologie 
        return 2;
    }

    if ($content =~/^Rh\d/){ # Rheinisches 
        return 2;
    }
    
    return $topicid;
}
