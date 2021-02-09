#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $is_digital = 0;
    
    if (defined $title_ref->{fields}{'0662'}){
        foreach my $item_ref (@{$title_ref->{fields}{'0662'}}){
            if ($item_ref->{content}=~m/digitalis/ || $item_ref->{content}=~m/permalink/){
		$is_digital = 1;
	    }
	}
    }

    if ($is_digital){
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
    }
    
    print encode_json $title_ref, "\n";
}
