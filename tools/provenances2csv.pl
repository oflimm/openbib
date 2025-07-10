#!/usr/bin/perl

#####################################################################
#
#  provenances2csv.pl
#
#  Umwandlung von Provenienz-Exporten im JSON-Format in eine CSV-Datei
#  zum Import in die hbz NZ
#
#  Dieses File ist (C) 2025 Oliver Flimm <flimm@openbib.org>
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

use warnings;
use strict;

use Getopt::Long;

use Log::Log4perl qw(get_logger :levels);
use Encode qw/decode_utf8 encode decode/;
use JSON::XS;
use Text::CSV_XS;
use YAML;

my ($help,$logfile,$loglevel);

&GetOptions(
    "logfile"  => \$logfile,
    "loglevel"  => \$loglevel,
    "help"     => \$help,
    );

if ($help){
    print_help();
}

$logfile  = ($logfile)?$logfile:'/var/log/openbib/provenances2csv.log';
$loglevel = ($loglevel)?$loglevel:'INFO';

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

my $out;

my $filename = "provenances_de38_361.csv";

open $out, ">:encoding(utf8)", $filename;

my $outputcsv = Text::CSV_XS->new ({
    'eol'         => "\n",
    'sep_char'    => "\t",
});

my $out_ref = [];

push @{$out_ref}, ('3611$o','3611$5','3611$s','3611$a','3611$0','3611$f','3611$l','3611$z','3611$u','035$a','Network Id','3611$y');

$outputcsv->print($out,$out_ref);

my $idx = 1;

while (my $json = <>){
    my $json_ref = decode_json $json;

    $out_ref = [];

    my $tpro_merkmal = "";

    my %tpro_merkmale = (
	# tpro_description-Teil => Ziel Merkmal
	'^Autogramm' => 'Autogramm',
	'^Einband' => 'Einband',
	'^Einlage' => 'Einlage',
	'^Etikett' => 'Etikett',
	'^Exlibris' => 'Exlibris',
	'^gedr. Besitzvermerk' => 'gedr. Besitzvermerk',
	'^hs. Besitzvermerk' => 'hs. Besitzvermerk',
	'^Indiz' => 'Indiz',
	'^Initiale' => 'Initiale',
	'^Monogramm' => 'Monogramm',
	'^Notiz' => 'Notiz',
	'^NS-Raubgut' => 'NS-Raubgut',
	'^Prämienband' => 'Prämienband',
	'^Restitution' => 'Restitution',
	'^Restitutionsexemplar' => 'Restitutionsexemplar',
	'^Stempel' => 'Stempel',
	'^Supralibros' => 'Supralibros',
	'^Wappenstempel' => 'Wappenstempel',
	'^Wappen' => 'Wappen',
	'^Wappenexlibris' => 'Wappenexlibris',
	'^Widmung' => 'Widmung',
	);

    if (!defined $json_ref->{tpro_description}){
	print STDERR "Keine TPRO-Beschreibung ".YAML::Dump($json_ref)."\n";
	next;
    }
	
    my $multiple_tpro = 0;
    foreach my $merkmal (keys %tpro_merkmale){
	if ($json_ref->{tpro_description} =~m/$merkmal/){
	    if ($tpro_merkmal){
		$multiple_tpro = 1;
		next;
	    }
		    	    
	    $tpro_merkmal = $tpro_merkmale{$merkmal};
	}
    }

    if ($multiple_tpro){	
	print STDERR "Mehrfache Merkmale: ".YAML::Dump($json_ref)."\n";
    }
    
    my $field_361_y  = $json_ref->{current_mark} || "";
    my $field_361_o  = "Vorbesitz";
    my $field_361_5  = ($json_ref->{sigel} !~ "^DE")?"DE-".$json_ref->{sigel}:$json_ref->{sigel};
    my $field_361_s  = $json_ref->{medianumber} || "";
    my $field_361_a  = $json_ref->{person_name} || $json_ref->{corporatebody_name} || $json_ref->{collection_name} || "";
    my $field_361_0  = $json_ref->{person_gnd} || $json_ref->{corporatebody_gnd} || $json_ref->{collection_gnd} || "";
    my $field_361_f  = $tpro_merkmal || '';
    my $field_361_l  = $json_ref->{entry_year} || "";
    my $field_361_u  = $json_ref->{scan_id} || "";
    my @fields_361_z = ();
    my $field_035_a  = $json_ref->{hbzid} || "";
    my $nz_id        = $json_ref->{nzid} || "";


    $field_361_0 = "(DE-588)$field_361_0" if( $field_361_0 && $field_361_0 !~m/DE-588/);
    
    push @fields_361_z, "T-Pro: ".$json_ref->{tpro_description};
    push @fields_361_z, "Alt-Signatur: ".$json_ref->{former_mark} if ($json_ref->{former_mark});
    push @fields_361_z, "Referenz: ".$json_ref->{reference} if ($json_ref->{reference});
    push @fields_361_z, "Bemerkung: ".$json_ref->{remark} if ($json_ref->{remark});
    push @fields_361_z, "Unvollst.: ".$json_ref->{incomplete} if ($json_ref->{incomplete});

    my $field_361_z  = join(', ',@fields_361_z);
    
    push @{$out_ref}, ($field_361_o,$field_361_5,$field_361_s,$field_361_a,$field_361_0,$field_361_f,$field_361_l,$field_361_z,$field_361_u,$field_035_a,$nz_id,$field_361_y);

    $outputcsv->print($out,$out_ref);

    if ($idx % 1000 == 0){
	$logger->info("$idx Records done");
    }

    $idx++;
}

close ($out);

sub print_help {
    print "provenances2csv.pl - Erzeugen von CSV-Import-Dateien aus Provenienz-Exporten fuer 361 in der NZ des hbz\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n\n";
    print "  --loglevel=             : Loglevel\n\n";
    print "  --logfile=              : Logfile\n\n";
    
    exit;
}
