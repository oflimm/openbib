#!/usr/bin/perl

#####################################################################
#
#  post_remote.pl
#
#  Dieses File ist (C) 2005-2006 Oliver Flimm <flimm@openbib.org>
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

my $pool          = $ARGV[0];

print "### $pool: AST und HST vereinen wegen Titel-Register und URL-Processing\n";

system("mv -f $rootdir/data/$pool/meta.title $rootdir/data/$pool/meta.title.tmp");
system("$rootdir/filter/$pool/change_ast_hst.pl < $rootdir/data/$pool/meta.title.tmp | $rootdir/filter/$pool/correct_urls.pl | $rootdir/filter/$pool/process_urls.pl > $rootdir/data/$pool/meta.title");
