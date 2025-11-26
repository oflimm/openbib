#!/usr/bin/perl

use JSON::XS;
use List::MoreUtils qw/ uniq /;

while (<>){
    my $title_ref = decode_json $_;

    # Doppelte Feldinhalte entfernen
    my $have_content_ref = {};
    my $mult_ref = {};
    foreach my $field (keys %{$title_ref->{fields}}){
	my $new_field = [];
	foreach my $item_ref (@{$title_ref->{fields}{$field}}){
	    next if (defined $have_content_ref->{$field}{$item_ref->{content}});
	    push @{$new_field}, $item_ref;
	    $have_content_ref->{$field}{$item_ref->{content}} = 1;
	}
	$title_ref->{fields}{$field} = $new_field;
    }

    # Identifier erkennen und verschieben

    if (defined $title_ref->{fields}{'0540'}){
	my $new_field = [];
	foreach my $item_ref (@{$title_ref->{fields}{'0540'}}){
	    if ($item_ref->{content} =~m/^http/){
		my $mult = ++$multcount_ref->{'0662'};
		push @{$title_ref->{fields}{'0662'}}, {
		    content => $item_ref->{content},
		    mult => $mult,
		    subfield => 'g',
		};
		push @{$title_ref->{fields}{'0663'}}, {
		    content => 'Volltext',
		    mult => $mult,
		    subfield => '',
		};		
		push @{$title_ref->{fields}{'4120'}}, {
		    content => $item_ref->{content},
		    mult => $mult,
		    subfield => 'g',
		};
	    }
	    elsif ($item_ref->{content} =~m/10\.18716/){ # DOI
		my $mult = ++$multcount_ref->{'0552'};		
		push @{$title_ref->{fields}{'0552'}}, {
		    content => $item_ref->{content},
		    mult => $mult,
		    subfield => '',
		};
	    }
	    elsif ($item_ref->{content} =~m/^urn/){ # URN
		my $mult = ++$multcount_ref->{'0552'};		
		push @{$title_ref->{fields}{'0552'}}, {
		    content => $item_ref->{content},
		    mult => 1,
		    subfield => '',
		};
	    }
	    # 13-Stellige ISBN
	    elsif (/\d-*\d-*\d-*\d-*\d-*\d-*\d-*\d-*\d-*\d-*\d-*\d-*[0-9xX]/){
		push @$new_field, $item_ref;
	    }
	    # 10-Stellige ISBN	    
	    elsif (/\d-*\d-*\d-*\d-*\d-*\d-*\d-*\d-*\d-*[0-9xX]/){
		push @$new_field, $item_ref;
	    }
	    # ISSN
	    elsif (/\d\d\d\d-*\d\d\d[0-9xX]/){
		my $mult = ++$multcount_ref->{'0543'};
		push @{$title_ref->{fields}{'0543'}}, {
		    content => $item_ref->{content},
		    mult => $mult,
		    subfield => '',
		};
	    }
	}

	# Wenn ISBN, dann diese setzen
	if (@$new_field){
	    $title_ref->{fields}{'0540'} = $new_field;
	}
	# Sonst ISBN-Feld entfernen
	else {
	    $title_ref->{fields}{'0540'} = [];
	    delete $title_ref->{fields}{'0540'};
	}
    }
    
    print encode_json $title_ref, "\n";
}
