#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use LWP::UserAgent;
use LWP::Simple;
use OpenBib::Config;
use POSIX qw(strftime);

use YAML;

use JSON::XS qw/decode_json encode_json/;

my %excluded_ids = ();

my $config = new OpenBib::Config;

my $dbname = $ARGV[0];

my $ua = new LWP::UserAgent;

my $retro_ref = $config->load_yaml("/opt/openbib/conf/retro.yml");

exit if (!defined $retro_ref->{$dbname});

my $page_url = $retro_ref->{$dbname}."/download";

my $result = $ua->get($page_url);

my $page_content = "";

eval {
    $page_content = $result->decoded_content;
};

if ($page_content){

    my $date = strftime "%Y-%m-%d", localtime;
    
    open(BACKUP,">/opt/openbib/autoconv/pools/$dbname/title_exclude_${date}.txt");
    print BACKUP $page_content;
    close(BACKUP);
    
    foreach my $line (split /\n/, $page_content){
	$line=~s/^\s*//g;
	$line=~s/\s*$//g;
	$excluded_ids{$line} = 1;
    }


    open(TITLE,"cat meta.title|");
    open(TITLEOUT,"> meta.title.tmp");

    while (<TITLE>){
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

	print TITLEOUT;
    }

    close(TITLE);
    close(TITLEOUT);

    system("mv -f meta.title.tmp meta.title");
}
