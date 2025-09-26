#!/usr/bin/perl

#####################################################################
#
#  alt_remote.pl
#
#  Holen via oai und konvertieren in das Meta-Format
#
#  Dieses File ist (C) 2003-2011 Oliver Flimm <flimm@openbib.org>
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

use DBI;
use OpenBib::Config;

my $config = new OpenBib::Config();

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $konvdir       = $config->{'conv_dir'};

my $wgetexe       = "/usr/bin/wget --auth-no-challenge -nH --cut-dirs=3";
my $eprints2metaexe = "$config->{'conv_dir'}/eprints2meta.pl";

my $pool          = $ARGV[0];

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $base_url =  $dbinfo->protocol."://".$dbinfo->host."/".$dbinfo->remotepath."/";

print "### $pool: Hole Exportdateien mit wget von $base_url\n";

my $httpauthstring="";
if ($dbinfo->protocol eq "https" && $dbinfo->remoteuser ne "" && $dbinfo->remotepassword ne ""){
    $httpauthstring=" --http-user=".$dbinfo->remoteuser." --http-passwd=".$dbinfo->remotepassword;
}
           
system("cd $pooldir/$pool ; rm meta.* *.xml");
system("$wgetexe $httpauthstring -P $pooldir/$pool/ $base_url".$dbinfo->titlefile." > /dev/null 2>&1 ");
system("$wgetexe $httpauthstring -P $pooldir/$pool/ $base_url".$dbinfo->subjectfile." > /dev/null 2>&1 ");

system("cd $pooldir/$pool ; xmllint --recover titles.xml > titles.xml.processed ; mv -f titles.xml.processed titles.xml");

system("cd $pooldir/$pool; $eprints2metaexe --titlefile=".$dbinfo->titlefile." --subjectfile=".$dbinfo->subjectfile." --configfile=/opt/openbib/conf/${pool}.yml; gzip meta.*");

