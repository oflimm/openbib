#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    my $prt_mult = 1;
    
    foreach my $field ('0700','0710'){
	my $field_ref = {};
        foreach my $item (@{$title_ref->{fields}{$field}}){
	    $field_ref->{$item->{mult}}{$item->{subfield}} = $item->{content};
	}

	foreach my $mult (keys %{$field_ref}){
	    next unless ($field_ref->{$mult}{'4'} =~m/prt/ || $field_ref->{$mult}{'4'} =~m/pbl/);

	    push @{$title_ref->{fields}{'1199'}}, {
		mult     => $prt_mult++,
		subfield => 'a',
		content  => $field_ref->{$mult}{'a'},
	    };
	}
    }
   
    print encode_json $title_ref, "\n";
}

