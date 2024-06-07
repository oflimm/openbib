#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;

#open(CHANGED,">./changed.json");

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

    my $titleid = $title_ref->{id};

    # Provenienzen mit TPRO anreichern

    if (defined $title_ref->{'fields'}{'4310'}){
	my $type_ref = [];
	foreach my $item_ref (@{$title_ref->{'fields'}{'4310'}}){
	    foreach my $merkmal (@tpro){
		if ($item_ref->{content} =~m/$merkmal/){
		    push @{$type_ref}, {
			mult     => $item_ref->{mult},
			subfield => 'm',
			content  => $merkmal,
		    };
		}
	    }
	}
	
	if (@$type_ref){
	    push @{$title_ref->{fields}{'4310'}}, @{$type_ref};
	}
    }
    print encode_json $title_ref, "\n";
}
