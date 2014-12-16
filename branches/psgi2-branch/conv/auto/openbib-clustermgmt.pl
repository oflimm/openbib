#!/usr/bin/perl

#####################################################################
#
#  openbib-clustermgmnt.pl
#
#  Cluster-Management: Umschalten der Cluster Aktualisierung<->Recherche
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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

use 5.008001;
use utf8;
use strict;
use warnings;

use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use OpenBib::Config;

my ($logfile,$loglevel);

&GetOptions(
            "logfile=s"     => \$logfile,
            "loglevel=s"    => \$loglevel,
	    );

my $config = OpenBib::Config->new;

$logfile=($logfile)?$logfile:"/var/log/openbib/openbib-clustermgmnt.log";
$loglevel=($loglevel)?$loglevel:"INFO";

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


$logger->info("###### Start Clustermanagement");

$logger->info("### Aktueller Cluster-Status");


my $update_clusterid;
my $search_clusterid;

my $clusterinfos = $config->get_clusterinfo_overview;

foreach my $cluster ($clusterinfos->all){
    if ($cluster->status eq "searchable"){
        $search_clusterid = $cluster->id;
    }
    else {
        $update_clusterid = $cluster->id;
    }
}

$logger->info("### Status des Update-Clusters mit Id $update_clusterid");

my $serverinfos = $config->get_serverinfo_overview;

my $server_updated = 0;

my @update_serverids = ();
my @search_serverids = ();

foreach my $server ($serverinfos->all){
    my $id        = $server->get_column('id');
    my $hostip    = $server->get_column('hostip');
    my $clusterid = $server->get_column('clusterid');
    my $status    = $server->get_column('status');
    my $active    = $server->get_column('active');

    next if (!$active);

    if ($clusterid == $update_clusterid){
        push @update_serverids, $id;
        
        if ($server->status eq "updated"){
            $logger->info("### Server $hostip updated");
            $server_updated++;
        }
        else {
            $logger->info("### Server-Status $hostip: $status");
        }
    }
    else {
        push @search_serverids, $id;
    }
}

my $complete_cluster_updated = ($server_updated == $#update_serverids+1)?1:0;

if ($complete_cluster_updated){
    $logger->info("### Tausch Update-Cluster <-> Recherche-Cluster");

#    foreach my $update_serverid (@update_serverids){
#        $config->update_server({ id => $update_serverid, status => "searchable"});
#    }

    $config->update_cluster({ id => $update_clusterid, status => "searchable" });

    sleep 20;

#    foreach my $search_serverid (@search_serverids){
#        $config->update_server({ id => $search_serverid, status => "updatable"});
#    }

    $config->update_cluster({ id => $search_clusterid, status => "updatable" });
}

$logger->info("###### Ende Clustermanagment");

