#!/usr/bin/perl

#####################################################################
#
#  webcrawler2meta.pl
#
#  Crawlen einer Website und Konvertierung der Meta-Tags in des
#  OpenBib Einlade-Metaformat
#
#  Dieses File ist (C) 2017 Oliver Flimm <flimm@openbib.org>
#
#  Dieses Programm ist freie Software. Sie koennen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es wuenschen) jeder spaeteren Version.
#
#  Die Veroeffentlichung dieses Programms erfolgt in der
#  Hoffnung, dass es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEWAEHRLEISTUNG - sogar ohne die implizite Gewaehrleistung
#  der MARKTREIFE oder der EIGNUNG FUER EINEN BESTIMMTEN ZWECK.
#  Details finden Sie in der GNU General Public License.
#
#  Sie sollten eine Kopie der GNU General Public License zusammen
#  mit diesem Programm erhalten haben. Falls nicht, schreiben Sie
#  an die Free Software Foundation, Inc., 675 Mass Ave, Cambridge,
#  MA 02139, USA.
#
#####################################################################   

use 5.008001;

use utf8;
use Encode;

use strict;
use warnings;

use Encode qw/decode_utf8/;
use MIME::Base64 qw(encode_base64url);
use Getopt::Long;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Mojo::UserAgent;
use Mojo::URL;

use Digest::MD5 qw(md5_hex);
use HTML::Strip;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;
use OpenBib::Record::Classification;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Person;
use OpenBib::Record::Subject;
use OpenBib::Record::Title;

my ($baseurl,$configfile,$logfile,$maxpages,$loglevel,$help);

&GetOptions(
    "base-url=s"     => \$baseurl,
    "max-pages=s"    => \$maxpages,
    "configfile=s"   => \$configfile,
    "logfile=s"      => \$logfile,
    "loglevel=s"     => \$loglevel,
    "help"           => \$help,
);

if ($help || !$baseurl || !$configfile) {
    print_help();
}

my $config      = OpenBib::Config->new;

$logfile=($logfile)?$logfile:"/var/log/openbib/webspider2meta.log";
$loglevel=($loglevel)?$loglevel:"INFO";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

my $base = Mojo::URL->new($baseurl);
my @urls = $base;

my @error_urls = ();

my $multcount_ref = {};

my $ua = Mojo::UserAgent->new;

$ua = $ua->request_timeout(50);

my %done;
my $url_count = 0;

our $hs = HTML::Strip->new(
    auto_reset => 1,
    
);

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

while (@urls) {
    my $url = shift @urls;

    my $path = $url->path;

    my $id = encode_base64url("$path");

    next if exists $done{$id};

    $logger->info("Processing: $url");

    my $res;
    
    eval {
	$res = $ua->get($url)->result; 
    };

    if ($@){
	$logger->error("Error fetching webpage: $url - ".$@);

	push @error_urls, $url;
	
	$done{$id} = 1;
	next;
    }
    
    # my $content_type = $res->headers->content_type;
    # my $status = $res->headers->status;
    
    # if ($status eq '200 OK' && $content_type ne "text/html"){
    # 	$logger->info("Ignoring non-html page ($status/$content_type)");
    # 	next;
    # }
    
    $logger->info("Generate record");

    gen_record($url,$res);

    $logger->info("Done. Next.");
    
    $done{$id} = 1;
    
    $url_count++;         
    
    $res->dom->find('a')->each(sub{
	my $logger = get_logger();

	my $url = Mojo::URL->new($_->{href});

	# Keine Fragments
	if ($url->fragment){
	    $url->fragment('');
	}

	$logger->debug("$url - ".$url->host);
	if (!defined $url->host && !defined $convconfig->{allowed_hosts}{$url->host}){
	    $url = $url->to_abs($base);
	}
	
	# Nur lokale URLs
	if ( $url->is_abs && defined $url->host && defined $base->host) {
	    if ($url->host ne $base->host && !defined $convconfig->{allowed_hosts}{$url->host}){
		$logger->debug("Host ".$url->host." not allowed");
		return;
	    }
	}

	# Keine URLs in Blacklist
	foreach my $bl_regexp (@{$convconfig->{blacklist_regexps}}){
	    my $path = $url->path;
	    if ($path =~m/$bl_regexp/){
		$logger->info("Ignoring blacklisted URL ".$url->path);
		return;
	    }
	}
	
	# Keine nicht-web links
	if ($url->scheme && $url->scheme !~m/http/){
	    $logger->info("Ignoring non-http(s) URL ".$url->path);

	    return;
	}

	$logger->info("Adding URL ".$url->path);
	
	push @urls, $url;
			       });
    
    last if ($maxpages && $url_count > $maxpages);
    
    sleep 1;
}

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

