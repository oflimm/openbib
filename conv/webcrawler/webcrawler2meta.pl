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

use OpenBib::Config;
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

my $ua = Mojo::UserAgent->new;
my %done;
my $url_count = 0;

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
        
    my $res = $ua->get($url)->res; 
    
    gen_record($url,$res);
    
    $done{$id} = 1;
    
    $url_count++;         
    
    $res->dom('a')->each(sub{
	my $logger = get_logger();

	my $url = Mojo::URL->new($_->{href});

	# Keine Fragments
	if ($url->fragment){
	    $url->fragment('');
	}

	$url = $url->to_abs($base);

	# Nur lokale URLs
	if ( $url->is_abs && defined $url->host && defined $base->host) {
	    return unless $url->host eq $base->host;
	}

	# Keine email links
	return if $url->scheme && $url->scheme eq 'mailto';

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

    my $id = encode_base64url("$path");
    
    my $title_ref = {
	'id'     => $id,
        'fields' => {},
    };

    foreach my $meta_selector (keys %{$convconfig->{title}}){
	my $content = $res->dom($meta_selector)->attr('content');

	eval {
	    $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
	};
	
	if ($@){
	    $logger->error($@);
	}
	
	push @{$title_ref->{fields}{$convconfig->{title}{$meta_selector}}}, {
	    content => "$content",
	    mult => 1,
	    subfield => "",
	       };
    }

    my $body_text_dom = $res->dom->find($convconfig->{webcontent});

    $body_text_dom->find('script')->strip;
    
    my $body_text = $body_text_dom->all_text;
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
