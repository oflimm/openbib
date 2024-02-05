#!/usr/bin/perl

use warnings;
use strict;

use utf8;

use JSON::XS;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;

unlink "./classifications.db";

my %classifications = ();

tie %classifications,             'MLDBM', "./classifications.db"
    or die "Could not tie classifications.\n";

open(CLS,"./meta.classification");

while (<CLS>){
    my $classifications_ref = decode_json $_;

    my $id = $classifications_ref->{id};
    
    if (defined $classifications_ref->{fields}{'0800'}[0]{content}){
	my ($rvk) = $classifications_ref->{fields}{'0800'}[0]{content} =~m/^([A-Z][A-Z] \d+)/;
	
	$classifications{$id} = $rvk if ($rvk);
    }
}

close(CLS);

while (<>){
    my $title_ref = decode_json $_;

    my $mult = 1;
    if (defined $title_ref->{fields}{'0700'}){

        foreach my $item (@{$title_ref->{fields}{'0700'}}){
	    my $id = $item->{id};

	    my $rvk = $classifications{$id};

	    push @{$title_ref->{fields}{'4101'}},
	    {
		mult     => $mult++,
		subfield => '',
		content  => $rvk,
	    } if ($rvk);
	}        
    }
   
    print encode_json $title_ref, "\n";
}
