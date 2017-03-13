#!/usr/bin/perl

#####################################################################
#
#  alt_move_searchengine.pl
#
#  Dieses File ist (C) 2005-2017 Oliver Flimm <flimm@openbib.org>
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

my $config = new OpenBib::Config;

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $konvdir       = $config->{'conv_dir'};

my $database      = $ARGV[0];

print "### $database: Aktiviere Suchindex von tmpfs\n";

if (!-d "$config->{xapian_index_base_path}/${database}tmp3"){
    system("mkdir $config->{xapian_index_base_path}/${database}tmp3");
}
else {
    system("rm -f $config->{xapian_index_base_path}/${database}tmp3/*");
}

system("cp $config->{xapian_index_base_path}/${database}tmp/* $config->{xapian_index_base_path}/${database}tmp3/");

if (-d "$config->{xapian_index_base_path}/$database"){
    system("mv $config->{xapian_index_base_path}/$database $config->{xapian_index_base_path}/${database}tmp2");
}

system("mv $config->{xapian_index_base_path}/${database}tmp3 $config->{xapian_index_base_path}/$database");

if (-d "$config->{xapian_index_base_path}/${database}tmp2"){
    system("rm $config->{xapian_index_base_path}/${database}tmp2/* ; rmdir $config->{xapian_index_base_path}/${database}tmp2");
}

if (-d "$config->{xapian_index_base_path}/${database}tmp3"){
    system("rm $config->{xapian_index_base_path}/${database}tmp3/* ; rmdir $config->{xapian_index_base_path}/${database}tmp3");
}

if (-d "$config->{xapian_index_base_path}/${database}tmp"){
    system("rm $config->{xapian_index_base_path}/${database}tmp/*");
}
