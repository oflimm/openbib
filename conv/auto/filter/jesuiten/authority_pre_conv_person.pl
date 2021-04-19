#!/usr/bin/perl

#####################################################################
#
#  authority_pre_conv_person.pl
#
#  Bearbeitung der Titeldaten
#
#  Dieses File ist (C) 2016 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Config;

my $pool          = $ARGV[0];

my $config        = new OpenBib::Config;

my $rootdir       = $config->{'autoconv_dir'};
my $datadir       = $rootdir."/data";

print "### $pool: Entfernen aller nicht GND-Fremdnummern sowie des (DE-588) GND-Prefixes aus Normdatei person\n";

system("cd $datadir/$pool ; cat authority_meta.person | $rootdir/filter/$pool/fix-gnd.pl > authority_meta.person.tmp ; mv -f authority_meta.person.tmp authority_meta.person");
