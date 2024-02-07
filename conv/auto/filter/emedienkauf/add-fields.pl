#!/usr/bin/perl

use JSON::XS;
use List::MoreUtils qw/ uniq /;

while (<>){
    my $title_ref = decode_json $_;

    my @rvks = ();
    
    # RVK aus 084$a in 4101 vereinheitlichen
    
    # Auswertung von 084$
    if (defined $title_ref->{fields}{'0084'}){
	my $cln_ref = {};
        foreach my $item (@{$title_ref->{fields}{'0084'}}){
	    $cln_ref->{$item->{mult}}{$item->{subfield}} = $item->{content};
	}
	
	foreach my $mult (keys %{$cln_ref}){
	    next unless (defined $cln_ref->{$mult}{'2'} && defined $cln_ref->{$mult}{'a'});
	    if ($cln_ref->{$mult}{'2'} eq "rvk"){
		push @rvks, $cln_ref->{$mult}{'a'};
	    }
	}
    }
        
    if (@rvks){
	my $rvk_mult = 1;

	foreach my $rvk (uniq @rvks){
	    push @{$title_ref->{fields}{'4101'}}, {
		mult     => $rvk_mult++,
		subfield => '',
		content  => $rvk,
	    };
	}
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
    ];

    print encode_json $title_ref, "\n";
}
