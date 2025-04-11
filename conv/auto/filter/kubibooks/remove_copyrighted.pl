#!/usr/bin/perl

use JSON::XS;
use POSIX qw(strftime);

my $thisyear = strftime "%Y", localtime;

my $min_copyrighted_year_range = 100; # festgelegte Urheberrechtsgrenze von 100 Jahren

while (<>){
    my $title_ref = decode_json $_;

    my $ignore_title = 0;
    if (defined $title_ref->{fields}{'1008'}){
	foreach my $item_ref (@{$title_ref->{fields}{'1008'}}){
	    if ($item_ref->{subfield} eq 'a'){
		my $year = $item_ref->{content};
		
		if ($thisyear - $year <= $min_copyrighted_year_range ){ 
		    $ignore_title = 1;
		}
	    }
	}
    }
			      
    next if ($ignore_title);
    
    print encode_json $title_ref, "\n";
}
