#!/usr/bin/perl

#####################################################################
#
#  openbib-autocron.pl
#
#  CRON-Job zum automatischen aktualisieren aller OpenBib-Datenbanken
#
#  Dieses File ist (C) 1997-2013 Oliver Flimm <flimm@openbib.org>
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
use threads;
use threads::shared;

use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use OpenBib::Config;

our ($logfile,$loglevel,$test,$cluster,$maintenance,$updatemaster);

&GetOptions(
    "cluster"       => \$cluster,
    "test"          => \$test,
    "maintenance"   => \$maintenance,
    "logfile=s"     => \$logfile,
    "loglevel=s"    => \$loglevel,
    "update-master" => \$updatemaster,
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

my $blacklist_enrichmnt_ref = {
    'bestellungen' => 1,
};

my $blacklist_ref = {
    'alekiddr' => 1,
    'edz' => 1,
    'lehrbuchsmlg' => 1,
    'rheinabt' => 1,
    'inst001' => 1,
    'lesesaal' => 1,
    'wiso' => 1,
    'econbiz' => 1,
    'inst301' => 1,
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
    'inst420master' => 1,
    'inst420' => 1,
    'inst421' => 1,
    'inst422' => 1,
    'inst423' => 1,
    'openlibrary' => 1,
};

$logger->info("###### Starting automatic update");

if ($cluster){
    if ($config->local_server_belongs_to_updatable_cluster()){
        $logger->info("### Updating in cluster mode");
        $logger->info("### Changing server-status to updating");
        $config->update_local_serverstatus("updating");
        $logger->info("### Changing cluster-status to updating");
        $config->update_local_clusterstatus("updating");
    }
    else {
        $logger->info("### Local server is not updatable. Exiting.");
        exit;
    }
}

$logger->info("### Restarting Apache");

system("sudo /etc/init.d/apache2 restart");

my @threads;

if ($test){
    push @threads, threads->new(\&threadTest,'Testkatalog');
}
else {
    push @threads, threads->new(\&threadA,'Einzelne Kataloge');
    push @threads, threads->new(\&threadB,'Abhaengige Kataloge');
}

foreach my $thread (@threads) {
    my $thread_description = $thread->join;
    $logger->info("### -> done with $thread_description");
}

$logger->info("### Generating joined searchindexes");

system("/opt/openbib/autoconv/bin/autojoinindex_xapian.pl");

if ($cluster){
    $logger->info("### Changing cluster/server-status to updated");
    $config->update_local_serverstatus("updated");
}

$logger->info("###### Updating done");

if ($updatemaster && $maintenance){
    $logger->info("### Updating clouds");
    
    foreach my $thistype (qw/2 8 10 11 12 13/){
        system("$config->{'base_dir'}/bin/gen_metrics.pl --type=$thistype");
    }
}
                                    
if ($maintenance){
    $logger->info("### Enriching USB BK's");
    
    system("$config->{'base_dir'}/conv/usb_bk2enrich.pl");

    $logger->info("### Dumping Enrichment-DB");
    
    system("$config->{'base_dir'}/bin/dump_enrichmnt.pl");
    
    $logger->info("###### Maintenance done");
}

sub threadA {
    my $thread_description = shift;

    $logger->info("### -> Aufgesplittete Kataloge");

    $logger->info("### VUBPDA");

    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['vubpda'] });

    ##############################

    $logger->info("### Standard-Institutskataloge");

    autoconvert({ updatemaster => $updatemaster, blacklist => $blacklist_ref, sync => 1, autoconv => 1});

    return $thread_description;
}

sub threadB {
    my $thread_description = shift;
    
    $logger->info("### -> Abhaengige Kataloge");

    $logger->info("### Master: USB Katalog");
    
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['inst001'] });
    
    ##############################
    
    $logger->info("### Aufgesplittete Teil-Kataloge aus USB Katalog");
    
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['lehrbuchsmlg','rheinabt','edz','lesesaal', 'wiso','usbsab','usbhwa'] });
    
    ##############################
    
    $logger->info("### Aufgesplittete Sammlungen aus dem USB Katalog");
    
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['afrikaans','alff','baeumker','becker','dante','digitalis','dirksen','evang','fichte','gabel','gruen','gymnasialbibliothek','islandica','kbg','kempis','kroh','lefort','loeffler','mukluweit','modernedtlit','modernelyrik','nevissen','oidtman','ostasiatica','quint','schia','schirmer','schmalenbach','schneider','syndikatsbibliothek','thorbecke','tietz','tillich','vormweg','wallraf','weinkauff','westerholt','wolff'] });
    
    ##############################

    $logger->info("### Master: inst301");
    
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['inst301'] });
    
    ##############################
    
    $logger->info("### Aufgesplittete Kataloge inst301");
    
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['inst303','inst304','inst305','inst306','inst307','inst308','inst309','inst310','inst311','inst312','inst313','inst314','inst315','inst319','inst320','inst321','inst324','inst325'] });

    ##############################

    $logger->info("### Master: inst420master");
    
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['inst420master'] });

    ##############################
    
    $logger->info("### Aufgesplittete Kataloge inst420");
    
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['inst420','inst421','inst422','inst423'] });
    
    ##############################

    $logger->info("### Master: inst323, inst137");
    
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['inst323','inst137'] });

    ##############################
    
    $logger->info("### Sammlungen aus dem Universitaet");
    
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['alekiddr','digitalis'] });
    
    ##############################
    

    return $thread_description;
}

sub threadTest {
    my $thread_description = shift;

    $logger->info("### -> Testkatalog");

    $logger->info("### Openbib");

    autoconvert({ updatemaster => $updatemaster, databases => ['openbib'] });

    return $thread_description;
}

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

    my $updatemaster    = exists $arg_ref->{updatemaster}
        ? $arg_ref->{updatemaster}          : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();


    push @ac_cmd, "/opt/openbib/autoconv/bin/autoconv.pl";
    push @ac_cmd, "-sync"    if ($sync); 
    push @ac_cmd, "-gen-mex" if ($genmex);
    push @ac_cmd, "-update-master" if ($updatemaster);

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

        if ($maintenance && !defined $blacklist_enrichmnt_ref->{$database}){
            $logger->info("### Enriching subject headings for all institutes");
            system("$config->{'base_dir'}/conv/swt2enrich.pl --database=$database");
        }
    }
}
