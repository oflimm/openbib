#!/usr/bin/perl

#####################################################################
#
#  import_ipscartitems.pl
#
#  Import der IPS Merklisteneintraege aus JSON
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
use Log::Log4perl qw(get_logger :levels);
use JSON::XS;
use YAML;

if ($#ARGV < 0){
    print_help();
}

my ($help,$inputfile,$outputfile,$username,$logfile,$loglevel);

&GetOptions(
    "help"         => \$help,
    "username=s"   => \$username,    
    "inputfile=s"  => \$inputfile,
    "outputfile=s" => \$outputfile,
    "logfile=s"    => \$logfile,            
    "loglevel=s"   => \$loglevel,            
    );

if ($help || !$inputfile || !$outputfile){
    print_help();
}

$loglevel  =($loglevel)?$loglevel:'INFO';

$logfile  =($logfile)?$logfile:'/var/log/openbib/import_ipsmerkliste.log';

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

$logger->debug("Processing JSON inputfile $inputfile");

my $config = new OpenBib::Config;
my $user = new OpenBib::User;

open(JSONOUT, ">$outputfile");

open(JSONIN,"<$inputfile");

while (my $line = <JSONIN>){

    my $input_ref = decode_json $line;

    my $this_username = $input_ref->{username};

    if ($username && $username ne $this_username){
	next;
    }
    
    if (!$user->user_exists($this_username)){
	$logger->error("NO_USER: $this_username");
	next;
    }

    my $userid = $user->get_userid_for_username($this_username);

    if (defined $input_ref->{'items'} && @{$input_ref->{'items'}}){
	foreach my $cartitem_ref (@{$input_ref->{'items'}}){
	    my $dbname = $cartitem_ref->{dbname};
	    my $titleid = $cartitem_ref->{titleid};

	    if (defined $cartitem_ref->{success} && $cartitem_ref->{success}){
		next;
	    }
	    
	    $logger->debug("Processing DB $dbname ID $titleid");	    
	    if (!$config->db_exists($dbname)){
		$logger->error("NO_DB: $dbname");
		next;
	    }
	    
	    if ($dbname !~ '^[a-z]'){ # Nur Kleinbuchstaben dbnamen sind lokal und unterstuetzt
		$logger->error("UNSUPPORTED_DB: $dbname");
		next;
	    }
	    
	    # titleid exists in dbname
	    
	    my $record = new OpenBib::Record::Title({ database => $dbname, id => $titleid});
	    
	    $record->load_brief_record;
	    
	    if ($record->record_exists){
		
		$user->add_item_to_collection({ userid => $userid, dbname => $dbname, titleid => $titleid });
		$cartitem_ref->{success} = 1; 
	    }
	    else {
		$logger->error("TITLE_NOT_EXIST: $dbname");
		$cartitem_ref->{'not_exist'} = 1; 
	    }
	}
	
	print JSONOUT encode_json $input_ref,"\n";
    }
}

close(JSONIN);

close(JSONOUT);


sub print_help {
    print << "ENDHELP";
import_ipscartitems.pl - Import IPS Merklisten-Eintraege in Infrastruktur

   Optionen:
   -help                 : Diese Informationsseite
       
   --inputfile=          : JSON Einladedatei mit Merklisteneintraegen pro Nutzer
   --outputfile=         : Ausgabedatei mit Annotation der vearbeiteten Eintraege

ENDHELP
    exit;
}

