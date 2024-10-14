#!/usr/bin/perl

#####################################################################
#
#  openbib-autocron.pl
#
#  CRON-Job zum automatischen aktualisieren aller OpenBib-Datenbanken
#
#  Dieses File ist (C) 1997-2024 Oliver Flimm <flimm@openbib.org>
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

our ($logfile,$loglevel,$test,$cluster,$maintenance,$updatemaster,$incremental,$genzsst,$zsstdir);

&GetOptions(
    "cluster"       => \$cluster,
    "test"          => \$test,
    "maintenance"   => \$maintenance,
    "incremental"   => \$incremental,
    "logfile=s"     => \$logfile,
    "loglevel=s"    => \$loglevel,
    "gen-zsst"      => \$genzsst,
    "zsstdir=s"     => \$zsstdir,    
    "update-master" => \$updatemaster,
    );

my $config = OpenBib::Config->new;

$logfile=($logfile)?$logfile:"/var/log/openbib/openbib-autocron-full.log";
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

my $denylist_enrichmnt_ref = {
    'bestellungen' => 1,
};

my $denylist_ref = {
    'alekiddr' => 1,
    'doab' => 1,
    'dreierpda' => 1,
    'ebookpda' => 1,
    'econbiz' => 1,
    'edz' => 1,
    'emedienkauf' => 1,
    'gentzdigital' => 1,
    'inst001' => 1,
    'inst005' => 1,
    'inst005master' => 1,
    'inst006' => 1,
    'inst006master' => 1,
    'inst007' => 1,
    'inst007master' => 1,
    'inst102' => 1,
    'inst102master' => 1,
    'inst103' => 1,
    'inst103master' => 1,
    'inst105' => 1,
    'inst105master' => 1,
    'inst108' => 1,
    'inst108master' => 1,
    'inst110' => 1,
    'inst110master' => 1,
    'inst112' => 1,
    'inst112master' => 1,
    'inst113' => 1,
    'inst113master' => 1,
    'inst118' => 1,
    'inst118master' => 1,
    'inst119' => 1,
    'inst119master' => 1,
    'inst123' => 1,
    'inst123master' => 1,
    'inst125' => 1,
    'inst125master' => 1,
    'inst128' => 1,    
    'inst128master' => 1,
    'inst132' => 1,
    'inst132master' => 1,
    'inst134' => 1,
    'inst134master' => 1,
    'inst136' => 1,
    'inst136master' => 1,
    'inst137' => 1,
    'inst146' => 1,
    'inst146master' => 1,
    'inst156' => 1,
    'inst156master' => 1,
    'inst157' => 1,
    'inst157master' => 1,
    'inst166' => 1,
    'inst166master' => 1,
    'inst201' => 1,
    'inst201master' => 1,
    'inst203' => 1,
    'inst203master' => 1,
    'inst204' => 1,
    'inst204' => 1,    
    'inst204master' => 1,
    'inst204master' => 1,    
    'inst205' => 1,    
    'inst205master' => 1,    
    'inst206' => 1,
    'inst206master' => 1,    
    'inst207' => 1,    
    'inst207master' => 1,    
    'inst208' => 1,    
    'inst208master' => 1,    
    'inst209' => 1,    
    'inst209master' => 1,    
    'inst210' => 1,    
    'inst210master' => 1,    
    'inst211' => 1,    
    'inst211master' => 1,    
    'inst212' => 1,    
    'inst212master' => 1,    
    'inst213' => 1,    
    'inst213master' => 1,    
    'inst214' => 1,    
    'inst214master' => 1,    
    'inst215' => 1,    
    'inst215master' => 1,    
    'inst216' => 1,    
    'inst216master' => 1,    
    'inst217' => 1,    
    'inst217master' => 1,    
    'inst218' => 1,    
    'inst218master' => 1,    
    'inst219' => 1,    
    'inst219master' => 1,    
    'inst221' => 1,    
    'inst221master' => 1,    
    'inst222' => 1,    
    'inst222master' => 1,    
    'inst223' => 1,    
    'inst223master' => 1,    
    'inst225' => 1,    
    'inst225master' => 1,    
    'inst226' => 1,    
    'inst226master' => 1,    
    'inst228' => 1,    
    'inst228master' => 1,    
    'inst230' => 1,    
    'inst230master' => 1,    
    'inst231' => 1,    
    'inst231master' => 1,    
    'inst234' => 1,    
    'inst234master' => 1,    
    'inst237' => 1,    
    'inst237master' => 1,    
    'inst301' => 1,
    'inst301retro' => 1,
    'inst302' => 1,
    'inst302master' => 1,
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
    'inst323' => 1,
    'inst323master' => 1,
    'inst324' => 1,
    'inst325' => 1,
    'inst404' => 1,
    'inst404master' => 1,
    'inst405' => 1,
    'inst405master' => 1,
    'inst406' => 1,
    'inst406master' => 1,
    'inst407' => 1,
    'inst407master' => 1,
    'inst409' => 1,
    'inst409master' => 1,
    'inst410' => 1,
    'inst410master' => 1,
    'inst411' => 1,
    'inst411master' => 1,
    'inst412' => 1,
    'inst412master' => 1,
    'inst413' => 1,
    'inst413master' => 1,
    'inst414' => 1,
    'inst414master' => 1,
    'inst416' => 1,
    'inst416master' => 1,
    'inst418' => 1,
    'inst418master' => 1,
    'inst419' => 1,
    'inst419master' => 1,
    'inst420' => 1,
    'inst420master' => 1,
    'inst420retro' => 1,
    'inst421' => 1,
    'inst422' => 1,
    'inst423' => 1,
    'inst424' => 1,
    'inst426' => 1,
    'inst426master' => 1,
    'inst427' => 1,
    'inst427master' => 1,
    'inst428' => 1,
    'inst428master' => 1,
    'inst429' => 1,
    'inst429master' => 1,
    'inst430' => 1,
    'inst430master' => 1,
    'inst431' => 1,
    'inst431master' => 1,
    'inst432' => 1,
    'inst432master' => 1,
    'inst434' => 1,
    'inst434master' => 1,
    'inst437' => 1,
    'inst437master' => 1,
    'inst438' => 1,
    'inst438master' => 1,
    'inst444' => 1,
    'inst444master' => 1,
    'inst445' => 1,
    'inst445master' => 1,
    'inst448' => 1,
    'inst448master' => 1,
    'inst460' => 1,
    'inst460master' => 1,
    'inst461' => 1,
    'inst461master' => 1,
    'inst464' => 1,
    'inst464master' => 1,
    'inst466' => 1,
    'inst466master' => 1,
    'inst467' => 1,
    'inst467master' => 1,
    'inst468' => 1,
    'inst468master' => 1,
    'inst501' => 1,
    'inst501master' => 1,
    'inst503' => 1,
    'inst503master' => 1,
    'inst514' => 1,
    'inst514master' => 1,
    'inst526' => 1,
    'inst526master' => 1,
    'inst622' => 1,
    'inst622master' => 1,
    'inst623' => 1,
    'inst623master' => 1,
    'kups'     => 1,
    'lehrbuchsmlg' => 1,
    'lesesaal' => 1,
    'oapen' => 1,
    'openlibrary' => 1,
    'gesiskoeln' => 1,
    'proquestpda' => 1,
    'rheinabt' => 1,
    'rheinabt' => 1,
    'roemkepda' => 1,
    'schweitzerpda' => 1,
    'tmpebooks' => 1,
    'uni' => 1,
    'usbebooks' => 1,
    'usbhwa' => 1,
    'usblbs' => 1,
    'usbls' => 1,
    'usbsab' => 1,
    'uzkzeitschriften' => 1,
    'wiso' => 1,
};

