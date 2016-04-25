#!/usr/bin/perl

#####################################################################
#
#  fix_xapian_data.pl
#
#  Dieses File ist (C) 2016 Oliver Flimm <flimm@openbib.org>
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
use utf8;

BEGIN {
#    $ENV{XAPIAN_PREFER_CHERT}    = '1';
    $ENV{XAPIAN_FLUSH_THRESHOLD} = $ENV{XAPIAN_FLUSH_THRESHOLD} || '200000';
}

use OpenBib::Config;
use OpenBib::Search::Factory;

use Log::Log4perl qw(get_logger :levels);
use Getopt::Long;
use JSON::XS;

my ($database,$help,$logfile,$loglevel,$dryrun);

&GetOptions(
    "database=s"      => \$database,
    "logfile=s"       => \$logfile,
    "loglevel=s"      => \$loglevel,
    "dry-run"         => \$dryrun,
    "help"            => \$help
);

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/fix_xapian_data.log';
$loglevel=($loglevel)?$loglevel:"INFO";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
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

my $config = new OpenBib::Config;

my $dbh = undef;

eval {
    $dbh = Search::Xapian::WritableDatabase->new( $config->{xapian_index_base_path}."/".$database, Search::Xapian::DB_OPEN );
};


if ($@){
    $logger->error("Initializing with Database: $database - :".$@." not available");
    exit;
}

my $last_docid    = $dbh->get_lastdocid;

my $current_docid = 1;

my $info_message_done = 0;

$logger->info("### $database: Processing Index");

while ($current_docid <= $last_docid) {

    
#for (my $iter = $dbh->postlist_begin(''); $iter != $dbh->postlist_end('') ; $iter++){

#    my $docid = $iter->get_docid;

    my $doc = $dbh->get_document($current_docid);

    
    if (!$doc){
        $current_docid++;
        next;
    }

    my  $data = $doc->get_data;

    my $new_data = fix_data($data);

    $doc->set_data($new_data);

    $dbh->replace_document($current_docid, $doc) unless ($dryrun);

    if (!$info_message_done && $new_data ne $data){
        $logger->info("### $database: Fixing Index");
        $info_message_done = 1;
    }
    
    if ($logger->is_debug && $new_data ne $data){
        $logger->debug("### $database: Changed $current_docid: $data -> ".$doc->get_data);
    }

    $current_docid++;

    #$iter++;
}

sub fix_data {
    my $data = shift;

    my $data_ref = decode_json $data;

    return $data unless (defined $data_ref->{locations});
    
    if (ref $data_ref->{locations}[0] eq "ARRAY"){
        $data_ref->{locations} = $data_ref->{locations}[0];
    }
    else {
        return $data;
    }
    
    my $new_data = encode_json $data_ref;

    return $new_data;
}

sub print_help {
    print << "ENDHELP";
fix_xapian_data.pl - Manipulation der Dokument-Daten im Xapian-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
