#!/usr/bin/perl
#####################################################################
#
#  quickinstall.pl
#
#  Dieses File ist (C) 2006-2011 Oliver Flimm <flimm@openbib.org>
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

my $documentroot   = "/var/www";

# 2) Wo ist das conf.d-Verzeichnis Ihres Web-Servers
#    z.B. /etc/apache/conf.d  OHNE abschliessenden /

my $confd          = "/etc/apache2/conf.d";

# 3) Wo ist das ausgecheckte Repository-Verzeichnis
#    z.B. /opt/svn/openbib-current

my $repositoryroot = "/opt/svn/openbib-current";

# 4) Nach erfolgter Anpassung der vorangegangenen Einstellunge
#    bitte mit 'touch' die Datei .changed_config erzeugen
#####################################################################

if (! -e ".changed_config"){
    print << "ERROR";
Bitte nehmen Sie im Skript lokale Einstellungen an der
entsprechenden Stelle vor und erzeugen dann mit die Datei .changed_config

   touch .changed_config

Aktuelle Einstellung:

   documentroot  : $documentroot
   confd         : $confd
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
    '/usr/local/lib/site_perl/',
);

my %cvs_links = (
    "$repositoryroot/portal/perl/templates"              => "/opt/openbib/templates",
    "$repositoryroot/tools"                              => "/opt/openbib/bin",
    "$repositoryroot/portal/perl/locales"                => "/opt/openbib/locales",
    "$repositoryroot/conv/aleph/aleph18seq2meta.pl"      => "/opt/openbib/conv/aleph18seq2meta.pl",
    "$repositoryroot/conv/aleph/alephmab2meta.pl"        => "/opt/openbib/conv/alephmab2meta.pl",
    "$repositoryroot/conv/allegro/ald2simple.pl"         => "/opt/openbib/conv/ald2simple.pl",
    "$repositoryroot/conv/amarok/amarok_mysql2meta.pl"   => "/opt/openbib/conv/amarok_mysql2meta.pl",
    "$repositoryroot/conv/auto/autoconv.pl"              => "/opt/openbib/autoconv/bin/autoconv.pl",
    "$repositoryroot/conv/auto/filter"                   => "/opt/openbib/autoconv/filter",
    "$repositoryroot/conv/cdm/cdm2meta.pl"               => "/opt/openbib/conv/cdm2meta.pl",
    "$repositoryroot/conv/cdm/conf/alff.yml"             => "/opt/openbib/conf/alff.yml",
    "$repositoryroot/conv/cdm/conf/umschlaege.yml"       => "/opt/openbib/conf/umschlaege.yml",
    "$repositoryroot/conv/econbiz/econbiz2meta.pl"       => "/opt/openbib/conv/econbiz2meta.pl",
    "$repositoryroot/conv/enrichmnt/natliz_eb2enrich.pl" => "/opt/openbib/conv/natliz_eb2enrich.pl",
    "$repositoryroot/conv/enrichmnt/picafiles2enrich.pl" => "/opt/openbib/conv/picafiles2enrich.pl",
    "$repositoryroot/conv/enrichmnt/swt2enrich.pl"       => "/opt/openbib/conv/swt2enrich.pl",
    "$repositoryroot/conv/enrichmnt/tictocs2enrich.pl"   => "/opt/openbib/conv/tictocs2enrich.pl",
    "$repositoryroot/conv/enrichmnt/usb_bk2enrich.pl"    => "/opt/openbib/conv/usb_bk2enrich.pl",
    "$repositoryroot/conv/enrichmnt/usb_eb2enrich.pl"    => "/opt/openbib/conv/usb_eb2enrich.pl",
    "$repositoryroot/conv/enrichmnt/usb_toc2enrich.pl"   => "/opt/openbib/conv/usb_toc2enrich.pl",
    "$repositoryroot/conv/enrichmnt/wikipedia2enrich.pl" => "/opt/openbib/conv/wikipedia2enrich.pl",
    "$repositoryroot/conv/filemaker/filemaker2meta.pl"   => "/opt/openbib/conv/filemaker2meta.pl",
    "$repositoryroot/conv/gutenberg/gutenberg2meta.pl"   => "/opt/openbib/conv/gutenberg2meta.pl",
    "$repositoryroot/conv/lars/lars2simple.pl"           => "/opt/openbib/conv/lars2simple.pl",
    "$repositoryroot/conv/lidos/lidos2meta.pl"           => "/opt/openbib/conv/lidos2meta.pl",
    "$repositoryroot/conv/lidos/lidos32meta.pl"          => "/opt/openbib/conv/lidos32meta.pl",
    "$repositoryroot/conv/mab/diskmab2meta.pl"           => "/opt/openbib/conv/diskmab2meta.pl",
    "$repositoryroot/conv/mab/mab2meta.pl"               => "/opt/openbib/conv/mab2meta.pl",
    "$repositoryroot/conv/marc/marc2meta.pl"             => "/opt/openbib/conv/marc2meta.pl",
    "$repositoryroot/conv/meta/meta2incr.pl"             => "/opt/openbib/conv/meta2incr.pl",
    "$repositoryroot/conv/meta/meta2mex.pl"              => "/opt/openbib/conv/meta2mex.pl",
    "$repositoryroot/conv/meta/meta2sql.pl"              => "/opt/openbib/conv/meta2sql.pl",
    "$repositoryroot/conv/oai/harvestOAI.pl"             => "/opt/openbib/conv/harvestOAI.pl",
    "$repositoryroot/conv/oai/oai2meta.pl"               => "/opt/openbib/conv/oai2meta.pl",
    "$repositoryroot/conv/olws/olws_updatedb.pl"         => "/opt/openbib/conv/olws_updatedb.pl",
    "$repositoryroot/conv/openlibrary/openlibrary2meta.pl" => "/opt/openbib/conv/openlibrary2meta.pl",
    "$repositoryroot/conv/repec/repec2meta.pl"           => "/opt/openbib/conv/repec2meta.pl",
    "$repositoryroot/conv/sikis/bcp2meta.pl"             => "/opt/openbib/conv/bcp2meta.pl",
    "$repositoryroot/conv/simple/simple2meta.pl"         => "/opt/openbib/conv/simple2meta.pl",
    "$repositoryroot/conv/simple/simplecsv2meta.pl"      => "/opt/openbib/conv/simplecsv2meta.pl",
    "$repositoryroot/conv/simple/conf/ebooks.yml"        => "/opt/openbib/conf/ebooks.yml",
    "$repositoryroot/conv/simple/conf/inst127.yml"       => "/opt/openbib/conf/inst127.yml",
    "$repositoryroot/conv/simple/conf/inst132alt.yml"    => "/opt/openbib/conf/inst134alt.yml",
    "$repositoryroot/conv/simple/conf/inst408.yml"       => "/opt/openbib/conf/inst408.yml",
    "$repositoryroot/conv/tellico/tellico_music2meta.pl" => "/opt/openbib/conv/tellico_music2meta.pl",
    "$repositoryroot/conv/wikisource/wikisource2meta.pl" => "/opt/openbib/conv/wikisource2meta.pl",
    "$repositoryroot/conv/xapian/db2xapian.pl"           => "/opt/openbib/conv/db2xapian.pl",
    "$repositoryroot/conv/xapian/file2xapian.pl"         => "/opt/openbib/conv/file2xapian.pl",
    "$repositoryroot/conv/zms/zmslibinfo2configdb.pl"    => "/opt/openbib/conv/zmslibinfo2configdb.pl",,
    "$repositoryroot/db"                                 => "/opt/openbib/db",
    "$repositoryroot/portal/perl/modules/OpenBib"        => "/usr/local/lib/site_perl/OpenBib",
    "$repositoryroot/portal/apache/openbib.conf"         => "$confd/openbib.conf",
    "$repositoryroot/portal/htdocs/gm"                   => "$documentroot/gm",
    "$repositoryroot/portal/htdocs/js"                   => "$documentroot/js",
    "$repositoryroot/portal/htdocs/styles"               => "$documentroot/styles",
    "$repositoryroot/portal/htdocs/images"               => "$documentroot/images",
    "$repositoryroot/portal/perl/conf/bk.yml"            => "/opt/openbib/conf/bk.yml",

);

