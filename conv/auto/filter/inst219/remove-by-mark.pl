#!/usr/bin/perl

use strict;
use warnings;

use JSON::XS;
use YAML;

open(HOLDING,"cat meta.holding|");
open(HOLDINGOUT," > meta.holding.tmp");

my $titleids_with_mark_ref = {};

while (<HOLDING>){
    my $holding_ref = decode_json $_;

    my $titleid = $holding_ref->{fields}{'0004'}[0]{content};

    if (defined $holding_ref->{fields}{'0014'} && $holding_ref->{fields}{'0014'}[0]{content} =~/^Bu/){
        $titleids_with_mark_ref->{$titleid} = 1;
        next;
    }

    print HOLDINGOUT encode_json($holding_ref),"\n";
}

close(HOLDING);

open(HOLDING,"cat meta.holding|");

my $titleids_with_mark_and_others_ref = {};
    
while (<HOLDING>){
    my $holding_ref = decode_json $_;

    my $titleid = $holding_ref->{fields}{'0004'}[0]{content};

    if (defined $titleids_with_mark_ref->{$titleid} && defined $holding_ref->{fields}{'0014'} && $holding_ref->{fields}{'0014'}[0]{content} !~/^Bu/){
        $titleids_with_mark_and_others_ref->{$titleid} = 1;
    }
}

close(HOLDING);

open(TITLE,"cat meta.title|");
open(TITLEOUT,"> meta.title.tmp");

while (<TITLE>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    if (defined $titleids_with_mark_ref->{$titleid} && !defined $titleids_with_mark_and_others_ref->{$titleid}){
        next;
    }

    print TITLEOUT encode_json($title_ref),"\n";
}

close(TITLEOUT);

system("mv -f meta.title.tmp meta.title ; mv -f meta.holding.tmp meta.holding");

print "Titel-IDs mit Signatur: ".(scalar keys %{$titleids_with_mark_ref})."\n";

#print YAML::Dump($titleids_with_mark_ref),"\n";

#print "Titel-IDs mit FBV, aber auch anderem Bestand: ".(scalar keys %{$titleids_with_mark_and_others_ref})."\n";

#print YAML::Dump($titleids_with_mark_and_others_ref),"\n";

