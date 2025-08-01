#!/usr/bin/perl

#####################################################################
#
#  alt_remote.pl
#
#  Holen via oai und konvertieren in das Meta-Format
#
#  Dieses File ist (C) 2003-2020 Oliver Flimm <flimm@openbib.org>
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

use DBI;
use OpenBib::Config;

my $config = new OpenBib::Config();

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $konvdir       = $config->{'conv_dir'};

my $catmanduexe          = "$config->{'conv_dir'}/marc2meta.pl";
my $marcjson2marcmetaexe = "$config->{'conv_dir'}/marcjson2marcmeta.pl";

my $pool          = $ARGV[0];

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $pool })->single;

my $oaiurl        = $dbinfo->protocol."://".$dbinfo->host;
$oaiurl = $oaiurl."/".$dbinfo->remotepath if ($dbinfo->remotepath);
$oaiurl = $oaiurl."/".$dbinfo->titlefile if ($dbinfo->titlefile);

my $oai_format = "MarcXchange";
my $oai_set    = "vd16";

my $from  = "";
my $until = "";

foreach my $this_filename (<pool-*.mrc>) {
    my ($this_format,$this_from,$this_to)=$this_filename=~m/^pool-(.*?)-(\d\d\d\d.+?Z)_to_(\d\d\d\d.+?Z).mrc$/;
    $format=$this_format unless ($format);
    $from = $this_to;
}

if (!$from){
    $from = "1970-01-01T12:00:00Z";
}

my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $dst) = localtime();
$mon += 1;
$year += 1900;

if (!$until){
    $until = sprintf "%4d-%02d-%02dT%02d:%02d:%02dZ",$year,$mon,$mday,$hour,$min,$sec;
}

print "### $pool: Datenabzug via OAI von $oaiurl from $from until $until\n";
system("cd $pooldir/$pool ; rm meta.* ; rm pool.mrc");
system("cd $pooldir/$pool ; catmandu convert OAI --url $oaiurl --metadataPrefix $oai_format --set $oai_set --from $from --until $until --handler marcxml to MARC  > pool-${oai_format}-${from}_to_${until}.mrc");

my @marc_files = sort { $b <=> $a } <pool-*.mrc>;
my $files = join(' ',@marc_files);

system("cd $pooldir/$pool ; cat $files > pool.mrc");

system("cd $pooldir/$pool; yaz-marcdump -i marc -o json pool.mrc | jq -S -c . > pool.json");

system("cd $pooldir/$pool; $marcjson2marcmetaexe --database=$pool -reduce-mem --inputfile=pool.json --configfile=/opt/openbib/conf/uni.yml; gzip meta.*");
