#!/usr/bin/perl
 
#####################################################################
#
#  gen_zsstlist-all.pl
#
#  Extrahieren der Zeitschriftenliste eines Instituts anhand aller
#  im Katalog instzs gefundenen lokalen Sigeln
#
#  Dieses File ist (C) 2006-2016 Oliver Flimm <flimm@openbib.org>
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

use utf8;

use OpenBib::Config;

use DBI;
use YAML;

my $config      = OpenBib::Config->new;

my $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=uzkzeitschriften;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

my $request=$dbh->prepare("select distinct content from holding_fields where field = 3330 order by content") or $logger->error($DBI::errstr);

$request->execute() or $logger->error($DBI::errstr);;

while (my $result=$request->fetchrow_hashref()){
    my $sigel=$result->{content};
    # Keine Liste fuer den USB-Bestand
    next if ($sigel eq "38");
    next unless ($sigel =~m/38-/);
    
    system($config->{tool_dir}."/gen_zsstlist.pl --sigel=$sigel --mode=tex -bibsort");
    system("cd /var/www/zeitschriftenlisten ; pdflatex --interaction=batchmode /var/www/zeitschriftenlisten/zeitschriften-$sigel.tex");
    system("cd /var/www/zeitschriftenlisten ; pdflatex --interaction=batchmode /var/www/zeitschriftenlisten/zeitschriften-$sigel-bibsort.tex");
    
    system($config->{tool_dir}."/gen_zsstlist.pl --sigel=$sigel -showall --enrichnatfile=/opt/openbib/autoconv/pools/uzkzeitschriften/nationallizenzen.csv --mode=tex -bibsort");
    system("cd /var/www/zeitschriftenlisten ; pdflatex --interaction=batchmode /var/www/zeitschriftenlisten/zeitschriften-$sigel-all.tex");
    system("cd /var/www/zeitschriftenlisten ; pdflatex --interaction=batchmode /var/www/zeitschriftenlisten/zeitschriften-$sigel-all-bibsort.tex");

    system("cd /var/www/zeitschriftenlisten ; rm *.tex *.aux *.loc *.out *.log");
}

sub print_help {
    print "gen-zsstlist-all.pl - Erzeugen von Zeitschiftenlisten fuer alle Sigel\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n";

    exit;
}
