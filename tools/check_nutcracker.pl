#!/usr/bin/perl

#####################################################################
#
#  check_nutcracker.pl
#
#  Untersuchen der Nutcracker Stats
#
#  Dieses File ist (C) 2025 Oliver Flimm <flimm@openbib.org>
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
no warnings 'redefine';
use utf8;

use Date::Manip;
use Getopt::Long;
use IO::Socket::INET;
use JSON::XS;
use YAML;
use Log::Log4perl qw(get_logger :levels);
use Date::Parse;

use OpenBib::Config;

my $config = new OpenBib::Config;

my ($help,$logfile,$loglevel,$ejected,$timeout);

&GetOptions(
    "logfile=s"         => \$logfile,
    "loglevel=s"        => \$loglevel,
    "help"              => \$help
    );

if ($help){
    print_help();
}

$loglevel=($loglevel)?$loglevel:'ERROR';
$logfile=($logfile)?$logfile:'/var/log/openbib/check_nutcracker.log';

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

my $socket = new IO::Socket::INET (
    PeerHost => 'localhost',
    PeerPort => '22222',
    Proto => 'tcp',
    );

if($socket) {
    $socket->send('');
    my $buffer = "";
    my $length = 4096;
    $socket->recv($buffer,$length);
    my $json_ref = decode_json $buffer;

    my $server_ejects = $json_ref->{server_ejects};

    foreach my $server  ($config->get_serverinfo_overview->all){
	my $servername = $server->get_column('description');

	if ($json_ref->{openbib}{$servername}{server_ejected_at}){
	    my $when = $json_ref->{openbib}{$servername}{server_ejected_at};
	    print "ERROR: $servername ejected at $when\n";
	}

	if ($json_ref->{openbib}{$servername}{server_timedout}){
	    print "ERROR: $servername timed out ".$json_ref->{openbib}{$servername}{server_timedout}."\n";
	}

    }

    
}



sub print_help {
    print << "ENDHELP";
check_nutcracker - Untersuchen der Nutcracker Stats


   Optionen:
   -help                 : Diese Informationsseite
       
ENDHELP
    exit;
}
