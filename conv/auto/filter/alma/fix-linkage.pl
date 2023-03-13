#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};
use OpenBib::Catalog::Subset;
use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;

unlink "./title_linkage.db";

my %title_hbzid2mmsid                = ();

tie %title_hbzid2mmsid,             'MLDBM', "./title_linkage.db"
    or die "Could not tie title_linkage.\n";

print STDERR "### inst001 Analysiere Titeldaten\n";

open(TITLE,"meta.title");

while (<TITLE>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    if (defined $title_ref->{fields}{'0035'}){
	foreach my $item_ref (@{$title_ref->{fields}{'0035'}}){
	    if ($item_ref->{'subfield'} eq "a" && $item_ref->{'content'} =~m/^.DE-605.(\w+)$/ ){
		$title_hbzid2mmsid{$1} = $titleid;
		last;
	    }
	}
    }
}

close(TITLE);

print STDERR "### inst001 Verknuepfungs-ID in 773\$w von hbz-ID auf mmsid aendern\n";

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    if (defined $title_ref->{fields}{'0773'}){
	foreach my $item_ref (@{$title_ref->{fields}{'0773'}}){
	    if ($item_ref->{'subfield'} eq "w" && $item_ref->{'content'} =~m/^.DE-605.(\w+)$/ ){
		$item_ref->{'content'} = $title_hbzid2mmsid{$1} if (defined $title_hbzid2mmsid{$1});
	    }
	}
    }
    
    print encode_json $title_ref, "\n";
}
