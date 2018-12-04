#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;

print STDERR "### schnuetgen RDA-Felder splitten und neu zuordnen\n";

while (<>){
    my $title_ref = decode_json $_;

    # 419a -> 410, 419b -> 412
    if (defined $title_ref->{fields}{'0419'}){
	foreach my $subfield_ref (@{$title_ref->{fields}{'0419'}}){
	    if ($subfield_ref->{subfield} eq "a"){
		push @{$title_ref->{fields}{'0410'}},$subfield_ref;

	    }
	    elsif ($subfield_ref->{subfield} eq "b"){
		push @{$title_ref->{fields}{'0412'}},$subfield_ref;
	    }
	}
    }
    
    print encode_json $title_ref, "\n";
}
