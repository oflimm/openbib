#!/usr/bin/perl
#####################################################################
#
#  quickinstall.pl
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

my $documentroot = "/var/www";

# 2) Wo ist das conf.d-Verzeichnis Ihres Web-Servers
#    z.B. /etc/apache/conf.d  OHNE abschliessenden /

my $confd        = "/etc/apache-perl/conf.d";

# 3) Nach erfolgter Anpassung der vorangegangenen Einstellunge
#    bitte mit 'touch' die Datei .changed_config erzeugen
#####################################################################

if (! -e ".changed_config"){
    print << "ERROR";
Bitte nehmen Sie im Skript lokale Einstellungen an der
entsprechenden Stelle vor und erzeugen dann mit die Datei .changed_config

   touch .changed_config
ERROR
    exit;
}

my ($cwd);
chomp($cwd = `pwd`);

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
    '/opt/openbib/autoconv/filter',
    '/opt/openbib/db',
    '/usr/local/lib/site_perl/',
);

my %cvs_links = (
    "$cwd/portal/perl/templates"            => "/opt/openbib/templates",
    "$cwd/tools"                            => "/opt/openbib/bin",
    "$cwd/portal/perl/locales"              => "/opt/openbib/locales",
    "$cwd/conv/oai/harvestOAI.pl"           => "/opt/openbib/conv/harvestOAI.pl",
    "$cwd/conv/oai/oai2meta.pl"             => "/opt/openbib/conv/oai2meta.pl",
    "$cwd/conv/meta/meta2mex.pl"            => "/opt/openbib/conv/meta2mex.pl",
    "$cwd/conv/meta/meta2sql.pl"            => "/opt/openbib/conv/meta2sql.pl",
    "$cwd/conv/olws/olws_updatedb.pl"       => "/opt/openbib/conv/olws_updatedb.pl",
    "$cwd/conv/lidos/lidos2meta.pl"         => "/opt/openbib/conv/lidos2meta.pl",
    "$cwd/conv/econbiz/econbiz2meta.pl"     => "/opt/openbib/conv/econbiz2meta.pl",
    "$cwd/conv/filemaker/filemaker2meta.pl" => "/opt/openbib/conv/filemaker2meta.pl",
    "$cwd/conv/xapian/db2xapian.pl"         => "/opt/openbib/conv/db2xapian.pl",
    "$cwd/conv/auto/autoconv.pl"            => "/opt/openbib/autoconv/bin/autoconv.pl",
    "$cwd/db/mysql"                         => "/opt/openbib/db/mysql",
    "$cwd/portal/perl/modules/OpenBib"      => "/usr/local/lib/site_perl/OpenBib",
    "$cwd/portal/apache/openbib.conf"       => "$confd/openbib.conf",
    "$cwd/portal/htdocs/styles"             => "$documentroot/styles",
    "$cwd/portal/htdocs/images"             => "$documentroot/images",
);

my %copy_files = (
    "$cwd/portal/perl/conf/portal.log4perl"           => "/opt/openbib/conf/portal.log4perl",
    "$cwd/portal/perl/modules/OpenBib/Config.pm-dist" => "$cwd/portal/perl/modules/OpenBib/Config.pm",
    "$cwd/portal/perl/modules/OpenBib/Search/Z3950/USBK/Config.pm-dist"
                                                      => "$cwd/portal/perl/modules/OpenBib/Search/Z3950/USBK/Config.pm",
);

print "Erzeuge Verzeichnisse\n";

foreach my $dir (@install_dirs){
    if (! -d $dir ){
        mkdir $dir;
    }
}

print "Erzeuge Links ins CVS\n";

while (my ($from,$to) = each %cvs_links){
    if (! -e $to ){
        system("ln -s $from $to");
    }
}

print "Kopiere Dateien vom CVS\n";

while (my ($from,$to) = each %copy_files){
    if (! -e $to ){
        system("cp $from $to");
    }
}

print "Fertig.\n\n";

print << "HINWEIS";
Bitte passen Sie nun die Datei

    $cwd/portal/perl/modules/OpenBib/Config.pm

entsprechend Ihren eigenen Beduerfnissen an.

Danach fuehren Sie bitte folgende Programme zur Erzeugung der
grundlegenden Datenbanken aus:

1) /opt/openbib/bin/createconfig.pl
2) /opt/openbib/bin/createsession.pl
3) /opt/openbib/bin/createuser.pl
4) /opt/openbib/bin/createenrichmnt.pl

Starten Sie schliesslich bitte Apache neu.
HINWEIS
