#!/usr/bin/perl

#####################################################################
#
#  updatetitcount.pl
#
#  Aktualisierung der Information ueber die Titelanzahl in den
#  Katalogen
#
#  Dieses File ist (C) 2003-20012 Oliver Flimm <flimm@openbib.org>
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
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Database::Catalog;

# Definition der Programm-Optionen
my ($database,$logfile);

&GetOptions(
    "database=s" => \$database,
    "logfile=s"  => \$logfile,    
);

$logfile=($logfile)?$logfile:'/var/log/openbib/updatetitcount.log';

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

my $config = OpenBib::Config->instance;

my @databases=();

# Wenn ein Katalog angegeben wurde, werden nur in ihm die Titel gezaehlt
# und der Counter aktualisiert

if ($database ne ""){
    @databases=("$database");
}
# Ansonsten werden alle als Aktiv markierten Kataloge aktualisiert
else {
    @databases = $config->get_active_databases();
}

my ($allcount,$journalcount,$articlecount,$digitalcount)=(0,0,0,0);

foreach $database (@databases){
    my $schema;

    if ($config->{dbimodule} eq "Pg"){
        eval {
            # UTF8: {'pg_enable_utf8'    => 1}
            $schema = OpenBib::Database::Catalog->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},{'pg_enable_utf8'    => 1}) or $logger->error($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $database: DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}");
            next;
        }
    }
    elsif ($config->{dbimodule} eq "mysql"){
        eval {
            # UTF8: {'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}
            $schema = OpenBib::Database::Catalog->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $database: DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}");
            next;
        }
    }
    
    # Gesamt-Titelzahl bestimmen;
    my $allcount = $schema->resultset('Title')->count;

    # Serien/Zeitschriften bestimmen
    # DBI "select count(distinct id) as rowcount from title where category=800 and content = 'Zeitschrift/Serie'"
    my $journalcount = $schema->resultset('TitleField')->search(
        {
            'field'                   => '0800',
            'content'                 => 'Zeitschrift/Serie',
        },
        {
            select   => ['titleid'],
            as       => ['thistitleid'], 
            group_by => ['titleid'], # via group_by und nicht via distinct (Performance)
            
        }
    )->count;

    # Aufsaetze bestimmen
    # DBI "select count(distinct id) as rowcount from title where category=800 and content = 'Aufsatz'"
    my $articlecount = $schema->resultset('TitleField')->search(
        {
            'field'                   => '0800',
            'content'                 => 'Aufsatz',
        },
        {
            select   => ['titleid'],
            as       => ['thistitleid'], 
            group_by => ['titleid'], # via group_by und nicht via distinct (Performance)
            
        }
    )->count;
    
    # E-Median bestimmen
    # DBI "select count(distinct id) as rowcount from title where category=800 and content = 'Digital'"
    my $digitalcount = $schema->resultset('TitleField')->search(
        {
            'field'                   => '0800',
            'content'                 => 'Digital',
        },
        {
            select   => ['titleid'],
            as       => ['thistitleid'], 
            group_by => ['titleid'], # via group_by und nicht via distinct (Performance)
            
        }
    )->count;

    # DBI "update databaseinfo set allcount = ?, journalcount = ?, articlecount = ?, digitalcount = ? where dbname=?"
    $config->update_databaseinfo(
        {
            dbname       => $database,
            
            allcount     => $allcount,
            journalcount => $journalcount,
            articlecount => $articlecount,
            digitalcount => $digitalcount,
        }
    );
  
    $logger->info("$database -> $allcount / $journalcount / $articlecount / $digitalcount");
  
}
