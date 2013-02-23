#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    # 'Normale' Schlagworte ignorieren
    foreach my $field (keys %$title_ref){
        if ($field =~/^09[01234][27]/){
            delete $title_ref->{$field};
        }
    }

    # 'Eigene' Schlagworte stattdessen verwenden
    foreach my $field (keys %$title_ref){
        if ($field =~/^19[01234][27]/){
            $new_field = '0'.substr($field,1,3);

            $title_ref->{$new_field} = $title_ref->{$field};
            
            delete $title_ref->{$field};
        }
    }

    print encode_json $title_ref, "\n";
}
