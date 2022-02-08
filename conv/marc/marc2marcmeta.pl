#!/usr/bin/perl

#####################################################################
#
#  marc2marcmeta.pl
#
#  Konverierung von MARC-Daten in das Meta-Format mit MARC-Feldern
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
#
#  basiert auf marc2meta.pl 2009-2016 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode_utf8';
use Getopt::Long;
use DBI;
use MARC::Batch;
use MARC::Charset 'marc8_to_utf8';
use MARC::File::XML;
use YAML::Syck;
use JSON::XS qw(encode_json);
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Conv::Common::Util;

our (%person,%corporatebody,%subject,%classification);

my ($inputfile,$configfile,$database,$globalencoding,$use_xml,$format,$loglevel);

&GetOptions(
    "database=s"      => \$database,
    "format=s"        => \$format,
    "encoding=s"      => \$globalencoding,
    "inputfile=s"     => \$inputfile,
    "configfile=s"    => \$configfile,
    "loglevel=s"      => \$loglevel,
    "use-xml"         => \$use_xml,
    );

my $logfile = "/var/log/openbib/marc2meta/${database}.log";

$loglevel=($loglevel)?$loglevel:'INFO';

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

my $config = OpenBib::Config->new;
my $enrichmnt = new OpenBib::Enrichment;

if (!$inputfile){
    print << "HELP";
marc2marcmeta.pl - Aufrufsyntax

    marc2marcmeta.pl --inputfile=xxx
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile) if ($configfile);

# Einlesen und Reorganisieren

open(DAT,"$inputfile");

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

our $multcount_ref = {};

my $excluded_titles = 0;

$format=($format)?$format:'USMARC';

$logger->debug("Using format $format");

my $batch;

if ($use_xml){
    $logger->debug("Using MARC-XML");
    
    MARC::File::XML->default_record_format($format);
    
    $batch = MARC::Batch->new('XML', $inputfile);    
}
else {
    $logger->debug("Using native MARC");
    $batch = MARC::Batch->new($format, $inputfile);
}

# Recover from errors
$batch->strict_off();
$batch->warnings_off();

# Fallback to UTF8
MARC::Charset->assume_unicode(1);

# Ignore Encoding Errors
MARC::Charset->ignore_errors(1);

my $have_title_ref = {};

my $count=1;

my $all_count=1;

my $mexid = 1;

my $exclude_by_isbn_in_file_ref = {};

if ($configfile && $convconfig->{exclude}{by_isbn_in_file} && $convconfig->{exclude}{by_isbn_in_file}{filename}){
    my $filename = $convconfig->{exclude}{by_isbn_in_file}{filename};

    $logger->info("Einladen auszuschliessender ISBNs aus Datei $filename ");
    
    open(ISBN,$filename);

    while (<ISBN>){
        # Normierung auf ISBN13
        my $isbn13 = OpenBib::Common::Util::to_isbn13($_);

        $exclude_by_isbn_in_file_ref->{$isbn13} = 1;
    }

    close(ISBN);
}

