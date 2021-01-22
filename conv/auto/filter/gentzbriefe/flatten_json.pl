#!/usr/bin/perl

use File::Slurp;
use JSON::XS;


my @files = glob ("*.json");

foreach my $file (@files){
    my $input = read_file($file);

    my $data_ref = decode_json $input;

    foreach my $item_ref (@{$data_ref->{objects}}){
	print encode_json $item_ref, "\n";
    }
}
    
