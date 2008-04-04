#!/usr/bin/perl
#####################################################################
#
#  update_similar_isbn_table.pl
#
#  Aktualisierung der similar_isbn-Tabelle, in der aehnliche ISBN's
#  nachgewiesen sind (via LibraryThing).
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Business::ISBN;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use Getopt::Long;
use YAML;
use XML::Twig;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Search::Util;
use OpenBib::Statistics;

our ($enrichdbh,$enrichrequest);

my ($filename,$help,$logfile);

&GetOptions("filename=s"      => \$filename,
            "logfile=s"       => \$logfile,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/update_similar_isbn.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = OpenBib::Config->instance;

$enrichdbh     = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd}) or die "could not connect";

$enrichrequest = $enrichdbh->prepare("insert into similar_isbn values (?,1)");

my $delrequest    = $enrichdbh->prepare("delete from similar_isbn where origin=1");
$delrequest->execute();


my $twig= XML::Twig->new(
    TwigHandlers => {
        "/thingISBNfeed/work" => \&parse_work
    }
);

$twig->parsefile($filename);

$enrichrequest->finish();
$delrequest->finish();
$enrichdbh->disconnect;

sub parse_work {
    my($t, $work)= @_;

    my @similar_isbns=();

    foreach my $isbn ($work->children('isbn')){
        unless (exists $isbn->{'att'}->{'uncertain'}){
            my $thisisbn = $isbn->text();
            
            # Normierung auf ISBN13
            my $isbn13 = Business::ISBN->new($thisisbn);
            
            if (defined $isbn13 && $isbn13->is_valid){
                $thisisbn = $isbn13->as_isbn13->as_string;
            }
            else {
                next;
            }
            
            # Normierung als String
            $thisisbn = OpenBib::Common::Util::grundform({
                category => '0540',
                content  => $thisisbn,
            });


            push @similar_isbns, $thisisbn;
        }
    }

    if ($#similar_isbns > 0){
        my $isbnstring=join(':',@similar_isbns);
        $enrichrequest->execute($isbnstring);
    }

    $t->purge;
}

sub print_help {
    print << "ENDHELP";
update_similar_isbn_table.pl - Aktualisierung der similar_isbn-Tabelle, in der die ISBN's
                               'aehnlicher' Titel nachgewiesen sind.


   Optionen:
   -help                 : Diese Informationsseite
       
   --filename=...        : Dateiname (LibraryThing XML-Datei)


ENDHELP
    exit;
}

