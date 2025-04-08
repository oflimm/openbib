#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    # Signaturlose Historische Systematik in 4314$b vereinigen
    if (defined $title_ref->{fields}{'4314'}){
	foreach my $item_ref (@{$title_ref->{fields}{'4314'}}){
	    my $content = $item_ref->{'content'};
	    
	    if ($content =~m/^(.+?)\s*\;.+?$/ || $content =~m/^(.+?)\s*[A-Z][A-Z]*?\d+$/){
		push @{$title_ref->{fields}{'4314'}}, {
		    content  => $1,
		    subfield => 'b',
		    mult     => $item_ref->{'mult'},
		};
	    }
	    else {
		push @{$title_ref->{fields}{'4314'}}, {
		    content  => $content,
		    subfield => 'b',
		    mult     => $item_ref->{'mult'},
		};
	    }
	}
    }

    print encode_json $title_ref, "\n";
}
