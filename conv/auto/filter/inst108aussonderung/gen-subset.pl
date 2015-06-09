#!/usr/bin/perl

#####################################################################
#
#  gen-subset.pl
#
#  Extrahieren einer Titeluntermenge eines Katalogs anhand der
#  Kategorieinhalte fuer die Erzeugung eines separaten neuen Katalogs
#
#  Dieses File ist (C) 2005-2011 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;

use Getopt::Long;
use OpenBib::Catalog::Subset;

use Log::Log4perl qw(get_logger :levels);

#if ($#ARGV < 0){
#    print_help();
#}

my ($help,$id);

my $pool=$ARGV[0];

&GetOptions(
	    "help" => \$help
	    );

if ($help){
    print_help();
}

my $logfile='/var/log/openbib/split-$pool.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, LOGFILE, Screen
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

my $titleid_ref = {};
my $titleid_a_ref;
my $titleid_b_ref;

my $subset = new OpenBib::Catalog::Subset("inst108",$pool);

# Basis: Alle Titel bis 1970
$subset->titleid_by_field_content('title',[ { operator => '<=', field => '0425', content => '1970' } ]);
$titleid_ref = $subset->get_titleid;

# # Titel bis 1980 in Signaturgruppen FPO, QAO, R
$subset->set_titleid({}); # Flushen
$subset->titleid_by_field_content('title',[ { operator => '<=', field => '0425', content => '1980' } ]);
$titleid_a_ref = $subset->get_titleid;
$subset->set_titleid({}); # Flushen
$subset->titleid_by_field_content('holding',[ { field => '0014', content => '^FP0' },  { field => '0014', content => '^QA0' },  { field => '0014', content => '^R' } ]);
$titleid_b_ref = $subset->get_titleid;

foreach my $titleid (keys %$titleid_a_ref){
    if (defined $titleid_b_ref->{$titleid}){
        $titleid_ref->{$titleid} = 1;
    }
}

# # Titel bis 1990 in Signaturgruppen L
$subset->set_titleid({}); # Flushen
$subset->titleid_by_field_content('title',[ { operator => '<=', field => '0425', content => '1990' } ]);
$titleid_a_ref = $subset->get_titleid;
$subset->set_titleid({}); # Flushen
$subset->titleid_by_field_content('holding',[ { field => '0014', content => '^L' } ]);
$titleid_b_ref = $subset->get_titleid;

foreach my $titleid (keys %$titleid_a_ref){
    if (defined $titleid_b_ref->{$titleid}){
        $titleid_ref->{$titleid} = 1;
    }
}

# # Titel bis 2000 in Signaturgruppen N, T
$subset->set_titleid({}); # Flushen
$subset->titleid_by_field_content('title',[ { operator => '<=', field => '0425', content => '2000' } ]);
$titleid_a_ref = $subset->get_titleid;
$subset->set_titleid({}); # Flushen
$subset->titleid_by_field_content('holding',[ { field => '0014', content => '^N' },  { field => '0014', content => '^T' } ]);
$titleid_b_ref = $subset->get_titleid;

foreach my $titleid (keys %$titleid_a_ref){
    if (defined $titleid_b_ref->{$titleid}){
        $titleid_ref->{$titleid} = 1;
    }
}

$subset->set_titleid($titleid_ref);


my $count=0;

foreach my $key (keys %{$subset->{titleid}}){
    $count++;
}

$logger->info("### $subset->{source} -> $subset->{destination}: Gefundene Titel-ID's $count");

# Keine Ueberordnungen, da Weiterverarbeitung der ids in titel_exclude $subset->get_title_hierarchy;

$subset->get_title_normdata;

# Exemplardaten
# DBI: "select targetid from conn where sourceid=? and sourcetype=1 and targettype=6"

foreach my $id (keys %{$subset->{titleid}}){
    my $holdings = $subset->get_schema->resultset('TitleHolding')->search_rs(
        {
            'titleid' => $id,
        },
        {
            select   => ['holdingid'],
            as       => ['thisid'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    while (my $item = $holdings->next){
        my $thisid = $item->{thisid};
        
        $subset->{holdingid}{$thisid}=1;
    }    
}

$subset->write_set;

sub print_help {
    print "gen-subset.pl - Erzeugen von Kataloguntermengen\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n\n";

    exit;
}
