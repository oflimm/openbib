#!/usr/bin/perl

use File::Slurp;
use JSON::XS;


my @files = glob ("*.json");

foreach my $file (@files){
    my $input = read_file($file);

    my $data_ref = decode_json $input;

    print encode_json $data_ref, "\n";    
}
    
