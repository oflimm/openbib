#!/usr/bin/perl
#####################################################################
#
#  process_mq_task.pl
#
#  Dieses File ist (C) 2026 Oliver Flimm <flimm@openbib.org>
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

use Encode qw/decode_utf8 encode_utf8/;
use JSON::XS qw( encode_json decode_json );
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use YAML;

use OpenBib::Config;
use OpenBib::MQ;

$SIG{'PIPE'} = 'IGNORE'; # Prevent SSL problem, see: https://metacpan.org/pod/Net::AMQP::RabbitMQ#connect(-%24hostname%2C-%24options-)

my ($help,$logfile,$loglevel);

GetOptions(
    'help'            => \$help,
    "loglevel=s"      => \$loglevel,
    "logfile=s"       => \$logfile,	    
    );

if ($help){
    print_help();
}

$logfile  = ($logfile)?$logfile:'/var/log/openbib/process_mq_task.log';
$loglevel = ($loglevel)?$loglevel:'INFO';

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

my $config = new OpenBib::Config;

my $mq = new OpenBib::MQ;

$logger->info("Waiting for messages");

while (1) {
    my $received_json_ref = $mq->consume_job({ queue => 'task_clusters'});    
    
    my $clusterid = $received_json_ref->{payload}{id};
    my $jobid     = $received_json_ref->{job_id};

    if ($clusterid && $jobid){
	$logger->info("Received payload for jobid $jobid and clusterid $clusterid-> ".YAML::Dump($received_json_ref));
	
	my $result_ref = $config->check_cluster_consistency($clusterid);
	
	if ($logger->is_info){
	    $logger->debug("Result is: ".YAML::Dump($result_ref));
	}
	
	$mq->set_result({ queue => 'task_clusters', job_id => $jobid, payload => $result_ref });
    }
}

sub print_help {
    print << "ENDHELP";
process_mq_task.pl - Verarbeitung von Auftraegen via RabbitMQ

   Optionen:
   -help                 : Diese Informationsseite
   --queue=...           : Queue-Namen, die bearbeitet werden
   --logfile=...         : Alternatives Logfile
   --loglevel=...        : Alternatives Logfile (default: INFO)

ENDHELP
    exit;
}