$logger->info("###### Starting automatic update");

$logger->info("### Restarting starman");

system("/usr/bin/sudo /usr/bin/systemctl restart starman.service");
#system("/etc/init.d/starman stop ; pkill -9 starman  ; /etc/init.d/starman start");

if ($cluster){
    if ($config->local_server_belongs_to_updatable_cluster()){
        $logger->info("### Updating in cluster mode");
        $logger->info("### Changing server-status to updating");
        $config->update_local_serverstatus("updating");
        if ($config->all_servers_of_local_cluster_have_status('updating')){
            $logger->info("### Changing cluster-status to updating");
            $config->update_local_clusterstatus("updating");
        }
    }
    else {
        $logger->info("### Local server is not updatable. Exiting.");
        exit;
    }
}

$logger->info("### Offene Bestellungen vorziehen");

autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['bestellungen'] });

my @threads;

if ($test){
    push @threads, threads->new(\&threadTest,'Testkatalog');
}
else {
    push @threads, threads->new(\&threadA,'Thread 1');
    push @threads, threads->new(\&threadB,'Thread 2');
    push @threads, threads->new(\&threadC,'Thread 3');
}

foreach my $thread (@threads) {
    my $thread_description = $thread->join;
    $logger->info("### -> done with $thread_description");
}

