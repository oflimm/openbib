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

my ($inputfile,$use_milid);

&GetOptions(
	    "inputfile=s"     => \$inputfile,
            "use-milid"       => \$use_milid,
	    );

if (!$inputfile){
    print << "HELP";
marc2meta.pl - Aufrufsyntax

    marc2meta.pl --inputfile=xxx
HELP
exit;
}

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

    if ($use_milid){
        my $field = $record->field('037');

        if ($field->as_string('b') eq "MIL"){
            $title_ref->{id} = $field->as_string('a');
        }
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

    # Verfasser

    {
        # Verfasser
        foreach my $fieldno ('100','700'){
            foreach my $field ($record->field($fieldno)){
                my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));
                my $content_c = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('c')):decode_utf8($field->as_string('c'));
                my $content_d = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('d')):decode_utf8($field->as_string('d'));

                if ($content_a){
                    my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($content_a);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $person_id;
                        
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
                    }
                    
                    my $multcount=++$multcount_ref->{'0100'};
                    
                    push @{$title_ref->{fields}{'0100'}}, {
                        mult       => $multcount,
                        subfield   => '',
                        id         => $person_id,
                        supplement => '',
                    };
                }
            }
        }
    }

    # Koerperschaften
    {
        foreach my $fieldno ('110','710'){
            foreach my $field ($record->field($fieldno)){
                my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));

                if ($content_a){
                    my ($corporatebody_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($content_a);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $corporatebody_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => konv($content_a),
                        };
                        
                        print CORPORATEBODY encode_json $item_ref, "\n";
                    }
                    
                    my $multcount=++$multcount_ref->{'0200'};
                    
                    push @{$title_ref->{fields}{'0200'}}, {
                        mult       => $multcount,
                        subfield   => '',
                        id         => $corporatebody_id,
                        supplement => '',
                    };
                }
            }
        }
    }

    # Klassifikationen

    {
        foreach my $field ($record->field('082')){
            my $content = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string($field)):decode_utf8($field->as_string($field));
            
            my ($classification_id,$new)=OpenBib::Conv::Common::Util::get_classification_id($content);
            
            if ($new){
                my $item_ref = {
                    'fields' => {},
                };
                $item_ref->{id} = $classification_id;
                push @{$item_ref->{fields}{'0800'}}, {
                    mult     => 1,
                    subfield => '',
                    content  => konv($content),
                };
                
                print CLASSIFICATION encode_json $item_ref, "\n";
            }
            
            my $multcount=++$multcount_ref->{'0700'};
            
            push @{$title_ref->{fields}{'0700'}}, {
                mult       => $multcount,
                subfield   => '',
                id         => $classification_id,
                supplement => '',
            };
        }
        
    }
    
    # Schlagworte

    {        
        # Schlagwort
        foreach my $fieldno ('650','651'){
            foreach my $field ($record->field($fieldno)){
                my $content = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string($field)):decode_utf8($field->as_string($field));
                
                my ($subject_id,$new) = OpenBib::Conv::Common::Util::get_subject_id($content);
                
                if ($new){
                    my $item_ref = {
                        'fields' => {},
                    };
                    $item_ref->{id} = $subject_id;
                    push @{$item_ref->{fields}{'0800'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => konv($content),
                    };
                    
                    print SUBJECT encode_json $item_ref, "\n";
                }
                
                my $multcount=++$multcount_ref->{'0710'};
                
                push @{$title_ref->{fields}{'0710'}}, {
                    mult       => $multcount,
                    subfield   => '',
                    id         => $subject_id,
                    supplement => '',
                };
            }
        }
    }
    
    # Titel

    {
        # ISBN
        foreach my $field ($record->field('020')){
            my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));

            $content_a=~s/\s+\(.+?\)\s*$//;
            
            if ($content_a){
                my $multcount=++$multcount_ref->{'0540'};
                
                push @{$title_ref->{fields}{'0540'}}, {
                    content  => konv($content_a),
                    subfield => '',
                    mult     => $multcount,
                };
            }
        }
        
        foreach my $field ($record->field('040')){
            my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));

            if ($content_a){
                my $multcount=++$multcount_ref->{'0015'};
                
                push @{$title_ref->{fields}{'0015'}}, {
                    content  => konv($content_a),
                    subfield => '',
                    mult     => $multcount,
                };
            }
        }

        # HST
        foreach my $field ($record->field('245')){
            my $content = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string()):decode_utf8($field->as_string());

            if ($content){
                my $multcount=++$multcount_ref->{'0331'};
                
                push @{$title_ref->{fields}{'0331'}}, {
                    content  => konv($content),
                    subfield => '',
                    mult     => $multcount,
                };
            }
        }

        # HST/GT
        if (0 == 1){
        foreach my $field ($record->field('245')){
            my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));
            my $content_c = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('c')):decode_utf8($field->as_string('c'));
            my $content_n = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('n')):decode_utf8($field->as_string('n'));
            my $content_p = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('p')):decode_utf8($field->as_string('p'));
            
            
            $content_p=~s/\s+\/\s+$//; # / am Ende entfernen
            
            # Teil einer Serie
            if ($content_p && $content_a){
                
                {
                    my $multcount=++$multcount_ref->{'0331'};
                    
                    push @{$title_ref->{fields}{'0331'}}, {
                        content  => konv($content_p),
                        subfield => '',
                        mult     => $multcount,
                    };
                }
                
                {
                    my $multcount=++$multcount_ref->{'0451'};
                    
                    push @{$title_ref->{fields}{'0451'}}, {
                        content  => konv($content_a),
                        subfield => '',
                        mult     => $multcount,
                    };
                }
                
                if ($content_n){
                    my $multcount=++$multcount_ref->{'0455'};
                    
                    push @{$title_ref->{fields}{'0455'}}, {
                        content  => konv($content_n),
                        subfield => '',
                        mult     => $multcount,
                    };
                }
            }
            else {
                my $multcount=++$multcount_ref->{'0331'};
                
                push @{$title_ref->{fields}{'0331'}}, {
                    content  => konv($content_a),
                    subfield => '',
                    mult     => $multcount,
                };
            }

            # Vorl. Verfasser/Koerperschaft
            if ($content_c){
                my $multcount=++$multcount_ref->{'0359'};
                
                push @{$title_ref->{fields}{'0359'}}, {
                    content  => konv($content_c),
                    subfield => '',
                    mult     => $multcount,
                };
            }
        }
    }
        
        # Auflage
        foreach my $field ($record->field('250')){
            my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));

            if ($content_a){
                my $multcount=++$multcount_ref->{'0403'};
                
                push @{$title_ref->{fields}{'0403'}}, {
                    content  => konv($content_a),
                    subfield => '',
                    mult     => $multcount,
                };
            }
        }

        # Verlag/Verlagsort/Jahr
        foreach my $field ($record->field('260')){
            my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));
            my $content_b = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('b')):decode_utf8($field->as_string('b'));
            my $content_c = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('c')):decode_utf8($field->as_string('c'));

            if ($content_a){
                my $multcount=++$multcount_ref->{'0410'};
                
                push @{$title_ref->{fields}{'0410'}}, {
                    content  => konv($content_a),
                    subfield => '',
                    mult     => $multcount,
                };
            }

            if ($content_b){
                my $multcount=++$multcount_ref->{'0412'};
                
                push @{$title_ref->{fields}{'0412'}}, {
                    content  => konv($content_b),
                    subfield => '',
                    mult     => $multcount,
                };
            }
            
            if ($content_c){
                my $multcount=++$multcount_ref->{'0425'};
                
                push @{$title_ref->{fields}{'0425'}}, {
                    content  => konv($content_c),
                    subfield => '',
                    mult     => $multcount,
                };
            }
        }

        # Kollation
        foreach my $field ($record->field('400')){
            my $content_a = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('a')):decode_utf8($field->as_string('a'));

            if ($content_a){
                my $multcount=++$multcount_ref->{'0433'};
                
                push @{$title_ref->{fields}{'0433'}}, {
                    content  => konv($content_a),
                    subfield => '',
                    mult     => $multcount,
                };
            }
        }


        # Fussnote
        foreach my $field ($record->field('500')){
            my $content = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string):decode_utf8($field->as_string);

            if ($content){
                my $multcount=++$multcount_ref->{'0501'};
                
                push @{$title_ref->{fields}{'0501'}}, {
                    content  => konv($content),
                    subfield => '',
                    mult     => $multcount,
                };
            }
        }

        # Format
        foreach my $field ($record->field('516')){
            my $content = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string):decode_utf8($field->as_string);

            if ($content){
                my $multcount=++$multcount_ref->{'0435'};
                
                push @{$title_ref->{fields}{'0435'}}, {
                    content  => konv($content),
                    subfield => '',
                    mult     => $multcount,
                };
            }
        }
        
        # WST
        foreach my $field ($record->field('700')){
            my $content = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string):decode_utf8($field->as_string);

            if ($content){
                my $multcount=++$multcount_ref->{'0370'};
                
                push @{$title_ref->{fields}{'0370'}}, {
                    content  => konv($content),
                    subfield => '',
                    mult     => $multcount,
                };
            }
        }

        # URLs
        foreach my $field ($record->field('856')){
            my $content_u = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('u')):decode_utf8($field->as_string('u'));
            my $content_z = ($encoding eq "MARC-8")?marc8_to_utf8($field->as_string('z')):decode_utf8($field->as_string('z'));
            
            if ($content_u){
                my $multcount=++$multcount_ref->{'0662'};
                
                push @{$title_ref->{fields}{'0662'}}, {
                    content  => $content_u,
                    subfield => '',
                    mult     => $multcount,
                };

                if ($content_z){
                    push @{$title_ref->{fields}{'0663'}}, {
                        content  => konv($content_z),
                        subfield => '',
                        mult     => $multcount,
                    };
                }
            }
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
    $content=~s/&/&amp;/g;
    $content=~s/</&lt;/g;
    $content=~s/>/&gt;/g;

    return $content;
}
