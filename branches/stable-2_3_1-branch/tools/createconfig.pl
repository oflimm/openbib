#!/usr/bin/perl

#####################################################################
#
#  createconfig.pl
#
#  Erzeugung der Config-Datenbank
#
#  Dieses File ist (C) 2001-2008 Oliver Flimm <flimm@openbib.org>
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

my $config = OpenBib::Config->instance;

# Anlegen der Config-DB

system("/usr/bin/mysqladmin -u $config->{'configdbuser'} --password=$config->{'configdbpasswd'} create $config->{'configdbname'}");

# Einladen der Datenbankdefinitionen

system("/usr/bin/mysql -u $config->{'configdbuser'} --password=$config->{'configdbpasswd'} $config->{'configdbname'} < $config->{'dbdesc_dir'}/mysql/config.mysql");

