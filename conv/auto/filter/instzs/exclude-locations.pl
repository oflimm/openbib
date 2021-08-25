#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

my $is_blacklisted_ref = {
    '006' => 1,    
    '007' => 1,
    '102' => 1,
    '103' => 1,
    '106' => 1,
    '108' => 1,
    '110' => 1,
    '112' => 1,
    '113' => 1,
    '117' => 1,
    '119' => 1,
    '123' => 1,
    '125' => 1,
    '128' => 1,
    '132' => 1,
    '134' => 1,
    '136' => 1,
    '146' => 1,
    '156' => 1,
    '157' => 1,
    '166' => 1,
    '201' => 1,
    '306' => 1,
    '311' => 1,
    '312' => 1,
    '313' => 1,
    '314' => 1,
    '315' => 1,
    '317' => 1,
    '323' => 1,
    '325' => 1,
    '38'  => 1,
    '401' => 1,
    '404' => 1,
    '405' => 1,
    '406' => 1,
    '407' => 1,
    '409' => 1,
    '410' => 1,
    '411' => 1,
    '413' => 1,
    '414' => 1,
    '416' => 1,
    '418' => 1,
    '419' => 1,
    '420' => 1,
    '421' => 1,
    '422' => 1,
    '423' => 1,
    '424' => 1,
    '425' => 1,
    '426' => 1,
    '427' => 1,
    '428' => 1,
    '429' => 1,
    '430' => 1,
    '431' => 1,
    '432' => 1,
    '434' => 1,
    '437' => 1,
    '438' => 1,
    '444' => 1,
    '445' => 1,
    '448' => 1,
    '450' => 1,
    '459' => 1,
    '460' => 1,
    '461' => 1,
    '462' => 1,
    '464' => 1,
    '468' => 1,
    '502' => 1,
    '514' => 1,
    '526' => 1,
    '622' => 1,
    '623' => 1,
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
