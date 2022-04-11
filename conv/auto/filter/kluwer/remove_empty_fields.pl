#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    foreach my $field (keys %{$title_ref->{fields}}) {
	my $remove_field = 0;
	foreach my $item_ref (@{$title_ref->{fields}{$field}}) {
	    if ($item_ref->{content} =~m/^\s+$/){
		$remove_field = 1;
	    }
	}
	if ($remove_field){
	    $title_ref->{fields}{$field} = [];
	    delete $title_ref->{fields}{$field};
	}
    }

    print encode_json $title_ref, "\n";
}
