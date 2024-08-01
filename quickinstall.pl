#!/usr/bin/perl
#####################################################################
#
#  quickinstall.pl
#
#  Dieses File ist (C) 2006-2020 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Hier bitte lokale Einstellungen vornehmen
#####################################################################
#
# 1) Wo ist das DocumentRoot des Web-Servers?
#    z.B. /var/www OHNE abschliessenden /

my $documentroot = "/var/www/html";

# 2) Wo ist das ausgecheckte Repository-Verzeichnis
#    z.B. /opt/git/openbib-current

my $repositoryroot = "/opt/git/openbib-current";

# 3) Nach erfolgter Anpassung der vorangegangenen Einstellunge
#    bitte mit 'touch' die Datei .changed_config erzeugen
#####################################################################

if (! -e ".changed_config"){
    print << "ERROR";
Bitte nehmen Sie im Skript lokale Einstellungen an der
entsprechenden Stelle vor und erzeugen dann mit die Datei .changed_config

   touch .changed_config

Aktuelle Einstellung:

   documentroot: $documentroot
   repositoryroot: $repositoryroot
ERROR
    exit;
}

my @install_dirs = (
    '/opt/openbib',
    '/opt/openbib/conf',
    '/opt/openbib/cql',
    '/opt/openbib/cql/USBK',
    '/opt/openbib/cql/Vaticana',
    '/opt/openbib/conv',
    '/opt/openbib/ft',
    '/opt/openbib/ft/xapian',
    '/opt/openbib/ft/xapian/index',
    '/opt/openbib/autoconv',
    '/opt/openbib/autoconv/bin',
    '/opt/openbib/autoconv/pools',
    '/opt/openbib/autoconv/data',
    '/var/log/openbib',
    '/usr/share/images',
    '/usr/share/images/openbib',
);

