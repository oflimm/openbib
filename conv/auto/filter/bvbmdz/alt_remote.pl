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

my $marc2metaexe = "$config->{'conv_dir'}/marc2meta.pl";

my $pool          = $ARGV[0];

print "### $pool: Zusammenspielen der Datenlieferungen und Umwandlung von MARC\n";
system("cd $pooldir/$pool ; rm meta.* ; rm pool*");

system("cd $pooldir/$pool ; cat header.xml > $pooldir/$pool/pool.xml ; zcat `ls -1 *mdz.xml.gz|sort -r |xargs` | sed -e 's/<marc:/</g' | sed -e 's/<\/marc:/</g'  >> $pooldir/$pool/pool.xml ; cat footer.xml >> $pooldir/$pool/pool.xml");

system("cd $pooldir/$pool; $marc2metaexe --database=$pool --inputfile=pool.xml -use-xml; gzip meta.*");
system("rm $pooldir/$pool/pool.xml");