$logger->info("### Offene Bestellungen");

autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['bestellungen'] });

##############################

#$logger->info("### EBOOKPDA");

#autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['proquestpda'] });

##############################

$logger->info("### PRINTPDA");

autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['dreierpda','schweitzerpda','roemkepda'] });

##############################

$logger->info("###### Updating done");

if ($cluster){
    $logger->info("### Changing cluster/server-status to updated");
    $config->update_local_serverstatus("updated");
}

$logger->info("### Generating joined searchindexes");

system("/opt/openbib/autoconv/bin/autojoinindex_xapian.pl");
system("/opt/openbib/autoconv/bin/autojoinindex_elasticsearch.pl");

if ($genzsst){
    $logger->info("### Generating journal catalog");    
    autoconvert({ incremental => $incremental, updatemaster => $updatemaster, sync => 1, databases => ['uzkzeitschriften'] });

    $logger->info("### Generating journal lists");        
    
    system("/opt/openbib/bin/gen_zsstlist-all.pl $zsstdir > /tmp/gen_zsstlist-all.log 2>&1");
}
    
$logger->info("### Dumping isbns");

system("cd /var/www.opendata/dumps/isbns/by_view ; /opt/openbib/bin/get_isbns.pl --view=warenkorb_usb 2>&1 > /dev/null");
system("cd /var/www.opendata/dumps/isbns/by_view ; /opt/openbib/bin/get_isbns.pl --view=warenkorb_kmb 2>&1 > /dev/null");
system("cd /var/www.opendata/dumps/isbns/by_view ; /opt/openbib/bin/get_isbns.pl --view=warenkorb_uni 2>&1 > /dev/null");
system("cd /var/www.opendata/dumps/isbns/by_view ; /opt/openbib/bin/get_isbns.pl --view=warenkorb_komplett 2>&1 > /dev/null");
# system("cd /var/www.opendata/dumps/isbns/by_view ; /opt/openbib/bin/get_isbns.pl --view=abgleich_ebookpda 2>&1 > /dev/null");
 system("cd /var/www.opendata/dumps/isbns/by_view ; /opt/openbib/bin/get_isbns.pl --view=warenkorb_komplett_ohne_tmpebooks 2>&1 > /dev/null");
# system("cd /var/www.opendata/dumps/isbns/by_view ; /opt/openbib/bin/get_isbns.pl --view=warenkorb_komplett_ohne_proquestpda 2>&1 > /dev/null");
system("cd /var/www.opendata/dumps/isbns/by_view ; /opt/openbib/bin/get_isbns.pl --view=tmpebooks 2>&1 > /dev/null");
system("cd /var/www.opendata/dumps/isbns/by_view ; /opt/openbib/bin/get_isbns.pl --view=emedienkauf 2>&1 > /dev/null");

# $logger->info("### Finding corresponding ebooks in inst526/inst006");

# system("/opt/openbib/bin/bestandsabgleich.pl --selector=ISBN13 --database=inst526 --database=usbebooks --filename=/var/www.kug/extra/inst526/abgleich-inst526-usbebooks.csv 2>&1 > /dev/null");
# system("/opt/openbib/bin/bestandsabgleich.pl --selector=ISBN13 --database=inst526 --database=tmpebooks --filename=/var/www.kug/extra/inst526/abgleich-inst526-tmpebooks.csv 2>&1 > /dev/null");
# system("/opt/openbib/bin/bestandsabgleich.pl --selector=ISBN13 --database=inst006 --database=usbebooks --filename=/var/www.kug/extra/inst006/abgleich-inst006-usbebooks.csv 2>&1 > /dev/null");
# system("/opt/openbib/bin/bestandsabgleich.pl --selector=ISBN13 --database=inst006 --database=tmpebooks --filename=/var/www.kug/extra/inst006/abgleich-inst006-tmpebooks.csv 2>&1 > /dev/null");

if ($updatemaster && $maintenance){
    $logger->info("### Updating clouds");
    
    foreach my $thistype (qw/2/){
        system("$config->{'base_dir'}/bin/gen_metrics.pl --type=$thistype");
    }

}
                                    
$logger->info("### Cleaning up Enrichment-DB");    

system("$config->{'base_dir'}/conv/remove_enriched_terms.pl --filename=$config->{'base_dir'}/conf/enrichmnt_denylist.txt --field=4300");
    
