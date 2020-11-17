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

my $json = read_file($inputfile) ;

my $json_ref = decode_json($json);

my $multcount_ref = {};

foreach my $item_ref (@{$json_ref->{objects}}){

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($item_ref));
    }
    
    my $letter_ref = $item_ref->{gentz_letter};
    
    my $title_ref = {
        'fields' => {},
    };

    $multcount_ref = {};

    if ($letter_ref->{contentdm_id}){
	$title_ref->{id} = $letter_ref->{contentdm_id};
    }
    else {
	$title_ref->{id} = $letter_ref->{_id};
    }

    # Person
    if ($letter_ref->{sender}{_standard}{1}{text}{'de-DE'}){
	my $name = $letter_ref->{sender}{_standard}{1}{text}{'de-DE'};
	
	my ($person_id,$new)=OpenBib::Conv::Common::Util::get_person_id($name);
	
	my $mult = 1;
	
	if ($new){
	    
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
    
    # Koerperschaft
    foreach my $recipient_ref (@{$letter_ref->{'_nested:gentz_letter__recipients'}}){	
	my $name = $recipient_ref->{recipient}{_standard}{1}{text}{'de-DE'};
	
	my ($corporatebody_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($name);
	
	my $mult = 1;
	
	if ($new){
	    
	    my $normitem_ref = {
		'fields' => {},
	    };
	    
	    $normitem_ref->{id} = $corporatebody_id;
	    push @{$normitem_ref->{fields}{'0800'}}, {
		mult     => 1,
		subfield => '',
		content  => $name,
	    };
	    
	    print CORPORATEBODY encode_json $normitem_ref, "\n";
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
    
    # Titel
    
    if ($letter_ref->{title}{'de-DE'}){
	push @{$title_ref->{fields}{'0331'}}, {
	    content => $letter_ref->{title}{'de-DE'},
	}
    }

    if ($letter_ref->{reference_publication_incipit}){
	push @{$title_ref->{fields}{'0335'}}, {
	    content => $letter_ref->{reference_publication_incipit},
	}
    }

    if ($letter_ref->{reference_publication}{_standard}{3}{text}{'de-DE'}){
	push @{$title_ref->{fields}{'0591'}}, {
	    content => $letter_ref->{reference_publication}{_standard}{3}{text}{'de-DE'},
	}
    }

    if ($letter_ref->{reference_publication}{_standard}{1}{text}{'de-DE'}){
	push @{$title_ref->{fields}{'0590'}}, {
	    content => $letter_ref->{reference_publication}{_standard}{1}{text}{'de-DE'},
	}
    }

    if ($letter_ref->{reference_publication_date}){
	push @{$title_ref->{fields}{'0595'}}, {
	    content => $letter_ref->{reference_publication_date},
	}
    }
    
    if ($letter_ref->{reference_publication_page}){
	push @{$title_ref->{fields}{'0433'}}, {
	    content => $letter_ref->{reference_publication_page},
	}
    }

    if ($letter_ref->{sent_date_original}){
	push @{$title_ref->{fields}{'0424'}}, {
	    content => $letter_ref->{sent_date_original},
	}
    }

    if ($letter_ref->{sent_date_year}){
	push @{$title_ref->{fields}{'0425'}}, {
	    content => $letter_ref->{sent_date_year},
	}
    }

    if ($letter_ref->{sent_location_normalized}{_standard}{1}{text}{'de-DE'}){
	push @{$title_ref->{fields}{'0410'}}, {
	    content => $letter_ref->{sent_location_normalized}{_standard}{1}{text}{'de-DE'},
	}
    }
    
    if ($letter_ref->{format_size}{'de-DE'}){
	push @{$title_ref->{fields}{'0433'}}, {
	    content => $letter_ref->{format_size}{'de-DE'},
	}
    }

    if ($letter_ref->{language}{_standard}{1}{text}{'de-DE'}){
	push @{$title_ref->{fields}{'0015'}}, {
	    content => $letter_ref->{language}{_standard}{1}{text}{'de-DE'},
	}
    }

    if ($letter_ref->{archive}{_standard}{1}{text}{'de-DE'}){
	push @{$title_ref->{fields}{'0412'}}, {
	    content => $letter_ref->{archive}{_standard}{1}{text}{'de-DE'},
	}
    }

    if ($letter_ref->{provenance}{'de-DE'}){
	push @{$title_ref->{fields}{'1664'}}, {
	    content => $letter_ref->{provenance}{'de-DE'},
	}
    }

    print TITLE encode_json($title_ref),"\n";
	

    
}
