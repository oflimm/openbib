#!/usr/bin/perl

#####################################################################
#
#  marc2meta.pl
#
#  Konverierung von MARC-Daten in das Meta-Format
#
#  Dieses File ist (C) 2009-2013 Oliver Flimm <flimm@openbib.org>
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
use YAML::Syck;
use JSON::XS qw(encode_json);
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

my $logfile = '/var/log/openbib/marc2meta.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, LOGFILE, Screen
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

my $config = OpenBib::Config->instance;

my ($inputfile,$configfile,$missinglinkmurksid);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
            "missinglinkmurksid"   => \$missinglinkmurksid,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
marc2meta.pl - Aufrufsyntax

    marc2meta.pl --inputfile=xxx --configfile=yyy.yml
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

# Einlesen und Reorganisieren

open(DAT,"$inputfile");

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

my $multcount_ref = {};

my $batch = MARC::Batch->new('USMARC', $inputfile);

# Recover from errors
$batch->strict_off();
$batch->warnings_off();

my $have_title_ref = {};

while (my $record = $batch->next()){
    
    my $title_ref = {
        'fields' => {},
    };

    $multcount_ref = {};

    my $encoding = $record->encoding();

    $logger->debug("Encoding:$encoding:");

    if ($missinglinkmurksid){
        my $field = $record->field('037');

        if ($field->as_string('b') eq "MIL"){
            $title_ref->{id} = $field->as_string('a');
        }
#         foreach my $field ($record->field('856')){
#             my $content = $field->as_string("u");
#             if ($content =~m/id=(\d+)/){

#                 last;
#             }
#         }
    }
    else {
        my $idfield = $record->field('001');
        
        $title_ref->{id} = (defined $idfield)?$idfield->as_string():undef;
    }

    unless (defined $title_ref->{id}){
        $logger->info("Keine ID vorhanden");
        next;
    }
    
    if (defined $have_title_ref->{$title_ref->{id}}){
        $logger->info("Doppelte ID ".$title_ref->{id});
        next;
    }

    $have_title_ref->{$title_ref->{id}} = 1;
    
    foreach my $field ($record->fields()){
        my $tag        = $field->tag();
        my $indicator1 = defined $field->indicator(1)?$field->indicator(1):"";
        my $indicator2 = defined $field->indicator(2)?$field->indicator(2):"";

        foreach my $subfield_ref ($field->subfields()){
            my $subfield = $subfield_ref->[0];
            
            my $kateg   = $tag.$indicator1.$indicator2.$subfield;
            #my $content = decode($config->{encoding},$field->as_string($subfield)) || $field->as_string($subfield);

                my $content = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string($subfield)):decode_utf8($field->as_string($subfield));

            $content = konv($content);
            
            $logger->debug(":$kateg:",$field->as_string($subfield));
            
            if (exists $convconfig->{title}{$kateg}){
                my $newcategory = $convconfig->{title}{$kateg};
                
                # Filter
                
#                 if ($kateg =~m/^040/){
#                     $content=~s/PGUSA //;
#                 }
                
#                 if ($kateg =~m/^245/){
#                     ($content) = $content=~m/\s+\/\s+(.*?)$/;
                    
#                     $content=~s/\s+\/\s+(.*?)$//;
#                     $content=~s/\s+\[electronic resource\]//;
#                 }
                
#                 if ($kateg =~/^260/){
#                     ($content) = $content=~m/,\s+(\d\d\d\d)$/;
                    
#                 }
                
#                 if ($kateg =~m/^856/){
#                     if ($content =~/http:\/\/www.gutenberg.org\/license/){
#                         next;
#                     }
                    
#                 }
            
                if ($content){
                    my $multcount=++$multcount_ref->{$newcategory};
                    
                    push @{$title_ref->{fields}{$newcategory}}, {
                        content  => $content,
                        subfield => '',
                        mult     => $multcount,
                    };
                }
            }
            
        
        # Autoren abarbeiten Anfang
        elsif (exists $convconfig->{person}{$kateg} && $content){
            my $newcategory = $convconfig->{person}{$kateg};
            
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
            
            my $multcount=++$multcount_ref->{$newcategory};
            
            push @{$title_ref->{fields}{$newcategory}}, {
                mult       => $multcount,
                subfield   => '',
                id         => $person_id,
                supplement => '',
            };
        }
        # Autoren abarbeiten Ende
        
        # Koerperschaften abarbeiten Anfang
        elsif (exists $convconfig->{corporatebody}{$kateg} && $content){
            my $newcategory = $convconfig->{corporatebody}{$kateg};
            
            my ($corporatebody_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($content);
            
            if ($new){
                my $item_ref = {
                    'fields' => {},
                };
                $item_ref->{id} = $corporatebody_id;
                push @{$item_ref->{fields}{'0800'}}, {
                    mult     => 1,
                    subfield => '',
                    content  => $content,
                };
                
                print CORPORATEBODY encode_json $item_ref, "\n";
            }

            my $multcount=++$multcount_ref->{$newcategory};
            
            push @{$title_ref->{fields}{$newcategory}}, {
                mult       => $multcount,
                subfield   => '',
                id         => $corporatebody_id,
                supplement => '',
            };
        }
        # Koerperschaften abarbeiten Ende
        
        # Notationen abarbeiten Anfang
        elsif (exists $convconfig->{classification}{$kateg} && $content){
            my $newcategory = $convconfig->{classification}{$kateg};

            my ($classification_id,$new)=OpenBib::Conv::Common::Util::get_classification_id($content);
            
            if ($new){
                my $item_ref = {
                    'fields' => {},
                };
                $item_ref->{id} = $classification_id;
                push @{$item_ref->{fields}{'0800'}}, {
                    mult     => 1,
                    subfield => '',
                    content  => $content,
                };
                
                print CLASSIFICATION encode_json $item_ref, "\n";
            }
            
            my $multcount=++$multcount_ref->{$newcategory};
            
            push @{$title_ref->{fields}{$newcategory}}, {
                mult       => $multcount,
                subfield   => '',
                id         => $classification_id,
                supplement => '',
            };
        }
        # Schlagworte abarbeiten Ende
        
        
        # Schlagworte abarbeiten Anfang
        elsif (exists $convconfig->{subject}{$kateg} && $content){
            my $newcategory = $convconfig->{subject}{$kateg};
            
            my ($subject_id,$new) = OpenBib::Conv::Common::Util::get_subject_id($content);
            
            if ($new){
                my $item_ref = {
                    'fields' => {},
                };
                $item_ref->{id} = $subject_id;
                push @{$item_ref->{fields}{'0800'}}, {
                    mult     => 1,
                    subfield => '',
                    content  => $content,
                };
                
                print SUBJECT encode_json $item_ref, "\n";
            }
            
            my $multcount=++$multcount_ref->{$newcategory};
            
            push @{$title_ref->{fields}{$newcategory}}, {
                mult       => $multcount,
                subfield   => '',
                id         => $subject_id,
                supplement => '',
            };
        }
        # Schlagworte abarbeiten Ende
    }
}    
    print TITLE encode_json $title_ref, "\n";
    
    $logger->debug(encode_json $title_ref);
        

}

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

close(DAT);

sub konv {
    my $content = shift;

    $content=~s/\s*[.,:]\s*$//g;
    
    return $content;
}