if ($maintenance){
    # TODO Alma
    # $logger->info("### Enriching from CDM");

    # system("cd /tmp ; mkdir kmbtocs ; cd kmbtocs ; wget http://peterlux.ub.uni-koeln.de/contentdm/export/kmbtocs.xml");

    # system("$config->{'base_dir'}/conv/cdm2enrich.pl --inputfile=/tmp/kmbtocs/kmbtocs.xml --configfile=$config->{'base_dir'}/conf/kmb_tocs.yml --database=inst001");

    # system("cd /tmp ; rm kmbtocs/* ; rmdir kmbtocs");

    # system("cd /tmp ; mkdir kmbregister ; cd kmbregister ; wget http://peterlux.ub.uni-koeln.de/contentdm/export/kmbregister.xml");

    # system("$config->{'base_dir'}/conv/cdm2enrich.pl --inputfile=/tmp/kmbregister/kmbregister.xml --configfile=$config->{'base_dir'}/conf/kmb_register.yml --database=inst001");

    # system("cd /tmp ; rm kmbregister/* ; rmdir kmbregister");
    
    # $logger->info("### Enriching USB BK's");
    
    # system("$config->{'base_dir'}/conv/usb_bk2enrich.pl");

    $logger->info("### Dumping Enrichment-DB");    
    
    system("$config->{'base_dir'}/bin/dump_enrichmnt.pl");
    
    $logger->info("###### Maintenance done");
}


sub threadA {
    my $thread_description = shift;

    $logger->info("### -> $thread_description");

    $logger->info("### Standard-Institutskataloge");

    autoconvert({ incremental => $incremental, updatemaster => $updatemaster, denylist => $denylist_ref, sync => 1, autoconv => 1});

    ##############################
    
#    $logger->info("### Rheinische Bibliotheken");
    
#    autoconvert({updatemaster => $updatemaster, sync => 1, databases => ['bruehl','franzmg','gbroich','gdonck','geistingen','gleuel','hennef','kempen','kwinter','wickrath','xanten','zuelpich'] });
    
    ##############################

    $logger->info("### Externe Katalog (OER, OAI, usw.)");

#autoconvert({ sync => 1, databases => ['openlibrary','gutenberg','wikisource_de'] });
#    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['doab','elis','gallica','gdz','gresham_oer','hathitrust','gutenberg','intechopen','khanacademy','khanacademy_de','loc','loviscach_oer','mitocw_oer','nptelhrd_oer','stanford_oer','ucberkeley_oer','ucla_oer','yale_oer','zvdd'] });
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['doab','oapen'] });

#    autoconvert({ updatemaster => $updatemaster, databases => ['gbvnationallizenzen'] });
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['gesiskoeln'] });

    $logger->info("### Sammlungen aus dem Universitaet");
    
#    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['inst404abklatsch'] });
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['inst526earchive','kups'] });

    return $thread_description;
}

sub threadB {
    my $thread_description = shift;

    $logger->info("### -> $thread_description");    

    $logger->info("### Master: Alma Uni Katalog");
    
    autoconvert({ incremental => $incremental, updatemaster => $updatemaster, purgefirst => 1, sync => 1, databases => ['uni'] });
i#    autoconvert({ incremental => $incremental, updatemaster => $updatemaster, purgefirst => 1, sync => 1, reducemem => 1, databases => ['uni'] });
#    autoconvert({ incremental => $incremental, updatemaster => $updatemaster, databases => ['inst001'] });
    
    ##############################

    # $logger->info("### Aufgesplittete Teil-Kataloge aus USB Katalog");
    
    # autoconvert({ incremental => $incremental, updatemaster => $updatemaster, sync => 1, databases => ['digisoz','provenienzen','jesuiten','rheinabt', 'usbhwa','usbsab', 'dissertationen','usbphil'] });

    autoconvert({ incremental => $incremental, updatemaster => $updatemaster, sync => 1, databases => ['usblbs','usbls'] });

    ##############################

    $logger->info("### Aufgesplittete Sammlungen aus dem USB Katalog");
    
    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['afrikaans','alff','artmann','auslaender','baenfer','baeumker','becker','belgischeshaus','benelux','bers','conrady','dante','digitalis','dirksen','englaender','evang','fichte','frauenlektuere','gabel','gruen','gymnasialbibliothek','herbschneider','herterich','hilferding','hinck','hochschulschriften','islandica','kbg','kempis','kloster','kroh','lefort','loeffler','mies','mukluweit','modernedtlit','modernelyrik','nevissen','oidtman','ostasiatica','quint','schia','schirmer','schmalenbach','schneider','schmitzotto','scholle','syndikatsbibliothek','thorbecke','tietz','tillich','vormweg','wallraf','weinkauff','westerholt','wolff'] });

    return $thread_description;
}


