#!/usr/bin/perl

#####################################################################
#
#  lobidjson2meta.pl
#
#  Dieses File ist (C) 2023 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode';
use Getopt::Long;
use IO::File;
use IO::Uncompress::Gunzip;
use IO::Uncompress::Bunzip2;
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
lobidjson2meta.pl - Aufrufsyntax

    lobidjson2meta.pl --inputfile=xxx

      --inputfile=                 : Name der Eingabedatei

HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/lobidjson2meta.log';
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

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

my $input_io;

if ($inputfile){
    if ($inputfile =~/\.gz$/){
        $input_io = IO::Uncompress::Gunzip->new($inputfile);
    }
    elsif ($inputfile =~/\.bz2$/){
        $input_io = IO::Uncompress::Bunzip2->new($inputfile);
    }
    else {
        $input_io = IO::File->new($inputfile);
    }
}

my $multcount_ref = {};

my $persons_done_ref = {};
my $corporatebodies_done_ref = {};
my $recipients_done_ref = {};

my $holding_id = 1;

while (my $jsonline = <$input_io>){
    my $record_ref = decode_json($jsonline); 

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($record_ref));
    }
    
    my $title_ref = {
        'fields' => {},
    };

    $multcount_ref = {};

    $title_ref->{id} = $record_ref->{hbzId};	
    
    ### Gesamter Exportsatz -> 0001
    push @{$title_ref->{fields}{'0001'}}, {
	mult     => 1,
	subfield => '',
	content => $record_ref,
    };

    # Personen und Koerperschaften
    if (defined $record_ref->{contribution}){
	
	foreach my $contribution_ref (@{$record_ref->{contribution}}){
	    my $contributor_id = $contribution_ref->{agent}{gndIdentifier};
	    my $name           = $contribution_ref->{agent}{label};
	    my $role           = $contribution_ref->{role}{label};

	    unless ($contributor_id){
		$contributor_id = OpenBib::Conv::Common::Util::normalize_id($name);
	    }
	    
	    if (!$contributor_id){
		$logger->error(YAML::Dump($contribution_ref));
		next;
	    }
	    
	    my $supplement = "";

	    if ($role){
		$supplement = "[".$role."]";
	    }

	    my $type      = "";

	    foreach my $agent_type (@{$contribution_ref->{agent}{type}}){
		if ($agent_type eq "Person"){
		    $type = "person";
		}
		elsif ($agent_type eq "Person"){
		    $type = "corporatebody";
		}
	    }

	    if ($type eq "person"){
		my $mult = 1;
		
		if (!defined $persons_done_ref->{$contributor_id}){
		    
		    my $normrecord_ref = {
			'fields' => {},
		    };
		    
		    $normrecord_ref->{id} = $contributor_id;
		    push @{$normrecord_ref->{fields}{'0800'}}, {
			mult     => 1,
			subfield => '',
			content  => $name,
		    };
		    
		    if (defined $contribution_ref->{agent}{dateOfBirth}){
			push @{$normrecord_ref->{fields}{'0304'}}, {
			    mult     => 1,
			    subfield => '',
			content  => $contribution_ref->{agent}{dateOfBirth},
			};
		    }
			
		    if (defined $contribution_ref->{agent}{dateOfDeath}){
			push @{$normrecord_ref->{fields}{'0306'}}, {
			    mult     => 1,
			    subfield => '',
			    content  => $contribution_ref->{agent}{dateOfDeath},
			};		
		    }

		    if (defined $contribution_ref->{agent}{altLabel}){
			my $label_mult = 1;

			if (ref $contribution_ref->{agent}{altLabel} eq "ARRAY"){
			    foreach my $verweisung (@{$contribution_ref->{agent}{altLabel}}){
				push @{$normrecord_ref->{fields}{'0830'}}, {
				    mult     => $label_mult++,
				    subfield => '',
				    content  => $verweisung,
				};
			    }
			}
			else {
			    push @{$normrecord_ref->{fields}{'0830'}}, {
				mult     => $label_mult++,
				subfield => '',
				content  => $contribution_ref->{agent}{altLabel},
			    };
			}
		    }

		    print PERSON encode_json $normrecord_ref, "\n";
		    
		    $persons_done_ref->{$contributor_id} = 1;
		}
	    
		my $new_category = "0100";

		if ($role eq "Autor/in"){
		    $supplement = "";
		}
		else {
		    $new_category = "0101"; 
		}
		
		push @{$title_ref->{fields}{$new_category}}, {
		    content    => $name,
		    mult       => $mult,
		    subfield   => '',
		    id         => $contributor_id,
		    supplement => $supplement,
		};
		
		$mult++;
	    }
	    elsif ($type eq "corporatebody"){
		my $mult = 1;
		
		if (! defined $corporatebodies_done_ref->{$contributor_id}){
		    
		    my $normrecord_ref = {
			'fields' => {},
		    };
		    $normrecord_ref->{id} = $contributor_id;
		    push @{$normrecord_ref->{fields}{'0800'}}, {
			mult     => 1,
			subfield => '',
			content  => $name,
		    };
		    
		    if (defined $contribution_ref->{agent}{dateOfBirth}){
			push @{$normrecord_ref->{fields}{'0304'}}, {
			    mult     => 1,
			    subfield => '',
			content  => $contribution_ref->{agent}{dateOfBirth},
			};
		    }
			
		    if (defined $contribution_ref->{agent}{dateOfDeath}){
			push @{$normrecord_ref->{fields}{'0306'}}, {
			    mult     => 1,
			    subfield => '',
			    content  => $contribution_ref->{agent}{dateOfDeath},
			};		
		    }
		
		    print PERSON encode_json $normrecord_ref, "\n";
		    
		    $corporatebodies_done_ref->{$contributor_id} = 1;
		}
	    
		my $new_category = "0200";
		
		push @{$title_ref->{fields}{$new_category}}, {
		    content    => $name,
		    mult       => $mult,
		    subfield   => '',
		    id         => $contributor_id,
		    supplement => $supplement,
		};
		
		$mult++;
	    }

	}
    }

    # if (defined $record_ref->{subject}){
    # 	foreach my $subject_ref (@{$record_ref->{subject}}){
	    
    # 	}
    # }
    
    ### title -> 0331 HST
    if (defined $record_ref->{title}){
	push @{$title_ref->{fields}{'0331'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $record_ref->{title},
	}
    }

    ### otherTitleInformation -> 0335 Zusatz zum HST
    if ($record_ref->{otherTitleInformation}){
	push @{$title_ref->{fields}{'0335'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $record_ref->{otherTitleInformation},
	}
    }
    
    ### extent -> 0433 Kollation    
    if (defined $record_ref->{extent}){
	push @{$title_ref->{fields}{'0433'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $record_ref->{extent},
	}
    }

    # language -> 0015 Sprache
    if (defined $record_ref->{language}){
	my $lang_mult = 1;
	foreach my $lang_ref (@{$record_ref->{language}}){
	    if ($lang_ref->{id} =~m{iso639-2/(.+)$}){
		push @{$title_ref->{fields}{'0433'}}, {
		    mult     => $lang_mult++,
		    subfield => '',
		    content => $1,
		}
	    }
	}
    }
	    
    # isbn -> 0540 Sprache
    if (defined $record_ref->{isbn}){
	my $isbn_mult = 1;
	foreach my $isbn (@{$record_ref->{isbn}}){
	    push @{$title_ref->{fields}{'0540'}}, {
		mult     => $isbn_mult++,
		subfield => '',
		content => $isbn,
	    };
	}
    }

    # issn -> 0543 Sprache
    if (defined $record_ref->{issn}){
	my $issn_mult = 1;
	foreach my $issn (@{$record_ref->{issn}}){
	    push @{$title_ref->{fields}{'0543'}}, {
		mult     => $issn_mult++,
		subfield => '',
		content => $issn,
	    };
	}
    }

    # fulltextOnline -> 4120 Volltext-URL
    if (defined $record_ref->{fulltextOnline}){
	my $fulltext_mult = 1;
	foreach my $fulltexturl (@{$record_ref->{fulltextOnline}}){
	    push @{$title_ref->{fields}{'4120'}}, {
		mult     => $fulltext_mult++,
		subfield => '',
		content => $fulltexturl,
	    };
	}
    }
    
    # responsibilityStatement -> 0359 Vorl. Verfasser/Koerperschaft
    if (defined $record_ref->{responsibilityStatement}){
	push @{$title_ref->{fields}{'0359'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $record_ref->{responsibilityStatement},
	};
    }
    
    if (defined $record_ref->{publication}){
	foreach my $pub_ref (@{$record_ref->{publication}}){

	    # location -> 0410 Verlagsort
	    if (defined $pub_ref->{location}){
		push @{$title_ref->{fields}{'0410'}}, {
		    mult     => 1,
		    subfield => '',
		    content => $pub_ref->{location},
		};
	    }

	    # publishedBy -> 0412 Verlag
	    if (defined $pub_ref->{publishedBy} && ref $pub_ref->{publishedBy} eq "ARRAY"){
		my $verlag_mult = 1;
		foreach my $verlag (@{$pub_ref->{publishedBy}}){
		    push @{$title_ref->{fields}{'0412'}}, {
			mult     => $verlag_mult++,
			subfield => '',
			content => $pub_ref->{publishedBy},
		    };
		}
	    }
	    elsif (defined $pub_ref->{publishedBy}){
		push @{$title_ref->{fields}{'0412'}}, {
		    mult     => 1,
		    subfield => '',
		    content => $pub_ref->{publishedBy},
		};
	    }

	    # startDate -> 0425 Erscheinungsjahr
	    if (defined $pub_ref->{startDate}){
		push @{$title_ref->{fields}{'0425'}}, {
		    mult     => 1,
		    subfield => '',
		    content => $pub_ref->{startDate},
		};
	    }

	    # publicationHistory -> 0405 Erscheinungsverlauf
	    if (defined $pub_ref->{publicationHistory}){
		push @{$title_ref->{fields}{'0405'}}, {
		    mult     => 1,
		    subfield => '',
		    content => $pub_ref->{publicationHistory},
		};
	    }
	    
	}
    }

    ### edition -> 0403 Auflage
    if (defined $record_ref->{edition}){
	push @{$title_ref->{fields}{'0403'}}, {
	    mult     => 1,
	    subfield => '',
	    content => $record_ref->{edition},
	}
    }

    # Exemplare

    if (defined $record_ref->{hasItem}){
	foreach my $holding_ref (@{$record_ref->{hasItem}}){
	    my $item_ref = {
		'fields' => {},
	    };
	    $item_ref->{id} = $holding_id;

	    my $call_number = $holding_ref->{callNumber};
	    my $label       = $holding_ref->{label};

	    if ($call_number){
		push @{$item_ref->{fields}{'0004'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $record_ref->{id},
		};
		
		push @{$item_ref->{fields}{'0014'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $call_number,
		};
		$holding_id++;
	    }
        
	    
	    print HOLDING encode_json $item_ref, "\n";
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

$input_io->close;
