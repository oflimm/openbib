#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    # Verlagsorte in 0470 vereinigen
    foreach my $field ('0410','0440','0673','7676'){
	if (defined $title_ref->{fields}{$field}){
	    my $rda_ref = {};

	    foreach my $item (@{$title_ref->{fields}{$field}}){
		if ($field eq "7676"){
		    # RDA sammeln
		    $rda_ref->{$item->{mult}}{$item->{subfield}} = $item->{content};
		}
		else {
		    push @{$title_ref->{fields}{'0470'}}, $item;
		}
	    }
	    
	    # RDA anhand 2er Subfelder
	    if ($field eq "7676"){
		foreach my $mult (keys %$rda_ref){
		    if (($rda_ref->{$mult}{'e'} eq "Erscheinungsort" || $rda_ref->{$mult}{'e'} eq "Herstellungsort") && defined $rda_ref->{$mult}{'g'}){
			push @{$title_ref->{fields}{'0470'}}, {
			    mult     => $mult,
			    subfield => '',
			    content  =>  $rda_ref->{$mult}{'g'},
			};
		    }
		}
	    }
	    
	}
    }

    # Verlage in 0471 vereinigen
    foreach my $field ('0412','0413','1680','1681','0676','7677'){
	if (defined $title_ref->{fields}{$field}){
	    my $rda_ref = {};

	    foreach my $item (@{$title_ref->{fields}{$field}}){
		if ($field eq "7677"){
		    # RDA sammeln
		    $rda_ref->{$item->{mult}}{$item->{subfield}} = $item->{content};
		}
		else {
		    push @{$title_ref->{fields}{'0471'}}, $item;
		}
	    }

	    # RDA anhand 2er Subfelder
	    if ($field eq "7677"){
		foreach my $mult (keys %$rda_ref){
		    if ($rda_ref->{$mult}{'e'} eq "Verlag" && defined $rda_ref->{$mult}{'p'}){
			push @{$title_ref->{fields}{'0471'}}, {
			    mult     => $mult,
			    subfield => '',
			    content  =>  $rda_ref->{$mult}{'p'},
			};
		    }
		}
	    }
	}
    }    

    # Signaturlose Historische Systematik in 0472 vereinigen
    foreach my $field ('4314'){
	if (defined $title_ref->{fields}{$field}){
	    foreach my $item_ref (@{$title_ref->{fields}{$field}}){
		my $content = $item_ref->{'content'};
		if ($content =~m/^(.+?)\s*\;.+?$/ || $content =~m/^(.+?)\s*[A-Z][A-Z]*?\d+$/){
		    push @{$title_ref->{fields}{'0472'}}, {
			content => $1,
			subfield => $item_ref->{'subfield'},
			mult => $item_ref->{'mult'},
		    };
		}
		else {
		    push @{$title_ref->{fields}{'0472'}}, $item_ref;
		}
	    }
	}
    }    

    
    my $is_digital = 0;

    # T0662 hat Inhalt http://www.ub.uni-koeln.de/permalink*
    if (defined $title_ref->{fields}{'0662'}){
        foreach my $item (@{$title_ref->{fields}{'0662'}}){
            if ($item->{content} =~m{^http://www.ub.uni-koeln.de/permalink}){
                $is_digital = 1;
            }        
        }
    }
    
    if ($is_digital){
        $title_ref->{fields}{'4400'} = [
            {
                mult     => 1,
                subfield => '',
                content  => "online",
            },
        ];
        
        $title_ref->{fields}{'4410'} = [
            {
                mult     => 1,
                subfield => '',
                content  => "Digital",
            },
        ];
    }
   
    print encode_json $title_ref, "\n";
}
