#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};

print STDERR "### inst001 Markierung diskriminierender Schlagworte\n";

my $discriminatory_terms_by_gndid_ref = {};

open(TERMS, "/opt/openbib/autoconv/filter/inst001/discriminatory_terms.json");
while(my $item=<TERMS>){
    my $term_ref = decode_json $item;

    push @{$discriminatory_terms_by_gndid_ref->{$term_ref->{id}}}, $term_ref->{content};
}

close(TERMS);

while (<>){
    my $subject_ref = decode_json $_;

    my %subjects_to_flag = ();
    foreach my $gndid_ref (@{$subject_ref->{fields}{'0010'}}){
        if ($discriminatory_terms_by_gndid_ref->{$gndid_ref->{content}}){
	    foreach my $subject (@{$discriminatory_terms_by_gndid_ref->{$gndid_ref->{content}}}){
		$subjects_to_flag{$subject} = 1;
	    }
        }
    }

    if (keys %subjects_to_flag){
	foreach my $synonym_ref (@{$subject_ref->{fields}{'0830'}}){
	    if ($subjects_to_flag{$synonym_ref->{content}}){
		$synonym_ref->{content}.=" (Diskriminierender Begriff)";
	    }
        }
    }
    

    print encode_json $subject_ref, "\n";
}
