#!/usr/bin/perl

use JSON::XS;
use List::MoreUtils qw/ uniq /;

while (<>){
    my $title_ref = decode_json $_;

    # Anreichern von 1008 $a mit vierstelliger Jahreszahl aus 260/264 $c, wenn 1008 $a nicht mit Jahreszahl besetzt.

    my $year_from_26x = "";

    if (defined $title_ref->{fields}{'0260'}){
	foreach my $item_ref (@{$title_ref->{fields}{'0260'}}){
	    if ($item_ref->{subfield} eq 'c' && $item_ref->{content} =~m/(\d\d\d\d)/){
		$year_from_26x = $1;
		last;
	    }
	}
    }

    if (!$year_from_26x && defined $title_ref->{fields}{'0264'}){
	foreach my $item_ref (@{$title_ref->{fields}{'0264'}}){
	    if ($item_ref->{subfield} eq 'c' && $item_ref->{content} =~m/(\d\d\d\d)/){
		$year_from_26x = $1;
		last;
	    }
	}
    }

    my $field_1008_has_a = 0;
    
    if ($year_from_26x && defined $title_ref->{fields}{'1008'}){
	foreach my $item_ref (@{$title_ref->{fields}{'1008'}}){
	    if ($item_ref->{subfield} eq 'a'){
		$field_1008_has_a = 1;
		if ($item_ref->{content} !~m/\d\d\d\d/){
		    $item_ref->{content} = $year_from_26x;
		}
	    }
	}
    }

    if ($year_from_26x && (!$field_1008_has_a || !defined $title_ref->{fields}{'1008'})){
	push @{$title_ref->{fields}{'1008'}}, {
	    mult => 1,
	    subfield => 'a',
	    content => $year_from_26x,	    
	};
    }

    ### Medientyp Digital/online zusaetzlich vergeben    
    $title_ref->{fields}{'4400'} = [
        {
            mult     => 1,
            subfield => '',
            content  => "online",
        },
    ];

    $title_ref->{fields}{'4410'} = [
        {
            mult     => 1,
            subfield => '',
            content  => "Digital",
        },
        {
            mult     => 2,
            subfield => '',
            content  => "Open Educational Resource",
        },
    ];

    print encode_json $title_ref, "\n";
}