while (my $record = safe_next($batch)){
    $all_count++;
    
    next unless ($record);

    my $title_ref = {
        'fields' => {},
    };

    $multcount_ref = {};

    my $encoding;
    
    if (defined $globalencoding && ($globalencoding eq "UTF-8" || $globalencoding eq "MARC-8")){
	$record->encoding($globalencoding);
	$encoding=$globalencoding;
    }
    elsif (!$globalencoding) {
	$encoding=$record->encoding();
    }
    
    $logger->debug("Encoding:$encoding:");


    my $idfield = $record->field('001');
    my $titleid = (defined $idfield)?$idfield->as_string():undef;

    if (!$titleid){
	my $isbnfield = $record->field('020');
	my $isbn = (defined $isbnfield->as_string('a'))?$isbnfield->as_string('a'):undef;
	# Cleanup
	$isbn=~s/[^0-9xX]//g;

	$titleid = $isbn if ($isbn);
    }

    if (!$titleid){
	$logger->error("Titelsatz hat keine ID in 001");
	next;
    }
    
    $title_ref->{id} = $titleid;
    
    my $field_mult_ref = {};
    
    # Process all fields
    foreach my $field ($record->fields()){
	my $field_nr = $field->tag();
	$field_mult_ref->{$field_nr} = 1 unless (defined $field_mult_ref->{$field_nr});
	# Immer alle Subfelder uebertragen
	foreach my $subfield_ref ($field->subfields()){
	    my $content = $subfield_ref->[1];
	    
	    if ($encoding eq "MARC-8"){
		$content = marc8_to_utf8($content);
	    }
#	    else {
#		$content = decode_utf8($content);	
#	    }
	    
	    push @{$title_ref->{'fields'}{$field_nr}}, {
		subfield => $subfield_ref->[0],
		content  => $content,
		mult     => $field_mult_ref->{$field_nr},
	    };
	}

	# Zusaetzlich ggf. Generierung der Normdaten
	
	# Verfasser
	{
	    # Verfasser
	    if ($field_nr eq "100" || $field_nr eq "700"){

		my $linkage = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('6')):$field->as_string('6');
		
		my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):$field->as_string('a'); # Personal name
		my $content_b = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('b')):$field->as_string('b'); # Numeration
		my $content_c = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('c')):$field->as_string('c'); # Titles and other words associated
		my $content_d = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('d')):$field->as_string('d'); # Dates associated
		my $content_0 = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('0')):$field->as_string('0'); # Authority number


		# Linkage = Verweis zur ID des Nordatensates

		if (!$linkage){
		    # Keine ID mitgegeben, dann ID aus Personennamen und Geburtsdatum generieren
		    $linkage = $content_a;
		    if ($content_d){
			$linkage.=$content_d;
		    }

		    $linkage=~s/\W+//g;

		    # Und als neues Linkage-Feld uebernehmen

		    push @{$title_ref->{'fields'}{$field_nr}}, {
			subfield => '6', # Linkage-Subfield
			content  => $linkage,
			mult     => $field_mult_ref->{$field_nr},
		    };
		}
		
		# Beispiel 'Maximilian II'
		if ($content_a && $content_b){
		    $content_a = $content_a." ".$content_b;
		}
		
		if ($content_a){
		    add_person($linkage,$content_0,$content_a,$content_c,$content_d);
		}		
	    }
	}

	# Koerperschaften
	{
	    if ($field_nr eq "110" || $field_nr eq "710"){
		my $linkage = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('6')):$field->as_string('6');

		my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):$field->as_string('a');

		# Linkage = Verweis zur ID des Nordatensates

		if (!$linkage){
		    # Keine ID mitgegeben, dann ID aus Koerperschaftsnamen generieren
		    $linkage = $content_a;

		    $linkage=~s/\W+//g;

		    # Und als neues Linkage-Feld uebernehmen
		    
		    push @{$title_ref->{'fields'}{$field_nr}}, {
			subfield => '6', # Linkage-Subfield
			content  => $linkage,
			mult     => $field_mult_ref->{$field_nr},
		    };
		}

		
		if ($content_a){
		    add_corporatebody($linkage,$content_a);
		}
	    }
	}
	
	# Klassifikationen	
	{
	    if ($field_nr eq "082"){
		my $linkage = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('6')):$field->as_string('6');

		my $content = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string($field)):$field->as_string($field);

		# Linkage = Verweis zur ID des Nordatensates

		if (!$linkage){
		    # Keine ID mitgegeben, dann ID aus Koerperschaftsnamen generieren
		    $linkage = $content;

		    $linkage=~s/\W+//g;

		    # Und als neues Linkage-Feld uebernehmen
		    
		    push @{$title_ref->{'fields'}{$field_nr}}, {
			subfield => '6', # Linkage-Subfield
			content  => $linkage,
			mult     => $field_mult_ref->{$field_nr},
		    };
		}

		
		if ($content){
		    add_classification($linkage,$content);
		}		
	    }	    
	}
	
	# Schlagworte
	{        
	    if ($field_nr eq "650" || $field_nr eq "650"){
		my $linkage = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('6')):$field->as_string('6');
		
		my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):$field->as_string('a');
		my $content_x = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('x')):$field->as_string('x');

		my $content = $content_a;

		if ($content && $content_x){
		    $content.=" / ".$content_x;
		}

		# Linkage = Verweis zur ID des Nordatensates

		if (!$linkage){
		    # Keine ID mitgegeben, dann ID aus Koerperschaftsnamen generieren
		    $linkage = $content;
		    
		    $linkage=~s/\W+//g;

		    # Und als neues Linkage-Feld uebernehmen
		    
		    push @{$title_ref->{'fields'}{$field_nr}}, {
			subfield => '6', # Linkage-Subfield
			content  => $linkage,
			mult     => $field_mult_ref->{$field_nr},
		    };
		}
		
		if ($content){
		    add_subject($linkage,$content);
		}		
	    }
	}
	
	# Exemplardaten
	{ 
	    if ($field_nr eq "852"){
		my $indicator_1 = $field->indicator(1);
		my $indicator_2 = $field->indicator(2);
		
		my $holding_ref = {
		    'id'     => $mexid++,
			'fields' => {
			    '0004' =>
				[
				 {
				     mult     => 1,
				     subfield => '',
				     content  => $title_ref->{id},
				 },
				],
		    },
		};
		
		if ($indicator_1 == 8){
		    my $content_b = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('b')):$field->as_string('b');
		    my $content_c = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('c')):$field->as_string('c');
		    my $content_h = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('h')):$field->as_string('h');
		    my $content_8 = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('8')):$field->as_string('8');
		    
		    if ($content_8){
			$holding_ref->{id} = $content_8;
		    }
		    
		    if ($content_b && $content_c){
			$content_c = $content_b." / ".$content_c;
		    }
		    
		    push @{$holding_ref->{fields}{'0016'}}, {
			content  => konv($content_c),
			subfield => '',
			mult     => 1,
		    };
		    
		    push @{$holding_ref->{fields}{'0014'}}, {
			content  => konv($content_h),
			subfield => '',
			mult     => 1,
		    };
		    
		}
		else {
		    my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):$field->as_string('a');
		    my $content_i = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('i')):$field->as_string('i');
		    
		    push @{$holding_ref->{fields}{'0016'}}, {
			content  => konv($content_a),
			subfield => '',
			mult     => 1,
		    };
		    
		    push @{$holding_ref->{fields}{'0014'}}, {
			content  => konv($content_i),
			subfield => '',
			mult     => 1,
		    };
		    
		}
		
		print HOLDING encode_json $holding_ref,"\n";
	    }
	    
	    if ($configfile && defined $convconfig->{localfields}{holdings}){
		
		#	    $logger->info("Processing local holding fields");
		
		my $localfields_ref = $convconfig->{localfields}{holdings};
		
		foreach my $localfield (keys %{$localfields_ref}){
		    #		$logger->info("Processing field $localfield");
		    
		    foreach my $field ($record->field($localfield)){
			
			my $holding_ref = {
			    'id'     => $mexid++,
				'fields' => {
				    '0004' =>
					[
					 {
					     mult     => 1,
					     subfield => '',
					     content  => $title_ref->{id},
					 },
					],
			    },
			};
			
			foreach my $subfield (keys %{$localfields_ref->{$localfield}}){
			    
			    my $destfield = $localfields_ref->{$localfield}{$subfield};
			    my $content = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string($subfield)):$field->as_string($subfield);
			    
			    
			    push @{$holding_ref->{fields}{$destfield}}, {
				content  => konv($content),
				subfield => '',
				mult     => 1,
			    };
			    
			}
			
			print HOLDING encode_json $holding_ref,"\n";
		    }		
		}	    
	    }
	}

	
	$field_mult_ref->{$field_nr} = $field_mult_ref->{$field_nr} + 1;
    }


    if ($configfile && $convconfig->{exclude}{by_availability}){
        my $key_field = $convconfig->{exclude}{by_availability}{field};
        
        my @keys = ();
        foreach my $item_ref (@{$title_ref->{fields}{$key_field}}){
            push @keys, $item_ref->{content};
        }
        
        my $databases_ref = $convconfig->{exclude}{by_availability}{databases};
        my $locations_ref = $convconfig->{exclude}{by_availability}{locations};
        
        if ($enrichmnt->check_availability_by_isbn({isbn => \@keys, databases => $databases_ref, locations => $locations_ref })){
            $logger->info("Titel mit ISBNs ".join(' ',@keys)." bereits an Standorten ".join(' ',@$locations_ref)." vorhanden!");
            $excluded_titles++;
            next;
        }        
    }

    if ($configfile && $convconfig->{exclude}{by_isbn_in_file}){
        my $key_field = $convconfig->{exclude}{by_isbn_in_file}{field};
        
        my $in_file = 0;
        my @keys = ();
        foreach my $item_ref (@{$title_ref->{fields}{$key_field}}){
            my $isbn13 = OpenBib::Common::Util::to_isbn13($item_ref->{content});
            push @keys, $isbn13 if ($isbn13);

            if (defined $exclude_by_isbn_in_file_ref->{$isbn13} && $exclude_by_isbn_in_file_ref->{$isbn13}){
                $in_file = 1;
            }
        }
        
        if ($in_file){
            $logger->info("Titel mit ISBNs ".join(' ',@keys)." ueber ISBN in Negativ-Datei ausgeschlossen");
            $excluded_titles++;
            next;
        }        
    }
    
    print TITLE encode_json $title_ref, "\n";
    
    $logger->debug(encode_json $title_ref);
        
    if ( my @warnings = $batch->warnings() ) {
        $logger->error(join(' ; ',@warnings));
    }

    if ($count % 10000 == 0){
        $logger->info("$count titles done");
    }

    
    $count++;
    
}