sub gen_record {
    my ($url,$res) = @_;

    my $logger = get_logger;

    my $path = $url->path;

    $logger->debug("Gen record for path $path");

    my $id = encode_base64url("$path");

    my $title_ref = {
	'id'     => $id,
        'fields' => {},
    };


    # convert person fields
    foreach my $selector (keys %{$convconfig->{person}}){
	my $content = "";

	$logger->debug("Processing selector $selector");

	if ($selector =~m/meta/){
	    foreach my $item ($res->dom->find($selector)->each){
		$content = $item->attr('content');
	    }
	}
	else {
	    foreach my $item ($res->dom->find($selector)->each){
		$content = $item->all_text;
	    }
	}
	

	$logger->debug("Found content $content");

	eval {
	    $content = $hs->parse($content);	    
	    $content = decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
	};
	
	if ($@){
	    $logger->error($@);
	}


	if ($content){
	    my $new_field = $convconfig->{person}{$selector};
	    
	    my @parts = ();
	    
	    if (exists $convconfig->{category_split_chars}{$selector} && $content=~/$convconfig->{category_split_chars}{$selector}/){
		@parts = split($convconfig->{category_split_chars}{$selector},$content);
	    }
	    else {
		push @parts, $content;
	    }
	    
	    foreach my $part (@parts){
		my ($person_id,$new)=OpenBib::Conv::Common::Util::get_person_id($part);
		
		if ($new){
		    my $item_ref = {
			'fields' => {},
		    };
		    $item_ref->{id} = $person_id;
		    push @{$item_ref->{fields}{'0800'}}, {
			mult     => 1,
			subfield => '',
			content  => $part,
		    };
		    
		    print PERSON encode_json $item_ref, "\n";
		}
		
		my $mult = ++$multcount_ref->{$new_field};
		
		push @{$title_ref->{fields}{$new_field}}, {
		    mult       => $mult,
		    subfield   => '',
		    id         => $person_id,
		    supplement => '',
		};
	    }
	}
    }
    
    # convert corporatebody fields
    foreach my $selector (keys %{$convconfig->{corporatebody}}){
	my $content = "";

	$logger->debug("Processing selector $selector");

	if ($selector =~m/meta/){
	    foreach my $item ($res->dom->find($selector)->each){
		$content = $item->attr('content');
	    }
	}
	else {
	    foreach my $item ($res->dom->find($selector)->each){
		$content = $item->all_text;
	    }
	}
	

	$logger->debug("Found content $content");

	eval {
	    $content = $hs->parse($content);	    
	    $content = decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
	};
	
	if ($@){
	    $logger->error($@);
	}


	if ($content){
	    my $new_field = $convconfig->{corporatebody}{$selector};
	    
	    my @parts = ();
	    
	    if (exists $convconfig->{category_split_chars}{$selector} && $content=~/$convconfig->{category_split_chars}{$selector}/){
		@parts = split($convconfig->{category_split_chars}{$selector},$content);
	    }
	    else {
		push @parts, $content;
	    }
	    
	    foreach my $part (@parts){
		my ($corporatebody_id,$new)=OpenBib::Conv::Common::Util::get_corporatebody_id($part);
		
		if ($new){
		    my $item_ref = {
			'fields' => {},
		    };
		    $item_ref->{id} = $corporatebody_id;
		    push @{$item_ref->{fields}{'0800'}}, {
			mult     => 1,
			subfield => '',
			content  => $part,
		    };
		    
		    print CORPORATEBODY encode_json $item_ref, "\n";
		}
		
		my $mult = ++$multcount_ref->{$new_field};
		
		push @{$title_ref->{fields}{$new_field}}, {
		    mult       => $mult,
		    subfield   => '',
		    id         => $corporatebody_id,
		    supplement => '',
		};
	    }
	}
    }

    # convert classification fields
    foreach my $selector (keys %{$convconfig->{classification}}){
	my $content = "";

	$logger->debug("Processing selector $selector");

	if ($selector =~m/meta/){
	    foreach my $item ($res->dom->find($selector)->each){
		$content = $item->attr('content');
	    }
	}
	else {
	    foreach my $item ($res->dom->find($selector)->each){
		$content = $item->all_text;
	    }
	}
	

	$logger->debug("Found content $content");

	eval {
	    $content = $hs->parse($content);	    
	    $content = decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
	};
	
	if ($@){
	    $logger->error($@);
	}


	if ($content){
	    my $new_field = $convconfig->{classification}{$selector};

	    my @parts = ();

	    if (exists $convconfig->{category_split_chars}{$selector} && $content=~/$convconfig->{category_split_chars}{$selector}/){
		@parts = split($convconfig->{category_split_chars}{$selector},$content);
	    }
	    else {
		push @parts, $content;
	    }
	    
	    foreach my $part (@parts){
		my ($classification_id,$new)=OpenBib::Conv::Common::Util::get_classification_id($part);
		
		if ($new){
		    my $item_ref = {
			'fields' => {},
		    };
		    $item_ref->{id} = $classification_id;
		    push @{$item_ref->{fields}{'0800'}}, {
			mult     => 1,
			subfield => '',
			content  => $part,
		    };
		    
		    print CLASSIFICATION encode_json $item_ref, "\n";
		}
		
		my $mult = ++$multcount_ref->{$new_field};
		
		push @{$title_ref->{fields}{$new_field}}, {
		    mult       => $mult,
		    subfield   => '',
		    id         => $classification_id,
		    supplement => '',
		};
	    }
	}
    }

    # convert subject fields
    foreach my $selector (keys %{$convconfig->{subject}}){
	my $content = "";

	$logger->debug("Processing selector $selector");

	if ($selector =~m/meta/){
	    foreach my $item ($res->dom->find($selector)->each){
		$content = $item->attr('content');
	    }
	}
	else {
	    foreach my $item ($res->dom->find($selector)->each){
		$content = $item->all_text;
	    }
	}
	

	$logger->debug("Found content $content");

	eval {
	    $content = $hs->parse($content);	    
	    $content = decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
	};
	
	if ($@){
	    $logger->error($@);
	}


	if ($content){
	    my $new_field = $convconfig->{subject}{$selector};

	    my @parts = ();

	    if (exists $convconfig->{category_split_chars}{$selector} && $content=~/$convconfig->{category_split_chars}{$selector}/){
		@parts = split($convconfig->{category_split_chars}{$selector},$content);
	    }
	    else {
		push @parts, $content;
	    }
	    
	    foreach my $part (@parts){
		my ($subject_id,$new)=OpenBib::Conv::Common::Util::get_subject_id($part);
		
		if ($new){
		    my $item_ref = {
			'fields' => {},
		    };
		    $item_ref->{id} = $subject_id;
		    push @{$item_ref->{fields}{'0800'}}, {
			mult     => 1,
			subfield => '',
			content  => $part,
		    };
		    
		    print SUBJECT encode_json $item_ref, "\n";
		}
		
		my $mult = ++$multcount_ref->{$new_field};
		
		push @{$title_ref->{fields}{$new_field}}, {
		    mult       => $mult,
		    subfield   => '',
		    id         => $subject_id,
		    supplement => '',
		};
	    }
	}
    }

    foreach my $selector (keys %{$convconfig->{title}}){
	my $content = "";

	$logger->debug("Processing selector $selector");

	if ($selector =~m/meta/){
	    foreach my $item ($res->dom->find($selector)->each){
		$content = $item->attr('content');
	    }
	}
	else {
	    foreach my $item ($res->dom->find($selector)->each){
		$content = $item->all_text;
	    }
	}
	

	$logger->debug("Found content $content");

	eval {
	    $content = $hs->parse($content);	    
	    $content = decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
	};
	
	if ($@){
	    $logger->error($@);
	}
	
	push @{$title_ref->{fields}{$convconfig->{title}{$selector}}}, {
	    content => "$content",
	    mult => 1,
	    subfield => "",
	};
    }

    my $body_text_col = $res->dom->at($convconfig->{webcontent});

    # Ignorieren, wenn kein Webcontent gefunden wurde!
    if (!$body_text_col){
	$logger->error("No content found in page block ".$convconfig->{webcontent});
	return ;
    }
    #$body_text_dom->find('script')->strip;
    
    my $body_text = process_dom($body_text_col);
#    my $body_text = $body_text_dom->all_contents;

    push @{$title_ref->{fields}{'0662'}}, {
	content => "$url",
	mult => 1,
	subfield => "",
    };

    push @{$title_ref->{fields}{'0750'}}, {
	content => "$body_text",
	mult => 1,
	subfield => "",
    };

    return unless ($id && $url && $body_text);
    
    print TITLE encode_json $title_ref, "\n";
    
    $logger->debug(YAML::Dump($title_ref)); 
    

    return;    
}

