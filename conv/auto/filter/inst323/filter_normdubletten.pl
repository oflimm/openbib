#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    {
        my $normdaten_ref = [];

        my $have_id_ref   = {};
        if (defined $title_ref->{fields}{'0700'}){
            foreach my $field_ref (@{$title_ref->{fields}{'0700'}}){
                if (!defined $have_id_ref->{$field_ref->{id}}){
                    push @$normdaten_ref, $field_ref;
                    $have_id_ref->{$field_ref->{id}} = 1;
                }
            }
            $title_ref->{fields}{'0700'} = $normdaten_ref;
        }
    }
    
    print encode_json $title_ref, "\n";
}
