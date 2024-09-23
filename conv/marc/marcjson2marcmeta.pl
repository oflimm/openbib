#!/usr/bin/perl

#####################################################################
#
#  marcjson2marcmeta.pl
#
#  Konverierung von MARC in JSON-Daten aus yaz-marcdump
#  in das Meta-Format mit MARC-Feldbenennungen
#
#  Dieses File ist (C) 2023 Oliver Flimm <flimm@openbib.org>
#
#  basiert auf marc2marcmeta.pl 2022 Oliver Flimm <flimm@openbib.org>
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
use BerkeleyDB;
use JSON::XS qw(decode_json encode_json);
use Log::Log4perl qw(get_logger :levels);
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Enrichment;
use OpenBib::Conv::Common::Util;

our (%person,%corporatebody,%subject,%classification);

my ($inputfile,$configfile,$database,$usebch,$loglevel,$help,$reducemem);

&GetOptions(
    "database=s"      => \$database,
    "inputfile=s"     => \$inputfile,
    "configfile=s"    => \$configfile,
    "reduce-mem"      => \$reducemem,
    "use-bch"         => \$usebch,
    "loglevel=s"      => \$loglevel,
    "help"            => \$help,    
    );

my $logfile = "/var/log/openbib/marcjson2marcmeta-${database}.log";

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

my $config    = OpenBib::Config->new;
my $enrichmnt = new OpenBib::Enrichment;

our $normalizer = new Normalizer;