my %git_links = (
    "$repositoryroot/portal/perl/templates"                 => "/opt/openbib/templates",
    "$repositoryroot/tools"                                 => "/opt/openbib/bin",
    "$repositoryroot/portal/perl/locales"                   => "/opt/openbib/locales",
    "$repositoryroot/conv/allegro/ald2simple.pl"            => "/opt/openbib/conv/ald2simple.pl",
    "$repositoryroot/conv/allegro/ald2simple.pl"            => "/opt/openbib/conv/ald2simple.pl",
    "$repositoryroot/conv/auto/autoconv.pl"                 => "/opt/openbib/autoconv/bin/autoconv.pl",
    "$repositoryroot/conv/auto/autojoinindex_xapian.pl"     => "/opt/openbib/autoconv/bin/autojoinindex_xapian.pl",
    "$repositoryroot/conv/auto/openbib-clustermgmt.pl"      => "/opt/openbib/autoconv/bin/openbib-clustermgmt.pl",
    "$repositoryroot/conv/auto/filter"                      => "/opt/openbib/autoconv/filter",
    "$repositoryroot/conv/cdm/cdm2meta.pl"                  => "/opt/openbib/conv/cdm2meta.pl",
    "$repositoryroot/conv/cdm/conf/alff.yml"                => "/opt/openbib/conf/alff.yml",
    "$repositoryroot/portal/perl/conf/portal.psgi"          => "/opt/openbib/conf/portal.psgi",
    "$repositoryroot/portal/perl/conf/portal.log4perl"      => "/opt/openbib/conf/portal.log4perl",
    "$repositoryroot/conv/cdm/conf/umschlaege.yml"          => "/opt/openbib/conf/umschlaege.yml",
    "$repositoryroot/conv/econbiz/econbiz2meta.pl"          => "/opt/openbib/conv/econbiz2meta.pl",
    "$repositoryroot/conv/enrichmnt/natliz_eb2enrich.pl"    => "/opt/openbib/conv/natliz_eb2enrich.pl",
    "$repositoryroot/conv/enrichmnt/picafiles2enrich.pl"    => "/opt/openbib/conv/picafiles2enrich.pl",
    "$repositoryroot/conv/enrichmnt/swt2enrich.pl"          => "/opt/openbib/conv/swt2enrich.pl",
    "$repositoryroot/conv/enrichmnt/usb_bk2enrich.pl"       => "/opt/openbib/conv/usb_bk2enrich.pl",
    "$repositoryroot/conv/enrichmnt/usb_eb2enrich.pl"       => "/opt/openbib/conv/usb_eb2enrich.pl",
    "$repositoryroot/conv/enrichmnt/usb_toc2enrich.pl"      => "/opt/openbib/conv/usb_toc2enrich.pl",
    "$repositoryroot/conv/enrichmnt/wikipedia2enrich.pl"    => "/opt/openbib/conv/wikipedia2enrich.pl",
    "$repositoryroot/conv/filemaker/filemaker2meta.pl"      => "/opt/openbib/conv/filemaker2meta.pl",
    "$repositoryroot/conv/gutenberg/gutenberg2meta.pl"      => "/opt/openbib/conv/gutenberg2meta.pl",
    "$repositoryroot/conv/lars/lars2simple.pl"              => "/opt/openbib/conv/lars2simple.pl",
    "$repositoryroot/conv/lidos/lidos2meta.pl"              => "/opt/openbib/conv/lidos2meta.pl",
    "$repositoryroot/conv/lidos/lidos32meta.pl"             => "/opt/openbib/conv/lidos32meta.pl",
    "$repositoryroot/conv/mab/diskmab2meta.pl"              => "/opt/openbib/conv/diskmab2meta.pl",
    "$repositoryroot/conv/mab/mab2meta.pl"                  => "/opt/openbib/conv/mab2meta.pl",
    "$repositoryroot/conv/marc/marc2meta.pl"                => "/opt/openbib/conv/marc2meta.pl",
    "$repositoryroot/conv/meta/meta2incr.pl"                => "/opt/openbib/conv/meta2incr.pl",
    "$repositoryroot/conv/meta/meta2mex.pl"                 => "/opt/openbib/conv/meta2mex.pl",
    "$repositoryroot/conv/meta/meta2sql.pl"                 => "/opt/openbib/conv/meta2sql.pl",
    "$repositoryroot/conv/meta/enrich_lobidgnd.pl"          => "/opt/openbib/conv/enrich_lobidgnd.pl",
    "$repositoryroot/conv/oai/harvestOAI.pl"                => "/opt/openbib/conv/harvestOAI.pl",
    "$repositoryroot/conv/oai/oai2meta.pl"                  => "/opt/openbib/conv/oai2meta.pl",
    "$repositoryroot/conv/olws/olws_updatedb.pl"            => "/opt/openbib/conv/olws_updatedb.pl",
    "$repositoryroot/conv/openlibrary/openlibrary2meta.pl"  => "/opt/openbib/conv/openlibrary2meta.pl",
    "$repositoryroot/conv/repec/repec2meta.pl"              => "/opt/openbib/conv/repec2meta.pl",
    "$repositoryroot/conv/sikis/bcp2meta.pl"                => "/opt/openbib/conv/bcp2meta.pl",
    "$repositoryroot/conv/simple/simple2meta.pl"            => "/opt/openbib/conv/simple2meta.pl",
    "$repositoryroot/conv/simple/simplecsv2meta.pl"         => "/opt/openbib/conv/simplecsv2meta.pl",
    "$repositoryroot/conv/simple/conf/ebooks.yml"           => "/opt/openbib/conf/ebooks.yml",
    "$repositoryroot/conv/simple/conf/inst127.yml"          => "/opt/openbib/conf/inst127.yml",
    "$repositoryroot/conv/simple/conf/inst132alt.yml"       => "/opt/openbib/conf/inst134alt.yml",
    "$repositoryroot/conv/simple/conf/inst408.yml"          => "/opt/openbib/conf/inst408.yml",
    "$repositoryroot/conv/tellico/tellico_music2meta.pl"    => "/opt/openbib/conv/tellico_music2meta.pl",
    "$repositoryroot/conv/wikisource/wikisource2meta.pl"    => "/opt/openbib/conv/wikisource2meta.pl",
    "$repositoryroot/conv/xapian/db2xapian.pl"              => "/opt/openbib/conv/db2xapian.pl",
    "$repositoryroot/conv/xapian/file2xapian.pl"            => "/opt/openbib/conv/file2xapian.pl",
    "$repositoryroot/conv/elasticsearch/file2elasticsearch.pl"         => "/opt/openbib/conv/file2elasticsearch.pl",
    "$repositoryroot/conv/aleph/alephseq2meta.pl"           => "/opt/openbib/conv/alephseq2meta.pl",
    "$repositoryroot/conv/xapian/authority2xapian.pl"       => "/opt/openbib/conv/authority2xapian.pl",
    "$repositoryroot/conv/enrichmnt/librarything_work_by_isbn2enrich.pl"    => "/opt/openbib/conv/librarything_work_by_isbn2enrich.pl",
    "$repositoryroot/conv/simple/simplexml2meta.pl"        => "/opt/openbib/conv/simplexml2meta.pl",
    "$repositoryroot/conv/auto/openbib-autocron-collect-data.pl"    => "/opt/openbib/autoconv/bin/openbib-autocron-collect-data.pl",
    "$repositoryroot/conv/auto/openbib-autocron.pl"          => "/opt/openbib/autoconv/bin/openbib-autocron.pl",
    "$repositoryroot/conv/auto/openbib-autocron-weekdays.pl" => "/opt/openbib/autoconv/bin/openbib-autocron-weekdays.pl",
    "$repositoryroot/conv/auto/openbib-autocron-weekend.pl"  => "/opt/openbib/autoconv/bin/openbib-autocron-weekend.pl",
    "$repositoryroot/conv/meta/enrich_meta.pl" => "/opt/openbib/conv/enrich_meta.pl",
    "$repositoryroot/conv/marc/marcjson2marcmeta.pl" => "/opt/openbib/conv/marcjson2marcmeta.pl",
    "$repositoryroot/conv/enrichmnt/remove_enriched_terms.pl" => "/opt/openbib/conv/remove_enriched_terms.pl",
    "$repositoryroot/conv/auto/autojoinindex-in-parallel.pl" => "/opt/openbib/autoconv/bin/autojoinindex-in-parallel.pl",
    "$repositoryroot/conv/auto/autojoinindex_elasticsearch.pl" => "/opt/openbib/autoconv/bin/autojoinindex_elasticsearch.pl",
    "$repositoryroot/conv/auto/index-in-parallel.pl" => "/opt/openbib/autoconv/bin/index-in-parallel.pl",
    "$repositoryroot/conv/auto/openbib-autocron-full.pl" => "/opt/openbib/autoconv/bin/openbib-autocron-full.pl",
    "$repositoryroot/conv/auto/openbib-autocron-pda.pl" => "/opt/openbib/autoconv/bin/openbib-autocron-pda.pl",
    "$repositoryroot/conv/simple/conf/paperc.yml"          => "/opt/openbib/conf/paperc.yml",    
    "$repositoryroot/conv/simple/conf/nla.yml"             => "/opt/openbib/conf/nla.yml",
    "$repositoryroot/conv/aleph/conf/spoho.yml"            => "/opt/openbib/conf/spoho.yml",
    "$repositoryroot/conv/cdm/conf/gentzdigital.yml"       => "/opt/openbib/conf/gentzdigital.yml",
    "$repositoryroot/conv/cdm/conf/totenzettel.yml"        => "/opt/openbib/conf/totenzettel.yml",
    "$repositoryroot/conv/simple/conf/gesiskoeln.yml"      => "/opt/openbib/conf/gesiskoeln.yml",    
    "$repositoryroot/conv/lidos/conf/inst450.yml"          => "/opt/openbib/conf/inst450.yml",
    "$repositoryroot/conv/simple/conf/vubpda.yml"          => "/opt/openbib/conf/vubpda.yml",
    "$repositoryroot/conv/simple/conf/ssgbwlvolltexte.yml" => "/opt/openbib/conf/ssgbwlvolltexte.yml",
    "$repositoryroot/conv/simple/conf/tusculum.yml"        => "/opt/openbib/conf/tusculum.yml",    
    "$repositoryroot/conv/cdm/conf/zpe.yml"                => "/opt/openbib/conf/zpe.yml",
    "$repositoryroot/conv/mab/conf/instzs.yml"             => "/opt/openbib/conf/instzs.yml",
    "$repositoryroot/conv/simple/conf/inst900.yml"         => "/opt/openbib/conf/inst900.yml",
    "$repositoryroot/conv/simple/conf/kups.yml"            => "/opt/openbib/conf/kups.yml",    
    "$repositoryroot/conv/cdm/conf/muenzen.yml"            => "/opt/openbib/conf/muenzen.yml",
    "$repositoryroot/conv/khanacademy/conf/khanacademy.yml" => "/opt/openbib/conf/khanacademy.yml",
    "$repositoryroot/conv/wikisource/conf/wikisource_de.yml" => "/opt/openbib/conf/wikisource_de.yml",
    "$repositoryroot/conv/mab/conf/nationallizenzen.yml"   => "/opt/openbib/conf/nationallizenzen.yml",
    "$repositoryroot/conv/simple/conf/nsdl.yml"            => "/opt/openbib/conf/nsdl.yml",
    "$repositoryroot/conv/simple/conf/bestellungen.yml"    => "/opt/openbib/conf/bestellungen.yml",
    "$repositoryroot/conv/marc/conf/ebookpda.yml"          => "/opt/openbib/conf/ebookpda.yml",
    "$repositoryroot/conv/simple/conf/arxiv.yml"           => "/opt/openbib/conf/arxiv.yml",
    "$repositoryroot/portal/perl/conf/usbbibliographie.yml" => "/opt/openbib/conf/usbbibliographie.yml",
    "$repositoryroot/conv/youtube/youtube2meta.pl"         => "/opt/openbib/conv/youtube2meta.pl",
    "$repositoryroot/conv/youtube/conf/ucla_oer.yml"       => "/opt/openbib/conf/ucla_oer.yml",
    "$repositoryroot/conv/youtube/conf/loviscach_oer.yml"  => "/opt/openbib/conf/loviscach_oer.yml",
    "$repositoryroot/conv/youtube/conf/khanacademy_de.yml" => "/opt/openbib/conf/khanacademy_de.yml",
    "$repositoryroot/conv/zms/zmslibinfo2configdb.pl"      => "/opt/openbib/conv/zmslibinfo2configdb.pl",

    "$repositoryroot/conv/mab/conf/inst450hbz.yml"         => "/opt/openbib/conf/inst450hbz.yml",
    "$repositoryroot/conv/simple/conf/mdz.yml"             => "/opt/openbib/conf/mdz.yml",
    "$repositoryroot/conv/youtube/conf/gresham_oer.yml"    => "/opt/openbib/conf/gresham_oer.yml",
    "$repositoryroot/conv/simple/conf/gdea.yml"            => "/opt/openbib/conf/gdea.yml",
    "$repositoryroot/conv/simple/conf/ndltd.yml"           => "/opt/openbib/conf/ndltd.yml",
    "$repositoryroot/conv/simple/conf/ezb.yml"             => "/opt/openbib/conf/ezb.yml",
    "$repositoryroot/conv/youtube/conf/stanford_oer.yml"   => "/opt/openbib/conf/stanford_oer.yml",
    "$repositoryroot/conv/simple/conf/gallica.yml"         => "/opt/openbib/conf/gallica.yml",
    "$repositoryroot/conv/simple/conf/zvdd.yml"            => "/opt/openbib/conf/zvdd.yml",
    "$repositoryroot/conv/cdm/conf/gentzdigital.yml"       => "/opt/openbib/conf/gentzdigital.yml",
    "$repositoryroot/conv/wikisource/conf/wikisource_en.yml" => "/opt/openbib/conf/wikisource_en.yml",
    "$repositoryroot/conv/simple/conf/filme.yml"           => "/opt/openbib/conf/filme.yml",
    "$repositoryroot/conv/simple/conf/hathitrust.yml"      => "/opt/openbib/conf/hathitrust.yml",
    "$repositoryroot/conv/mab/conf/olgkoeln.yml"           => "/opt/openbib/conf/olgkoeln.yml",
    "$repositoryroot/conv/youtube/conf/nptelhrd_oer.yml"   => "/opt/openbib/conf/nptelhrd_oer.yml",
    "$repositoryroot/conv/marc/conf/gutenberg.yml"         => "/opt/openbib/conf/gutenberg.yml",
    "$repositoryroot/conv/simple/conf/doab.yml"            => "/opt/openbib/conf/doab.yml",
    "$repositoryroot/conv/simple/conf/inst404card.yml"     => "/opt/openbib/conf/inst404card.yml",
    "$repositoryroot/conv/simple/conf/intechopen.yml"      => "/opt/openbib/conf/intechopen.yml",
    "$repositoryroot/conv/simple/conf/loc.yml"             => "/opt/openbib/conf/loc.yml",
    "$repositoryroot/conv/simple/conf/inst526earchive.yml" => "/opt/openbib/conf/inst526earchive.yml",
    "$repositoryroot/conv/youtube/conf/yale_oer.yml"       => "/opt/openbib/conf/yale_oer.yml",
    "$repositoryroot/conv/simple/conf/ocwconsortium.yml"   => "/opt/openbib/conf/ocwconsortium.yml",
    "$repositoryroot/conv/youtube/conf/ucberkeley_oer.yml" => "/opt/openbib/conf/ucberkeley_oer.yml",
    "$repositoryroot/conv/youtube/conf/mitocw_oer.yml"     => "/opt/openbib/conf/mitocw_oer.yml",
    "$repositoryroot/conv/simple/conf/elis.yml"            => "/opt/openbib/conf/elis.yml",
    "$repositoryroot/conv/simple/conf/inst132alt.yml"      => "/opt/openbib/conf/inst132alt.yml",
    "$repositoryroot/conv/khanacademy/khanacademy2meta.pl" => "/opt/openbib/conv/khanacademy2meta.pl",
    "$repositoryroot/conv/marc/conf/gutenberg.yml"         => "/opt/openbib/conf/gutenberg.yml",
    "$repositoryroot/conv/simple/conf/gdz.yml"             => "/opt/openbib/conf/gdz.yml",



    "$repositoryroot/db"                                   => "/opt/openbib/db",
    "$repositoryroot/portal/perl/modules/OpenBib"          => "/usr/share/perl5/OpenBib",
    "$repositoryroot/portal/htdocs/gm"                     => "$documentroot/gm",
    "$repositoryroot/portal/htdocs/js"                     => "$documentroot/js",
    "$repositoryroot/portal/htdocs/css"                    => "$documentroot/css",
    "$repositoryroot/portal/htdocs/images"                 => "$documentroot/images",
    "$repositoryroot/portal/perl/conf/bk.yml"              => "/opt/openbib/conf/bk.yml",
    "$repositoryroot/portal/perl/conf/lcc.yml"             => "/opt/openbib/conf/lcc.yml",
    "$repositoryroot/portal/perl/conf/rvk.yml"             => "/opt/openbib/conf/rvk.yml",
    "$repositoryroot/portal/perl/conf/ddc.yml"             => "/opt/openbib/conf/ddc.yml",
    "$repositoryroot/portal/perl/conf/usbbibliographie.yml" => "/opt/openbib/conf/usbbibliographie.yml",

);

