#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

my $is_blacklisted_ref = {
    '38'  => 1,
    '123' => 1,
    '132' => 1,
    '418' => 1,
    '420' => 1,
    '422' => 1,
    '423' => 1,
    '426' => 1,
    '427' => 1,
    '429' => 1,
    '438' => 1,
    '448' => 1,
    '450' => 1,
    '459' => 1,
};

my $title_with_valid_holdings_ref = {}; 

open(HOLDING,"meta.holding");
open(HOLDINGOUT,">meta.holding.tmp");

while (<HOLDING>){
    my $holding_ref = decode_json $_;

    my $titleid = $holding_ref->{fields}{'0004'}[0]{content};

    my $location = $holding_ref->{fields}{'3330'}[0]{content};
    
    next unless ($titleid);
    next unless ($location);

    next if (defined $is_blacklisted_ref->{$location} && $is_blacklisted_ref->{$location});
 
    $title_with_valid_holdings_ref->{$titleid} = 1;
   
    print HOLDINGOUT $_;
}

close(HOLDINGOUT);
close(HOLDING);

open(TITLE,"meta.title");
open(TITLEOUT,">meta.title.tmp");

while (<TITLE>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    next unless ($titleid);

    next unless ($title_with_valid_holdings_ref->{$titleid});

    print TITLEOUT $_;
}

close(TITLEOUT);
close(TITLE);