if (!$inputfile){
    print_help();
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

# my $db = new DB_File::HASHINFO ;

# my $flags = O_CREAT|O_RDWR;

# tie %person, 'DB_File', "./person.db", $flags , 0777, $db ;
# tie %corporatebody, 'DB_File', "./corporatebody.db", $flags, 0777, $db ;
# tie %classification, 'DB_File', "./classification.db", $flags, 0777, $db ;
# tie %subject, 'DB_File', "./subject.db", $flags, 0777, $db ;

if ($reducemem){
    tie %person, 'BerkeleyDB::Hash', -Filename         => "person.db";
    tie %corporatebody, 'BerkeleyDB::Hash', -Filename  => "corporatebody.db";
    tie %classification, 'BerkeleyDB::Hash', -Filename => "classification.db";
    tie %subject, 'BerkeleyDB::Hash', -Filename        => "subject.db";
}

our $excluded_titles = 0;

our $have_title_ref = {};

my $all_count=1;

our $exclude_by_isbn_in_file_ref = {};

our $counter   = 1;
our $mexid     = 1;

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

my $localfields_ref = {};

if ($configfile && defined $convconfig->{localfields}{holdings}){
    $localfields_ref = $convconfig->{localfields}{holdings};
}

my $enrichment_field_mapping_ref = {
    'GND' => '1942', # GND Enrichment
    'HOL' => '1943', # Holdings Enrichment
    'ITM' => '1944', # Items Enrichment
    'POF' => '1945', # Portfolios Enrichment
    'DIV' => '1946', # Digital Inventory Enrichment
};

while (<DAT>){
    my $record_ref = decode_json $_;

    $all_count++;
    
    my $title_ref = {
        'fields' => {},
    };
    
    my $field_mult_ref = {};

    my $titleid = "";

    # ID bestimmen
    foreach my $field_ref (@{$record_ref->{fields}}){
	if (defined $field_ref->{'001'}){
	    $titleid = $field_ref->{'001'};
		
	    # Cleanup Identifier. No slashes!
	    $titleid=~s/\//_/g;
	    $titleid=~s/\\/_/g;    
	    $titleid=~s/\s//g;
	    
	    $title_ref->{id} = $titleid;
	    
	    last;
	}
    }

    if (!$titleid){
    	$logger->error("Titelsatz hat keine ID in 001");
    	next;
    }

    if (defined $have_title_ref->{$title_ref->{id}}){
        $logger->info("Doppelte oder geloeschte ID ".$title_ref->{id});
        next;
    }

    $have_title_ref->{$title_ref->{id}} = 1;
    
    # Leader verarbeiten
    my $leader = $record_ref->{leader};

    if ($leader){
	push @{$title_ref->{'fields'}{'1000'}}, {
	    subfield => 'a', 
	    content  => $leader,
	    mult     => 1,
	};
	
	my $record_status = substr($leader,5,1);
	
	if ($record_status eq "d"){
	    $logger->debug("Ignoring deleted record $titleid");
	    next;
	}
    }
    
    my $has_items    = 0;
    my $has_holdings = 0;
    
    # Sonstige Felder umwandeln

    my $holdings_ref = [];
    
    foreach my $field_ref (@{$record_ref->{fields}}){
	foreach my $field (keys %$field_ref){
	    my $field_nr;

	    # Numeric Fields
	    if ($field =~m/^\d+$/){
		$field_nr = sprintf "%04d", $field;
	    }
	    # Enrichments
	    elsif (defined $enrichment_field_mapping_ref->{$field}){
		$field_nr = $enrichment_field_mapping_ref->{$field};
	    }
	    # Ignore others
	    else {
		next;
	    }

	    # Holdings separat fuer nachgelagertes processing sichern
	    if ($field eq "HOL"){
		push @$holdings_ref, {
		    $field => $field_ref->{$field},
		};

		$has_holdings = 1;
	    }
	    
	    # Leader bearbeiten
	    if ($field =~m/^00\d$/){
		push @{$title_ref->{'fields'}{$field_nr}}, {
		    subfield => '', 
		    content  => $field_ref->{$field},
		    mult     => 1,
		};

		# Einzelinhalte aus 008 in 1008 duplizieren
		if ($field eq '008'){
		    my $date1 = substr($field_ref->{'008'},7,4);
		    my $date2 = substr($field_ref->{'008'},11,4);
		    my $lang  = substr($field_ref->{'008'},35,3);
		    
		    push @{$title_ref->{'fields'}{'1008'}}, {
			subfield => 'a', 
			content  => $date1,
			mult     => 1,
		    } if ($date1 =~m/\d\d\d\d/);
		    
		    push @{$title_ref->{'fields'}{'1008'}}, {
			subfield => 'b', 
			content  => $date2,
			mult     => 1,
		    } if ($date2 =~m/\d\d\d\d/);

		    push @{$title_ref->{'fields'}{'1008'}}, {
			subfield => 'l', 
			content  => $lang,
			mult     => 1,
		    } if ($lang =~m/[a-z][a-z][a-z]/);
		}
		
		next;
	    }
	    
	    my $person_data_ref         = {};
	    my $corporatebody_data_ref  = {};
	    my $subject_data_ref        = {};
	    my $classification_data_ref = {};
	    my $holding_data_ref        = {};	    
	    
	    
	    $field_mult_ref->{$field_nr} = 1 unless (defined $field_mult_ref->{$field_nr});

	    my $ind = "";
	    
	    if (defined $field_ref->{$field}{ind1} && defined $field_ref->{$field}{ind2}){
		$ind = $field_ref->{$field}{ind1}.$field_ref->{$field}{ind2};
	    }

	    unless ($ind =~m/^.?.?$/){
		$logger->fatal("Ungueltige Indikatoren in Titelsatz $titleid");
		next;
	    }
	    
	    my $subfields_ref = [];

	    if (ref $field_ref->{$field} eq "HASH" && defined $field_ref->{$field}{subfields}){
		$subfields_ref = $field_ref->{$field}{subfields};
	    }
	    
	    # Default: Alle Felder sind immer auch Titelfelder
	    foreach my $subfield_ref (@$subfields_ref){
		foreach my $subfield_code (keys %$subfield_ref){
		    my $content = $normalizer->cleanup($subfield_ref->{$subfield_code});
		    push @{$title_ref->{'fields'}{$field_nr}}, {
			subfield => $subfield_code,
			content  => $content,
			ind      => $ind,
			mult     => $field_mult_ref->{$field_nr},
		    };
		    
		    # Cachen von Normdateninhalten
		    if ($field eq "100" || $field eq "700"){
			$person_data_ref->{$subfield_code} = $content;
		    }
		    elsif ($field eq "110" || $field eq "710"){
			$corporatebody_data_ref->{$subfield_code} = $content;
		    }
		    elsif ($field eq "082"){
			$classification_data_ref->{$subfield_code} = $content;
		    }
		    elsif ($field eq "600" || $field eq "610" || $field eq "648" || $field eq "650" || $field eq "651" || $field eq "655" || $field eq "688" || $field eq "689"){
			$subject_data_ref->{$subfield_code} = $content;
		    }

		    if (defined $localfields_ref->{$field}){
			$holding_data_ref->{$subfield_code} = $content;
		    }
		}
	    }
	    
	    # Zusaetzlich ggf. Generierung der Normdaten

	    # Verfasser
	    if ($field eq "100" || $field eq "700"){
		# Verfasser
		my $linkage   = $person_data_ref->{'6'} || "";
		
		my $content_a = $person_data_ref->{'a'} || ""; # Personal name
		my $content_b = $person_data_ref->{'b'} || ""; # Numeration
		my $content_c = $person_data_ref->{'c'} || ""; # Titles and other words associated
		my $content_d = $person_data_ref->{'d'} || ""; # Dates associated
		my $content_0 = $person_data_ref->{'0'} || ""; # Authority number
		
		# Linkage = Verweis zur ID des Nordatensates

		# GND vorhanden, dann Lingage = GND
		if ($content_0 && $content_0 =~m/DE-588/){
		    $linkage = $content_0;
		}
		
		if (!$linkage){
		    # Keine GND mitgegeben, dann ID aus Personennamen und Geburtsdatum generieren
		    $linkage = $content_a;
		    if ($content_d){
			$linkage.=$content_d;
		    }
		    
		    $linkage=~s/\W+//g;
		}
		
		# Und als neues Linkage-Feld uebernehmen
		push @{$title_ref->{'fields'}{$field_nr}}, {
		    subfield => '6', # Linkage-Subfield
		    content  => $linkage,
		    ind      => $ind,
		    mult     => $field_mult_ref->{$field_nr},
		};
		
		# Beispiel 'Maximilian II'
		if ($content_a && $content_b){
		    $content_a = $content_a." ".$content_b;
		}
		
		if ($linkage && $content_a){
		    add_person($linkage,$content_0,$content_a,$content_c,$content_d);
		}		
	    } # Ende Personen 
	    # Koerperschaften
	    elsif ($field eq "110" || $field eq "710"){
		my $linkage   = $corporatebody_data_ref->{'6'} || "";
		
		my $content_a = $corporatebody_data_ref->{'a'} || ""; # Name
		my $content_0 = $corporatebody_data_ref->{'0'} || ""; # Authority number
		
		# Linkage = Verweis zur ID des Nordatensates

		# GND vorhanden, dann Lingage = GND
		if ($content_0 && $content_0 =~m/DE-588/){
		    $linkage = $content_0;
		}
		
		if (!$linkage){
		    # Keine ID mitgegeben, dann ID aus Koerperschaftsnamen generieren
		    $linkage = $content_a;
		    
		    $linkage=~s/\W+//g;
		}

		# Und als neues Linkage-Feld uebernehmen		    
		push @{$title_ref->{'fields'}{$field_nr}}, {
		    subfield => '6', # Linkage-Subfield
		    content  => $linkage,
		    ind      => $ind,
		    mult     => $field_mult_ref->{$field_nr},
		};
				
		if ($linkage && $content_a){
		    add_corporatebody($linkage,$content_a);
		}
	    } # Ende Koerperschaften
	    # Klassifikationen
	    elsif ($field eq "082"){
		my $linkage = $classification_data_ref->{'6'} || "";
		
		my $content = $classification_data_ref->{'a'} || ""; # Name
		
		# Linkage = Verweis zur ID des Nordatensates
		
		if (!$linkage){
		    # Keine ID mitgegeben, dann ID aus Koerperschaftsnamen generieren
		    $linkage = $content;
		    
		    $linkage=~s/\W+//g;

		    # Und als neues Linkage-Feld uebernehmen		    
		    push @{$title_ref->{'fields'}{$field_nr}}, {
			subfield => '6', # Linkage-Subfield
			content  => $linkage,
			ind      => $ind,
			mult     => $field_mult_ref->{$field_nr},
		    } if ($linkage);
		}
		
		
		if ($linkage && $content){
		    add_classification($linkage,$content);
		}		
	    } # Ende Klassifikationen
	    # Schlagworte
	    elsif ($field eq "600" || $field eq "610" || $field eq "648" || $field eq "650" || $field eq "651" || $field eq "655" || $field eq "688" || $field eq "689"){
		my $linkage = $classification_data_ref->{'6'} || "";
		
		my $content_a = $subject_data_ref->{'a'} || ""; # Name
		my $content_x = $subject_data_ref->{'x'} || ""; # 
		my $content_0 = $subject_data_ref->{'0'} || ""; # Authority number
		
		my $content = $content_a;
		
		if ($content && $content_x){
		    $content.=" / ".$content_x;
		}
		
		# Linkage = Verweis zur ID des Nordatensates

		# GND vorhanden, dann Lingage = GND
		if ($content_0 && $content_0 =~m/DE-588/){
		    $linkage = $content_0;
		}
		
		if (!$linkage){
		    # Keine ID mitgegeben, dann ID aus Koerperschaftsnamen generieren
		    $linkage = $content;
		    
		    $linkage=~s/\W+//g;
		}

		# Und als neues Linkage-Feld uebernehmen		    
		push @{$title_ref->{'fields'}{$field_nr}}, {
		    subfield => '6', # Linkage-Subfield
		    content  => $linkage,
		    ind      => $ind,
		    mult     => $field_mult_ref->{$field_nr},
		} if ($linkage);
		
		if ($linkage && $content){
		    add_subject($linkage,$content);
		}		
	    } # Ende Subject
	    # Exemplardaten
	    elsif (defined $localfields_ref->{$field}){
		# Feld und Subfeld anhand Item Anreicherung beim Publishing
		#
		# Items in Feld ITM
		#
		# Subfields
		# 'd': 'id'
		# 'h': '3330' # Permanent library subfield
		# 's': '0014' # Item call number subfield
		# 'k': '0016' # Permanent location subfield
		# 'a': '0010' # Barcode subfield
		# 'p': '0020' # Item policy subfield
		# 'g': '0021' # Material type subfield
		# 'e': '0022' # Item status subfield
		# 'b': '0023' # Call number subfield
		# 'm': '0024' # Current location subfield
		# 'i': '0025' # Description subfield
		# 'n': '0026' # Public note subfield
		# 'f': '0027' # Fulfillment note subfield
		# 'u': '0028' # Internal note 1 subfield
		# 'v': '0029' # Internal note 2 subfield
		# 'w': '0030' # Internal note 3 subfield
		# 'q': '0031' # Due back date subfield
		# 'r': '0032' # Receiving date subfield
		# 'x': '0033' # Retention reason subfield
		# 'y': '0034' # Retention note subfield


		my $is_issue       = 0;
		my $is_acquisition = 0;
		
		my $subfields_ref = [];
		
		if (ref $field_ref->{$field} eq "HASH" && defined $field_ref->{$field}{subfields}){
		    $subfields_ref = $field_ref->{$field}{subfields};
		}

		
		# Default: Alle Felder sind immer auch Titelfelder
		foreach my $subfield_ref (@$subfields_ref){
		    foreach my $subfield_code (keys %$subfield_ref){
			if ($subfield_code eq "t" && $subfield_ref->{$subfield_code} eq "ACQ"){
			    $is_acquisition = 1;
			}
			if ($subfield_code eq "g" && $subfield_ref->{$subfield_code} eq "ISSUE"){
			    $is_issue = 1;
			}
			
		    }
		}

		# Zeitschriftenhefte im Erwerbungsstatus ausschliessen
		unless ($is_acquisition && $is_issue && $usebch){
		
		    $has_items = 1;
		    
		    $logger->debug("Processing field $field");
		    
		    my $holding_ref = {
			'id'     => $mexid++,
			    'fields' => {
				'0004' =>
				    [
				     {
					 mult     => 1,
					 subfield => '',
					 content  => $title_ref->{id},
					 ind      => $ind,
				     },
				    ],
			},
		    };
		    
		    foreach my $subfield (keys %{$localfields_ref->{$field}}){
			$logger->debug("Processing subfield $subfield");
			my $destfield = $localfields_ref->{$field}{$subfield};
			my $content = $holding_data_ref->{$subfield};
			
			# Ggf. ID in Subfeld verwenden
			if ($destfield eq "id"){
			    $holding_ref->{id} = $content;
			}
			else {
			    push @{$holding_ref->{fields}{$destfield}}, {
				content  => $normalizer->cleanup($content),
				subfield => '',
				mult     => 1,
			    };
			}
		    }
		    
		    if ($logger->is_debug){
			$logger->debug(Dump($holding_ref));
		    }
		    
		    print HOLDING encode_json $holding_ref,"\n";
		}
	    }	    
	    
	    $field_mult_ref->{$field_nr}++;
	}
    }


    $logger->debug("has items: $has_items - has holdings: $has_holdings");    

    # Keine Items? Dann Exemplardaten aus holdings, z.B. bei Zeitschriften
    if (!$has_items && $has_holdings){
	# Feld und Subfeld anhand Holding Anreicherung beim Publishing
	#
	# Holdings in Feld HOL
	#
	# Subfields
	# '8'    : 'id'
	# 'b'    : '3330' # Permanent library subfield
	# 'h'    : '0014' # Item call number subfield
	# 'c'    : '0016' # Permanent location subfield
	# 'a'+'z': '1204' # Timespan + gaps

	$logger->debug("Processing holdings");

	# Holding-Anreicherung in HOL
	if ($logger->is_debug){
	    $logger->debug("Holdings". YAML::Dump($holdings_ref));
	}

	my $all_holdings_ref   = [];
	my $single_holding_ref = {};

	# Reorganisieren der umgstaendlich gepublishten Holding-Informationen
	foreach my $field_ref (@$holdings_ref){
	    
	    my $subfields_ref =  $field_ref->{'HOL'}{'subfields'};

	    # if ($logger->is_debug){
	    # 	$logger->debug(YAML::Dump($subfields_ref));
	    # }
	    
	    foreach my $subfield_ref (@$subfields_ref){
		foreach my $subfield_code (keys %$subfield_ref){
		    next unless ($subfield_code =~m/^(a|b|c|h|z|8|9)$/);

		    if ($subfield_code eq "b" && keys %{$single_holding_ref}){ # Beginn neues Holding
			push @$all_holdings_ref, $single_holding_ref; # fertiges altes holding speichern
			$single_holding_ref = {};
			$single_holding_ref->{$subfield_code} = $subfield_ref->{$subfield_code};
		    }
		    else {
			$single_holding_ref->{$subfield_code} = $subfield_ref->{$subfield_code};		    
		    }
		}
	    }	
	}

	push @$all_holdings_ref, $single_holding_ref if (keys %{$single_holding_ref}); # letztes holding speichern

	
	foreach my $single_holding_ref (@$all_holdings_ref){
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

	    # Holding-ID setzten, ansonsten bleibt hochgezaehlte ID
	    if ($single_holding_ref->{'8'}){
		$holding_ref->{'id'} = $single_holding_ref->{'8'};
	    }
	    
	    if ($single_holding_ref->{'b'}){
		my $content = $single_holding_ref->{'b'};
		
		push @{$holding_ref->{fields}{'3330'}}, {
		    content  => $normalizer->cleanup($content),
		    subfield => '',
		    mult     => 1,
		};
	    }

	    if ($single_holding_ref->{'c'}){
		my $content = $single_holding_ref->{'c'};

		push @{$holding_ref->{fields}{'0016'}}, {
		    content  => $normalizer->cleanup($content),
		    subfield => '',
		    mult     => 1,
		};
	    }

	    if ($single_holding_ref->{'h'}){
		my $content = $single_holding_ref->{'h'};

		push @{$holding_ref->{fields}{'0014'}}, {
		    content  => $normalizer->cleanup($content),
		    subfield => '',
		    mult     => 1,
		};
	    }

	    if ($single_holding_ref->{'a'}){
		my $content = $single_holding_ref->{'a'};

		if ($single_holding_ref->{'z'}){
		    $content.=" ".$single_holding_ref->{'z'};
		}

		if ($single_holding_ref->{'9'}){
		    $content = $single_holding_ref->{'9'}." ".$content;
		}
		
		push @{$holding_ref->{fields}{'1204'}}, {
		    content  => $normalizer->cleanup($content),
		    subfield => '',
		    mult     => 1,
		};
	    }

	    if ($logger->is_debug){
		$logger->debug(Dump($holding_ref));
	    }
	    
	    print HOLDING encode_json $holding_ref,"\n";	    
	}
	
	if ($logger->is_debug){
	    $logger->debug(YAML::Dump($all_holdings_ref));
	}	
    }
    
    # if ($configfile && $convconfig->{exclude}{by_availability}){
    #     my $key_field = $convconfig->{exclude}{by_availability}{field};
        
    #     my @keys = ();
    #     foreach my $item_ref (@{$title_ref->{fields}{$key_field}}){
    #         push @keys, $item_ref->{content};
    #     }
        
    #     my $databases_ref = $convconfig->{exclude}{by_availability}{databases};
    #     my $locations_ref = $convconfig->{exclude}{by_availability}{locations};
        
    #     if ($enrichmnt->check_availability_by_isbn({isbn => \@keys, databases => $databases_ref, locations => $locations_ref })){
    #         $logger->info("Titel mit ISBNs ".join(' ',@keys)." bereits an Standorten ".join(' ',@$locations_ref)." vorhanden!");
    #         $excluded_titles++;
    #         next;
    #     }        
    # }

    # if ($configfile && $convconfig->{exclude}{by_isbn_in_file}){
    #     my $key_field = $convconfig->{exclude}{by_isbn_in_file}{field};
        
    #     my $in_file = 0;
    #     my @keys = ();
    #     foreach my $item_ref (@{$title_ref->{fields}{$key_field}}){
    #         my $isbn13 = OpenBib::Common::Util::to_isbn13($item_ref->{content});
    #         push @keys, $isbn13 if ($isbn13);

    #         if (defined $exclude_by_isbn_in_file_ref->{$isbn13} && $exclude_by_isbn_in_file_ref->{$isbn13}){
    #             $in_file = 1;
    #         }
    #     }
        
    #     if ($in_file){
    #         $logger->info("Titel mit ISBNs ".join(' ',@keys)." ueber ISBN in Negativ-Datei ausgeschlossen");
    #         $excluded_titles++;
    #         next;
    #     }        
    # }
    
    print TITLE encode_json $title_ref, "\n";
    
    # if ($logger->is_debug){
    # 	$logger->debug(encode_json $title_ref);
    # }
    
    if ($counter % 10000 == 0){
	$logger->info("$counter titles done");
    }
        
    $counter++;
}

$logger->info(($all_count - 1)." titles done");
$logger->info(($counter - 1)." titles survived");
$logger->info("Excluded titles: $excluded_titles");

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

close(DAT);

print STDERR "All $counter records converted\n";

sub add_person {
    my ($person_id,$content_0,$content_a,$content_c,$content_d,$title_ref) = @_;
    
    if (exists $person{$person_id}){
	return;
    }

    $person{$person_id} = 1;
    
    my $item_ref = {
	'fields' => {},
    };
    
    $item_ref->{id} = $person_id;

    # Todo: Umstellung auf MARC-Feldnummern

    if ($person_id=~m/DE-588/){
	my ($gnd) = $person_id =~m/^.DE-588.(.+)*/;
	push @{$item_ref->{fields}{'0010'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => $gnd,
	};
    }
    
    push @{$item_ref->{fields}{'0800'}}, {
	mult     => 1,
	subfield => '',
	content  => $normalizer->cleanup($content_a),
    };
    
    # Beruf
    if ($content_c){
	push @{$item_ref->{fields}{'0201'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => $normalizer->cleanup($content_c),
	};
    }
    
    
    # Lebensjahre
    if ($content_d){
	push @{$item_ref->{fields}{'0200'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => $normalizer->cleanup($content_d),
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

    if ($corporatebody_id=~m/DE-588/){
	my ($gnd) = $corporatebody_id =~m/^.DE-588.(.+)*/;
	push @{$item_ref->{fields}{'0010'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => $gnd,
	};
    }

    push @{$item_ref->{fields}{'0800'}}, {
	mult     => 1,
	subfield => '',
	content  => $normalizer->cleanup($content_a),
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
	content  => $normalizer->cleanup($content_a),
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

    if ($subject_id=~m/DE-588/){
	my ($gnd) = $subject_id =~m/^.DE-588.(.+)*/;
	push @{$item_ref->{fields}{'0010'}}, {
	    mult     => 1,
	    subfield => '',
	    content  => $gnd,
	};
    }

    push @{$item_ref->{fields}{'0800'}}, {
	mult     => 1,
	subfield => '',
	content  => $normalizer->cleanup($content),
    };
        
    print SUBJECT encode_json $item_ref, "\n";
    
    return;
}

sub print_help {
    print << "HELP";
marcjson2marcmeta.pl - Aufrufsyntax

    marcjson2marcmeta.pl --inputfile=xxx --configfile=yyy

      --inputfile=source.json      : Name der Eingabedatei
      --configfile=pool.yml        : Name der Parametrisierungsdaei
      --database=pool              : Name der Katalogdatenbank

      -reduce-mem                  : Speichernutzungsreduzierung durch Auslagerungsdateien
      
Die Eingabedatei muss im MARC-IN-JSON Format vorliegen, wie es yaz-marcdump generiert:

yaz-marcdump -o json source.mrc | jq -S -c . > source.json

Wenn ausgehend von einem Komplettexport weitere Incrementelle Exporte 
existieren, dann muessen diese vorher zu einer Gesamtdatei zusammengefuegt 
werden. Dabei sind folgende Regeln einzuhalten:

* Die einzelnen Dateien werden in der Reihenfolge ihrer Aktualitaet 
  zusammengefuegt, von der aktuellsten am Anfang zur aeltesten am Ende
* An den Anfang der Gesamtdatei kommen die nach Aktualitaet sortierten 
  Exportdateien mit geloeschten Titeln
* Danach kommen die nach Aktualitaet sortierten Exportdateien mit neuen
  Titeln

z.B.

cat `ls -r1 ubkfull*_delete*.mrc` `ls -r1 ubkfull*_new*.mrc` > source.mrc

HELP

}

package Normalizer;

sub new {
    my $class = shift;

    my $self = {};

    bless ($self, $class);

    # Cleanup UTF8
    # see: https://blog.famzah.net/2010/07/01/filter-a-character-sequence-leaving-only-valid-utf-8-characters/
#    $content =~ s/.*?((?:[\t\n\r\x20-\x7E])+|(?:\xD0[\x90-\xBF])+|(?:\xD1[\x80-\x8F])+|(?:\xC3[\x80-\xBF])+|).*?/$1/sg;
    
    my %char_replacements = (
#	"\s*[.,:\/]\s*\$","",
	"&","&amp;",
	"<","&lt;",
	">","&gt;",
	
	);

    my $chars_to_replace = join '|',
	#    map quotemeta, 
	keys %char_replacements;
    
    $self->{chars_to_replace} = qr/$chars_to_replace/;
    
    $self->{char_replacements} = \%char_replacements;

    return $self;
}

sub cleanup {
    my $self = shift;
    my $content = shift;

    return "" unless (defined $content);
    
    my $chars_to_replace   = $self->{chars_to_replace};
    my %char_replacements  = %{$self->{char_replacements}};

    # Reset &lt; / &gt;
    $content =~ s/&lt;/</g;
    $content =~ s/&gt;/>/g;

    # Normalize
    $content =~ s/($chars_to_replace)/$char_replacements{$1}/g;

    return $content;

}
