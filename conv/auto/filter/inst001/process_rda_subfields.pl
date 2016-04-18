#!/usr/bin/perl

use utf8;
use JSON::XS;

while (<>){
    my $record_ref = decode_json $_;

    foreach my $field (keys %{$record_ref->{fields}}){
        next if ($field eq "0671");
        my $new_field_ref = [];
        foreach my $field_ref (@{$record_ref->{fields}{$field}}){
            if ($field_ref->{content} =~m/¬\$[a-zA-Z0-9] /){
                my $processed_field_ref = process_subfields({content => $field_ref->{content}, mult => $field_ref->{mult}});
                push @$new_field_ref, @$processed_field_ref if (@$processed_field_ref);
            }
            else {
                push @$new_field_ref, $field_ref;
            }
        }
        $record_ref->{fields}{$field} = $new_field_ref;
    }

    print encode_json $record_ref,"\n";
    
}

sub process_subfields {
    my ($arg_ref) = @_;

    my $content = $arg_ref->{content} || "";
    my $mult    = $arg_ref->{mult}    || "";

    my $new_field_ref = [];

    # Leading elements
    while ($content =~m/¬\$([a-zA-Z0-9]) (.+?)(?=¬\$)/g){
        push @$new_field_ref, {
            mult     => $mult,
            content  => $2,
            subfield => $1,
        };
    }

    # last element
    $content=~m/(?<!¬\$).+¬\$([a-zA-Z0-9]) (.+?)$/;
    push @$new_field_ref, {
        mult     => $mult,
        content  => $2,
        subfield => $1,
    };

    
    return $new_field_ref;
}
