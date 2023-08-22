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

use warnings;
use strict;

use Getopt::Long;
use OpenBib::Config;
use OpenBib::User;
use OpenBib::Record::Title;

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

open(JSONOUT, ">:utf8",$outputfile);

open(JSONIN, "<:utf8",$inputfile);

while (my $line = <JSONIN>){

    my $input_ref = decode_json $line;

    my $this_username = $input_ref->{username};

    if ($username && $username ne $this_username){
	next;
    }
    
    if (!$user->user_exists($this_username)){
	print JSONOUT encode_json $input_ref,"\n";	
	$logger->error("NO_USER: $this_username");
	next;
    }

    my $userid = $user->get_userid_for_username($this_username);

    $logger->info("Importing for username $this_username with id $userid");
    if (defined $input_ref->{'items'} && @{$input_ref->{'items'}}){
	foreach my $cartitem_ref (@{$input_ref->{'items'}}){
	    my $dbname     = $cartitem_ref->{dbname};
	    my $titleid    = $cartitem_ref->{titleid};
	    my $fields_ref = $cartitem_ref->{fields};

	    if (defined $cartitem_ref->{success} && $cartitem_ref->{success}){
		$logger->debug("NOT processing DB $dbname ID $titleid - already imported");	    
		next;
	    }

	    my $import_fields = 0;
	    
	    if ($dbname eq "EDS"){
		$dbname="eds";
		# Umwandlung in OpenBib EDS-ID-Trenner :: statt :
		$titleid =~s/^([^:]+?):(.+?)$/$1::$2/;
		$import_fields = 1;
	    }

	    if ($dbname eq "UBK"){
		$dbname="inst001";
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
	    
	    my $record = new OpenBib::Record::Title({ database => $dbname, id => $titleid, config => $config});

	    if ($import_fields){
		$record->set_fields_from_storable($fields_ref);
	    }
	    else {
		$record->load_full_record;
	    }

	    # Fall A: 1:1 Uebertragung moeglich
	    if ($record->record_exists && !$import_fields){
		
		add_item_to_collection({ userid => $userid, dbname => $dbname, titleid => $titleid, config => $config });
		$cartitem_ref->{success} = 1; 
	    }
	    # Fall B: Alte Datenquelle kein existierender Katalog, dann aus Cache-Daten
	    elsif ($import_fields){
		add_item_to_collection({ userid => $userid, dbname => $dbname, titleid => $titleid, config => $config, record => $record });
		$cartitem_ref->{success} = 1; 
	    }
	    # Fall B: Alte Datenquelle ist existierender Katalog, aber Titel existiert nicht mehr, dann aus Cache-Daten
	    # elsif (!$record->record_exists){
	    # 	$record->set_fields_from_storable($fields_ref);		
	    # 	add_item_to_collection({ userid => $userid, dbname => $dbname, titleid => $titleid, config => $config, record => $record });
	    # }	    
	    else {
		$logger->error("TITLE_NOT_EXIST: $dbname - $titleid");
		$cartitem_ref->{'not_exist'} = 1; 
	    }
	}
	
	print JSONOUT encode_json $input_ref,"\n";
    }
}

close(JSONIN);

close(JSONOUT);

sub add_item_to_collection {
    my ($arg_ref)=@_;

    my $userid       = exists $arg_ref->{userid}
        ? $arg_ref->{userid}               : undef;

    my $dbname       = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}               : undef;
    
    my $titleid      = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}              : undef;
    
    my $comment      = exists $arg_ref->{comment}
        ? $arg_ref->{comment}              : '';
    
    my $record       = exists $arg_ref->{record}
        ? $arg_ref->{record}               : undef;

    my $config       = exists $arg_ref->{config}
        ? $arg_ref->{config}               : new OpenBib::Config;
    
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $new_title ;

    # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
            
    my $have_title = $config->get_schema->resultset('UserCartitem')->search_rs(
	{
	    'userid.id'          => $userid,
            'cartitemid.dbname'  => $dbname,
            'cartitemid.titleid' => $titleid,
	},
	{
	    join => ['userid','cartitemid'],
	}
        )->count;
    
    if (!$have_title && $record){
        
        my $record_json = $record->to_json;
        
        # DBI: "select count(userid) as rowcount from collection where userid = ? and dbname = ? and titleid = ?"
        
	$logger->info("Adding Title to Usercollection of user $userid: $record_json");
	
	# DBI "insert into treffer values (?,?,?,?)"
	$new_title = $config->get_schema->resultset('Cartitem')->create(
	    {
		titleid    => $titleid,
		dbname     => $dbname,
		titlecache => $record_json,
		comment    => $comment,
		tstamp     => \'NOW()',
	    }
	    );
	
	$config->get_schema->resultset('UserCartitem')->create(
	    {
		userid           => $userid,
		cartitemid       => $new_title->id,
	    }
	    );
    }
    elsif (!$have_title) {
        # DBI: "select count(userid) as rowcount from collection where userid = ? and dbname = ? and titleid = ?"
        
	my $cached_title = new OpenBib::Record::Title({ database => $dbname , id => $titleid, config => $config });
	my $record_json = $cached_title->load_full_record->to_json;
	
	$logger->debug("Adding Title to Usercollection: $record_json");
	
	# DBI "insert into treffer values (?,?,?,?)"
	$new_title = $config->get_schema->resultset('Cartitem')->create(
	    {
		dbname     => $dbname,
		titleid    => $titleid,
		titlecache => $record_json,
		comment    => $comment,
		tstamp     => \'NOW()',
	    }
            );
	
	$config->get_schema->resultset('UserCartitem')->create(
	    {
		userid           => $userid,
		cartitemid => $new_title->id,
	    }
            );
    }
    
    if ($new_title){
        my $new_titleid = $new_title->id;
        $logger->debug("Created new collection entry with id $new_titleid");
        return $new_titleid;
    }
    
    return ;
}


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

