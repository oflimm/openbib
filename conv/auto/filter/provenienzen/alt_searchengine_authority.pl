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

use OpenBib::Config;

my $database      = $ARGV[0];

my $config        = new OpenBib::Config;

my $authority     = $database."_authority";
my $authoritytmp  = $authority."tmp";

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";

my $konvdir       = $config->{'conv_dir'};

print "### $database: Indexierung nur der Normdaten von Provenienzen in eigenen Normdatenindex\n";

my $authority_indexpathtmp = $config->{xapian_index_base_path}."/$authoritytmp";
	
$logger->info("### $database: Importing authority data into searchengine");
	
my $cmd = "$rootdir/filter/$database/authority2xapian.pl --loglevel=ERROR -with-sorting -with-positions --database=$database --indexpath=$authority_indexpathtmp";
	
$logger->info("Executing: $cmd");
	
system($cmd);
