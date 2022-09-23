#!/usr/bin/perl

#####################################################################
#
#  mbox2meta.pl
#
#  Konvertierung einer Mailbox im mbox-Format in des OpenBib Einlade-Metaformat
#
#  Dieses File ist (C) 2022 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;

use utf8;
use Encode;

use Date::Manip qw/ParseDate UnixDate/;
use Mail::Mbox::MessageParser;
use Email::MIME;
use XML::Twig;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use YAML::Syck;
use JSON::XS;

use OpenBib::Conv::Common::Util;

my ($inputfile,$configfile,$logfile,$loglevel);

&GetOptions(
    "inputfile=s"          => \$inputfile,
    "configfile=s"         => \$configfile,
    "logfile=s"            => \$logfile,
    "loglevel=s"           => \$loglevel,
    );

if (!$inputfile && !$configfile){
    print << "HELP";
mbox2meta.pl - Aufrufsyntax

    filemaker2meta.pl --inputfile=xxx --configfile=mapping.yml

    filemaker2meta.pl --inputfile=xxx --configfile=mapping.yml --loglevel=DEBUG --logfile=/tmp/out.log
HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/mbox2meta.log';
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

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile) if ($configfile);

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

# Set up cache. (Not necessary if enable_cache is false.)
Mail::Mbox::MessageParser::SETUP_CACHE(
  { 'file_name' => '/tmp/mboxcache' } );

my $mbox_reader = new Mail::Mbox::MessageParser({
    'file_name' => $inputfile,
	'enable_grep' => 1,
	'enable_cache' => 1,
						});



while(!$mbox_reader->end_of_file()){

    my $title_ref = {};
    
    my $mailblob = $mbox_reader->read_next_email();
    my $email = Email::MIME->new($mailblob);

    my $id = $email->header('Message-ID');

    $id=~s/[<>\/]//g;
    
    $title_ref->{id} = $id;

    # Persons (eg. From)
    my $pers_mult = 1;
    foreach my $field (keys %{$convconfig->{'person'}}){
	my $content = $email->header($field);

	my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($content);
                    
	if ($new){
	    my $item_ref = {
		'fields' => {},
	    };
	    $item_ref->{id} = $person_id;
	    push @{$item_ref->{fields}{'0800'}}, {
		mult     => 1,
		subfield => '',
		content  => $content,
	    };
	    
	    print PERSON encode_json $item_ref, "\n";
	}
                    
	my $new_category = $convconfig->{person}{$field};
                    
	push @{$title_ref->{fields}{$new_category}}, {
	    mult       => $pers_mult,
	    subfield   => '',
	    id         => $person_id,
	    supplement => '',
	};
	
	$pers_mult++;
    }
    
    # Corporatebody (eg. To)
    my $corp_mult = 1;
    foreach my $field (keys %{$convconfig->{'corporatebody'}}){
	my $content = $email->header($field);
	
	my ($corp_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($content);
                    
	if ($new){
	    my $item_ref = {
		'fields' => {},
	    };
	    $item_ref->{id} = $corp_id;
	    push @{$item_ref->{fields}{'0800'}}, {
		mult     => 1,
		subfield => '',
		content  => $content,
	    };
	    
	    print CORPORATEBODY encode_json $item_ref, "\n";
	}
                    
	my $new_category = $convconfig->{corporatebody}{$field};
                    
	push @{$title_ref->{fields}{$new_category}}, {
	    mult       => $corp_mult,
	    subfield   => '',
	    id         => $corp_id,
	    supplement => '',
	};
	
	$corp_mult++;
    }

    # Title (eg. Subject)
    foreach my $field (keys %{$convconfig->{'title'}}){
	my $content = $email->header($field);

	push @{$title_ref->{fields}{$convconfig->{'title'}{$field}}}, {
	    content  => $content,
	    mult     => 1,
	    subfield => '',
	}
    }

    # Body
    {
	my @parts = $email->subparts;

	my $mult = 1;
	foreach my $part (@parts){
	    my $content = $part->body_str;

	    if ($convconfig->{'html_only'} && $part->content_type =~m/html/){
		push @{$title_ref->{fields}{$convconfig->{'body'}}}, {
		    content  => $content,
		    mult     => $mult++,
		    subfield => '',
		}
	    }
	    elsif (!$convconfig->{'html_only'}){
		push @{$title_ref->{fields}{$convconfig->{'body'}}}, {
		    content  => $content,
		    mult     => $mult++,
		    subfield => '',
		}
	    }
	}
    }

    # Erweiterungen
    {
	if (defined $title_ref->{fields}{'0002'}){
	    my $send_date = ParseDate($title_ref->{fields}{'0002'}[0]{content});
	    my $year = Date::Manip::UnixDate($send_date,"%Y%m%d%H%M%S");
	    if ($year){
		push @{$title_ref->{fields}{'0425'}}, {
		    content  => $year,
		    mult     => 1,
		    subfield => '',
		}
	    }
	}
    }

    print TITLE encode_json $title_ref,"\n";
}



close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);
