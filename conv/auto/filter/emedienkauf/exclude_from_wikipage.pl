#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use MediaWiki::API;
use JSON::XS qw/decode_json encode_json/;

my $mw = MediaWiki::API->new( {api_url => 'https://intern.ub.uni-koeln.de/usbwiki/api.php' } );

my $page = $mw->get_page( { title => 'Emedienkauf - Exkludierte ISBNS' } );

my $page_content = $page->{'*'};

my %excluded_isbns = ();

foreach my $line (split /\n/, $page_content){
    $line=~s/^\s*//g;
    $line=~s/\s*$//g;
    $excluded_isbns{$line} = 1;
}

while (<>){
    my $title_ref;

    eval {
       $title_ref = decode_json $_;
    };

    if ($@){
        print STDERR $@,"\n";
        next;
    }

    my $exclude_title = 0;
    foreach my $isbn_ref (@{$title_ref->{fields}{'0020'}}){
	if ($isbn_ref->{subfield} eq "a"){	    
	    my $isbn = $isbn_ref->{content};
	    $isbn =~s/^\s+//;	    
	    $isbn =~s/-//g;
	    $isbn =~s/^([0-9Xx]+)\s+.+$/$1/;

	    if (defined $excluded_isbns{$isbn} && $excluded_isbns{$isbn}){
		$exclude_title = $isbn;
		last;
	    }
	} 
    }

    if ($exclude_title){
        print STDERR "Titel mit ISBN $exclude_title excluded\n";
        next;
    }

    print;
}
