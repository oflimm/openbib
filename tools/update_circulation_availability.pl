#!/usr/bin/perl

#####################################################################
#
#  update_circulation_availability.pl
#
#  Aktualisierung der Zugriffs-Information der Titel aus dem
#  zugehoerigen SISIS-Ausleihsystem
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;

use OpenBib::Config;
use OpenBib::Catalog::Factory;
use OpenBib::Index::Factory;
use OpenBib::Index::Document;
use OpenBib::Index::Backend::Xapian;

use DBI;
use Getopt::Long;
use Encode qw(decode encode);
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use DBIx::Class::ResultClass::HashRefInflator;
use YAML::Syck;
use Search::Xapian;

if ($#ARGV < 0){
    print_help();
}

our ($help,$configfile,$withsearchprofiles,$database,$logfile,$month,$year);

&GetOptions(
            "help"                => \$help,
            "database=s"          => \$database,
            "configfile=s"        => \$configfile,
            "logfile=s"           => \$logfile,
            "with-searchprofiles" => \$withsearchprofiles,
            );

$logfile=($logfile)?$logfile:"/var/log/openbib/update_circulation_availability.log";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, LOGFILE, Screen
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

# Message Katalog laden
our $msg = OpenBib::L10N->get_handle('de') || $logger->error("L10N-Fehler");
$msg->fail_with( \&OpenBib::L10N::failure_handler );

our $entl_map_ref = {
      'X' => 0, # nein
      ' ' => 1, # ja
      'L' => 2, # Lesesaal
      'B' => 3, # Bes. Lesesaal
      'W' => 4, # Wochenende
  };

our $config = OpenBib::Config->new;

if (! $config->local_server_is_active_and_searchable){
    $logger->info("### Local server is neither active nor searchable. Exiting.");
    exit;
}

our $acq_config = YAML::LoadFile($configfile);

my $dsn = sprintf "dbi:Proxy:%s;dsn=%s",$acq_config->{proxy}, $acq_config->{dsn_at_proxy};

our $dbh = DBI->connect($dsn, $acq_config->{dbuser}, $acq_config->{dbpasswd}) or $logger->error_die($DBI::errstr);

my $remotedbname = $acq_config->{dbname};
my $sql_statement = qq{
  select * 

  from $remotedbname.sisis.d50zweig
  };
  
my $request=$dbh->prepare($sql_statement);
$request->execute() or $logger->error_die($DBI::errstr);

my %zweig=();
while (my $res=$request->fetchrow_hashref()){
    $zweig{$res->{'d50zweig'}}{Bezeichnung}=$res->{'d50bezeich'};
}

$sql_statement = qq{
  select * 

  from $remotedbname.sisis.d60abteil
  };

$request=$dbh->prepare($sql_statement);
$request->execute() or $logger->error_die($DBI::errstr);

my %abteilung=();
while (my $res=$request->fetchrow_hashref()){
    $abteilung{$res->{'d60zweig'}}{$res->{'d60abt'}}=$res->{'d60bezeich'};
}

$sql_statement = qq{
  select * 

  from $remotedbname.sisis.d63mtyp
  };

$request=$dbh->prepare($sql_statement);
$request->execute() or $logger->error_die($DBI::errstr);

my $mtyp_ref = {};
while (my $res=$request->fetchrow_hashref()){
    $mtyp_ref->{$res->{'d63mtyp'}} = {
	vmanz     => $res->{'d63anzvm'},
	sotext    => $res->{'d63sotext'},
	helptext  => $res->{'d63helptest'},
    };
}

our $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $database});

unlink "availability_status_${database}.db";

my %availability_status = ();

tie %availability_status,           'MLDBM', "availability_status_${database}.db",
    or die "Could not tie availability data.\n";


$logger->info("Processing old availability status");

my $titles = $catalog->get_schema->resultset('TitleField')->search(
    {
        field => '4400',
        content => {'!=' => 'online'},
    },
    {
        select => ['titleid','content'],
        as     => ['thistitleid','thisavailability'],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator', 
    }
);

while (my $title = $titles->next()){
    my $titleid      = $title->{thistitleid};
    my $availability = $title->{thisavailability};

    $availability_status{$titleid} = {
        old => {
            $availability => 1
        },
    };
}

$logger->info("Processing current availability status");

