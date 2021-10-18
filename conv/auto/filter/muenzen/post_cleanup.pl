#!/usr/bin/perl

#####################################################################
#
#  pre_unpack.pl
#
#  Bearbeitung der Titeldaten
#
#  Dieses File ist (C) 2005-2011 Oliver Flimm <flimm@openbib.org>
#
#  Dieses Programm ist freie Software. Sie k"onnen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es w"unschen) jeder sp"ateren Version.
#
#  Die Ver"offentlichung dieses Programms erfolgt in der
#  Hoffnung, da"s es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEW"AHRLEISTUNG - sogar ohne die implizite Gew"ahrleistung
#  der MARKTREIFE oder der EIGNUNG F"UR EINEN BESTIMMTEN ZWECK.
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


print "### $pool: Dropdown-Menu fuer erweiterte Suche cachen\n";

system("$rootdir/filter/$pool/store_searchform_choices.pl");

print "### $pool: Metriken erstellen und cachen\n";
system("/opt/openbib/bin/gen_metrics.pl --database=muenzen --type=14 --field=0100");
system("/opt/openbib/bin/gen_metrics.pl --database=muenzen --type=14 --field=0800");
system("/opt/openbib/bin/gen_metrics.pl --database=muenzen --type=14 --field=0710");
system("/opt/openbib/bin/gen_metrics.pl --database=muenzen --type=14 --field=0338");

