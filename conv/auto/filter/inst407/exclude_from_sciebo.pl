#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use LWP::UserAgent;
use LWP::Simple;
use OpenBib::Config;

use YAML;

use JSON::XS qw/decode_json encode_json/;

my %excluded_ids = ();

my $config = new OpenBib::Config;

my $ua = new LWP::UserAgent;

my $page_url = $config->get('retro_url')->{'inst407'}."/download";

if ($page_url){
    my $result = $ua->get($page_url);

    my $page_content = "";
    
    eval {
	$page_content = $result->decoded_content;
    };
	
    foreach my $line (split /\n/, $page_content){
	$line=~s/^\s*//g;
	$line=~s/\s*$//g;
	$excluded_ids{$line} = 1;
    }
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
