#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use MediaWiki::API;
use JSON::XS qw/decode_json encode_json/;

my %excluded_ids = ();
my %excluded_isbns = ();

eval {
    my $mw = MediaWiki::API->new( {api_url => 'https://intern.ub.uni-koeln.de/usbwiki/api.php' } );
    
    my $page = $mw->get_page( { title => 'Tmpebooks - Exkludierte Titel' } );
    
    my $page_content = $page->{'*'};
    
    
    
    foreach my $line (split /\n/, $page_content){
	$line=~s/^\s*//g;
	$line=~s/\s*$//g;
	$excluded_ids{$line} = 1;
    }
    
    
    $page = $mw->get_page( { title => 'Tmpebooks - Exkludierte ISBNS' } );
    
    $page_content = $page->{'*'};

    foreach my $line (split /\n/, $page_content){
	$line=~s/^\s*//g;
	$line=~s/\s*$//g;
	$excluded_isbns{$line} = 1;
    }
};

if ($@){
    print STDERR $@,"\n";
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

    if (defined $excluded_ids{$title_ref->{id}}){
        print STDERR "Titel-ID $title_ref->{id} excluded\n";
        next;
    }

    my $exclude_title = 0;
    foreach my $isbn_ref (@{$title_ref->{fields}{'0540'}}){
	if (defined $excluded_isbns{$isbn_ref->{content}}){
	    $exclude_title = $isbn_ref->{content}; 
	    last;
	} 
    }


    foreach my $isbn_ref (@{$title_ref->{fields}{'0553'}}){
	if (defined $excluded_isbns{$isbn_ref->{content}}){
	    $exclude_title = $isbn_ref->{content}; 
	    last;
	} 
    }

    if ($exclude_title){
        print STDERR "Titel mit ISBN $exclude_title excluded\n";
        next;
    }

    print;
}
