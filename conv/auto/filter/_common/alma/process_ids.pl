#!/usr/bin/perl

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;
    
    my $fields_ref = $record_ref->{fields};

    my $mult_ref = {};

    $mult_ref->{'1001'} = 1;

    if (defined $fields_ref->{'0035'}){
	foreach my $item_ref (@{$fields_ref->{'0035'}}){
	    if ($item_ref->{subfield} eq "a"){
		if ($item_ref->{content} =~m/^\(DE-600\)(.+?)$/){
		    my $zdbid = $1;

		    my $mult    = $mult_ref->{'1001'}++;

		    push @{$record_ref->{fields}{'1001'}}, {
			mult     => $mult,
			subfield => 'z',
			content  => $zdbid,
		    };
		}
		elsif ($item_ref->{content} =~m/^\(DE-599\)ZDB(.+?)$/){
		    my $zdbid = $1;

		    my $mult    = $mult_ref->{'1001'}++;

		    push @{$record_ref->{fields}{'1001'}}, {
			mult     => $mult,
			subfield => 'z',
			content  => $zdbid,
		    };
		}
		elsif ($item_ref->{content} =~m/^\(EXLCZ\)(.+?)$/ || $item_ref->{content} =~m/^\(EXLNZ-49HBZ_NETWORK\)(.+?)$/ || $item_ref->{content} =~m/^\(DE-605\)(.+?)$/){
		    my $hbzid = $1;

		    my $mult    = $mult_ref->{'1001'}++;
		    
		    push @{$record_ref->{fields}{'1001'}}, {
			mult     => $mult,
			subfield => 'h',
			content  => $hbzid,
		    };
		}		    
	    }
	}
    }

    if (defined $fields_ref->{'0981'}){
	foreach my $item_ref (@{$fields_ref->{'0981'}}){
	    if ($item_ref->{subfield} eq "a"){		
		if ($item_ref->{content} =~m/^\(DE-38\)(.+?)$/){
		    my $usboldid = $1;
		    
		    my $mult    = $mult_ref->{'1001'}++;
		    
		    push @{$record_ref->{fields}{'1001'}}, {
			mult     => $mult,
			subfield => 'u',
			content  => $usboldid,
		    };
		}
	    }
	}
    }

    print encode_json $record_ref, "\n";
}
