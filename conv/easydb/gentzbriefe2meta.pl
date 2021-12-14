#!/usr/bin/perl

#####################################################################
#
#  gentzbriefe2meta.pl
#
#  Dieses File ist (C) 2020 Oliver Flimm <flimm@ub.uni-koeln.de>
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

use File::Slurp;
use Encode 'decode';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use JSON::XS;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;
use OpenBib::Catalog::Factory;

my ($logfile,$loglevel,$inputfile);

&GetOptions(
	    "inputfile=s"             => \$inputfile,
            "logfile=s"               => \$logfile,
            "loglevel=s"              => \$loglevel,
	    );

if (!$inputfile){
    print << "HELP";
gentzbriefe2meta.pl - Aufrufsyntax

    gentzbriefe2meta.pl --inputfile=xxx

      --inputfile=                 : Name der Eingabedatei

HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/gentzbriefe2meta.log';
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

our $have_titleid_ref = {};

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

open(IN ,           "<:raw", $inputfile );

my $multcount_ref = {};

my $persons_done_ref = {};
my $corporatebodies_done_ref = {};
my $recipients_done_ref = {};

while (my $jsonline = <IN>){
    my $item_ref = decode_json($jsonline); 

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($item_ref));
    }
    
    my $title_ref = {
        'fields' => {},
    };

    $multcount_ref = {};

    if ($item_ref->{_system_object_id}) {
	$title_ref->{id} = $item_ref->{_system_object_id};
    }
    else {
	$logger->error("No id found for record: ".YAML::Dump($item_ref));
	exit;
    }

    if (defined $have_titleid_ref->{$title_ref->{id}}){
	$logger->error("Doppelte ID: ".$title_ref->{id}."(_system_object_id: ".$item_ref->{_system_object_id}.", contentdm_id: ".$item_ref->{contentdm_id});
	next;
    }

    $have_titleid_ref->{$title_ref->{id}} = 1;

    ### contentdm_id -> 0010
    if ($item_ref->{contentdm_id}){
	push @{$title_ref->{fields}{'0010'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{contentdm_id},
	};
    }

    ### sender -> 0100 (Personen)
    my @senders = ();
    
    if (defined $item_ref->{sender}){
	my @name = ();
	
	if ($item_ref->{sender}{familyname} || $item_ref->{sender}{givenname}){
	    push @name, $item_ref->{sender}{familyname} if ($item_ref->{sender}{familyname});
	    push @name, $item_ref->{sender}{givenname} if ($item_ref->{sender}{givenname});
	}
	elsif ($item_ref->{sender}{name}){
	    push @name, $item_ref->{sender}{name};
	}
	
	if (@name){
	    my $name = join(', ',@name);
	    
	    my $person_id = $item_ref->{sender}{_system_object_id};
	    
	    push @senders, $name;
	    
	    my $mult = 1;
	    
	    if (!$persons_done_ref->{$person_id}){
		
		my $normitem_ref = {
		    'fields' => {},
		};
		$normitem_ref->{id} = $person_id;
		push @{$normitem_ref->{fields}{'0800'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $name,
		};
		
		if ($item_ref->{sender}{person_gndid}{conceptURI}){
		    push @{$normitem_ref->{fields}{'0312'}}, { # PND/GND
			mult     => 1,
			subfield => '',
			content  => $item_ref->{sender}{person_gndid}{conceptURI},
		    };		
		}
		
		print PERSON encode_json $normitem_ref, "\n";
		
		$persons_done_ref->{$person_id} = 1;
	    }
	    
	    my $new_category = "0100";
	    
	    push @{$title_ref->{fields}{$new_category}}, {
		content    => $name,
		mult       => $mult,
		subfield   => '',
		id         => $person_id,
		supplement => '',
	    };
	    
	    $mult++;
	}
    }

    ### _nested:gentz_letter__recipients -> 0101 (Personen)
    
    my @recipients = ();
    
    if (defined $item_ref->{'_nested:gentz_letter__recipients'}){
	foreach my $recipient_ref (@{$item_ref->{'_nested:gentz_letter__recipients'}}){
	    
	    my @name = ();
	    if ($recipient_ref->{familyname} || $recipient_ref->{givenname}){
		push @name, $recipient_ref->{familyname} if ($recipient_ref->{familyname});
		push @name, $recipient_ref->{givenname} if ($recipient_ref->{givenname});

	    }
	    elsif ($recipient_ref->{name}){ # Koerperschaft....
		push @name, $recipient_ref->{name};
	    }
	    
	    my $name = join(', ',@name);
	    
	    my $person_id = $recipient_ref->{_system_object_id};
	    
	    push  @recipients, $name;
	    
	    my $mult = 1;
	    
	    if (!$persons_done_ref->{$person_id}){
		
		my $normitem_ref = {
		    'fields' => {},
		};
		
		$normitem_ref->{id} = $person_id;
		push @{$normitem_ref->{fields}{'0800'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $name,
		};
		
		if ($recipient_ref->{person_gndid}{conceptURI}){
		    push @{$normitem_ref->{fields}{'0312'}}, { # PND/GND
			mult     => 1,
			subfield => '',
			content  => $recipient_ref->{person_gndid}{conceptURI},
		    };		
		}
		
		print PERSON encode_json $normitem_ref, "\n";
		
		$persons_done_ref->{$person_id} = 1;
	    }
	    
	    my $new_category = "0101";
	    
	    push @{$title_ref->{fields}{$new_category}}, {
		content    => $name,
		mult       => $mult,
		subfield   => '',
		id         => $person_id,
		supplement => '',
	    };
	    
	    $mult++;
	}        
    }

    ### archive -> 0200 (Koerperschaften)
    if (defined $item_ref->{archive}){
	my $name = $item_ref->{archive}{name};
	
	my $corporatebody_id = $item_ref->{archive}{_system_object_id};
	    
	my $mult = 1;
	
	if (!$corporatebodies_done_ref->{$corporatebody_id}){
		
	    my $normitem_ref = {
		'fields' => {},
	    };
	    $normitem_ref->{id} = $corporatebody_id;
	    push @{$normitem_ref->{fields}{'0800'}}, {
		mult     => 1,
		subfield => '',
		content  => $name,
	    };
	    
	    if ($item_ref->{archive}{archive_location}){
		push @{$normitem_ref->{fields}{'0810'}}, { # Ort
		    mult     => 1,
		    subfield => '',
		    content  => $item_ref->{archive}{archive_location},
		};		
	    }
	    
	    if ($item_ref->{archive}{archive_country}){
		push @{$normitem_ref->{fields}{'0820'}}, { # Land
		    mult     => 1,
		    subfield => '',
		    content  => $item_ref->{archive}{archive_country},
		};		
	    }
		
	    print CORPORATEBODY encode_json $normitem_ref, "\n";
		
	    $corporatebodies_done_ref->{$corporatebody_id} = 1;

	}
	
	my $new_category = "0200";
	
	push @{$title_ref->{fields}{$new_category}}, {
	    content    => $name,
	    mult       => $mult,
	    subfield   => '',
	    id         => $corporatebody_id,
	    supplement => '',
	};
	
	$mult++;
    }
    
    ### Gesamter Exportsatz -> 0001
    push @{$title_ref->{fields}{'0001'}}, {
	mult     => 1,
	subfield => '',
	content => $item_ref,
    };
        
    ### title -> 0331    
    if ($item_ref->{title}){
	push @{$title_ref->{fields}{'0331'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{title},
	}
    }
    
    ### reference_publication_incipit -> 0335
    if ($item_ref->{reference_publication_incipit}){
	push @{$title_ref->{fields}{'0335'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{reference_publication_incipit},
	}
    }

    ### incipit -> 0336
    if ($item_ref->{incipit}){
	push @{$title_ref->{fields}{'0336'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{incipit},
	}
    }
    
    ### reference_publication/print_title -> 0590
    if ($item_ref->{reference_publication}{print_title}){
	my $content = $item_ref->{reference_publication}{print_title};

	if ($item_ref->{reference_publication}{print_publication_year}){
	    $content.=", (".$item_ref->{reference_publication}{print_publication_year}.")";
	}
	
	push @{$title_ref->{fields}{'0590'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $content,
	}
    }

    ### reference_publication/_nested:printed_publication_print_editor -> 0591
    if (defined $item_ref->{reference_publication}){
	my $print_editors = $item_ref->{reference_publication}{'_nested:printed_publication__print_editors'};

	if ($print_editors){
	    foreach my $editor_ref (@{$item_ref->{reference_publication}{'_nested:printed_publication__print_editors'}}){
		if ($editor_ref->{print_editor}){
		    my $content = $editor_ref->{print_editor};
		    
		    if ($item_ref->{reference_publication}{print_additional_info}){
			$content.="; [".$item_ref->{reference_publication}{print_additional_info}."]";
		    }
		    
		    push @{$title_ref->{fields}{'0591'}}, {
			mult     => 1,
			subfield => '',
			content => $content,
		    }		    
		}
	    }
	}
    }


    ### reference_publication/print_locations -> 0592
    if (defined $item_ref->{reference_publication}){
	my $print_locations = $item_ref->{reference_publication}{'print_locations'};

	push @{$title_ref->{fields}{'0592'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $print_locations,
	} if ($print_locations);		    
    }

    ### reference_publication/print_publication_type -> 0593
    if (defined $item_ref->{reference_publication}){
	my $print_type = $item_ref->{reference_publication}{'print_publication_type'}{'de-DE'};

	push @{$title_ref->{fields}{'0593'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $print_type,
	} if ($print_type);		    
    }

    ### reference_publication/print_publication_type -> 0594
    if (defined $item_ref->{reference_publication}){
	my $print_type = $item_ref->{reference_publication}{'print_publication_type'}{'de-DE'};

	push @{$title_ref->{fields}{'0593'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $print_type,
	} if ($print_type);		    
    }
    
    ### reference_publication_date -> 0595
    if ($item_ref->{reference_publication_date}){
	push @{$title_ref->{fields}{'0595'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{reference_publication_date},
	}
    }

    ### reference_publication_page -> 0443
    if ($item_ref->{reference_publication_page}){
	push @{$title_ref->{fields}{'0433'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{reference_publication_page},
	}
    }

    ### based_on -> 0451
    if ($item_ref->{based_on}){
	push @{$title_ref->{fields}{'0451'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{based_on}{'de-DE'},
	}
    }

    ### tanscription_creator -> 0480
    if ($item_ref->{transcription_creator}){
	push @{$title_ref->{fields}{'0480'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{transcription_creator},
	}
    }
    
    ### tanscription_method -> 0481
    if ($item_ref->{transcription_method}){
	push @{$title_ref->{fields}{'0481'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{transcription_method}{'de-DE'},
	}
    }

    ### tanscription_type -> 0482
    if ($item_ref->{transcription_type}){
	push @{$title_ref->{fields}{'0482'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{transcription_type}{'de-DE'},
	}
    }

    ### transmission_type -> 
    if ($item_ref->{status_archive}){
	push @{$title_ref->{fields}{'0483'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{transmission_type},
	}
    }
            
    ### sent_date_original -> 0424
    my $year = "";
    
    if ($item_ref->{sent_date_original}){
	($year) = $item_ref->{sent_date_original} =~m/(\d\d\d\d)/;
	
	push @{$title_ref->{fields}{'0424'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{sent_date_original},
	}
    }

    ### sent_date_year || sent_date_original -> 0425
    if ($year || $item_ref->{sent_date_year}){
	$year = ($item_ref->{sent_date_year})?$item_ref->{sent_date_year}:$year;
	
	push @{$title_ref->{fields}{'0425'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $year,
	}
    }

    ### _nested:gentz_letter__records_collection_herterich/collection_herterich -> 0490
    ### _nested:gentz_letter__records_collection_herterich/collection_herterich_type -> 0491
    my $herterich_mult = 1;

    if (defined $item_ref->{'_nested:gentz_letter__records_collection_herterich'} && @{$item_ref->{'_nested:gentz_letter__records_collection_herterich'}}){
	foreach my $subitem_ref (@{$item_ref->{'_nested:gentz_letter__records_collection_herterich'}}){
	    push @{$title_ref->{fields}{'0490'}}, {
		mult     => $herterich_mult,
		subfield => '',
		content => $subitem_ref->{collection_herterich},
	    } if ($subitem_ref->{collection_herterich});

	    push @{$title_ref->{fields}{'0491'}}, {
		mult     => $herterich_mult,
		subfield => '',
		content => $subitem_ref->{collection_herterich_type}{'de-DE'},
	    } if ($subitem_ref->{collection_herterich_type});

	    $herterich_mult++;
	}
    }    

    ### sent_location_normalized -> Multgruppe 0410/2410a/2410b
    # Alternativ: Eigene Normdatei (Klassifikation oder Schlagwort)
    my $location_mult = 1;
        
    if ($item_ref->{sent_location_normalized}{name}){
	push @{$title_ref->{fields}{'0410'}}, {
	    mult => $location_mult,
	    subfield => '',
	    content => $item_ref->{sent_location_normalized}{name},
	}
    }

    if (defined $item_ref->{sent_location_normalized}{geoname} && $item_ref->{sent_location_normalized}{geoname}{conceptURI}){
	push @{$title_ref->{fields}{'2410'}}, {
	    mult => $location_mult,
	    subfield => "a",
	    content => $item_ref->{sent_location_normalized}{geoname}{conceptURI},
	}
    }
    
    if (defined $item_ref->{sent_location_normalized}{gnd_location} && $item_ref->{sent_location_normalized}{gnd_location}{conceptURI}){
	push @{$title_ref->{fields}{'2410'}}, {
	    mult => $location_mult,
	    subfield => "b",
	    content => $item_ref->{sent_location_normalized}{gnd_location}{conceptURI},
	}
    }

    ### format_size -> 0433
    if ($item_ref->{format_size}){
	push @{$title_ref->{fields}{'0433'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{format_size},
	}
    }

    ### language -> 0015
    if ($item_ref->{language}{'de-DE'}){
	push @{$title_ref->{fields}{'0015'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{language}{'de-DE'},
	}
    }

    ### _tags (validiert/Ersterhebung) -> 0511
    if ($item_ref->{_tags}){
	foreach my $tags_ref (@{$item_ref->{_tags}}){
	    if ($tags_ref->{_name}{'de-DE'} && ($tags_ref->{_name}{'de-DE'} eq "validiert" || $tags_ref->{_name}{'de-DE'} eq "Ersterhebung")){
		push @{$title_ref->{fields}{'0511'}}, {
		    mult     => 1,
		    subfield => '',
		    content => $tags_ref->{_name}{'de-DE'},
		};
	    }
	}
    }

    ### archiv(name+archive_location+archive_country) -> 0412
    if ($item_ref->{archive}{name}){
	my @names = ();

	push @names, $item_ref->{archive}{name} if ($item_ref->{archive}{name});
	push @names, $item_ref->{archive}{archive_location} if ($item_ref->{archive}{archive_location});
	push @names, $item_ref->{archive}{archive_country} if ($item_ref->{archive}{archive_country});

	my $name = join(', ',@names);
	
    	push @{$title_ref->{fields}{'0412'}}, {
    	    mult     => 1,
    	    subfield => '',
    	    content => $name,
    	}
    }

    ### citation -> 0522
    if ($item_ref->{citation}){
	push @{$title_ref->{fields}{'0522'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{citation},
	}
    }

    ### status_archive -> 0413
    if ($item_ref->{status_archive}){
	push @{$title_ref->{fields}{'0413'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{status_archive}{'de-DE'},
	}
    }
    
    ### provenance -> 1664
    if ($item_ref->{provenance}){
	push @{$title_ref->{fields}{'1664'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{provenance},
	}
    }

    ### _nested:gentz_letter__doublets -> Multgruppe 460ff
    my $doublets_mult = 1;
    if (defined $item_ref->{'_nested:gentz_letter__doublets'} && @{$item_ref->{'_nested:gentz_letter__doublets'}}){
	foreach my $subitem_ref (@{$item_ref->{'_nested:gentz_letter__doublets'}}){
	    push @{$title_ref->{fields}{'0460'}}, {
		mult     => $doublets_mult,
		subfield => '',
		content => $subitem_ref->{doublet_publication}{print_title},
	    } if ($subitem_ref->{doublet_publication}{print_title});
	    
	    push @{$title_ref->{fields}{'0461'}}, {
		mult     => $doublets_mult,
		subfield => '',
		content => $subitem_ref->{page_doublet},
	    } if ($subitem_ref->{page_doublet});
	    
	    push @{$title_ref->{fields}{'0462'}}, {
		mult     => $doublets_mult,
		subfield => '',
		content => $subitem_ref->{incipit_doublet},
	    } if ($subitem_ref->{incipit_doublet});

	    push @{$title_ref->{fields}{'0463'}}, {
		mult     => $doublets_mult,
		subfield => '',
		content => $subitem_ref->{sent_location_doublet},
	    } if ($subitem_ref->{sent_location_doublet});

	    push @{$title_ref->{fields}{'0464'}}, {
		mult     => $doublets_mult,
		subfield => '',
		content => $subitem_ref->{doublet_publication}{print_locations},
	    } if ($subitem_ref->{doublet_publication}{print_locations});
	    

	    $doublets_mult++;
	}
    } 
    

    
    # Auswertung Kategorie 'Mit Inhaltsrepraesentation'    
    my $is_inhalt_volltext = 0;
    my $is_inhalt_analog = 0;
    my $is_inhalt_ohne = 0;
    
    {	
	# Kategorie Mit Inhaltsrepraesentation: Volltext
	if ($item_ref->{'transcription_type'}){
	    eval {
		if ($item_ref->{transcription_type}{'de-DE'} eq "digital"){
		    $is_inhalt_volltext = 1;
		}
	    };
	}
	elsif (defined $item_ref->{'_nested:gentz_letter__transcriptions'} && @{$item_ref->{'_nested:gentz_letter__transcriptions'}}){
	    foreach my $subitem_ref (@{$item_ref->{'_nested:gentz_letter__transcriptions'}}){
		if ($subitem_ref->{transscription_fulltext}){
		    $is_inhalt_volltext = 1;
		}
	    }
	}
	
	# Kategorie Mit Inhaltsrepraesentation: analog transkribiert
	if ($item_ref->{'transcription_type'}){
	    eval {
		if ($item_ref->{transcription_type}{'de-DE'} eq "Handschrift" || $item_ref->{transcription_type}{'de-DE'} eq "Schreibmaschine"  || $item_ref->{transcription_type}{'de-DE'} eq "Ausdruck Textdatei" ){
		    $is_inhalt_analog = 1;
		}
		if ($item_ref->{transcription_type}{'de-DE'} eq "ohne Transkription" ){
		    $is_inhalt_ohne = 1;
		}
	    };
	}

	# 0517: Angaben zum Inhalt
	if ($is_inhalt_volltext){
	    push @{$title_ref->{fields}{'0517'}}, {
		mult     => 1,
		subfield => '',
		content => 'Volltext',
	    }
	}
	if ($is_inhalt_analog){
	    push @{$title_ref->{fields}{'0517'}}, {
		mult     => 1,
		subfield => '',
		content => 'analog',
	    }
	}
	if ($is_inhalt_ohne){
	    push @{$title_ref->{fields}{'0517'}}, {
		mult     => 1,
		subfield => '',
		content => 'untranskribiert',
	    }
	}

	
    }
    
    # Auswergung Kategorie 'Kopie Original'
    
    my $is_papierkopie_usb = 0;
    my $is_mikrofilm_digitalisiert = 0;
    my $is_digitalisat = 0;
    
    {

	# Todo: Im Export noch keine Inhalte zum Auswerten von is_digitalisat vorhanden!
	
	eval {
	    if (defined $item_ref->{'hardcopy_herterich'} && $item_ref->{'hardcopy_herterich'}{'de-DE'} eq "Papier"){
		$is_papierkopie_usb = 1;
	    }
	    
	    if (defined $item_ref->{'hardcopy_herterich'} && $item_ref->{'hardcopy_herterich'}{'de-DE'} eq "Mikrofilm (digitalisiert)"){
		$is_mikrofilm_digitalisiert = 1;
	    }
	    
	    if (defined $item_ref->{'_nested:gentz_letter__digitized_versions'} && @{$item_ref->{'_nested:gentz_letter__digitized_versions'}}){
		$is_digitalisat = 1;
	    }
	    
	};

	# 0334: Material = Kopie Originalbrief
	if ($is_papierkopie_usb){
	    push @{$title_ref->{fields}{'0334'}}, {
		mult     => 1,
		subfield => '',
		content => 'Xerokopie (USB), identifizert',
	    }
	}
	else {
	    push @{$title_ref->{fields}{'0334'}}, {
		mult     => 1,
		subfield => '',
		content => '"Xerokopie (USB), naheliegend, Verzeichnung offen',
	    }
	}
	if ($is_mikrofilm_digitalisiert){
	    push @{$title_ref->{fields}{'0334'}}, {
		mult     => 1,
		subfield => '',
		content => 'Mikrofilm (digitalisiert)',
	    }
	}
	if ($is_digitalisat){
	    push @{$title_ref->{fields}{'0333'}}, {
		mult     => 1,
		subfield => '',
		content => 'Digitalisat',
	    }
	}	
    }

    # Auswertung Kategorie 'Sammlung Herterich'

    my $is_sammlung_herterich = 0;
    my $is_herterich_ungedruckt = 0;
    my $is_herterich_gedruckt = 0;
    my $is_herterich_archiv = 0;

    {
	
	eval {

	    if (defined $item_ref->{'_nested:gentz_letter__records_collection_herterich'} && @{$item_ref->{'_nested:gentz_letter__records_collection_herterich'}}){
		foreach my $subitem_ref (@{$item_ref->{'_nested:gentz_letter__records_collection_herterich'}}){
		    if (defined $subitem_ref->{collection_herterich} && $subitem_ref->{collection_herterich} =~m/^HERT/){
			$is_sammlung_herterich = 1;
		    }
		}
		
	    }
	    elsif (defined $item_ref->{contentdm_id}){
		$is_sammlung_herterich = 1;
	    }

	    if ($is_sammlung_herterich){
		if ($item_ref->{archive}{name}){
		    $is_herterich_archiv = 1;
		}
		
		if (! defined $item_ref->{reference_publication}{print_title} && ! @${$item_ref->{'_nested:gentz_letter__doublets'}}){
		    $is_herterich_ungedruckt = 1;
		}
		if ($item_ref->{reference_publication}{print_title} || @${$item_ref->{'_nested:gentz_letter__doublets'}}){
		    $is_herterich_gedruckt = 1;
		}
	    }
	    
	};

	if ($is_sammlung_herterich){
	    push @{$title_ref->{fields}{'4700'}}, {
		mult     => 1,
		subfield => '',
		content => 'Daten erhoben am Original',
	    }
	}
	# # 4700: Sammlungsschwerpunkt
	# if ($is_herterich_ungedruckt){
	#     push @{$title_ref->{fields}{'4700'}}, {
	# 	content => 'Ungedruckt',
	#     }
	# }
	# if ($is_herterich_gedruckt){
	#     push @{$title_ref->{fields}{'4700'}}, {
	# 	content => 'Gedruckt',
	#     }
	# }
	# if ($is_herterich_archiv){
	#     push @{$title_ref->{fields}{'4700'}}, {
	# 	content => 'Archiv',
	#     }
	# }
	
    }

    # Todo
    #
    # Neue Kategorie zur Facettierung mit Inhalten gedruckt und ungegedruckt
    # Besetzung entsprechen Hertericht (s.o.) aber fortan unabhaengig der Sammlung Hertericht
    # Zusaetzlich Anhaengsel " (Stand 2021)" in der Facettierung

    my $is_generell_ungedruckt = 0;
    my $is_generell_gedruckt = 0;

    {
	
	eval {	    		
	    if (! defined $item_ref->{reference_publication}{print_title} && ! @${$item_ref->{'_nested:gentz_letter__doublets'}}){
		$is_generell_ungedruckt = 1;
	    }
	    if ($item_ref->{reference_publication}{print_title} || @${$item_ref->{'_nested:gentz_letter__doublets'}}){
		$is_generell_gedruckt = 1;
	    }
	};

	if ($is_generell_gedruckt){
	    push @{$title_ref->{fields}{'0471'}}, {
		mult     => 1,
		subfield => '',
		content => 'gedruckt',
	    }
	}
	elsif ($is_generell_ungedruckt){
	    push @{$title_ref->{fields}{'0471'}}, {
		mult     => 1,
		subfield => '',
		content => 'ungedruckt',
	    }
	}	
    }

    
    # Auswertung Kategorie 'Druckpublikationen'
    
    my $is_druck_mehrfach = 0;
    my $is_druck_archiv = 0;
    my $is_referenz_publikation = 0;
    my $is_druckpublikation = 0;
    
    {
	
	eval {
	    if (defined $item_ref->{based_on}){
		if ($item_ref->{based_on}{'de-DE'} eq "Druckpublikation"){
		    $is_druckpublikation = 1;
		}
	    }
	    
	    if (defined $item_ref->{reference_publication}){
		$is_referenz_publikation = 1;
		
		if ($item_ref->{archive}{name}){
		    $is_druck_archiv = 1;
		}
		
		if (@${$item_ref->{'_nested:gentz_letter__doublets'}}){
		    foreach my $subitem_ref (@${$item_ref->{'_nested:gentz_letter__doublets'}}){
			if ($subitem_ref->{'doublet_publication'}){			
			    $is_druck_mehrfach = 1;
			}
		    }
		} 
	    }
	};

	# 0434: Sonstige Angaben
	if ($is_druckpublikation){
	    push @{$title_ref->{fields}{'0434'}}, {
		mult     => 1,
		subfield => '',
		content => 'Daten erhoben am Druck',
	    }
	}
	# if ($is_druck_mehrfach){
	#     push @{$title_ref->{fields}{'0434'}}, {
	# 	content => 'Mehrfach gedruckt',
	#     }
	# }
	# if ($is_druck_archiv){
	#     push @{$title_ref->{fields}{'0434'}}, {
	# 	content => 'Archiv',
	#     }
	# }
	# if ($is_referenz_publikation){
	#     push @{$title_ref->{fields}{'0434'}}, {
	# 	content => 'Referenzpublikation',
	#     }
	# }
	
    }

    # Auswertung Kategorie Ueberlieferung

    my $is_gedruckt = 0;
    my $is_handschriftlich = 0;

    {
	if ($is_referenz_publikation || $is_druck_mehrfach){
	    $is_gedruckt = 1;
	}
	else {
	    $is_handschriftlich = 1;
	}
	
	if ($is_gedruckt){
	    push @{$title_ref->{fields}{'0470'}}, {
		mult     => 1,
		subfield => '',
		content => 'gedruckt',
	    }
	}
	elsif ($is_handschriftlich){
	    push @{$title_ref->{fields}{'0470'}}, {
		mult     => 1,
		subfield => '',
		content => 'handschriftlich',
	    }
	}
    }
    
    my $is_digital = 0;


    # URLs zu den Digitalisaten

    my $url_mult = 1;
    if (defined $item_ref->{'_nested:gentz_letter__digitized_versions'} && @{$item_ref->{'_nested:gentz_letter__digitized_versions'}}){
	
	foreach my $digitized_ref (@{$item_ref->{'_nested:gentz_letter__digitized_versions'}}){

	    my $description = $digitized_ref->{description};
	    
	    # URLs
	    foreach my $file_ref (@{$digitized_ref->{'_nested:digitized_version__files'}}){
		
		# Volles Bild zum Download
		if ($file_ref->{versions}{original}{url}){
		    push @{$title_ref->{fields}{'0662'}}, {
			mult => $url_mult,
			subfield => '',
			content => $file_ref->{versions}{original}{download_url},
		    };
		    $is_digital = 1;
		}
		
		# Thumbnail
		if ($file_ref->{versions}{small}{url}){
		    push @{$title_ref->{fields}{'2662'}}, {
			mult => $url_mult,
			subfield => '',
			content => $file_ref->{versions}{small}{url},
		    };
		    $is_digital = 1;
		}
		
		if ($description){
		    push @{$title_ref->{fields}{'0663'}}, {
			mult => $url_mult,
			subfield => '',
			content => $description,
		    };
		}
		
		$url_mult++;
	    }
	}
    }
    
    # URLs zu den Transcriptions

    foreach my $transcription_ref (@{$item_ref->{'_nested:gentz_letter__transcriptions'}}){

	if ($transcription_ref->{transcription_fulltext}){
	    push @{$title_ref->{fields}{'6053'}}, {
		mult     => 1,
		subfield => '',
		content => $transcription_ref->{'transcription_fulltext'},
	    }
	}
	

	# URLs
	my $file_ref = $transcription_ref->{transcription_file} ;

	my $description = $transcription_ref->{transcription_name};
	
	# Volles Bild zum Download
	if ($file_ref->{versions}{original}{url}){
	    push @{$title_ref->{fields}{'0662'}}, {
		mult => $url_mult,
		subfield => '',
		content => $file_ref->{versions}{original}{download_url},
	    };
	    $is_digital = 1;
	}
	
	# Thumbnail
	if ($file_ref->{versions}{small}{url}){
	    push @{$title_ref->{fields}{'2662'}}, {
		mult => $url_mult,
		subfield => '',
		content => $file_ref->{versions}{small}{url},
	    };
	    $is_digital = 1;
	}

	if ($description){
	    push @{$title_ref->{fields}{'0663'}}, {
		mult => $url_mult,
		subfield => '',
		content => $description,
	    };
	}	

	$url_mult++;
    }
    

    if ($is_digital){
	push @{$title_ref->{fields}{'4400'}}, {
	    content  => 'online',
	    mult     => 1,
	    subfield => '',
	}
    }


    ### Analyse: Einordnung der Briefe von/an Gentz bzw. Dritter -> 0800
    my $mediatype = "";

    foreach my $sender (@senders){
	if ($sender eq "Gentz, Friedrich"){
	    $mediatype = "Briefe von Gentz";
	}
    }

    foreach my $recipient (@recipients){
	if ($recipient eq "Gentz, Friedrich"){
	    $mediatype = "Briefe an Gentz";
	}
    }

    if (!$mediatype){
	$mediatype = "Briefe Dritter";
    }

    if ($mediatype){
	$title_ref->{fields}{'0800'} = [
	    {
		mult     => 1,
		subfield => '',
		content  => $mediatype,
	    }
	    ];
    }

    ### Briefe von Gentz/Jahr -> 0426 bzw. 0425/0426 (ohne Jahr)
    ### Briefe an Gentz/Jahr  -> 0427 bzw. 0425/0427 (ohne Jahr)    
    ### Briefe Dritter        -> 0428 bzw. 0425/0428 (ohne Jahr)    
    if ($mediatype eq "Briefe von Gentz"){
	if ($year){
	    $title_ref->{fields}{'0426'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $year,
		},
                ];
	}
	else {
	    $title_ref->{fields}{'0425'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	    $title_ref->{fields}{'0426'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	}
    }
    elsif ($mediatype eq "Briefe an Gentz"){
	if ($year){
	    $title_ref->{fields}{'0427'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $year,
		},
                ];
	}
	else {
	    $title_ref->{fields}{'0425'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	    $title_ref->{fields}{'0427'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	}
    }
    elsif ($mediatype eq "Briefe Dritter"){
	if ($year){
	    $title_ref->{fields}{'0428'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $year,
		},
                ];
	}
	else {
	    $title_ref->{fields}{'0425'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	    $title_ref->{fields}{'0428'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => 'ohne Jahr',
		},
                ];
	}
    }

    
    print TITLE encode_json($title_ref),"\n";
	

    
}

close (TITLE);
close (PERSON);
close (CORPORATEBODY);
close (CLASSIFICATION);
close (SUBJECT);
close (HOLDING);

close(IN);
