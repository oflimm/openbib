#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $id = $title_ref->{id};

    if (defined $title_ref->{fields}{'4120'}){
        foreach my $item_ref (@{$title_ref->{fields}{'4120'}}){
            $item_ref->{content}=~s{http://www.ub.uni-koeln.de}{https://services.ub.uni-koeln.de};
        }
    }

    if (defined $title_ref->{fields}{'2662'}){
        foreach my $item_ref (@{$title_ref->{fields}{'2662'}}){
            $item_ref->{content}=~s{http://www.ub.uni-koeln.de}{https://services.ub.uni-koeln.de};
        }
    }

    print encode_json $title_ref, "\n";
}

