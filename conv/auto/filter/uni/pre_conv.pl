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

system("cd $datadir/$pool ; cat meta.title | $rootdir/filter/$pool/add-fields.pl > meta.title.tmp ; mv -f meta.title.tmp meta.title");

print "### $pool: Erweiterung um Standortinformationen, weiteres Processing - Stage 1\n";

system("cd $datadir/$pool ; cat meta.title | $rootdir/filter/$pool/remove_duplicates_in_nz.pl | $rootdir/filter/$pool/remove_empty_portfolio.pl | $rootdir/filter/$pool/remove_ill.pl | $rootdir/filter/$pool/fix-linkage.pl   > meta.title.tmp ; mv -f meta.title.tmp meta.title");

print "### $pool: Erweiterung um Standortinformationen, weiteres Processing - Stage 2\n";

system("cd $datadir/$pool ; cat meta.title | $rootdir/filter/$pool/gen_local_topic.pl | $rootdir/filter/$pool/process_urls.pl | $rootdir/filter/$pool/add-locationid.pl | $rootdir/filter/$pool/process_ids.pl | $rootdir/filter/$pool/volume2year.pl | $rootdir/filter/$pool/process_provenances.pl  > meta.title.tmp ; mv -f meta.title.tmp meta.title");

print "### $pool: Anreicherung der Exemplarinformationen\n";

system("cd $datadir/$pool ; cat meta.holding| $rootdir/filter/$pool/add-navid.pl > meta.holding.tmp ; mv -f meta.holding.tmp meta.holding");

print "### $pool: Anreicherung der Normdaten mit Informationen aus lobidgnd\n";

system("cd $datadir/$pool ; /opt/openbib/conv/enrich_lobidgnd.pl --type=person --filename=meta.person > meta.person_enriched ; mv -f meta.person_enriched meta.person");

system("cd $datadir/$pool ; /opt/openbib/conv/enrich_lobidgnd.pl --type=corporatebody --filename=meta.corporatebody > meta.corporatebody_enriched ; mv -f meta.corporatebody_enriched meta.corporatebody");

system("cd $datadir/$pool ; /opt/openbib/conv/enrich_lobidgnd.pl --type=subject --filename=meta.subject > meta.subject_enriched ; mv -f meta.subject_enriched meta.subject");
