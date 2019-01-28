#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $id = $title_ref->{id};

    if (defined $title_ref->{fields}{'0662'}){
        foreach my $item_ref (@{$title_ref->{fields}{'0662'}}){
            if ($item_ref->{content}=~m/digitalis/){
                $item_ref->{content}="http://www.ub.uni-koeln.de/permalink/db/digitalis/id/$id";
            }
        }
    }

    print encode_json $title_ref, "\n";
}