$logger->info("$all_count titles done");
$logger->info("$count titles survived");
$logger->info("Excluded titles: $excluded_titles");

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

close(DAT);

sub konv {
    my $content = shift;

    $content=~s/\s*[.,:\/]\s*$//g;
    $content=~s/&/&amp;/g;
    $content=~s/</&lt;/g;
    $content=~s/>/&gt;/g;
    # Buchstabenersetzungen Grundbuchstabe plus Diaeresis
    $content=~s/u\x{0308}/ü/g;
    $content=~s/a\x{0308}/ä/g;
    $content=~s/o\x{0308}/ö/g;
    $content=~s/U\x{0308}/Ü/g;
    $content=~s/A\x{0308}/Ä/g;
    $content=~s/O\x{0308}/Ö/g;

    return $content;
}

sub add_person {
    my ($person_id,$content_0,$content_a,$content_c,$content_d,$title_ref) = @_;

    # Verlinkt per GND
    if (defined $content_0 && $content_0 =~m/DE-588/){
	$person_id = $content_0;
    }
    
    if (exists $person{$person_id}){
	return;
    }
    
    $person{$person_id} = 1;
    
    my $item_ref = {
	'fields' => {},
    };
    
    $item_ref->{id} = $person_id;

    # Todo: Umstellung auf MARC-Feldnummern
    push @{$item_ref->{fields}{'0800'}}, {
	mult     => 1,
	subfield => '',
	content  => konv($content_a),
    };
    
    # Beruf
    if ($content_c){
	push @{$item_ref->{fields}{'0201'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => konv($content_c),
	};
    }
    
    
    # Lebensjahre
    if ($content_d){
	push @{$item_ref->{fields}{'0200'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => konv($content_d),
	};
    }
    
    print PERSON encode_json $item_ref, "\n";
    
    return $title_ref;
}

sub add_corporatebody {
    my ($corporatebody_id,$content_a) = @_;
    
    if (exists $corporatebody{$corporatebody_id}){
	return;
    }
    
    $corporatebody{$corporatebody_id} = 1;
    
    my $item_ref = {
	'fields' => {},
    };
    
    $item_ref->{id} = $corporatebody_id;

    # Todo: Umstellung auf MARC-Feldnummern
    push @{$item_ref->{fields}{'0800'}}, {
	mult     => 1,
	subfield => '',
	content  => konv($content_a),
    };
        
    print CORPORATEBODY encode_json $item_ref, "\n";
    
    return;
}

sub add_classification {
    my ($classification_id,$content_a) = @_;
    
    if (exists $classification{$classification_id}){
	return;
    }
    
    $classification{$classification_id} = 1;
    
    my $item_ref = {
	'fields' => {},
    };
    
    $item_ref->{id} = $classification_id;

    # Todo: Umstellung auf MARC-Feldnummern
    push @{$item_ref->{fields}{'0800'}}, {
	mult     => 1,
	subfield => '',
	content  => konv($content_a),
    };
        
    print CLASSIFICATION encode_json $item_ref, "\n";
    
    return;
}

sub add_subject {
    my ($subject_id,$content) = @_;
    
    if (exists $subject{$subject_id}){
	return;
    }
    
    $subject{$subject_id} = 1;
    
    my $item_ref = {
	'fields' => {},
    };
    
    $item_ref->{id} = $subject_id;

    # Todo: Umstellung auf MARC-Feldnummern
    push @{$item_ref->{fields}{'0800'}}, {
	mult     => 1,
	subfield => '',
	content  => konv($content),
    };
        
    print SUBJECT encode_json $item_ref, "\n";
    
    return;
}


sub safe_next {
    my $batch = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $record;
    
    eval {
	$record = $batch->next();
    };

    if ($@){
	$logger->error("Error reading next record: ".$@);
	$record=safe_next($batch);
    }

    return $record;
}
