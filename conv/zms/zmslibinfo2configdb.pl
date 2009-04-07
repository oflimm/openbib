#!/usr/bin/perl
#####################################################################
#
#  zmslibinfo2configdb.pl
#
#  Automatisierte Uebernahme der Informationen des Bibliotheksfuehrers
#  aus ZMS und Einspielung in die libraryinfo-Tabelle der config-Datenbank
#
#  Dieses File ist (C) 2009 Oliver Flimm <flimm@openbib.org>
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

use utf8;
use URI;
use YAML;
use Web::Scraper;
use Encode qw/decode/;
use OpenBib::Config;
use OpenBib::Database::DBI;
use URI::Escape;

my $config = OpenBib::Config->instance;

# Verbindung zur SQL-Datenbank herstellen
my $dbh
    = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
    or $logger->error_die($DBI::errstr);

my $s = scraper {
  process 'table.ZMSTable tr td ' => 'zeilen[]'   => 'HTML';
};

my $category_map_ref = {
    'Institutsname' => '10',
    'Straße' => '20',
    'Gebäude' => '30',
    'Interaktiver Lageplan der Universität' => '40',
    'Gemeinsame Bibliothek' => '50',
    'Telefon' => '60',
    'Fax' => '70',
    'E-Mail' => '80',
    'Internet' => '90',
    'Auskunft / Bibliothekar(in)' => '100',
    'Öffnungszeiten' => '110',
    'Bestand'  => '120',
    'Anzahl laufender Zeitschriften' => '140',
    'CDs / Digitale Medien' => '150',
    'Sonstige Bestandsangaben' => '160',
    'Besondere Sammelgebiete' => '170',
    'Art der Bibliothek' => '180',
    'Neuerwerbungslisten' => '190',
    'Kopierer / Technische Ausstattung' => '200',
    'Art der Vernetzung' => '260',
    'DV-Ausstattung' => '210',
    'Art des Systems' => '220',
    'Online-Katalogisierung seit Erscheinungsjahr' => '230',
    'Online-Katalogisierung seit Erwerbungsjahr' => '235',
    'Mitarbeit am KUG' => '240',
    'Sigel in ZDB' => '250',
};

my $dboverview_ref = $config->get_dbinfo_overview();
foreach my $katalog_ref (@$dboverview_ref){
    
    next unless ($katalog_ref->{url}=~/bibliotheksfuehrer/);

    my $url    = $katalog_ref->{url};
    my $dbname = $katalog_ref->{dbname};

    print "### $dbname : $katalog_ref->{description}\n";
    my $content = URI->new($url);

    my $r;
    eval {
        $r = $s->scrape($content);
    };

    next if ($@);
    
    my $del_request = $dbh->prepare("delete from libraryinfo where dbname = ? and category < 1000");
    $del_request->execute($dbname);
    
    my $request = $dbh->prepare("insert into libraryinfo values (?,?,NULL,?)");
    my @inhalt = @{$r->{zeilen}};
    
    for ($i=0;$i< $#inhalt;$i=$i+2){
        my ($category,$content);
        $category = decode("latin1",$inhalt[$i]);

        eval {
            $content  = decode("latin1",$inhalt[$i+1]);
        };
        if ($@){
            $content = $inhalt[$i+1];
        }
        my $category = $inhalt[$i];
        my $content  = $inhalt[$i+1];
        
        $category =~s{\</*p\>}{}g;
        $content =~s{\</p>\<p\>}{<br/>}g;
        $content =~s{\</*p\>}{}g;
        $num_category = $category_map_ref->{$category};

        if ($num_category eq "120"){
            my ($num_monos)    = $content =~/(\d+)\s+Mono/;
            my ($num_zeitschr) = $content =~/(\d+)\s+Zeitsch/;

            if ($num_monos){
                $request->execute($dbname,120,$num_monos);
            }
            if ($num_zeitschr){
                $request->execute($dbname,130,$num_zeitschr);
            }
            if (!$num_monos && !$num_zeitschr){
                $request->execute($dbname,120,$content);
            }
            
        }       
        else {
            $request->execute($dbname,$num_category,$content);
        }
        print "$category / $num_category : $content\n";
    }
}

