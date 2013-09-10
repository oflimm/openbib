#!/usr/bin/perl
#####################################################################
#
#  zmslibinfo2configdb.pl
#
#  Automatisierte Uebernahme der Informationen des Bibliotheksfuehrers
#  aus ZMS und Einspielung in die locationinfo-Tabelle der System-Datenbank
#
#  Dieses File ist (C) 2009-2012 Oliver Flimm <flimm@openbib.org>
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
use Encode qw/decode encode_utf8/;
use OpenBib::Config;
use OpenBib::Schema::DBI;
use URI::Escape;

my $database=$ARGV[0];

my $config = OpenBib::Config->instance;

my $s = scraper {
  process 'table.ZMSTable tr td ' => 'zeilen[]'   => 'HTML';
};

my $field_map_ref = {
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
    'Bestand Monographien'  => '120',
    'Bestand Zeitschriften'  => '130',        
    'Bestand (Bände)'  => '120',
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
    'Online-Katalogisierung' => '230',
    'Online-Katalogisierung seit Erwerbungsjahr' => '235',
    'Mitarbeit am KUG' => '240',
    'Sigel in ZDB' => '250',
    'Bemerkung' => '270',
    'Geo-Position (Bg,Lg)' => '280',
};

foreach my $dbinfo ($config->get_dbinfo_overview->all){
    
    next unless ($dbinfo->url=~/bibliotheksfuehrer/);

    my $url         = $dbinfo->url;
    my $dbname      = $dbinfo->dbname;
    my $description = $dbinfo->description;
    my $location    = $dbinfo->locationid;
    my $sigel       = $dbinfo->sigel;

    if ($database && $dbname ne $database){
        next;
    }

    print "### $dbname : ".$dbinfo->description."\n";
    my $content = URI->new($url);

    my $r;
    eval {
        $r = $s->scrape($content);
    };

    next if ($@);

    if (!$location){
        my $identifier = "DE-38-$sigel";
        my $type       = "ISIL";

        if ($dbname !~m/^inst[0-9][0-9][0-9]/){
            $identifier = $dbname;
            $type = "Generic";
        }

        $location = $config->{schema}->resultset("Locationinfo")->create(
            {
                identifier    => $identifier,
                type          => $type,
                tstamp_create => \'NOW()',
                description   => $description,
            }
        );
        
        $dbinfo->update({locationid => $location->id });
    }
    
    $location->locationinfo_fields->delete;

    my $fields_ref = [];
    
    my @inhalt = @{$r->{zeilen}};
    
    for ($i=0;$i< $#inhalt;$i=$i+2){
        my ($field,$content);
        $field = decode("latin1",$inhalt[$i]);
        
        eval {
            $content  = decode("latin1",$inhalt[$i+1]);
        };
        if ($@){
            $content = $inhalt[$i+1];
        }
        $field = $inhalt[$i];
        $content  = $inhalt[$i+1];
        
        #        print "Content pre:$content:\n";
        $field =~s{\</*p\>}{}g;
        $field =~s{\<br.*?>}{}g;
        $field =~s{^\s+}{}g;
        #        $content =~s/<br \/>//g;
        $content =~s{\</p>\<p\>}{<br/>}g;
        $content =~s{\</*p\>}{}g;
        $content =~s{\<br \/>$}{}g;
        $content  =~s/^\s+//g;
        $content  =~s/\s+$//g;
        #        print "Content post:$content:\n";
        
        $num_field = $field_map_ref->{$field};
        
        if ($num_field){
            if ($num_field eq "120" && ($content =~/(\d+)\s+Mono/ || $content =~/(\d+)\s+Zeitschr/) ){
                my ($num_monos)    = $content =~/(\d+)\s+Mono/;
                my ($num_zeitschr) = $content =~/(\d+)\s+Zeitsch/;
                
                if ($num_monos){
                    push @$fields_ref,
                        {
                            field   => 120,
                            mult    => 1,
                            content => $num_monos,
                        };
                }
                if ($num_zeitschr){
                    push @$fields_ref,
                        {
                            field   => 130,
                            mult    => 1,
                            content => $num_zeitschr,
                        };
                }
                if (!$num_monos && !$num_zeitschr){
                    push @$fields_ref,
                        {
                            field   => 120,
                            mult    => 1,
                            content => $content,
                        };
                }
                
            }
            elsif ($num_field eq "120" || $num_field eq "130" || $num_field eq "140"){
                #            $content =~s/(\D+)//g;
                push @$fields_ref,
                    {
                        field   => $num_field,
                        mult    => 1,
                        content => $content,
                    };
            }
            else {
                push @$fields_ref,
                    {
                        field   => $num_field,
                        mult    => 1,
                        content => $content,
                    };
            }
        }
        print ":$field: / :$num_field: - :$content:\n";
    }
    
    $location->locationinfo_fields->populate($fields_ref);
}

