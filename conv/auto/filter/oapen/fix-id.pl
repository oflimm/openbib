#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $fields_ref = $title_ref->{fields};

    foreach my $thisfield_ref (@{$fields_ref}){
	if (defined $thisfield_ref->{'001'} && $thisfield_ref->{'001'}){
	    $thisfield_ref->{'001'} =~s{https://library.oapen.org/handle/}{};
	    $thisfield_ref->{'001'} =~s{/}{:}g;
	}
    }

    print encode_json $title_ref, "\n";
}
