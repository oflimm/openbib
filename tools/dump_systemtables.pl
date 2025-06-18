#!/usr/bin/perl
#####################################################################
#
#  dump_systemtables.pl
#
#  Export der Systemtabellen aus der System-DB
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
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
no warnings 'redefine';
use utf8;

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use Unicode::Collate;
use YAML;

use OpenBib::Config;
use OpenBib::Catalog;
use OpenBib::Schema::Catalog;
use OpenBib::Schema::System;
use OpenBib::Statistics;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::User;

my ($database,$help,$loglevel,$logfile);

&GetOptions(
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "help"            => \$help
    );

if ($help){
    print_help();    
}

$loglevel = ($loglevel)?$loglevel:"INFO";
$logfile  = ($logfile)?$logfile:'/var/log/openbib/dump_systemtables.log';

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

my $config     = OpenBib::Config->new;

my $pg_dump    = "/usr/bin/pg_dump";
my $gzip       = "/bin/gzip";
my $tar        = "/bin/tar";

my @system_tables = (
    'databaseinfo',
    'databaseinfo_searchengine',
    'locationinfo',
    'locationinfo_fields',
    'locationinfo_occupancy',
    'rssinfo',
    'profileinfo',
    'orgunitinfo',
    'orgunit_db',
    'viewinfo',
    'view_db',
    'view_rss',
    'view_location',
    'clusterinfo',
    'serverinfo',
    'userinfo',
    'user_searchlocation',
    'roleinfo',
    'role_view',
    'role_viewadmin',
    'role_right',
    'user_role',
    'user_db',
    'templateinfo',
    'user_template',
    'templateinforevision',
    'registration',
    'authtoken',
    'authenticatorinfo',
    'authenticator_view',
    'user_searchprofile',
    'searchfield',
    'livesearch',
    'user_cartitem',
    'tag',
    'tit_tag',
    'review',
    'reviewrating',
    'litlist',
    'litlistitem',
    'topic',
    'litlist_topic',
    'topicclassification',
    'dbrtopic',
    'dbistopic',
    'dbrtopic_dbistopic',
    'dbisdb',
    'dbistopic_dbisdb',
    'paia',
    );

my $table_string = join(' ', map { "-T $_"} @system_tables);

system("echo \"*:*:*:$config->{'systemdbuser'}:$config->{'systemdbpasswd'}\" > ~/.pgpass ; chmod 0600 ~/.pgpass");

system("$pg_dump -U $config->{'systemdbuser'} -h $config->{'systemdbhost'} -c $table_string openbib_system | $gzip > system_tables.sql.gz");

sub print_help {
    print << "ENDHELP";
dump_systemtables.pl - Export der Systemtabellen aus der System-DB

   Optionen:
   -help                 : Diese Informationsseite
   --logfile=...         : Alternatives Logfile
   --loglevel=...        : Alternatives Loglevel
ENDHELP
    exit;
}