my $sql_statement_t = qq{
  select distinct(katkey) from $remotedbname.sisis.titel_buch_key 
  };

my $request_t=$dbh->prepare($sql_statement_t);
$request_t->execute() or $logger->error_die($DBI::errstr);;

our $change_count = 0;

while (my $res_t=$request_t->fetchrow_hashref()){
    my $titleid = $res_t->{katkey};

    $sql_statement = qq{
  select tbk.katkey,d.d01aort,d.d01gsi,d.d01ort,d.d01entl,d.d01mtyp,d.d01ex,d.d01status,d.d01skond,d.d01vmanz,d.d01rv,d.d01abtlg,d.d01zweig,d.d01bnr

  from $remotedbname.sisis.d01buch as d, $remotedbname.sisis.titel_buch_key as tbk

  where d.d01mcopyno=tbk.mcopyno and tbk.katkey = ? 
  };
    

    $request=$dbh->prepare($sql_statement);
    $request->execute($titleid) or $logger->error_die($DBI::errstr);;

    my $bindeeinheit = 0; 

    my $status_ref;
    
    if (defined $availability_status{$titleid}){
        $status_ref = $availability_status{$titleid};
    }
    else {
        $status_ref = {};
    }

    my $circulation_ref = [];
    
    while (my $res=$request->fetchrow_hashref()){
	my $titleid    = $res->{'katkey'};
	my $mediennr   = $res->{'d01gsi'};
	my $signatur   = $res->{'d01ort'};
	my $exemplar   = $res->{'d01ex'};
	my $rueckgabe  = $res->{'d01rv'};
	my $entl       = $res->{'d01entl'};
	my $status     = $res->{'d01status'};
	my $skond      = $res->{'d01skond'};
	my $abteilung  = $res->{'d01abtlg'};
	my $mtyp       = $res->{'d01mtyp'};
	my $bnr        = $res->{'d01bnr'};
	my $zweignr    = $res->{'d01zweig'};
	my $vmanz      = $res->{'d01vmanz'};
	my $ausgabeort = $res->{'d01aort'};
	my $seqnr      = $res->{'seqnr'};
	my $zweigst    = "";
	
	my $statusstring   = "";
	my $standortstring = "";
	my $vormerkbar     = 0;
	my $opactext       = (exists $mtyp_ref->{$mtyp}{sotext})?$mtyp_ref->{$mtyp}{sotext}:'';
	
	if ($seqnr > 1){
	    $bindeeinheit = 1;
	}
	
	if ($vmanz < $mtyp_ref->{$mtyp}{vmanz}){
	    $vormerkbar   = 1;
	}
	
	if ($abteilung{"$zweignr"}{"$abteilung"}){
	    $standortstring=$abteilung{"$zweignr"}{"$abteilung"};
	}
	
	if ($zweig{"$zweignr"}{Bezeichnung}){
	    $standortstring=$zweig{"$zweignr"}{Bezeichnung}." / $standortstring";
	}
	
	if ($entl_map_ref->{$entl} == 0){
	    $statusstring="nicht entleihbar";
	}
	elsif ($entl_map_ref->{$entl} == 1){
	    if ($status eq "0"){
		$statusstring="bestellbar";
	    }
	    elsif ($status eq "2"){
		$statusstring="entliehen"; # Sonderwunsch. Eigentlich: bestellt
	    }
	    elsif ($status eq "4"){
		$statusstring="entliehen";
	    }
	    else {
		$statusstring="unbekannt";
	    }
	}
	elsif ($entl_map_ref->{$entl} == 2){
	    $statusstring="nur in Lesesaal bestellbar";
	}
	elsif ($entl_map_ref->{$entl} == 3){
	    $statusstring="nur in bes. Lesesaal bestellbar";
	}
	elsif ($entl_map_ref->{$entl} == 4){
	    $statusstring="nur Wochenende";
	    
	    if ($status eq "2"){
		$statusstring="entliehen"; # Sonderwunsch. Eigentlich: bestellt
	    }
	    elsif ($status eq "4"){
		$statusstring="entliehen";
	    }	
	}
	else {
	    $statusstring="unbekannt";
	}
	
	# Sonderkonditionen
	
	if ($skond eq "16"){
	    $statusstring="verloren";
	}
	elsif ($skond eq "32"){
	    $statusstring="vermi&szlig;t";
	}
	
	$rueckgabe=~s/12:00AM//;
	
	$standortstring="-" unless ($standortstring);
	
	my $d39sql_statement = qq{
       select d39fusstext

       from $remotedbname.sisis.d39fussnoten

       where d39gsi = ?
         AND d39ex = ?
         AND d39fussart = 1

       order by d39fussnr
 };

	my $request2=$dbh->prepare($d39sql_statement);
	$request2->execute($mediennr,$exemplar) or $logger->error_die($DBI::errstr);;
	
	$logger->info("Fussnoten fuer Mediennr:$mediennr: Exemplar:$exemplar:");
	my $fussnote = "";
	
	while (my $res2=$request2->fetchrow_hashref){
	    $fussnote.=$res2->{d39fusstext};
	}
	
	$request2->finish();
	
	
	my $singleex_ref = {
	    Mediennr       => encode("utf-8",decode("iso-8859-1",$mediennr)),
	    Zweigstelle    => encode("utf-8",decode("iso-8859-1",$zweignr)),
	    Signatur       => encode("utf-8",decode("iso-8859-1",$signatur)),
	    Exemplar       => encode("utf-8",decode("iso-8859-1",$exemplar)),
	    Abteilungscode => encode("utf-8",decode("iso-8859-1",$abteilung)),
	    Standort       => encode("utf-8",decode("iso-8859-1",$standortstring)),
	    Status         => encode("utf-8",decode("iso-8859-1",$statusstring)),
	    Statuscode     => encode("utf-8",decode("iso-8859-1",$status)),
	    Opactext       => encode("utf-8",decode("iso-8859-1",$opactext)),
	    Fussnote       => encode("utf-8",decode("iso-8859-1",$fussnote)),
	    Entleihbarkeit => $entl_map_ref->{$entl},
	    Vormerkbarkeit => $vormerkbar,
	    Rueckgabe      => encode("utf-8",decode("iso-8859-1",$rueckgabe)),
	    Ausgabeort     => encode("utf-8",decode("iso-8859-1",$ausgabeort)),
	};


	if ($statusstring eq "bestellbar"){
	    $status_ref->{current}{lendable} = 1;
	}
	elsif ($statusstring eq "nur in Lesesaal bestellbar" || $statusstring eq "nur in bes. Lesesaal bestellbar"){
	    $status_ref->{current}{presence} = 1;                    
	}
	elsif ($statusstring eq "nur Wochenende"){
	    $status_ref->{current}{lendable} = 1;
	}
	elsif ($statusstring eq "nicht entleihbar"){
	    $status_ref->{current}{presence} = 1;
	}
	elsif ($statusstring eq "entliehen"){
	    $status_ref->{current}{lent} = 1;
	}
	
	push @$circulation_ref, $singleex_ref;
    }

    my $memc_key = "record:title:circulation:$database:$titleid";

    # Medienstatus eines Titel wird mit allen Exemplaren immer aktualisiert
    if (defined $config->{memc}){
	# Update in Memcached
        $config->{memc}->set($memc_key,$circulation_ref,$config->{memcached_expiration}{'record:title:circulation'});
    }

    #    $logger->debug("$titleid -> Status: $status");
    
    
    $availability_status{$titleid} = $status_ref;

    #print YAML::Dump(\%availability_status);
    
    $logger->info("Processing changed availability status");
    
    foreach my $titleid (keys %availability_status){
	# Autovivication bedenken!
	
	#    $logger->debug(YAML::Dump($availability_status{$titleid}));
	# 1) Buch inzwischen ausgeliehen und nicht mehr ausleihbar bzw. praesent (Sonderausleihe!)
	if ((defined $availability_status{$titleid}->{old}{lendable} || defined $availability_status{$titleid}->{old}{presence}) && defined $availability_status{$titleid}->{current}{lent}){
	    update_status($database,$titleid,"");
	}
	# 2) Buch wieder zurueckgegeben und jetzt ausleihbar
	elsif (!defined $availability_status{$titleid}->{old}{lendable} && defined $availability_status{$titleid}->{current}{lendable}){
	    update_status($database,$titleid,"lendable");
	}
	# 3) Buch wieder zurueckgegeben und jetzt wieder Praesenzbestand
	elsif (!defined $availability_status{$titleid}->{old}{lendable} && defined $availability_status{$titleid}->{current}{presence}){
	    update_status($database,$titleid,"presence");
	}
    }
}

