#!/usr/bin/perl

#####################################################################
#
#  filemaker2meta.pl
#
#  Konvertierung des FileMaker XML-Formates in des OpenBib Einlade-Metaformat
#
#  Dieses File ist (C) 2005-2012 Oliver Flimm <flimm@openbib.org>
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

use XML::Twig;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use YAML;
use JSON::XS;

use OpenBib::Conv::Common::Util;

my ($inputfile,$configfile,$logfile,$loglevel);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "logfile=s"            => \$logfile,
            "loglevel=s"           => \$loglevel,
	    );

if (!$inputfile){
    print << "HELP";
filemaker2meta.pl - Aufrufsyntax

    filemaker2meta.pl --inputfile=xxx

    filemaker2meta.pl --inputfile=xxx --loglevel=DEBUG --logfile=/tmp/out.log
HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/filemaker2meta.log';
$loglevel=($loglevel)?$loglevel:'INFO';

our $metaidx = 0;
our $mexidn  = 1;
our %metadata;

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

my $twig= XML::Twig->new(
   TwigHandlers => {
     "/FMPXMLRESULT/METADATA/FIELD" => \&parse_metadata,
     "/FMPXMLRESULT/RESULTSET/ROW" => \&parse_titset,
   },
 );


print STDERR "Daten werden eingelesen und geparsed\n";
$twig->safe_parsefile($inputfile);

sub parse_metadata {
    my($t, $field)= @_;

    my $att=$field->{'att'}->{'NAME'};

    $metadata{$att}=int($metaidx);

    print "Mapping Category $att to index $metaidx - ".int($metaidx)."\n";
    
    $metaidx++;
    # Release memory of processed tree
    # up to here
    $t->purge();
}

sub parse_titset {
    my($t, $titset)= @_;

    my $title_ref = {
        'fields' => {},
    };
    
    my $id=$titset->{'att'}->{'RECORDID'};

    $title_ref->{id} = $id;


    my @cols=$titset->children('COL');


    # Verfasser/Personen
    # Autor
    my @verfasser=();
    if(exists $metadata{'Autor'} && $cols[$metadata{'Autor'}]->first_child('DATA')->text()) {
        for my $singleverf (split (";",$cols[$metadata{'Autor'}]->first_child('DATA')->text())){
            # Inhalt bereinigen
            $singleverf=~s/\s*:\s*$//;
            $singleverf=~s/. -$//;
            $singleverf=~s/^\s+//;
            $singleverf=~s/\s+$//;
            push @verfasser, $singleverf;
        }
    }

    # AutorJap
    if( exists $metadata{'AutorJap'} && $cols[$metadata{'AutorJap'}]->first_child('DATA')->text()) {
        for my $singleverf (split (";",$cols[$metadata{'AutorJap'}]->first_child('DATA')->text())){
            # Inhalt bereinigen
            $singleverf=~s/\s*:\s*$//;
            $singleverf=~s/. -$//;
            $singleverf=~s/^\s+//;
            $singleverf=~s/\s+$//;
            push @verfasser, $singleverf;
        }
    }

    # AV
    if( exists $metadata{'AV'} && $cols[$metadata{'AV'}]->first_child('DATA')->text()) {
        for my $singleverf (split (";",$cols[$metadata{'AV'}]->first_child('DATA')->text())){
            # Inhalt bereinigen
            $singleverf=~s/\s*:\s*$//;
            $singleverf=~s/. -$//;
            $singleverf=~s/^\s+//;
            $singleverf=~s/\s+$//;
            push @verfasser, $singleverf;
        }
    }

    my %seen_terms = ();
    my @unique_verfasser = grep { ! $seen_terms{$_} ++ } @verfasser;

    my $person_mult = 1;
    foreach my $singleverf (@unique_verfasser){        
	next unless ($singleverf);
        my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($singleverf);
	
        if ($new){
            my $item_ref = {
                'fields' => {},
            };
            $item_ref->{id} = $person_id;
            push @{$item_ref->{fields}{'0800'}}, {
                mult     => 1,
                subfield => '',
                content  => $singleverf,
            };
            
            print PERSON encode_json $item_ref, "\n";
        }

        push @{$title_ref->{fields}{'0100'}}, {
            mult       => $person_mult,
            subfield   => '',
            id         => $person_id,
            supplement => '',
        };
                    
        $person_mult++;
    }


    # Schlagworte
    my $subject_mult = 1;
    if(exists $metadata{'Schlagwort'} && $cols[$metadata{'Schlagwort'}]->first_child('DATA')->text()) {
        my $swtans_all=$cols[$metadata{'Schlagwort'}]->first_child('DATA')->text();

        if ($swtans_all){
            my @swts = split(" +",$swtans_all);

            foreach my $swtans (@swts){
		$swtans=~s/\n//g;
		next unless ($swtans);
                my ($subject_id,$new) = OpenBib::Conv::Common::Util::get_subject_id($swtans);
                
                if ($new){
                    my $item_ref = {
                        'fields' => {},
                    };
                    $item_ref->{id} = $subject_id;
                    push @{$item_ref->{fields}{'0800'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $swtans,
                    };
                    
                    print SUBJECT encode_json $item_ref, "\n";
                }
                
                push @{$title_ref->{fields}{'0710'}}, {
                    mult       => $subject_mult,
                    subfield   => '',
                    id         => $subject_id,
                    supplement => '',
                };
                
                $subject_mult++;
            }
        }
    }


    # Titelkategorien

    # Titel
    my @titel=();
    if(exists $metadata{'Titel'} && $cols[$metadata{'Titel'}]->first_child('DATA')->text()) {
        push @titel, $cols[$metadata{'Titel'}]->first_child('DATA')->text();
    }
    # Titel Jap
    if(exists $metadata{'TitelJap'} && $cols[$metadata{'TitelJap'}]->first_child('DATA')->text()) {
        push @titel, $cols[$metadata{'TitelJap'}]->first_child('DATA')->text();
    }
    if (@titel){
        push @{$title_ref->{fields}{'0331'}}, {
            content  => join(' / ',@titel),
            subfield => '',
            mult     => 1,
        };
    }

    # Ausgabe
    if(exists $metadata{'Ausgabe'} && $cols[$metadata{'Ausgabe'}]->first_child('DATA')->text()){
        push @{$title_ref->{fields}{'0403'}}, {
            content  => $cols[$metadata{'Ausgabe'}]->first_child('DATA')->text(),
            subfield => '',
            mult     => 1,
        };
    }


    # Verlag
    my @verlag=();
    if(exists $metadata{'Verlag'} && $cols[$metadata{'Verlag'}]->first_child('DATA')->text()){
        push @verlag, $cols[$metadata{'Verlag'}]->first_child('DATA')->text();
    }
    if(exists $metadata{'VerlJap'} && $cols[$metadata{'VerlJap'}]->first_child('DATA')->text()){
        push @verlag, $cols[$metadata{'VerlJap'}]->first_child('DATA')->text();
    }

    if (@verlag){
        push @{$title_ref->{fields}{'0412'}}, {
            content  => join(' / ',@verlag),
            subfield => '',
            mult     => 1,
        };
    }

    # Verlagsort
    my @verlagsorte=();
    if(exists $metadata{'Ort'} && $cols[$metadata{'Ort'}]->first_child('DATA')->text()){
        push @verlagsorte, $cols[$metadata{'Ort'}]->first_child('DATA')->text();
    }
    if(exists $metadata{'OrtJap'} && $cols[$metadata{'OrtJap'}]->first_child('DATA')->text()){
        push @verlagsorte, $cols[$metadata{'OrtJap'}]->first_child('DATA')->text();
    }
    if (@verlagsorte){
        push @{$title_ref->{fields}{'0410'}}, {
            content  => join(' / ',@verlagsorte),
            subfield => '',
            mult     => 1,
        };
    }

    # Umfang/Format
    if(exists $metadata{'Kollation'} && $cols[$metadata{'Kollation'}]->first_child('DATA')->text()){
        push @{$title_ref->{fields}{'0433'}}, {
            content  => $cols[$metadata{'Kollation'}]->first_child('DATA')->text(),
            subfield => '',
            mult     => 1,
        };
    }

    # Jahr
    if(exists $metadata{'Jahr'} && $cols[$metadata{'Jahr'}]->first_child('DATA')->text()){
        push @{$title_ref->{fields}{'0425'}}, {
            content  => $cols[$metadata{'Jahr'}]->first_child('DATA')->text(),
            subfield => '',
            mult     => 1,
        };
    }

    # Gesamttitel / Reihe
    my @gesamttitel=();
    if(exists $metadata{'Gesamttitel'} && $cols[$metadata{'Gesamttitel'}]->first_child('DATA')->text()){
        push @gesamttitel, $cols[$metadata{'Gesamttitel'}]->first_child('DATA')->text();
    }
    if(exists $metadata{'GesamtJap'} && $cols[$metadata{'GesamtJap'}]->first_child('DATA')->text()){
        push @gesamttitel, $cols[$metadata{'GesamtJap'}]->first_child('DATA')->text();
    }
    if(exists $metadata{'Reihe'} && $cols[$metadata{'Reihe'}]->first_child('DATA')->text()){
        push @gesamttitel, $cols[$metadata{'Reihe'}]->first_child('DATA')->text();
    }
    if(exists $metadata{'ReiheJap'} && $cols[$metadata{'ReiheJap'}]->first_child('DATA')->text()){
        push @gesamttitel, $cols[$metadata{'ReiheJap'}]->first_child('DATA')->text();
    }
    if (@gesamttitel){
        push @{$title_ref->{fields}{'0451'}}, {
            content  => join(' / ',@gesamttitel),
            subfield => '',
            mult     => 1,
        };
    }
    
    if(exists $metadata{'Sprache'} && $cols[$metadata{'Sprache'}]->first_child('DATA')->text()){
        push @{$title_ref->{fields}{'0015'}}, {
            content  => $cols[$metadata{'Sprache'}]->first_child('DATA')->text(),
            subfield => '',
            mult     => 1,
        };
    }

    if(exists $metadata{'Fußnote'} && $cols[$metadata{'Fußnote'}]->first_child('DATA')->text()){
        push @{$title_ref->{fields}{'0501'}}, {
            content  => $cols[$metadata{'Fußnote'}]->first_child('DATA')->text(),
            subfield => '',
            mult     => 1,
        };
    }

    if(exists $metadata{'Inventar'} && $cols[$metadata{'Inventar'}]->first_child('DATA')->text()){
        push @{$title_ref->{fields}{'0005'}}, {
            content  => $cols[$metadata{'Inventar'}]->first_child('DATA')->text(),
            subfield => '',
            mult     => 1,
        };
    }

    # Quelle
    if(exists $metadata{'Jg,Heft,Bd'} && $cols[$metadata{'Jg,Heft,Bd'}]->first_child('DATA')->text()){
        push @{$title_ref->{fields}{'0590'}}, {
            content  => $cols[$metadata{'Jg,Heft,Bd'}]->first_child('DATA')->text(),
            subfield => '',
            mult     => 1,
        };
    }

    # ISBN
    my $isbn_mult = 1;
    if(exists $metadata{'ISBN'} && $cols[$metadata{'ISBN'}]->first_child('DATA')->text()){
        foreach my $isbn (split /\n/, $cols[$metadata{'ISBN'}]->first_child('DATA')->text()){
            push @{$title_ref->{fields}{'0540'}}, { 
                content  => $isbn, 
                subfield => '',
                mult     => $isbn_mult++,
            };
        }
    }

    # Datum
    if(exists $metadata{'Datum'} && $cols[$metadata{'Datum'}]->first_child('DATA')->text()){
        push @{$title_ref->{fields}{'0002'}}, {
            content  => $cols[$metadata{'Datum'}]->first_child('DATA')->text(),
            subfield => '',
            mult     => 1,
        };
    }

    if(exists $metadata{'Standort erweitert'} && $cols[$metadata{'Standort erweitert'}]->first_child('DATA')->text()){
        push @{$title_ref->{fields}{'0016'}}, {
            content  => $cols[$metadata{'Standort erweitert'}]->first_child('DATA')->text(),
            subfield => '',
            mult     => 1,
        };
    }

    if(exists $metadata{'Signatur_flach'} && $cols[$metadata{'Signatur_flach'}]->first_child('DATA')->text()){
        push @{$title_ref->{fields}{'0014'}}, {
            content  => $cols[$metadata{'Signatur_flach'}]->first_child('DATA')->text(),
            subfield => '',
            mult     => 1,
        };
    }

    print TITLE encode_json $title_ref, "\n";

    # Exemplardaten
    if ((exists $metadata{'Signatur_flach'} && $cols[$metadata{'Signatur_flach'}]->first_child('DATA')->text()) || $cols[$metadata{'Standort erweitert'}]->first_child('DATA')->text()){

        my $item_ref = {
            'fields' => {},
        };
        $item_ref->{id} = $mexidn;
        push @{$item_ref->{fields}{'0004'}}, {
            mult     => 1,
            subfield => '',
            content  => $id,
        };

        if(exists $metadata{'Standort erweitert'} && $cols[$metadata{'Standort erweitert'}]->first_child('DATA')->text()){
            push @{$item_ref->{fields}{'0016'}}, {
                content  => $cols[$metadata{'Standort erweitert'}]->first_child('DATA')->text(),
                subfield => '',
                mult     => 1,
            };
        }
        
        if(exists $metadata{'Signatur_flach'} && $cols[$metadata{'Signatur_flach'}]->first_child('DATA')->text()){
            push @{$item_ref->{fields}{'0014'}}, {
                content  => $cols[$metadata{'Signatur_flach'}]->first_child('DATA')->text(),
                subfield => '',
                mult     => 1,
            };
        }
        
        $mexidn++;
        
        print HOLDING encode_json $item_ref, "\n";
    }


    # Release memory of processed tree
    # up to here
    $t->purge();
}                                                                    

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);
