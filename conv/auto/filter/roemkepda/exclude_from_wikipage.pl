#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use MediaWiki::API;
use JSON::XS qw/decode_json encode_json/;

my $mw = MediaWiki::API->new( {api_url => 'https://intern.ub.uni-koeln.de/usbwiki/api.php' } );

my $page = $mw->get_page( { title => 'Roemkepda - Exkludierte Titel' } );

my $page_content = $page->{'*'};

my %excluded_ids = ();

foreach my $line (split /\n/, $page_content){
    $line=~s/^\s*//g;
    $line=~s/\s*$//g;
    $excluded_ids{$line} = 1;
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

    print;
}
