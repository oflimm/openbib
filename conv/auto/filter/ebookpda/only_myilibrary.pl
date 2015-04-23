#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $urls_ref = [];
    
    if (defined $title_ref->{fields}{'0662'}){
        foreach my $field_ref (@{$title_ref->{fields}{'0662'}}){
            if ($field_ref->{content} =~m/myilibrary/){
                push @$urls_ref, $field_ref;
            }
        }
        $title_ref->{fields}{'0662'} = $urls_ref;
    }

    
    print encode_json $title_ref, "\n";
}
