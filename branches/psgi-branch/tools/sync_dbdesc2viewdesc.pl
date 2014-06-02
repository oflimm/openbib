#!/usr/bin/perl
#####################################################################
#
#  sync_dbdesc2viewdesc.pl
#
#  Synchronisation aller Datenbank-Beschreibungen zu Beschreibungen
#  korrespondierender Views
#
#  Dieses File ist (C) 2014 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use OpenBib::Config;

my $config     = OpenBib::Config->instance;

foreach my $database ($config->{schema}->resultset('Databaseinfo')->all){
    my $corresponding_view = $config->{schema}->resultset('Viewinfo')->single({viewname => $database->dbname});

    if ($corresponding_view){
        if ($corresponding_view->description ne $database->description){
            $corresponding_view->update({ description => $database->description});
            
            print STDERR "Syncing\nView: ",$corresponding_view->description,"\nDatabase: ",$database->description,"\n----------------------------------------------\n";
            
        }
    }
}
