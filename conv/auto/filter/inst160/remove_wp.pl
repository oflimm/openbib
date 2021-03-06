#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    if (defined $title_ref->{fields}{'0016'}){
        my $ignore = 0;
        foreach my $field_ref (@{$title_ref->{fields}{'0016'}}){
            if ($field_ref->{content} =~m/^WP-Bibliothek/){
                $ignore = 1;
            }
        }
        next if ($ignore);
    }
    
    print encode_json $title_ref, "\n";
}