$logger->info("$change_count titles changed status");

unlink "availability_status_${database}.db";

sub print_help {
    print "update_circulation_availability.pl - Aktualisierung der Zugriffs-Information aus dem Ausleihsystem\n\n";
    print "Optionen: \n";
    print "  -help                        : Diese Informationsseite\n";
    print "  --configfile=acq_inst431.yml : Konfigurationsdatei der Bibliothek\n";
    
    exit;
}

sub get_mediastatus {
    my ($entl,$status,$skond) = @_;

    my $statusstring   = "";

    if    ($entl_map_ref->{$entl} == 0){
        $statusstring="nicht entleihbar";
    }
    elsif ($entl_map_ref->{$entl} == 1){
    	if ($status eq "0"){
            $statusstring="bestellbar";
        }
        elsif ($status eq "2"){
            $statusstring="entliehen"; # Sonderwunsch. Eigentlich: bestellt
        }
        elsif ($status eq "4"){
            $statusstring="entliehen";
        }
        else {
            $statusstring="unbekannt";
        }
    }
    elsif ($entl_map_ref->{$entl} == 2){
      $statusstring="nur in Lesesaal bestellbar";
    }
    elsif ($entl_map_ref->{$entl} == 3){
      $statusstring="nur in bes. Lesesaal bestellbar";
    }
    elsif ($entl_map_ref->{$entl} == 4){
      $statusstring="nur Wochenende";
    }
    else {
      $statusstring="unbekannt";
    }

    # Sonderkonditionen

    if ($skond eq "16"){
      $statusstring="verloren";
    }
    elsif ($skond eq "32"){
      $statusstring="vermi&szlig;t";
    }

    return $statusstring;
}

