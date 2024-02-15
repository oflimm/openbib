#!/usr/bin/perl

#####################################################################
#
#  meta2marc.pl
#
#  Generierung einer MARC21 Datei aus dem Meta-Format
#
#  Dieses File ist (C) 2024 Oliver Flimm <flimm@openbib.org>
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

use Benchmark ':hireswallclock';
use Business::ISBN;
use DB_File;
use Digest::MD5 qw(md5_hex);
use Encode qw/decode_utf8/;
use Getopt::Long;
use JSON::XS;
use Lingua::Identify::CLD;
use Log::Log4perl qw(get_logger :levels);
use MARC::Record;
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML;

use OpenBib::Config;

my ($outputfile,$mappingfile,$logfile,$loglevel,$count,$help);

&GetOptions(
    "outputfile=s"   => \$outputfile,
    "mappingfile=s"  => \$mappingfile,    
    "logfile=s"      => \$logfile,
    "loglevel=s"     => \$loglevel,
    "help"           => \$help,
    );

if ($help || (!$mappingfile && !$outputfile)) {
    print_help();
}
    
my $config      = OpenBib::Config->new;

$logfile=($logfile)?$logfile:"./meta2marc.log";
$loglevel=($loglevel)?$loglevel:"INFO";
$outputfile=($outputfile)?$outputfile:"./output.mrc";

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

my $dir=`pwd`;
chop $dir;

my %data_person         = ();
my %data_corporatebody  = ();
my %data_classification = ();
my %data_subject        = ();
my %data_holding        = ();
my %titleid_exists      = ();

tie %data_person,        'MLDBM', "./data_person.db"
        or die "Could not tie data_person.\n";

tie %data_corporatebody,        'MLDBM', "./data_corporatebody.db"
        or die "Could not tie data_corporatebody.\n";

tie %data_subject,        'MLDBM', "./data_subject.db"
    or die "Could not tie data_subject.\n";

tie %data_classification,        'MLDBM', "./data_classification.db"
    or die "Could not tie data_classification.\n";

tie %data_holding,        'MLDBM', "./data_holding.db"
    or die "Could not tie data_holding.\n";

my $stammdateien_ref = {
    person => {
        infile             => "meta.person.gz",
    },

    corporatebody => {
        infile             => "meta.corporatebody.gz",
    },
    
    subject => {
        infile             => "meta.subject.gz",
    },
    
    classification => {
        infile             => "meta.classification.gz",
    },
};

my $atime;

foreach my $type (keys %{$stammdateien_ref}) {
    if (-f $stammdateien_ref->{$type}{infile}){
        $atime = new Benchmark;

        $count = 1;
        
        $logger->info("### Bearbeite $stammdateien_ref->{$type}{infile} / $stammdateien_ref->{$type}{outfile}");
        
        open(IN , "zcat ".$stammdateien_ref->{$type}{infile}." | " )        || die "IN konnte nicht geoeffnet werden";

	binmode(IN,":raw");
	
        while (my $json=<IN>){
	    my $record_ref = decode_json $json;

	    my $id = $record_ref->{id};
	    
	    if ($type eq "person"){
		$data_person{$id} = $record_ref->{fields};
	    }
	    elsif ($type eq "corporatebody"){
		$data_corporatebody{$id} = $record_ref->{fields};
	    }
	    elsif ($type eq "subject"){
		$data_subject{$id} = $record_ref->{fields};
	    }
	    elsif ($type eq "classification"){
		$data_classification{$id} = $record_ref->{fields};
	    }
	    elsif ($type eq "holding"){
		$data_holding{$id} = $record_ref->{fields};
	    }
		
            if ($count % 1000 == 0) {
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                
                $atime      = new Benchmark;
                $logger->info("### 1000 ($count) Saetze in $resulttime fuer $type bearbeitet");
            } 
            
            $count++;
        }
	
        close(IN);
        
    }
    else {
        $logger->error("### $stammdateien_ref->{$type}{infile} nicht vorhanden!");
    }
}

#######################

$logger->info("### Bearbeite meta.title");

$stammdateien_ref = {
    title => {
        infile             => "meta.title.gz",
    },    
};

open(IN , "zcat ".$stammdateien_ref->{'title'}{'infile'}." | " )     || die "IN konnte nicht geoeffnet werden";

