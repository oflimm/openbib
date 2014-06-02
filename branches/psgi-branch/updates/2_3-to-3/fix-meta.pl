#!/usr/bin/perl

use JSON::XS;
use Encode qw/decode_utf8/;

binmode(\*STDOUT,":raw");

while (<>){
    
    my $item_ref = decode_json decode_utf8($_);
    
    $item_ref->{fields} = {};

    foreach my $field (keys %$item_ref){
	next if ($field eq "id" || $field eq "fields");

	$item_ref->{fields}{$field} = $item_ref->{$field};
	delete $item_ref->{$field};
    }
   
    print encode_json $item_ref, "\n";
}
