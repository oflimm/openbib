#!/usr/bin/perl

use JSON::XS;
use POSIX qw(strftime);

my $thisyear = strftime "%Y", localtime;

my $min_copyrighted_year_range = 100; # festgelegte Urheberrechtsgrenze von 100 Jahren

while (<>){
    my $title_ref = decode_json $_;

    if (defined $title_ref->{fields}{'0425'} && $title_ref->{fields}{'0425'}[0]{content}=~m/(\d\d\d\d)/ ){
        my $year = $1;

        if ($thisyear - $year <= $min_copyrighted_year_range ){ 
            next;
        }
    }
    elsif (defined $title_ref->{fields}{'0424'} && $title_ref->{fields}{'0424'}[0]{content}=~m/(\d\d\d\d)/ ){
        my $year = $1;

        if ($thisyear - $year <= $min_copyrighted_year_range ){ 
            next;
        }
    }

    print encode_json $title_ref, "\n";
}
