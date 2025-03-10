#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use YAML;

my $path="/alma/export";

my @iz_files = <$path/ubkfull_*>;
my @electronic_iz_nz_files = <$path/ubkelectronicfull_*>;

my @resultfiles = ();

my %dates = ();

foreach my $file (@iz_files){
    my ($date) = $file =~m{ubkfull_(\d\d\d\d\d\d\d\d)};
    $dates{$date} = 1 if ($date);
}

foreach my $file (@electronic_iz_nz_files){
    my ($date) = $file =~m{ubkelectronicfull_(\d\d\d\d\d\d\d\d)};
    $dates{$date} = 1 if ($date);
}

foreach my $date (reverse sort keys %dates){
    my @iz_by_date = grep {/ubkfull_$date/} @iz_files;
    my @electronic_iz_nz_by_date = grep {/ubkelectronicfull_$date/} @electronic_iz_nz_files;

    push @resultfiles, @iz_by_date if (@iz_by_date);
    push @resultfiles, @electronic_iz_nz_by_date if (@electronic_iz_nz_by_date);
}

print join ' ',@resultfiles;
