#!/usr/bin/perl

#####################################################################
#
#  corr-bib.pl
#
#  Korrektur der besitzenden Bibliothek durch setzen des Sigels
#
#  Dieses File ist (C) 2007 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;
use OpenBib::Config;

use DBI;

my $config = OpenBib::Config->instance;

my $database=$ARGV[0];

my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

# IDN's der Exemplardaten und daran haengender Titel bestimmen

my %sigeltab=(
    'USB-Magazin'                            => '001',
    'USB-Lesesaal'                           => '954',
    'USB-Lehrbuchsammlung'                   => '998',
    'USB-Katalogsaal'                        => '001',
    'USB-Freihandmagazin'                    => '001',
    'Heilpädagogik-Lesesaal'                 => '001',
    'Heilpädagogik-Magazin'                  => '001',
    'Erziehungswiss. Abtl.-Lehrbuchsammlung' => '001',
    'Erziehungswiss. Abtl.-Magazin'          => '001',
    'Erziehungswiss. Abtl.-Lesesaal'         => '001',
    'Fachbibliothek Chemie'                  => '001',
);

foreach my $standort (sort keys %sigeltab){
    print "### $pool: Setze Sigel $sigeltab{$standort} fuer Standort $standort\n";

    my $request=$dbh->prepare("select distinct id from mex where mex.category=16 and mex.content=?") or $logger->error($DBI::errstr);

    $request->execute($standort) or $logger->error($DBI::errstr);;

    while (my $result=$request->fetchrow_hashref()){
        my $id = $result->{'id'};
        my $request2=$dbh->prepare("delete from mex where id=? and category=3300") or $logger->error($DBI::errstr);
        $request2->execute($id);
        $request2=$dbh->prepare("insert into mex values (?,3300,1,?)") or $logger->error($DBI::errstr);
        $request2->execute($id,$sigeltab{$standort});

    }

}