sub update_status {
    my ($database,$titleid,$new_status) = @_;

    if (!$catalog->get_schema->resultset('Title')->single({ id => $titleid})){
        $logger->error("Title ID $titleid doesn't yet exisit");

        return;
    }

    # SQL-Datenbank
    
    update_status_db($titleid,$new_status);

    # Suchindex

    # 1) Datenbankindex (gleicher Name wie SQL-DB)

    update_status_index_from_db($database,$titleid);
    
    return;
};

sub update_status_db {
    my ($titleid,$new_status) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    eval {
        my $availability = $catalog->get_schema->resultset('TitleField')->single(
            {
                titleid => $titleid,
                field   => '4400',
                content => 'lendable',
            },
        );

        # 1) Wechsel von lendable zu not lendable
        if ($availability && !$new_status){
            $logger->info("--> Titleid $titleid jetzt ausgeliehen");
            $availability->delete;
            $change_count++
        }
        # 2) Wechsel von not lendable zu lendable
        elsif (!$availability && $new_status){
            $logger->info("<-- Titleid $titleid jetzt ausleihbar");

            $catalog->get_schema->resultset('TitleField')->create({
                titleid  => $titleid,
                field    => 4400,
                content  => $new_status,
                subfield => '',
                mult     => 1,
            });
            $change_count++;
        }
	else {
            $logger->info("Unbekannt fuer Id $titleid: availability:$availability->count / new_status:$new_status");
	}
    };

    if ($@){
        $logger->error($@);
    }

    return;
}

sub update_status_index_from_db {
    my ($database,$titleid) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;
    
    $catalog->load_conv_config;

    my $document    = $catalog->create_index_document($titleid);

    $logger->info("Updating Index for database $database");
    
    my $indexer     = OpenBib::Index::Factory->create_indexer({ database => $database, index_type => 'readwrite' }); # no create_index !!!
    my $indexer_doc = $indexer->create_document({ document => $document });
    $indexer->update_record($titleid,$indexer_doc);

    if ($withsearchprofiles){
        foreach my $searchprofileid ($config->get_searchprofiles_with_database($database)){
            my $index_path = $config->{xapian_index_base_path}."/_searchprofile/".$searchprofileid;
            
            next unless (-d $index_path);
            
            $logger->info("Updating Index for searchprofile $searchprofileid");
            my $indexer     = OpenBib::Index::Factory->create_indexer({ searchprofile => $searchprofileid, index_type => 'readwrite' }); # no create_index !!!
            my $indexer_doc = $indexer->create_document({ document => $document });
            $indexer->update_record($titleid,$indexer_doc);
        }
    }

    
    return;
}