sub threadC {
    my $thread_description = shift;

    $logger->info("### -> $thread_description");    

    ##############################

#    $logger->info("### Master: inst132master");
    
#    autoconvert({ updatemaster => $updatemaster, sync => 1, nosearchengine => 1, databases => ['inst132master'] });

    ##############################
    
#    $logger->info("### Aufgesplittete Kataloge inst132master");
    
    autoconvert({ updatemaster => $updatemaster, databases => ['inst132'] });
    
    ##############################

#    $logger->info("### Master: MEKUTH-Masterkataloge");
    
#    autoconvert({ updatemaster => $updatemaster, sync => 1, nosearchengine => 1, databases => ['inst429master','inst448master'] });

    ##############################
    
    $logger->info("### Aufgesplittete Kataloge MEKUTH");
    
    autoconvert({ updatemaster => $updatemaster, databases => ['inst429','inst448'] });

    ##############################

#    $logger->info("### Master: VWL-Masterkataloge");
    
#    autoconvert({ updatemaster => $updatemaster, sync => 1, nosearchengine => 1, databases => ['inst103master','inst105master','inst113master','inst128master','inst146master','inst157master','inst166master'] });

    ##############################

    $logger->info("### Aufgesplittete Kataloge aus VWL-Masterkatalogen");
    
    autoconvert({ updatemaster => $updatemaster, databases => ['inst103','inst105','inst113','inst128','inst146','inst157','inst166'] });
    
    ##############################
    
#    $logger->info("### Master: inst301 und inst301retro");
    
#    autoconvert({ updatemaster => $updatemaster, sync => 1, nosearchengine => 1, databases => ['inst301','inst301retro'] });
    
    ##############################
    
    $logger->info("### Aufgesplittete Kataloge inst301");
    
    autoconvert({ updatemaster => $updatemaster, databases => ['inst303','inst304','inst305','inst306','inst307','inst308','inst309','inst310','inst311','inst312','inst313','inst314','inst315','inst317','inst318','inst319','inst320','inst321','inst324','inst325'] });

    ##############################
    
#    $logger->info("### Kataloge mit offiziellen Literaturliste muessen immer komplett aktualisiert werden");
    
#    autoconvert({ updatemaster => $updatemaster, sync => 1, nosearchengine => 1, databases => ['inst123master','inst123master','inst218master','inst401master'] });
    autoconvert({ updatemaster => $updatemaster, databases => ['inst123','inst123','inst218','inst401'] });

    ##############################

#    $logger->info("### Master: inst420master und -retro");
    
#    autoconvert({ updatemaster => $updatemaster, sync => 1, nosearchengine => 1, databases => ['inst420master','inst420retro'] });

    ##############################
    
    $logger->info("### Aufgesplittete Kataloge inst420");
    
    autoconvert({ updatemaster => $updatemaster, databases => ['inst420','inst421','inst422','inst423','inst424'] });

    ##############################

#    $logger->info("### Sonstige Master-Institutskataloge");
    
#    autoconvert({ updatemaster => $updatemaster, sync => 1, nosearchengine => 1, databases => ['inst005master','inst006master','inst007master','inst102master','inst108master','inst110master','inst112master','inst118master','inst119master','inst125master','inst134master','inst136master','inst156master','inst201master','inst203master','inst204master','inst205master','inst206master','inst207master','inst208master','inst209master','inst210master','inst211master','inst212master','inst213master','inst214master','inst215master','inst216master','inst217master','inst219master','inst221master','inst222master','inst223master','inst225master','inst226master','inst228master','inst230master','inst231master','inst234master','inst237master','inst302master','inst323master','inst401master','inst404master','inst405master','inst406master','inst407master','inst409master','inst410master','inst411master','inst412master','inst413master','inst414master','inst416master','inst418master','inst419master','inst426master','inst427master','inst428master','inst430master','inst431master','inst432master','inst434master','inst437master','inst438master','inst444master','inst445master','inst460master','inst461master','inst464master','inst466master','inst467master','inst468master','inst501master','inst503master','inst514master','inst622master','inst623master'] });

    ##############################
    
    $logger->info("### Aufgesplittete sonstige Institutskataloge");
    
    autoconvert({ updatemaster => $updatemaster, databases => ['inst005','inst006','inst007','inst102','inst108','inst110','inst112','inst118','inst119','inst125','inst134','inst136','inst156','inst201','inst203','inst204','inst205','inst206','inst207','inst208','inst209','inst210','inst211','inst212','inst213','inst214','inst215','inst216','inst217','inst219','inst221','inst222','inst223','inst225','inst226','inst228','inst230','inst231','inst234','inst237','inst302','inst323','inst401','inst404','inst405','inst406','inst407','inst409','inst410','inst411','inst412','inst413','inst414','inst416','inst418','inst419','inst426','inst427','inst428','inst430','inst431','inst432','inst434','inst437','inst438','inst444','inst445','inst460','inst461','inst464','inst466','inst467','inst468','inst501','inst503','inst514','inst622','inst623'] });

    ##############################

    $logger->info("### Master: inst137");
    
    autoconvert({ updatemaster => $updatemaster, databases => ['inst137'] });

    ##############################
    
    $logger->info("### Sammlungen aus dem Universitaet");
    
#    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['alekiddr','digitalis','schatzbehalter'] });

    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['gentzdigital'] });

    system("$config->{'base_dir'}/bin/gen_metrics.pl --database=gentzdigital --type=5 --num=100");
