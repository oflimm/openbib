#!/usr/bin/perl

#####################################################################
#
#  dbshortdesc2locationshortdesc.pl
#
#  Uebertragung der Kurzbezeichnungen von Datenbanken zu den damit verknuepften
#  Standorten
#
#  Dieses File ist (C) 2020 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;

use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

use Business::ISBN;
use DBIx::Class::ResultClass::HashRefInflator;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use YAML::Syck;

my $config      = OpenBib::Config->new;

my $logfile='/var/log/openbib/dbshortdesc2locationshortdesc.log';
my $loglevel='INFO';

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

my $dbshorts = $config->get_schema->resultset('Databaseinfo')->search(
    {
        'locationid.id' => { '>' => 0 },
	'me.dbname' => {'~' => '^inst'},    
    },
    {
	join         => ['locationid'],
	select       => ['me.shortdesc','locationid.id'],
	as           => ['thisshortdesc','thislocationid'],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
);

while (my $thisloc = $dbshorts->next()){
    my $shortdesc = $thisloc->{thisshortdesc};
    my $locationid = $thisloc->{thislocationid};
    my $col = 'shortdesc';
    
    my $location =  $config->get_schema->resultset('Locationinfo')->search(
	{
	    id => $locationid,
	},
	{
	}
	);

    print "Updating locationid $locationid with shortdesc $shortdesc\n";
    
    foreach my $oldlocation ($location->next()){
	print "Updating locationid $locationid with shortdesc $shortdesc\n";	
	$oldlocation->set_column($col => $shortdesc);
	$oldlocation->update;
    }
}
