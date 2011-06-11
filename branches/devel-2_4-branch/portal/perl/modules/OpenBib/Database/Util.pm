#####################################################################
#
#  OpenBib::Database::Subset
#
#  Zusammenfassung von Funktionen, die von mehreren Datenbackends
#  verwendet werden
#
#  Dieses File ist (C) 1997-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Database::Subset;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;

use OpenBib::Config;

sub new {
    my $class    = shift;
    my $database = shift;
    
    my $self         = {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{config}   = new OpenBib::Config;

    if ($database){
        $self->{database} = $database;
        $self->{dbh}      = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);
    }
    
    $self->{titleid}  = ();

    bless ($self, $class);

    return $self;
}

sub set_database {
    my $self     = shift;
    my $database = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{database} = $database;
    $self->{dbh}      = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

    return $self;
}

sub get_title_ids_by_mark {
    my ($arg_ref) = @_;

    # Set defaults
    my $database   = exists $arg_ref->{database}
        ? $arg_ref->{database}              : undef;

    my $mark       = exists $arg_ref->{mark}
        ? $arg_ref->{mark}                  : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    
    my $request=$dbh->prepare("select distinct conn.sourceid as titid from conn,holding where holding.category=14 and holding.content rlike ? and conn.targetid=holding.id and conn.sourcetype=1 and conn.targettype=6") or $logger->error($DBI::errstr);

    $request->execute($mark) or $logger->error($DBI::errstr);;

    while (my $result=$request->fetchrow_hashref()){
        $self->{titleid}{$result->{'titid'}=1;
    }

    my $count=0;

    foreach my $key (keys %{$self->{titleid}}){
        $count++;
    }

    $logger->info("### $database: Gefundene Titel-ID's $count");

    %title_id       = get_title_hierarchy({ database => $database, title_id => \%titleid});

    $normdataid_ref = get_title_normdata({ database => $database, title_id => \%titleid});

    my %holdingid = ();

    # Exemplardaten *nur* vom entsprechenden Institut!
    $request=$dbh->prepare("select distinct id from holding where category=14 and content rlike ?") or $logger->error($DBI::errstr);
    $request->execute($signaturanfang);
    
    while (my $result=$request->fetchrow_hashref()){
        $holdingid{$result->{'id'}}=1;
    }    
    
    
    
}

sub get_title_hierarchy {
    my ($arg_ref) = @_;

    # Set defaults
    my $database       = exists $arg_ref->{database}
        ? $arg_ref->{database}              : undef;

    my $title_id_ref   = exists $arg_ref->{title_id}
        ? $arg_ref->{title_id}              : {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config;

    my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

    $logger->info("### $pool: Bestimme uebergeordnete Titel");

    my %tmp_titleid_super = %$title_id_ref;
    
    while (keys %tmp_titleid_super){
        my %found = ();
        
        foreach my $titidn (keys %tmp_titleid_super){
            
            # Ueberordnungen
            $request=$dbh->prepare("select distinct targetid from conn where sourceid=? and sourcetype=1 and targettype=1") or $logger->error($DBI::errstr);
            $request->execute($titidn) or $logger->error($DBI::errstr);;
            
            while (my $result=$request->fetchrow_hashref()){
                $title_id_ref->{$result->{'targetid'}} = 1;
                if ($titidn != $result->{'targetid'}){ # keine Ringschluesse - ja, das gibt es
                    $found{$result->{'targetid'}}   = 1;
                }
                
            }
            
        }
        
        %tmp_titleid_super = %found;
    }

    return \%title_id_ref;
}

sub get_title_normdata {
    my ($arg_ref) = @_;

    # Set defaults
    my $database   = exists $arg_ref->{database}
        ? $arg_ref->{database}              : undef;

    my $title_id_ref   = exists $arg_ref->{title_id}
        ? $arg_ref->{title_id}              : {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config;

    my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

    # IDN's der Autoren, Koerperschaften, Schlagworte, Notationen bestimmen

    $logger->debug("### $pool: Bestimme Normdaten");

    my $subjectid_ref        = {};
    my $personid_ref         = {};
    my $corporatebodyid_ref  = {};
    my $classificationid_ref = {};
    my $holdingid_ref        = {};

    foreach my $id (keys %$title_id_ref){
        
        # Verfasser/Personen
        my $request=$dbh->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=2") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $result=$request->fetchrow_hashref()){
            $personid_ref->{$result->{'targetid'}}=1;
        }
        
        # Urheber/Koerperschaften
        $request=$dbh->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=3") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $result=$request->fetchrow_hashref()){
            $corporatebodyid_ref->{$result->{'targetid'}}=1;
        }
        
        # Notationen
        $request=$dbh->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=5") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $result=$request->fetchrow_hashref()){
            $classificationid_ref->{$result->{'targetid'}}=1;
        }
        
        # Schlagworte
        $request=$dbh->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=4") or $logger->error($DBI::errstr);
        $request->execute($id);
        
        while (my $result=$request->fetchrow_hashref()){
            $subjectid_ref->{$result->{'targetid'}}=1;
        }
    }

    return {
        personid         => $personid_ref,
        corporatebodyid  => $corporatebodyid_ref,
        subjectid        => $subject_ref,
        classificationid => $classification_ref,
    };
}
