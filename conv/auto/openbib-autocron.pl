#!/usr/bin/perl

#####################################################################
#
#  openbib-autocron.pl
#
#  CRON-Job zumr automatischen aktualisieren aller OpenBib-Datenbanken
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

$logfile=($logfile)?$logfile:"/var/log/openbib/openbib-autocron.log";
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


my $blacklist_ref = {
    'edz' => 1,
    'lehrbuchsmlg' => 1,
    'rheinabt' => 1,
    'inst001' => 1,
    'lesesaal' => 1,
    'wiso' => 1,
    'econbiz' => 1,
    'inst303' => 1,
    'inst304' => 1,
    'inst305' => 1,
    'inst306' => 1,
    'inst307' => 1,
    'inst308' => 1,
    'inst309' => 1,
    'inst310' => 1,
    'inst311' => 1,
    'inst312' => 1,
    'inst313' => 1,
    'inst314' => 1,
    'inst315' => 1,
    'inst316' => 1,
    'inst317' => 1,
    'inst318' => 1,
    'inst319' => 1,
    'inst320' => 1,
    'inst321' => 1,
    'inst324' => 1,
    'inst325' => 1,
    'inst420' => 1,
    'inst421' => 1,
    'inst422' => 1,
    'inst423' => 1,
    'openlibrary' => 1,    
};

$logger->info("###### Beginn der automatischen Konvertierung");

##############################

$logger->info("### Standard-Institutskataloge");

autoconvert({ blacklist => $blacklist_ref, sync => 1, genmex => 1, autoconv => 1});

##############################

$logger->info("### Aufgesplittete Kataloge inst301");

autoconvert({ sync => 1, databases => ['inst303','inst304','inst305','inst306','inst307','inst308','inst309','inst310','inst311','inst312','inst313','inst314','inst315','inst316','inst317','inst318','inst319','inst320','inst321','inst324','inst325'] });

##############################

$logger->info("### Aufgesplittete Kataloge inst420");

autoconvert({ sync => 1, databases => ['inst420','inst421','inst422','inst423'] });

##############################

$logger->info("### Katalog der USB");

autoconvert({ sync => 1, databases => ['inst001'] });

##############################

$logger->info("### Aufgesplittete Kataloge aus USB Katalog");

autoconvert({ sync => 1, databases => ['lehrbuchsmlg','rheinabt','edz','lesesaal', 'wiso', 'islandica'] });

##############################

$logger->info("###### Ende der automatischen Konvertierung");

sub autoconvert {
    my ($arg_ref) = @_;

    my @ac_cmd = ();
    
    # Set defaults
    my $blacklist_ref   = exists $arg_ref->{blacklist}
        ? $arg_ref->{blacklist}             : {};

    my $databases_ref   = exists $arg_ref->{databases}
        ? $arg_ref->{databases}             : [];

    my $sync            = exists $arg_ref->{sync}
        ? $arg_ref->{sync}                  : 0;

    my $genmex          = exists $arg_ref->{genmex}
        ? $arg_ref->{genmex}                : 0;

    my $autoconv        = exists $arg_ref->{autoconv}
        ? $arg_ref->{autoconv}              : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();


    push @ac_cmd, "/opt/openbib/autoconv/bin/autoconv.pl";
    push @ac_cmd, "-sync"    if ($sync); 
    push @ac_cmd, "-gen-mex" if ($genmex);

    my $ac_cmd_base = join(' ',@ac_cmd);

    my @databases = ();

    if (@$databases_ref){
        push @databases, @$databases_ref;
    }

    if ($autoconv){
        my $dbinfo = $config->get_databaseinfo->search(
            {
                'autoconvert' => 1,
            },
            {
                order_by => 'dbname',
            }
        );
        foreach my $item ($dbinfo->all){
            push @databases, $item->dbname;
        }
    }
  
    foreach my $database (@databases){
        if (exists $blacklist_ref->{$database}){
            $logger->info("Katalog $database auf Blacklist");
            next;
        }
        
        my $this_cmd = "$ac_cmd_base --database=$database";
        $logger->info("Konvertierung von $database");
        $logger->info("Ausfuehrung von $this_cmd");
        system($this_cmd);
    }
}
