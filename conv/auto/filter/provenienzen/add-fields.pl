#!/usr/bin/perl

use JSON::XS;

my @tpro = (
    'Autogramm',
    'Einlage',
    'Exlibris',
    'gedr. Besitzvermerk',
    'Herkunft',
    'hs. Besitzvermerk',
    'Stempel',
    'Supralibros',
    'Widmung',
    );

while (<>){
    my $title_ref = decode_json $_;

    my $type_ref = [];
    my $mult = 1;
    my $have_merkmal_ref = {};
    foreach my $item_ref (@{$title_ref->{'fields'}{'4310'}}){
	foreach my $merkmal (@tpro){
	    next if (defined $have_merkmal_ref->{$merkmal});
	    if ($item_ref->{content} =~m/$merkmal/){
		if (!defined $have_merkmal_ref->{$merkmal}){
		    push @{$type_ref}, {
			mult     => $mult,
			subfield => '',
			content  => $merkmal,
		    };
		    $mult++;
		    $have_merkmal_ref->{$merkmal} = 1;
		}
	    }
	}
    }

    if (@$type_ref){
	$title_ref->{fields}{'4410'} = $type_ref;
    }
    
    print encode_json $title_ref, "\n";
}
