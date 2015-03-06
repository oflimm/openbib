#!/usr/bin/perl
#####################################################################
#
#  librarything_work_by_isbn2enrich.pl
#
#  Aktualisierung der work_by_isbn-Tabelle, in der ISBN's eines Werkes
#  nachgewiesen sind (via LibraryThing).
#
#  Dieses File ist (C) 2008-2012 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Schema::Enrichment;
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

$logfile=($logfile)?$logfile:'/var/log/openbib/libraryting_work_by_isbn2enrich.log';

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

my $config = OpenBib::Config->new;

our $schema;

eval {
    # UTF8: {'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}
    $schema = OpenBib::Schema::Enrichment->connect("DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error_die($DBI::errstr);
};

if ($@){
    $logger->fatal("Unable to connect schema to Enrichmntment database");
    exit;
}

# Delete old entries

$schema->resultset('WorkByIsbn')->search_rs(
    {
        origin => 1,
    }
)->delete;

my $twig= XML::Twig->new(
    TwigHandlers => {
        "/thingISBNfeed/work" => \&parse_work
    }
);

$twig->parsefile($filename);

sub parse_work {
    my($t, $work)= @_;

    my $similar_isbns_ref = [];

    my $workid = $work->{'att'}->{'workcode'};
    
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
            $thisisbn = OpenBib::Common::Util::normalize({
                field => 'T0540',
                content  => $thisisbn,
            });


            push @$similar_isbns_ref, {
                workid => $workid,
                isbn   => $thisisbn,
                origin => 1,
            };
        }
    }

    if (@{$similar_isbns_ref}){
#        print YAML::Dump($similar_isbns_ref);

        $schema->resultset('WorkByIsbn')->populate($similar_isbns_ref);
    }

    $t->purge;
}

sub print_help {
    print << "ENDHELP";
update_same_work_by_isbn_from_librarything.pl - Aktualisierung der similar_isbn-Tabelle, in der die ISBN's
                               'aehnlicher' Titel nachgewiesen sind.


   Optionen:
   -help                 : Diese Informationsseite
       
   --filename=...        : Dateiname (LibraryThing XML-Datei)


ENDHELP
    exit;
}

