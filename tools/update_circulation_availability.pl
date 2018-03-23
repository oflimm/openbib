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

our $acq_config = YAML::LoadFile($configfile);

my $dsn = sprintf "dbi:Proxy:%s;dsn=%s",$acq_config->{proxy}, $acq_config->{dsn_at_proxy};

our $dbh = DBI->connect($dsn, $acq_config->{dbuser}, $acq_config->{dbpasswd}) or $logger->error_die($DBI::errstr);

our $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $database});

unlink 'availability_status.db';

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

my $request=$dbh->prepare("select t.katkey,d.d01entl,d.d01status,d.d01skond from d01buch as d,titel_buch_key as t where d.d01mcopyno = t.mcopyno");# group by t.katkey");

eval {
    $request->execute();
};

if ($@){
    $logger->error($@);
}
    
while (my $result=$request->fetchrow_arrayref){
    my $titleid = $result->[0];
    my $status  = get_mediastatus($result->[1],$result->[2],$result->[3]);

    my $status_ref;
    
    if (defined $availability_status{$titleid}){
        $status_ref = $availability_status{$titleid};
    }
    else {
        $status_ref = {};
    }

#    $logger->debug("$titleid -> Status: $status");
    
    if ($status eq "bestellbar"){
        $status_ref->{current}{lendable} = 1;
    }
    elsif ($status eq "nur in Lesesaal bestellbar" || $status eq "nur in bes. Lesesaal bestellbar"){
        $status_ref->{current}{presence} = 1;                    
    }
    elsif ($status eq "nur Wochenende"){
        $status_ref->{current}{lendable} = 1;
    }
    elsif ($status eq "nicht entleihbar"){
        $status_ref->{current}{presence} = 1;
    }
    elsif ($status eq "entliehen"){
        $status_ref->{current}{lent} = 1;
    }

    $availability_status{$titleid} = $status_ref;

}

#print YAML::Dump(\%availability_status);

$logger->info("Processing changed availability status");

our $change_count = 0;
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
