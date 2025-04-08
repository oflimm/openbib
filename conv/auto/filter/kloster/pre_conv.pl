#!/usr/bin/perl

#####################################################################
#
#  pre_conv.pl
#
#  Bearbeitung der Titeldaten
#
#  Dieses File ist (C) 2005-2024 Oliver Flimm <flimm@openbib.org>
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

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $baseurl       = $dbinfo->protocol."://".$dbinfo->host."/".$dbinfo->remotepath;

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $datadir       = $rootdir."/data";
my $konvdir       = $config->{'conv_dir'};

print "### $pool: Erweiterung um Zugriffsinformation online, Typ Digital und Themengebiet \n";

system("cd $datadir/$pool ; cat meta.title | $rootdir/filter/_common/alma/add-fields.pl |  $rootdir/filter/$pool/add-printer.pl > meta.title.tmp ; mv -f meta.title.tmp meta.title");

print "### $pool: Erweiterung um Standortinformationen, weiteres Processing - Stage 1\n";

system("cd $datadir/$pool ; cat meta.title | $rootdir/filter/_common/alma/remove_duplicates_in_nz.pl | $rootdir/filter/_common/alma/remove_empty_portfolio.pl | $rootdir/filter/_common/alma/remove_ill.pl | $rootdir/filter/_common/alma/fix-linkage.pl   > meta.title.tmp ; mv -f meta.title.tmp meta.title");

print "### $pool: Erweiterung um Standortinformationen - Stage 2\n";

system("cd $datadir/$pool ; cat meta.title | $rootdir/filter/_common/alma/add-locationid.pl > meta.title.tmp ; mv -f meta.title.tmp meta.title");

print "### $pool: Weiteres Processing - Stage 3\n";

system("cd $datadir/$pool ; cat meta.title | $rootdir/filter/_common/alma/gen_local_topic.pl | $rootdir/filter/_common/alma/process_urls.pl | $rootdir/filter/_common/alma/process_ids.pl | $rootdir/filter/_common/alma/volume2year.pl | $rootdir/filter/_common/alma/process_provenances.pl | $rootdir/filter/_common/alma/add-iiifdoi.pl > meta.title.tmp ; mv -f meta.title.tmp meta.title");

print "### $pool: Sammlungsspezifisches Processing - Stage 4\n";

system("cd $datadir/$pool ; cat meta.title | $rootdir/filter/$pool/process_collection.pl | $rootdir/filter/$pool/restrict_kloster.pl > meta.title.tmp ; mv -f meta.title.tmp meta.title");

print "### $pool: Anreicherung der Exemplarinformationen\n";

system("cd $datadir/$pool ; cat meta.holding| $rootdir/filter/_common/alma/add-navid.pl > meta.holding.tmp ; mv -f meta.holding.tmp meta.holding");

print "### $pool: Anreicherung der Normdaten mit Informationen aus lobidgnd\n";

system("cd $datadir/$pool ; /opt/openbib/conv/enrich_lobidgnd.pl --type=person --filename=meta.person > meta.person_enriched ; mv -f meta.person_enriched meta.person");

system("cd $datadir/$pool ; /opt/openbib/conv/enrich_lobidgnd.pl --type=corporatebody --filename=meta.corporatebody > meta.corporatebody_enriched ; mv -f meta.corporatebody_enriched meta.corporatebody");

system("cd $datadir/$pool ; /opt/openbib/conv/enrich_lobidgnd.pl --type=subject --filename=meta.subject > meta.subject_enriched ; mv -f meta.subject_enriched meta.subject");
