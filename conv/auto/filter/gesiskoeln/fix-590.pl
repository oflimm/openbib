#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    if (defined $title_ref->{fields}{'0590'}){

	my $jg = "";
	if (defined $title_ref->{fields}{'0476'}){
	    foreach my $item (@{$title_ref->{fields}{'0476'}}){
		$jg=$item->{content};
	    }
	}

	my $heft = "";
	if (defined $title_ref->{fields}{'0477'}){
	    foreach my $item (@{$title_ref->{fields}{'0477'}}){
		$heft=$item->{content};
	    }
	}
	
	my $von_s = "";
	if (defined $title_ref->{fields}{'0478'}){
	    foreach my $item (@{$title_ref->{fields}{'0478'}}){
		$von_s=$item->{content};
	    }
	}


	my $bis_s = "";
	if (defined $title_ref->{fields}{'0479'}){
	    foreach my $item (@{$title_ref->{fields}{'0479'}}){
		$bis_s=$item->{content};
	    }
	}

	my $seiten;

	if ($von_s){
	    $seiten = "S. ${von_s}-${bis_s}";
	}
	
	my @angaben = ();

	if ($jg){
	    push @angaben, "Jg $jg";
	}
	if ($heft){
	    push @angaben, "Heft $heft";
	}
	if ($seiten){
	    push @angaben, $seiten;
	}

	my $angabenstring=join(' ; ',@angaben);
	
	foreach my $item (@{$title_ref->{fields}{'0590'}}){
	    if ($angabenstring){
		my $sep;
		if ($item->{content}=~m/\.$/){
		    $sep = " ";
		}
		else {
		    $sep = " ; ";
		}
		$item->{content} = $item->{content}.$sep.$angabenstring;
	    }
	}
	
    }
   
    print encode_json $title_ref, "\n";
}
