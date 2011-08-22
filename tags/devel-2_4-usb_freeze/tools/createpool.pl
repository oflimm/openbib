#!/usr/bin/perl

#####################################################################
#
#  createpool.pl
#
#  Erzeugung einer Katalog-Datenbank
#
#  Dieses File ist (C) 1997-2008 Oliver Flimm <flimm@openbib.org>
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

$pool=$ARGV[0];

#####################################################################
# Einladen der benoetigten Perl-Module 
#####################################################################

use OpenBib::Config;

my $config = OpenBib::Config->instance;

# Anlegen des Mysql-Pools

print "Creating Pool $pool\n";

system("/usr/bin/mysqladmin -u $config->{'dbuser'} --password=$config->{'dbpasswd'} create $pool");

# Einladen der Datenbankdefinitionen

system("/usr/bin/mysql -u $config->{'dbuser'} --password=$config->{'dbpasswd'} $pool < $config->{'dbdesc_dir'}/mysql/pool.mysql");

# Anlegen des Verzeichnisses zur lokalen Speicherung der Daten

system("mkdir -p $config->{'autoconv_dir'}/pools/$pool");
