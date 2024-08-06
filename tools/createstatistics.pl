#!/usr/bin/perl

#####################################################################
#
#  createstatistics.pl
#
#  Erzeugung der Statistics-Datenbank
#
#  Dieses File ist (C) 2006-2008 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Config;

my $config = OpenBib::Config->new;

system("echo \"*:*:*:$config->{'statisticsdbuser'}:$config->{'statisticsdbpasswd'}\" > ~/.pgpass ; chmod 0600 ~/.pgpass");
system("/usr/bin/dropdb -U $config->{'statisticsdbuser'} -h $config->{'statisticsdbhost'} $config->{'statisticsdbname'}");
system("/usr/bin/createdb -U $config->{'statisticsdbuser'} -h $config->{'statisticsdbhost'} -E UTF-8 -O $config->{'statisticsdbuser'} $config->{'statisticsdbname'}");

# Einladen der Datenbankdefinitionen (immer partitioniert)

system("/usr/bin/psql -U $config->{'statisticsdbuser'} -h $config->{'statisticsdbhost'} -f '$config->{'dbdesc_dir'}/postgresql/statistics.sql' $config->{'statisticsdbname'}");
system("/usr/bin/psql -U $config->{'statisticsdbuser'} -h $config->{'statisticsdbhost'} -f '$config->{'dbdesc_dir'}/postgresql/statistics_create_index.sql' $config->{'statisticsdbname'}");

system("/usr/bin/psql -U $config->{'statisticsdbuser'} -h $config->{'statisticsdbhost'} -f '$config->{'dbdesc_dir'}/postgresql/statistics_create_partitions.sql' $config->{'statisticsdbname'}");
