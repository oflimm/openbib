#!/usr/bin/perl
#####################################################################
#
#  lookup_enrichmnt_mldbm.pl
#
#  Ausgabe der Anreicherungsinformatinen in zugehoerigem MLDBM
#  zu ISBN13, ISSN oder database:titleid
#
#  Dieses File ist (C) 2019 Oliver Flimm <flimm@openbib.org>
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

use 5.008001;
use utf8;
use strict;
use warnings;

use DB_File;
use Encode qw/decode_utf8/;
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML;

use OpenBib::Config;

my $config      = OpenBib::Config->new;

my $enrichmntdumpdir = $config->{autoconv_dir}."/data/enrichment";

my %enrichmntdata = ();

if (-e "$enrichmntdumpdir/enrichmntdata.db") {
    tie %enrichmntdata,           'MLDBM', "$enrichmntdumpdir/enrichmntdata.db"
        or die "Could not tie enrichment data.\n";
}

my $key = $ARGV[0];

unless ($key){
    print STDERR "Syntax: lookup_enrichmnt_mldbm.pl <isbn13|issn|db:titleid>\n";
    exit;
}

my $lookup_ref = $enrichmntdata{$key};

print "Ergebnis fuer $key:\n";

print YAML::Dump($lookup_ref),"\n";
