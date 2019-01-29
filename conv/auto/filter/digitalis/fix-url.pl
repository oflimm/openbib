#!/usr/bin/perl

use JSON::XS;
use YAML;

my %positive_id = ();

open(POSITIVLISTE,"/opt/openbib/autoconv/pools/digitalis/digitalis.xml");

while(<POSITIVLISTE>){
    if (/<katkey>(\d+)<\/katkey>/){
	$positive_id{$1} = 1;
    }    
}

close(POSITIVLISTE);

while (<>){
    my $title_ref = decode_json $_;

    my $id = $title_ref->{id};

    my $delete_field = 0;
    
    if (defined $title_ref->{fields}{'0662'}){
        foreach my $item_ref (@{$title_ref->{fields}{'0662'}}){
            if ($item_ref->{content}=~m/digitalis/){
		if ($positive_id{$id}){
		    $item_ref->{content}="https://www.ub.uni-koeln.de/permalink/db/digitalis/id/$id";
		}
		else {
		    $delete_field=1;
		}
            }
        }
    }

    if ($delete_field){
	delete $title_ref->{fields}{'0662'};
    }
    
    print encode_json $title_ref, "\n";
}
