#!/usr/bin/perl

#####################################################################
#
#  createconfig.pl
#
#  Erzeugung der System-Datenbank
#
#  Dieses File ist (C) 2001-2011 Oliver Flimm <flimm@openbib.org>
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

system("echo \"*:*:*:$config->{'systemdbuser'}:$config->{'systemdbpasswd'}\" > ~/.pgpass ; chmod 0600 ~/.pgpass");
system("/usr/bin/dropdb -U $config->{'systemdbuser'} -h $config->{'systemdbhost'} $config->{systemdbname}");
system("/usr/bin/createdb -U $config->{'systemdbuser'} -h $config->{'systemdbhost'} -E UTF-8 -O $config->{'systemdbuser'} $config->{systemdbname}");

# Einladen der Datenbankdefinitionen

system("/usr/bin/psql -U $config->{'systemdbuser'} -h $config->{'systemdbhost'} -f '$config->{'dbdesc_dir'}/postgresql/system.sql' $config->{systemdbname}");
system("/usr/bin/psql -U $config->{'systemdbuser'} -h $config->{'systemdbhost'} -f '$config->{'dbdesc_dir'}/postgresql/system_create_index.sql' $config->{systemdbname}");
system("/usr/bin/psql -U $config->{'systemdbuser'} -h $config->{'systemdbhost'} -f '$config->{'dbdesc_dir'}/postgresql/system_defaultinit.sql' $config->{systemdbname}");