open(OUT, ">:utf8",$outputfile);

binmode (IN, ":raw");

$count = 1;

$atime = new Benchmark;

my $mapping_ref = YAML::Syck::LoadFile($mappingfile);

my $title_mapping_ref = $mapping_ref->{convtab}{title};
    
while (my $json=<IN>){
    
    my $record_ref = decode_json $json;

    my $fields_ref = $record_ref->{fields};

    my $marc_record = new MARC::Record;

    $marc_record->add_fields('001',$record_ref->{id});
    
    $logger->debug(YAML::Dump($fields_ref));
    
    foreach my $marcfield (keys %{$title_mapping_ref}){
	my ($ind1)    = $marcfield =~m/^..._(.)_.$/;
	my ($ind2)    = $marcfield =~m/^..._._(.)$/;

	$logger->debug("$marcfield -> Ind1: x${ind1}x - Ind2: x${ind2}x");
	
	$ind1 = "\'$ind1\'";
	$ind2 = "\'$ind2\'";

	my ($fieldno) = $marcfield =~m/^(\d\d\d)/;

	# Daten mit mapping-Datein in interne MARC21-Struktur ueberfuehren
	my $marcfields_ref = {};

	# Titeldaten
	foreach my $marcdef_ref (@{$title_mapping_ref->{$marcfield}}){
	    $logger->debug(YAML::Dump($marcdef_ref));
	    my $mab2_field = $marcdef_ref->{from_field};
	    if (defined $fields_ref->{$mab2_field}){
		
		foreach my $thisfield_ref (@{$fields_ref->{$mab2_field}}){
		    if (!defined $marcfields_ref->{$thisfield_ref->{mult}}){
			$marcfields_ref->{$thisfield_ref->{mult}} = [];
		    }
		    push @{$marcfields_ref->{$thisfield_ref->{mult}}}, {
			ind1 => $ind1,
			ind2 => $ind2,
			subfield => $marcdef_ref->{subfield},
			content => cleanup($thisfield_ref->{content}),
		    }
		}
	    }
	}

	$logger->debug(YAML::Dump($marcfields_ref));

	# Aus interner MARC21-Struktur valide MARC21-Ausgabedaten erzeugen
	foreach my $mult (sort keys %{$marcfields_ref}){
	    my $first = 1;
	    my $new_field;
	    foreach my $thisitem_ref (@{$marcfields_ref->{$mult}}){
		if ($first){
		    $new_field = MARC::Field->new($fieldno, $thisitem_ref->{ind1}, $thisitem_ref->{ind2}, $thisitem_ref->{subfield} => $thisitem_ref->{content});

		}
		else {
		    $new_field->add_subfields($thisitem_ref->{subfield} => $thisitem_ref->{content});
		}
		$first = 0;
	    }
	    $marc_record->append_fields($new_field) if ($new_field);	    
	}
    }

    # Normdaten processen

    # Personendaten
    my @personids = ();
    foreach my $thisfield_ref (@{$fields_ref->{'0100'}}){
	push @personids, $thisfield_ref->{id};
    }
    
    foreach my $thisfield_ref (@{$fields_ref->{'0101'}}){
	push @personids, $thisfield_ref->{id};
    }
    
    foreach my $thisfield_ref (@{$fields_ref->{'0102'}}){
	push @personids, $thisfield_ref->{id};
    }
    
    foreach my $thisfield_ref (@{$fields_ref->{'0103'}}){
	push @personids, $thisfield_ref->{id};
    }
    
    if (@personids){
	
	# Erste in 100 11
	my $personid = shift @personids;
	
	my $person_fields_ref = $data_person{$personid};

	$logger->debug("Persondata: ".YAML::Syck::Dump($person_fields_ref));
	my @subfields = ();

	# Ansetzungsform
	if ($person_fields_ref->{'0800'}){
	    push (@subfields,'a', cleanup($person_fields_ref->{'0800'}[0]{content}));
	}

	# GND
	if ($person_fields_ref->{'0010'}){
	    push (@subfields,'0', "(DE-588)".$person_fields_ref->{'0010'}[0]{content});
	}

	# Relationship
	push (@subfields,'4', "aut");
	
	my $new_field = MARC::Field->new('100', '1',  ' ', @subfields);

	$marc_record->append_fields($new_field) if ($new_field);	    	

	foreach my $personid (@personids){
	    my $person_fields_ref = $data_person{$personid};

	    my @subfields = ();
	    
	    # Ansetzungsform
	    if ($person_fields_ref->{'0800'}){
		push (@subfields,'a', cleanup($person_fields_ref->{'0800'}[0]{content}));
	    }
	    
	    # GND
	    if ($person_fields_ref->{'0010'}){
		push (@subfields,'0', "(DE-588)".$person_fields_ref->{'0010'}[0]{content});
	    }
	    
	    # Relationship
	    push (@subfields,'4', "aut");
	    	    
	    my $new_field = MARC::Field->new('700', '1',  ' ', @subfields);
	    
	    $marc_record->append_fields($new_field) if ($new_field);	    	
	}	
    }
	
    # Koerperschaften
    my @corporatebodyids = ();
    foreach my $thisfield_ref (@{$fields_ref->{'0200'}}){
	push @corporatebodyids, $thisfield_ref->{id};
    }
    
    foreach my $thisfield_ref (@{$fields_ref->{'0201'}}){
	push @corporatebodyids, $thisfield_ref->{id};
    }
        
    if (@corporatebodyids){
	
	# Erste in 100 11
	my $corporatebodyid = shift @corporatebodyids;
	
	my $corporatebody_fields_ref = $data_corporatebody{$corporatebodyid};

	$logger->debug("Corporatebodydata: ".YAML::Syck::Dump($corporatebody_fields_ref));
	my @subfields = ();

	# Ansetzungsform
	if ($corporatebody_fields_ref->{'0800'}){
	    push (@subfields,'a', cleanup($corporatebody_fields_ref->{'0800'}[0]{content}));
	}

	# GND
	if ($corporatebody_fields_ref->{'0010'}){
	    push (@subfields,'0', "(DE-588)".$corporatebody_fields_ref->{'0010'}[0]{content});
	}

	# Relationship
	push (@subfields,'4', "prt");
	
	my $new_field = MARC::Field->new('110', '1',  ' ', @subfields);

	$marc_record->append_fields($new_field) if ($new_field);	    	

	foreach my $corporatebodyid (@corporatebodyids){
	    my $corporatebody_fields_ref = $data_corporatebody{$corporatebodyid};

	    my @subfields = ();
	    
	    # Ansetzungsform
	    if ($corporatebody_fields_ref->{'0800'}){
		push (@subfields,'a', cleanup($corporatebody_fields_ref->{'0800'}[0]{content}));
	    }
	    
	    # GND
	    if ($corporatebody_fields_ref->{'0010'}){
		push (@subfields,'0', "(DE-588)".$corporatebody_fields_ref->{'0010'}[0]{content});
	    }
	    
	    # Relationship
	    push (@subfields,'4', "prt");
	    	    
	    my $new_field = MARC::Field->new('710', '2',  ' ', @subfields);
	    
	    $marc_record->append_fields($new_field) if ($new_field);	    	
	}	
    }
    
    # URLs processen

    # Exemplardaten processen
    
    if ($count % 1000 == 0) {
        my $btime      = new Benchmark;
        my $timeall    = timediff($btime,$atime);
        my $resulttime = timestr($timeall,"nop");
        $resulttime    =~s/(\d+\.\d+) .*/$1/;
        
        $atime      = new Benchmark;
        $logger->info("### 1000 ($count) Titelsaetze in $resulttime bearbeitet");
    } 

    print OUT $marc_record->as_usmarc;

    $count++;
}

$logger->info("### $count Titelsaetze bearbeitet");

close(IN);
close(OUT);

sub print_help {
    print << "ENDHELP";
meta2marc.pl - Erzeugung einer MARC21 Datei aus den Import-Dateien im MAB2 Metaformat

   Optionen:
   -help                 : Diese Informationsseite
       
   --outputfile=...      : Name der MARC21 Ausgabedatei
   --logfile=...         : Logfile inkl Pfad.
   --loglevel=...        : Loglevel

ENDHELP
    exit;
}

sub cleanup {
    my $content = shift;

    $content=~s/&lt;/</g;
    $content=~s/&gt;/>/g;
    $content=~s/&amp;/&/g;

    return $content;
}
