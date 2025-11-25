#!/usr/bin/perl

use JSON::XS;
use List::MoreUtils qw/ uniq /;

while (<>){
    my $title_ref = decode_json $_;

    # Doppelte Feldinhalte entfernen
    my $have_content_ref = {};
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
		push @{$title_ref->{fields}{'0662'}}, {
		    content => $item_ref->{content},
		    mult => 1,
		    subfield => '',
		};
		push @{$title_ref->{fields}{'0663'}}, {
		    content => $item_ref->{content},
		    mult => 1,
		    subfield => '',
		};		
		push @{$title_ref->{fields}{'4120'}}, {
		    content => $item_ref->{content},
		    mult => 1,
		    subfield => '',
		};
	    }
	    elsif ($item_ref->{content} =~m/10.18716/){ # DOI
		push @{$title_ref->{fields}{'0552'}}, {
		    content => $item_ref->{content},
		    mult => 1,
		    subfield => '',
		};
	    }
	    elsif ($item_ref->{content} =~m/^urn/){ # URN
		push @{$title_ref->{fields}{'0552'}}, {
		    content => $item_ref->{content},
		    mult => 1,
		    subfield => '',
		};
	    }
	    else {
		push @$new_field, $item_ref;
	    }
	}
	if (@$new_field){
	    $title_ref->{fields}{'0540'} = $new_field;
	}
    }

    
    print encode_json $title_ref, "\n";
}