my %copy_files = (
    "$repositoryroot/portal/perl/conf/portal.log4perl"                => "/opt/openbib/conf/portal.log4perl-dist",
    "$repositoryroot/portal/perl/conf/portal.yml-dist"                => "/opt/openbib/conf/portal.yml",
    "$repositoryroot/portal/perl/conf/portal.psgi"                    => "/opt/openbib/conf/portal.psgi",
    "$repositoryroot/portal/perl/conf/convert.yml-dist"               => "/opt/openbib/conf/convert.yml",
    "$repositoryroot/portal/perl/conf/dispatch_rules.yml-dist"        => "/opt/openbib/conf/dispatch_rules.yml",
    "$repositoryroot/portal/starman/init.d/starman"                   => "/etc/init.d/starman",
    "$repositoryroot/portal/starman/systemd/starman.service"          => "/etc/systemd/system/starman.service",
    "$repositoryroot/portal/perl/modules/OpenBib/Search/Backend/Z3950/USBK/Config.pm-dist"
                                                           => "$repositoryroot/portal/perl/modules/OpenBib/Search/Backend/Z3950/USBK/Config.pm",
);

print "Erzeuge Verzeichnisse\n";

foreach my $dir (@install_dirs){
    if (! -d $dir ){
        mkdir $dir;
    }
}

print "Erzeuge Links ins GIT\n";

while (my ($from,$to) = each %git_links){
    if (-e $to ){
        system("rm $to");
        print "Loesche $to\n";
    }

    system("ln -s $from $to");
}

print "Kopiere Dateien vom GIT\n";

while (my ($from,$to) = each %copy_files){
    if (! -e $to ){
        system("cp $from $to");
    }
}

print "Fertig.\n\n";

print << "HINWEIS";
Bitte passen Sie nun die Datei

    /opt/openbib/conf/portal.yml bzw.

    /opt/openbib/conf/convert.yml

entsprechend Ihren eigenen Beduerfnissen an.

Danach fuehren Sie bitte folgende Programme zur Erzeugung der
grundlegenden Datenbanken aus:

1) /opt/openbib/bin/createsystem.pl
2) /opt/openbib/bin/createenrichmnt.pl
3) /opt/openbib/bin/createstatistics.pl

Starten Sie schliesslich bitte starman neu.
HINWEIS
