#!/usr/bin/perl

#####################################################################
#
#  totenzettel2meta.pl
#
#  Dieses File ist (C) 2021 Oliver Flimm <flimm@ub.uni-koeln.de>
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
use Text::Unidecode;
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
totenzettel2meta.pl - Aufrufsyntax

    gentzbriefe2meta.pl --inputfile=xxx

      --inputfile=                 : Name der Eingabedatei

HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/totenzettel2meta.log';
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

our %german_umlauts = (
    'Ä' => 'AE',
    'ä' => 'ae',
    'Ö' => 'OE',
    'ö' => 'oe',
    'Ü' => 'UE',
    'ü' => 'ue',
    'ß' => 'ss', 
    );

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
my $classifications_done_ref = {};

my $mexid = 1;

while (my $jsonline = <IN>){
    my $item_ref = decode_json($jsonline); 

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($item_ref));
    }
    
    my $title_ref = {
        'fields' => {},
    };

    $multcount_ref = {};

    if ($item_ref->{contentdm_id}){
    	$title_ref->{id} = $item_ref->{contentdm_id};
    }
    elsif ($item_ref->{_system_object_id}) {
	$title_ref->{id} = "edb_".$item_ref->{_system_object_id};
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

    ### Gesamter Exportsatz -> 0001
    push @{$title_ref->{fields}{'0001'}}, {
	mult     => 1,
	subfield => '',
	content => $item_ref,
    };
    
    ### contentdm_id -> 0010
    if ($item_ref->{contentdm_id}){
	push @{$title_ref->{fields}{'0010'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{contentdm_id},
	};
    }
    
    ### _nested:death_notes__weddings/married_partner -> 0014 (Exemplare)
    ### _nested:death_notes__weddings/wedding_date    -> 0016 (Exemplare)
    ### _nested:death_notes__weddings/wedding_place   -> 0005 (Exemplare)

    if (defined $item_ref->{'_nested:death_notes__weddings'} && @{$item_ref->{'_nested:death_notes__weddings'}}){
	my $mult = 1;
	foreach my $wedding_ref (@{$item_ref->{'_nested:death_notes__weddings'}}){

	    my $normitem_ref = {
		'fields' => {},
	    };
	    
	    $normitem_ref->{id} = $mexid;
	    
	    push @{$normitem_ref->{fields}{'0004'}}, {
		mult     => $mult,
		subfield => '',
		content  => $title_ref->{id},
	    };
	    
	    push @{$normitem_ref->{fields}{'0014'}}, {
		mult     => $mult,
		subfield => '',
		content  => $wedding_ref->{married_partner},
	    };

	    push @{$normitem_ref->{fields}{'0016'}}, {
		mult     => $mult,
		subfield => '',
		content  => $wedding_ref->{marriage_place},
	    };

	    push @{$normitem_ref->{fields}{'0005'}}, {
		mult     => $mult,
		subfield => '',
		content  => $wedding_ref->{marriage_date},
	    };

	    $mult++;
	    $mexid++;
        
	    print HOLDING encode_json $normitem_ref, "\n";
	    
	}
    }

    ### name -> 0331    
    if ($item_ref->{name}){
	push @{$title_ref->{fields}{'0331'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{name},
	};
    }
    
    ### birth_name -> 0370
    if ($item_ref->{birth_name}){
	push @{$title_ref->{fields}{'0370'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{birth_name},
	};
    }

    ### religious_name -> 0310
    if ($item_ref->{religious_name}){
	push @{$title_ref->{fields}{'0310'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{religious_name},
	};
    }

    ### title_original -> 0335
    if ($item_ref->{title_original}){
	push @{$title_ref->{fields}{'0335'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{title_original},
	};
    }

    ### title_original -> 0335
    if ($item_ref->{title_original}){
	push @{$title_ref->{fields}{'0335'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{title_original},
	};
    }

    ### _nested:death_notes__professions_stands_normalized/profession_stand_normalized/_standard/1/text/de-DE -> 0433
    
    if (defined $item_ref->{'_nested:death_notes__professions_stands_normalized'} && @{$item_ref->{'_nested:death_notes__professions_stands_normalized'}}){
	my $mult = 1;
	foreach my $stands_ref (@{$item_ref->{'_nested:death_notes__professions_stands_normalized'}}){
	    if (defined $stands_ref->{profession_stand_normalized}{_standard}{1}{text}{'de-DE'}){
		push @{$title_ref->{fields}{'0433'}}, {
		    mult     => $mult,
		    subfield => '',
		    content => $stands_ref->{profession_stand_normalized}{_standard}{1}{text}{'de-DE'},
		};
		$mult++;
	    }
	}
    }

    ### bereaved_persons -> 0451
    if (defined $item_ref->{'bereaved_persons'}){
	my $mult = 1;
	
	my $names = $item_ref->{'bereaved_persons'};
	
	foreach my $name (split(' / ',$names)){
	    	    
	    my $new_category = "0451";
	    
	    push @{$title_ref->{fields}{$new_category}}, {
		content    => $name,
		mult       => $mult,
		subfield   => '',
	    };

	    $mult++;
	}        
    }

    ### search_terms -> 0600
    if ($item_ref->{search_terms}){
	push @{$title_ref->{fields}{'0600'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $item_ref->{search_terms},
	};
    }
    
    ### provenance/de-DE -> 0700
    if ($item_ref->{provenance}){
	my $mult = 1;
	
	my $name = $item_ref->{'provenance'}{'de-DE'};

	my $classification_id = normalize_id($name); 
	
	if (!$classifications_done_ref->{$classification_id}){
	    
	    my $normitem_ref = {
		'fields' => {},
	    };
	    
	    $normitem_ref->{id} = $classification_id;
	    
	    push @{$normitem_ref->{fields}{'0800'}}, {
		mult     => 1,
		subfield => '',
		content  => $name,
	    };
	    
	    print CLASSIFICATION encode_json $normitem_ref, "\n";

	    $classifications_done_ref->{$classification_id} = 1;
	}
	
	my $new_category = "0700";
	
	push @{$title_ref->{fields}{$new_category}}, {
	    content    => $name,
	    mult       => $mult,
	    subfield   => '',
	    id         => $classification_id,
	    supplement => '',
	};
    }
    
    ### birth_date_original -> 0595/426
    if ($item_ref->{birth_date_original}){
	my $thisdate = $item_ref->{birth_date_original};
	
	push @{$title_ref->{fields}{'0595'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $thisdate,
	};

	if ($thisdate =~m/(\d\d\d\d)/){
	    push @{$title_ref->{fields}{'0426'}}, {
		mult     => 1,
		subfield => '',
		content => $1,
	    };
	}

    }    

    ### death_date_original -> 0424/0425
    if ($item_ref->{death_date_original}){
	my $thisdate = $item_ref->{death_date_original};
	
	push @{$title_ref->{fields}{'0424'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $thisdate,
	};

	if ($thisdate =~m/(\d\d\d\d)/){
	    push @{$title_ref->{fields}{'0425'}}, {
		mult     => 1,
		subfield => '',
		content => $1,
	    };
	}

    }
    
    ### death_place_normalized -> Multgruppe 0410/2410b
    my $death_location_mult = 1;
        
    if ($item_ref->{death_place_normalized}{name}){
	push @{$title_ref->{fields}{'0410'}}, {
	    mult => $death_location_mult,
	    subfield => '',
	    content => $item_ref->{death_place_normalized}{name},
	};
    }

    if (defined $item_ref->{death_place_normalized}{gnd_location} && $item_ref->{death_place_normalized}{gnd_location}{conceptURI}){
	push @{$title_ref->{fields}{'2410'}}, {
	    mult => $death_location_mult,
	    subfield => "b",
	    content => $item_ref->{death_place_normalized}{gnd_location}{conceptURI},
	};
    }

    ### birth_place_normalized -> Multgruppe 0411/2411b
    my $birth_location_mult = 1;
        
    if ($item_ref->{birth_place_normalized}{name}){
	push @{$title_ref->{fields}{'0411'}}, {
	    mult => $birth_location_mult,
	    subfield => '',
	    content => $item_ref->{birth_place_normalized}{name},
	};
    }

    if (defined $item_ref->{birth_place_normalized}{gnd_location} && $item_ref->{birth_place_normalized}{gnd_location}{conceptURI}){
	push @{$title_ref->{fields}{'2411'}}, {
	    mult => $death_location_mult,
	    subfield => "b",
	    content => $item_ref->{birth_place_normalized}{gnd_location}{conceptURI},
	};
    }

    ### parent_father -> 0101 (Personen)
    if (defined $item_ref->{'parent_father'}){
	my $mult = 1;

	my $name = $item_ref->{'parent_father'};

	my $person_id = normalize_id($name); 
	
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
    }

    ### parent_mother -> 0102 (Personen)
    if (defined $item_ref->{'parent_mother'}){
	my $mult = 1;

	my $name = $item_ref->{'parent_mother'};

	my $person_id = normalize_id($name); 
	
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
	    
	    print PERSON encode_json $normitem_ref, "\n";

	    $persons_done_ref->{$person_id} = 1;
	}
	
	my $new_category = "0102";
	
	push @{$title_ref->{fields}{$new_category}}, {
	    content    => $name,
	    mult       => $mult,
	    subfield   => '',
	    id         => $person_id,
	    supplement => '',
	};
    }

    ### children -> 0103 (Personen)
    if (defined $item_ref->{'children'}){
	my $mult = 1;

	my $names = $item_ref->{'children'};

	foreach my $name (split(' / ',$names)){
	    
	    my $person_id = normalize_id($name); 
	    
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
		
		print PERSON encode_json $normitem_ref, "\n";
		
		$persons_done_ref->{$person_id} = 1;
	    }
	    
	    my $new_category = "0102";
	    
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

    # URLs zu den Digitalisaten

    my $url_mult = 1;
    if (defined $item_ref->{'_nested:death_notes__digitized_versions'} && @{$item_ref->{'_nested:death_notes__digitized_versions'}}){
	
	foreach my $digitized_ref (@{$item_ref->{'_nested:death_notes__digitized_versions'}}){

	    my $description = $digitized_ref->{death_note_type}{'de-DE'};
	    
	    # URLs
	    foreach my $file_ref (@{$digitized_ref->{'file'}}){
		
		# Volles Bild zum Download
		if ($file_ref->{versions}{original}{url}){
		    push @{$title_ref->{fields}{'0662'}}, {
			mult => $url_mult,
			subfield => '',
			content => $file_ref->{versions}{original}{download_url},
		    };
		}
		
		# Thumbnail
		if ($file_ref->{versions}{small}{url}){
		    push @{$title_ref->{fields}{'2662'}}, {
			mult => $url_mult,
			subfield => '',
			content => $file_ref->{versions}{small}{url},
		    };
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
	
    print TITLE encode_json($title_ref),"\n";
	    
}

close (TITLE);
close (PERSON);
close (CORPORATEBODY);
close (CLASSIFICATION);
close (SUBJECT);
close (HOLDING);

close(IN);

sub normalize_id {
    my ($content)=@_;

    $content = lc($content);

    $content=~s/([ÄäÖöÜüß])/$german_umlauts{$1}/g;
    
    $content=~s/\W/_/g;
    $content=~s/__+/_/g;
    $content=~s/_$//;
    
    return unidecode($content);
}