my %copy_files = (
    "$repositoryroot/portal/perl/conf/portal.log4perl"                => "/opt/openbib/conf/portal.log4perl",
    "$repositoryroot/portal/perl/conf/portal.yml-dist"                => "/opt/openbib/conf/portal.yml",
    "$repositoryroot/portal/perl/conf/convert.yml-dist"               => "/opt/openbib/conf/convert.yml",
    "$repositoryroot/portal/perl/modules/OpenBib/Search/Z3950/USBK/Config.pm-dist"
                                                           => "$repositoryroot/portal/perl/modules/OpenBib/Search/Z3950/USBK/Config.pm",
);

print "Erzeuge Verzeichnisse\n";

foreach my $dir (@install_dirs){
    if (! -d $dir ){
        mkdir $dir;
    }
}

print "Erzeuge Links nach SVN Checkout\n";

while (my ($from,$to) = each %cvs_links){
    if (-e $to ){
        system("rm $to");
        print "Loesche $to\n";
    }

    system("ln -s $from $to");
}

print "Kopiere Dateien vom SVN Checkout\n";

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

1) /opt/openbib/bin/createconfig.pl
2) /opt/openbib/bin/createsession.pl
3) /opt/openbib/bin/createuser.pl
4) /opt/openbib/bin/createenrichmnt.pl
5) /opt/openbib/bin/createstatistics.pl

Starten Sie schliesslich bitte Apache neu.
HINWEIS
