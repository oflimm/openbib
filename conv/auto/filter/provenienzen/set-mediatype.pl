#!/usr/bin/perl

use JSON::XS;

use utf8;

my @tpro = (
    'Autogramm',
    'Einband',
    'Einlage',
    'Etikett',
    'Exlibris',
    'gedr. Besitzvermerk',
    'Herkunft',
    'hs. Besitzvermerk',
    'Indiz',
    'Initiale',
    'Monogramm',
    'Notiz',
    'NS-Raubgut',
    'Prämienband',
    'Restitution',
    'Restitutionsexemplar',
    'Stempel',
    'Supralibros',
    'Widmung',
    );

while (<>){
    my $title_ref = decode_json $_;

    my $type_ref = [];
    my $have_merkmal_ref = {};
    foreach my $item_ref (@{$title_ref->{'fields'}{'4310'}}){
	foreach my $merkmal (@tpro){
	    next if (defined $have_merkmal_ref->{$merkmal});
	    if ($item_ref->{content} =~m/$merkmal/){
		if (!defined $have_merkmal_ref->{$merkmal}){
		    push @{$type_ref}, {
			mult     => $item_ref->{content},
			subfield => 'm',
			content  => $merkmal,
		    };
		    $have_merkmal_ref->{$merkmal} = 1;
		}
	    }
	}
    }

    if (@$type_ref){
	push @{$title_ref->{fields}{'4310'}}, @{$type_ref};
    }
    
    print encode_json $title_ref, "\n";
}
