#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $is_digital = 0;

    # DOI gesetzt
    if (defined $title_ref->{fields}{'0552'}){
        foreach my $item (@{$title_ref->{fields}{'0552'}}){
            if ($item->{content} =~m/doi/){
                $is_digital = 1;
            }        
        }
    }

    my $mtidx=1;

    $title_ref->{fields}{'4410'} = [
	{
	    mult     => $mtidx++,
	    subfield => '',
	    content  => "Aufsatz",
	},
	];
    
    if ($is_digital){
	if (@{$title_ref->{fields}{'4400'}}){
	    push @{$title_ref->{fields}{'4400'}}, {
                mult     => 1,
                subfield => '',
                content  => "online",
            };
	}
	else {
	    $title_ref->{fields}{'4400'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => "online",
		},
		];
        }


	if (@{$title_ref->{fields}{'4410'}}){
	    push @{$title_ref->{fields}{'4410'}}, {
                mult     => $mtidx++,
                subfield => '',
                content  => "Digital",
            };
	}
    }
   
    print encode_json $title_ref, "\n";
}
