#!/usr/bin/perl

use JSON::XS;
use YAML;

my %cdm_id  = ();
my %digitalis_id = ();

open(POSITIVLISTE,"/opt/openbib/autoconv/pools/digitalis/digitalis.xml");

while(<POSITIVLISTE>){
    if (/<katkey>(\d+)<\/katkey>/){
	$cdm_id{$1} = 1;
    }    
}

close(POSITIVLISTE);

open(CDMIDS,">/opt/openbib/autoconv/pools/digitalis/cdm-missing-inst137-ids.txt");
open(INSTIDS,">/opt/openbib/autoconv/pools/digitalis/inst137-missing-cdm-ids.txt");

while (<>){
    my $title_ref = decode_json $_;

    my $id = $title_ref->{id};

    my $skip_title = 0;
    
    if (defined $title_ref->{fields}{'0662'}){
        foreach my $item_ref (@{$title_ref->{fields}{'0662'}}){
            if ($item_ref->{content}=~m/digitalis/){
		
		$digitalis_id{$id} = 1;

		if ($cdm_id{$id}){
		    # Replace Link
		    $item_ref->{content}="https://www.ub.uni-koeln.de/permalink/db/digitalis/id/$id";
		}
		else {
		    print INSTIDS $id,":",$item_ref->{content},"\n";
		    
		    $skip_title=1;
		}
            }
        }
    }

    if ($skip_title){
	next;
    }
    
    print encode_json $title_ref, "\n";
}

foreach my $cdmid (keys %cdm_id){
    if (!defined $digitalis_id{$cdmid} || !$digitalis_id{$cdmid}){
	print CDMIDS $cdmid,"\n";
    }
}

close(CDMIDS);