#    system("$config->{'base_dir'}/bin/gen_metrics.pl --database=gentzbriefe --type=5 --num=100");
        
    ##############################

    $logger->info("### Diverse Kataloge");
   
    # instzs wurde in eigenes Steuerscript ausgelagert, da die Lieferung des hbz erst Montag morgen erfolgt 

    # Todo Alma: neue ZBMED-Lieferungen, spoho ueber Lobid
    #    autoconvert({ updatemaster => $updatemaster, sync => 1, databases => ['spoho','zbmed'] });

    # autoconvert({ updatemaster => $updatemaster, denylist => $denylist_ref, sync => 1, databases => ['usbweb'] });
    
    ##############################
    
    $logger->info("### Gekaufte und lizensierte E-Medien");
    
    autoconvert({ updatemaster => $updatemaster, databases => ['emedienkauf','tmpebooks'] });
    
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
    my $denylist_ref   = exists $arg_ref->{denylist}
        ? $arg_ref->{denylist}             : {};

    my $databases_ref   = exists $arg_ref->{databases}
        ? $arg_ref->{databases}             : [];

    my $sync            = exists $arg_ref->{sync}
        ? $arg_ref->{sync}                  : 0;

    my $incremental     = exists $arg_ref->{incremental}
        ? $arg_ref->{incremental}           : 0;

    my $genmex          = exists $arg_ref->{genmex}
        ? $arg_ref->{genmex}                : 0;

    my $autoconv        = exists $arg_ref->{autoconv}
        ? $arg_ref->{autoconv}              : 0;

    my $updatemaster    = exists $arg_ref->{updatemaster}
        ? $arg_ref->{updatemaster}          : 0;

    my $nosearchengine  = exists $arg_ref->{nosearchengine}
        ? $arg_ref->{nosearchengine}        : 0;

    my $reducemem       = exists $arg_ref->{reducemem}
        ? $arg_ref->{reducemem}             : 0;
    
    my $purgefirst      = exists $arg_ref->{purgefirst}
        ? $arg_ref->{purgefirst}            : 0;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    push @ac_cmd, "/opt/openbib/autoconv/bin/autoconv.pl";
    push @ac_cmd, "-sync"    if ($sync); 
    push @ac_cmd, "-gen-mex" if ($genmex);
    push @ac_cmd, "-incremental" if ($incremental);
    push @ac_cmd, "-update-master" if ($updatemaster);
    push @ac_cmd, "-no-searchengine" if ($nosearchengine);
    push @ac_cmd, "-reduce-mem" if ($reducemem);
    push @ac_cmd, "-purge-first" if ($purgefirst);

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
        if (exists $denylist_ref->{$database}){
            $logger->info("Katalog $database auf Denylist");
            next;
        }
        
        my $this_cmd = "$ac_cmd_base --database=$database";
        $logger->info("Konvertierung von $database");
        $logger->info("Ausfuehrung von $this_cmd");
        system($this_cmd);

	# Todo Alma
        # if ($maintenance && !defined $denylist_enrichmnt_ref->{$database}){
        #     $logger->info("### Enriching subject headings for all institutes");
            
        #     system("$config->{'base_dir'}/conv/swt2enrich.pl --database=$database");
        # }
    }
}