sub process_dom {
    my $dom = shift;

    my $logger=get_logger();

    $logger->debug("1");
#    $logger->debug(YAML::Dump($dom));
#    $logger->debug($dom->size);

    # eval {
    # 	while($dom->at('form')->replace('<!-- form -->')){};	
    # 	while($dom->at('script')->replace('<!-- script -->')){};
    # 	while($dom->at('style')->replace('<!-- style -->')){};
    # };
    $logger->debug("2");
    my $content = $dom->content;
    
    $logger->debug("Preprocess: $content");
    $content =~s/<[\s\/]*?script\b[^>]*>[^>]*<\/script>//msg;
    #    $content =~s/<[\s\/]*style\b[^>]*>[^>]*<\/style>//g;
    $content =~s/<[\s\/]*?style\b[^>]*>.*?<\/style>//msg;
    
    $logger->debug("3");
    $logger->debug("Postprocess: $content");
    
    $content = $hs->parse($content);
    
    
    eval {
	if ($convconfig->{encoding}){
	    my $octets = decode($convconfig->{encoding},$content,Encode::FB_DEFAULT);
	    $content = decode($convconfig->{encoding},$octets,Encode::FB_CROAK);
	}
    };
    
    if ($@){
	$logger->error("ERROR: ".$@);
	return '';
    }
    $logger->debug("4");
    $logger->debug("Postprocess: $content");

    return $content;
}

sub print_help {
    print << "ENDHELP";
webcrawler2meta.pl - Crawlen einer Website und Umwandlung in das Metaformat

   Optionen:
   -help                   : Diese Informationsseite
       
   --base-url="http://..." : Basis-URL der Website
   --logfile=...           : Logfile inkl Pfad.
   --loglevel=...          : Loglevel

ENDHELP
    exit;
}
