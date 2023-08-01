#!/usr/bin/perl

#####################################################################
#
#  export_ipsudb2json.pl
#
#  Import der IPS Nutzer-DB und Extraktion der Merklisteneintraege
#
#  Dieses File ist (C) 2023 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module 
#####################################################################

use utf8;

use Getopt::Long;
use OpenBib::Config;
use OpenBib::User;

use Date::Manip;
use Encode qw/decode_utf8 encode decode/;
use File::Find;
use File::Slurper 'read_binary';
use Log::Log4perl qw(get_logger :levels);
use JSON::XS;
use XML::Twig;
use YAML;

if ($#ARGV < 0){
    print_help();
}

my ($help,$basedir,$logfile,$loglevel,$renderer);

&GetOptions(
    "help"       => \$help,
    "basedir=s"  => \$basedir,
    "logfile=s"  => \$logfile,            
    "loglevel=s" => \$loglevel,            
    );

if ($help || !$basedir){
    print_help();
}

$loglevel  =($loglevel)?$loglevel:'INFO';

$logfile  =($logfile)?$logfile:'/var/log/openbib/ipsudb2json.log';

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

our $peoplecount_ref = {};

$logger->debug("Processing directory $basedir");

open(JSONOUT, ">./ips_cartitems.json");

find(\&process_file, $basedir);

close(JSONOUT);

sub process_file {
    my $logger = get_logger();
    
    return unless ($File::Find::name=~/cart.xml$/);

    my $filename = $File::Find::name;

    my $dirname  = $File::Find::dir;

    $dirname =~s/$basedir\///;

    my $username = $dirname;
    
    $username =~s/\///g;

    $username =~ s/(..)/chr(hex($1))/eg;

    $logger->debug("Processing user $username: $filename in dir $dirname");

    my $xmlcontent = read_binary($filename);

    my $this_cart_ref = {};
    
    while ($xmlcontent =~m{<ID>(.+?)</ID>}g){
	my $content = $1;

	my $dbname;
	my $titleid;
	
	if ($content =~m/^([^:]+?):(.+)$/){
	    $dbname = $1;
	    $titleid = $2;
	}

	$this_cart_ref->{username} = $username;
	push @{$this_cart_ref->{items}},{
	    dbname => $dbname,
		titleid => $titleid,
	} if ($dbname && $titleid);
	$logger->debug("DB: $dbname ID: $titleid");
    }

    print JSONOUT encode_json $this_cart_ref,"\n";
    $logger->debug("User: $username: ".YAML::Dump($this_cart_ref));
}


sub print_help {
    print << "ENDHELP";
export_ipsudb2json.pl - Dump IPS Merklisten-Eintraege in JSON pro User

   Optionen:
   -help                 : Diese Informationsseite
       
   --basedir=            : Vollqualifizierter absoluter Basis-Pfad der IPS UDB

ENDHELP
    exit;
}

