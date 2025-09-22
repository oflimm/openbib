#!/usr/bin/perl
#####################################################################
#
#  export_provenances.pl
#
#  Export der Provenienzen in ein JSON-Format
#
#  Dieses File ist (C) 2015- Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use DBIx::Class::ResultClass::HashRefInflator;
use Getopt::Long;
use JSON::XS qw/encode_json/;
use YAML;
use POSIX qw/strftime/;

use OpenBib::Config;
use OpenBib::Catalog::Factory;
use OpenBib::Common::Util;
use OpenBib::Statistics;
use OpenBib::Search::Util;

my $config     = OpenBib::Config->new;

my ($database,$help,$logfile,$filename);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
            "filename=s"      => \$filename,
	    "help"            => \$help
	    );

if ($help || !$database){
    print_help();
}

$logfile=($logfile)?$logfile:"/var/log/openbib/export_provenances.log";
$filename=($filename)?$filename:"provenances_$database.json";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=ERROR, LOGFILE, Screen
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

$logger->info("Exporting provenances to JSON");

my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $database});

open(OUT,">$filename");

my $titles_with_provenances = $catalog->get_schema->resultset('TitleField')->search(
    {
        'field'   => '4309',
    },
    {
        column   => ['titleid'],
        group_by => ['titleid','id','mult','content'],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
);

my $provenances_count = 0;

my $title_done_ref = {};

foreach my $title ($titles_with_provenances->all){
    my $titleid = $title->{titleid};

    print STDERR "Titelid: $titleid\n";
    
    next if (defined $title_done_ref->{$titleid});

    my $record = OpenBib::Record::Title->new({ database => $database, id => $titleid, config => $config})->load_full_record;

    my $ids_ref  = $record->get_field({ field => 'T0035' });

    my $hbzid = "";
    my $nzid  = "";

    foreach my $item_ref (@$ids_ref){
	if ($item_ref->{subfield} eq "a" && $item_ref->{content} =~m/\(EXLNZ-49HBZ_NETWORK\)(\d+)$/){
	    $nzid=$1;
	}
	if ($item_ref->{subfield} eq "a" && $item_ref->{content} =~m/(\(DE-605\).+)$/){
	    $hbzid=$1;
	}
    }
    
    my $harvard_citation = $record->to_harvard_citation;
    
    $logger->debug("Record: ".YAML::Dump($record->get_fields));
    
    my $provenances_ids_ref = [];
    foreach my $field_ref (@{$record->get_field({field => 'T4309'})}){
 #       $logger->debug("Record-Field: ".YAML::Dump($field_ref));
        push @$provenances_ids_ref, $field_ref->{mult};
    }

#    $logger->debug("Mult: ".YAML::Dump($provenances_ids_ref));
    
    foreach my $mult (@$provenances_ids_ref){
        my $provenance_ref = {};

        my $medianumber   = $record->get_field({ field => 'T4309', subfield => 'a', mult => $mult});
        my $description   = $record->get_field({ field => 'T4310',, subfield => 'a', mult => $mult});
        my $sigel         = $record->get_field({ field => 'T4311', subfield => 'a', mult => $mult});
        my $incomplete    = $record->get_field({ field => 'T4312', subfield => 'a', mult => $mult});
        my $reference     = $record->get_field({ field => 'T4313', subfield => 'a', mult => $mult});
        my $former_mark   = $record->get_field({ field => 'T4314', subfield => 'a', mult => $mult});
        my $scan_id       = $record->get_field({ field => 'T4315', subfield => 'a', mult => $mult});
        my $entry_year    = $record->get_field({ field => 'T4316', subfield => 'a', mult => $mult});
        my $remark        = $record->get_field({ field => 'T4317', subfield => 'a', mult => $mult});

        # Mark from Holdings

        my $current_mark = "";
        foreach my $holding_ref (@{$record->get_holding}){
            my $this_medianumber = $holding_ref->{X0010}{content};
            $this_medianumber =~s/# $//;
            if ($this_medianumber eq $medianumber){
                $current_mark = $holding_ref->{X0014}{content};
            }
        }

        # GND for collections

        my $collection_gnd  = "";
        my $collection_name = "";

        if ($record->has_field('T4306')){
	    $collection_gnd   = $record->get_field({ field => 'T4306', subfield => 'g', mult => $mult});
	    $collection_name  = $record->get_field({ field => 'T4306', subfield => 'a', mult => $mult});
        }

        # GND and name for corporate bodies

        my $corp_gnd  = "";
        my $corp_name = "";

        if ($record->has_field('T4307')){                    
	    $corp_gnd   = $record->get_field({ field => 'T4307', subfield => 'g', mult => $mult});
	    $corp_name  = $record->get_field({ field => 'T4307', subfield => 'a', mult => $mult});
        }
        
        # GND and name for Persons

        my $person_gnd  = "";
	my $person_name = "";

        if ($record->has_field('T4308')){
	    $person_gnd   = $record->get_field({ field => 'T4308', subfield => 'g', mult => $mult});
	    $person_name  = $record->get_field({ field => 'T4308', subfield => 'a', mult => $mult});
        }

	$provenance_ref->{titleid}           = $titleid if ($titleid);
        $provenance_ref->{hbzid}             = $hbzid if ($hbzid);
        $provenance_ref->{nzid}              = $nzid if ($nzid);
        $provenance_ref->{medianumber}       = cleanup_term($medianumber) if ($medianumber);
        $provenance_ref->{tpro_description}  = cleanup_term($description) if ($description);
        $provenance_ref->{sigel}             = cleanup_term($sigel) if ($sigel);
        $provenance_ref->{incomplete}        = cleanup_term($incomplete) if ($incomplete);
        $provenance_ref->{reference}         = cleanup_term($reference)  if ($reference);
        $provenance_ref->{former_mark}       = cleanup_term($former_mark)  if ($former_mark);
        $provenance_ref->{current_mark}      = cleanup_term($current_mark)  if ($current_mark);
        $provenance_ref->{collection_gnd}    = $collection_gnd  if ($collection_gnd);
        $provenance_ref->{corporatebody_gnd} = $corp_gnd  if ($corp_gnd);
        $provenance_ref->{person_gnd}        = $person_gnd  if ($person_gnd);

        $provenance_ref->{collection_name}    = cleanup_term($collection_name)  if ($collection_name);
        $provenance_ref->{corporatebody_name} = cleanup_term($corp_name)  if ($corp_name);
        $provenance_ref->{person_name}        = cleanup_term($person_name)  if ($person_name);

        $provenance_ref->{scan_id}            = cleanup_term($scan_id)  if ($scan_id);
        $provenance_ref->{entry_year}         = cleanup_term($entry_year)  if ($entry_year);
        $provenance_ref->{remark}             = cleanup_term($remark)  if ($remark);
        $provenance_ref->{title_citation}     = cleanup_term($harvard_citation)  if ($harvard_citation);
        $provenance_ref->{linkage}            = $mult;
	
	if ($logger->is_debug){
	    $logger->debug(YAML::Dump($provenance_ref));
	}


        print OUT encode_json $provenance_ref, "\n"; # if ($corp_gnd || $person_gnd || $collection_gnd);
    }

    $title_done_ref->{$titleid} = 1;
}


close(OUT);

$logger->info("$provenances_count provenances exported");

sub cleanup_term {
    my $term = shift;

    $term=~s{&gt;}{>}g;
    $term=~s{&lt;}{<}g;
    $term=~s{&amp;}{&}g;
    $term=~s{</?i>}{}g;

    # Fix Doppelkodierungen
    $term=~s{&gt;}{>}g;
    $term=~s{&lt;}{<}g;
    $term=~s{&amp;}{&}g;
    $term=~s{</?i>}{}g;
    
    return $term;
}

sub print_help {
    print << "ENDHELP";
export_provenances.pl - Export der Provenienzen in ein JSON-Format


   Optionen:
   -help                 : Diese Informationsseite
       
   --database=uni        : Datenbankname (UzK=uni)


ENDHELP
    exit;
}

