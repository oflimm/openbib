#!/usr/bin/perl

#####################################################################
#
#  alt_remote.pl
#
#  Holen via http und konvertieren in das Meta-Format
#
#  Dieses File ist (C) 2003-2006 Oliver Flimm <flimm@openbib.org>
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
my $confdir       = $config->{'base_dir'}."/conf";
my $wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";
my $aleph2metaexe = "$konvdir/aleph18seq2meta.pl";

my $pool          = $ARGV[0];

my $dboptions_ref = $config->get_dboptions($pool);

my $url        = "$dboptions_ref->{protocol}://$dboptions_ref->{host}/$dboptions_ref->{remotepath}/$dboptions_ref->{filename}";
my $httpauthstring="";
if ($dboptions_ref->{protocol} eq "http" && $dboptions_ref->{remoteuser} ne "" && $dboptions_ref->{remotepasswd} ne ""){
    $httpauthstring=" --http-user=$dboptions_ref->{remoteuser} --http-passwd=$dboptions_ref->{remotepasswd}";
}

print "### $pool: Datenabzug via http von $url\n";
system("cd $pooldir/$pool ; rm unload* ; rm $dboptions_ref->{filename}");
system("$wgetexe $httpauthstring -P $pooldir/$pool/ $url > /dev/null 2>&1 ");
system("cd $pooldir/$pool; zcat $dboptions_ref->{filename} > pool.dat ; $aleph2metaexe --filename=pool.dat; gzip unload.*");
