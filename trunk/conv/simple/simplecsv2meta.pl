#!/usr/bin/perl

#####################################################################
#
#  simplecsv2meta.pl
#
#  Konverierung der einfach aufgebauter CVS-Daten in das Meta-Format
#
#  Dieses File ist (C) 1999-2013 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;
use utf8;

use Encode 'decode';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Text::CSV_XS;
use JSON::XS;
use YAML::Syck;
use DBIx::Class::ResultClass::HashRefInflator;

use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Conv::Common::Util;
use OpenBib::Catalog::Factory;

my $config    = new OpenBib::Config;
my $enrichmnt = new OpenBib::Enrichment;

my ($database,$inputfile,$configfile,$logfile,$loglevel,$persistentnormdataids);

&GetOptions(
    	    "database=s"              => \$database,
	    "inputfile=s"             => \$inputfile,
            "configfile=s"            => \$configfile,
            "persistent-normdata-ids" => \$persistentnormdataids,
            "logfile=s"               => \$logfile,
            "loglevel=s"              => \$loglevel,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
simplecsv2meta.pl - Aufrufsyntax

    simplecsv2meta.pl --inputfile=xxx --configfile=yyy.yml

      --inputfile=                 : Name der Eingabedatei
      --configfile=                : Name der Parametrisierungsdaei

      --database=                  : Name der Katalogdatenbank
      -persistent-normdata-ids     : Persistente Normdaten-IDs im Katalog

      --logfile=                   : Name der Logdatei
      --loglevel=                  : Loglevel
HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/simplecsv2meta.log';
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
my $convconfig = YAML::Syck::LoadFile($configfile);

# Einlesen und Reorganisieren

my $outputencoding = ($convconfig->{outputencoding})?$convconfig->{outputencoding}:'utf8';
my $inputencoding  = ($convconfig->{encoding})?$convconfig->{encoding}:'utf8';

my $csv_options = {};

foreach my $csv_option (keys %{$convconfig->{csv}}){
    $csv_options->{$csv_option} = $convconfig->{csv}{$csv_option};
}

my $csv = Text::CSV_XS->new($csv_options);

our $mexidn=1;

open my $in,   "<:encoding($inputencoding)",$inputfile;

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

if ($persistentnormdataids){

    unless ($database){
        $logger->error("### Datenbankname fuer Persistente Normdaten-IDs notwendig. Abbruch.");
        exit;
    }

    my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database});
    
    $logger->info("### Persistente Normdaten-IDs");

    my $persons = $catalog->{schema}->resultset("PersonField")->search(
        {
            field => 800,
        },
        {
            columns => [qw/ personid content /],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    my $count=1;
    foreach my $person ($persons->all){
        OpenBib::Conv::Common::Util::set_person_id($person->{personid},$person->{content});

        my $item_ref = {
            'fields' => {},
        };
        $item_ref->{id} = $person->{personid};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $person->{content},
        };
        
        print PERSON encode_json $item_ref, "\n";
        
        $count++;
    }

    $logger->info("### Persistente Normdaten-IDs: $count Personen eingelesen");

    my $corporatebodies = $catalog->{schema}->resultset("CorporatebodyField")->search(
        {
            field => 800,
        },
        {
            columns => [qw/ corporatebodyid content /],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    $count=1;
    foreach my $corporatebody ($corporatebodies->all){
        OpenBib::Conv::Common::Util::set_corporatebody_id($corporatebody->{corporatebodyid},$corporatebody->{content});        

        my $item_ref = {
            'fields' => {},
        };
        $item_ref->{id} = $corporatebody->{corporatebodyid};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $corporatebody->{content},
        };
        
        print CORPORATEBODY encode_json $item_ref, "\n";

        $count++;
    }

    $logger->info("### Persistente Normdaten-IDs: $count Koerperschaften eingelesen");

    my $classifications = $catalog->{schema}->resultset("ClassificationField")->search(
        {
            field => 800,
        },
        {
            columns => [qw/ classificationid content /],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    $count=1;
    foreach my $classification ($classifications->all){
        OpenBib::Conv::Common::Util::set_classification_id($classification->{classificationid},$classification->{content});        

        my $item_ref = {
            'fields' => {},
        };
        $item_ref->{id} = $classification->{classificationid};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $classification->{content},
        };
        
        print CLASSIFICATION encode_json $item_ref, "\n";

        $count++;
    }

    $logger->info("### Persistente Normdaten-IDs: $count Klassifikationen eingelesen");
    
    my $subjects = $catalog->{schema}->resultset("SubjectField")->search(
        {
            field => 800,
        },
        {
            columns => [qw/ subjectid content /],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    $count=1;
    foreach my $subject ($subjects->all){
        OpenBib::Conv::Common::Util::set_subject_id($subject->{subjectid},$subject->{content});        

        my $item_ref = {
            'fields' => {},
        };
        $item_ref->{id} = $subject->{subjectid};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $subject->{content},
        };
        
        print SUBJECT encode_json $item_ref, "\n";

        $count++;
    }

    $logger->info("### Persistente Normdaten-IDs: $count Schlagworte eingelesen");
    
}

my $titleid = 1;
my $have_titleid_ref = {};

my $excluded_titles = 0;

my @cols = @{$csv->getline ($in)};
my $row = {};
$csv->bind_columns (\@{$row}{@cols});

while ($csv->getline ($in)){
    if ($logger->is_debug){
        $logger->debug(YAML::Dump($row));
    }
    
    my $title_ref = {
        'fields' => {},
    };
    
    if ($convconfig->{exclude}{by_availability}){
        my $key_field = $convconfig->{exclude}{by_availability}{field};
        my $content = $row->{$key_field};
        
        my @keys = ();
        if (exists $convconfig->{category_split_chars}{$key_field} && $content=~/$convconfig->{category_split_chars}{$key_field}/){
            @keys = split($convconfig->{category_split_chars}{$key_field},$content);
        }
        else {
            $content=~s/\n/ /g;
            push @keys, $content;
        }
        
        my $databases_ref = $convconfig->{exclude}{by_availability}{databases};
        
        if ($enrichmnt->check_availability_by_isbn({isbn => \@keys, databases => $databases_ref })){
            $logger->info("Titel mit ISBNs ".join(' ',@keys)." bereits in Datenbanken ".join(' ',@$databases_ref)." vorhanden!");
            $excluded_titles++;
            next;
        }        
    }

    if ($convconfig->{uniqueidfield}){
        my $id = $row->{$convconfig->{uniqueidfield}};

        $id=~s/\//_/g;

        if ($convconfig->{uniqueidmatch}){
            my $uniquematchregexp = $convconfig->{uniqueidmatch};
            ($id)=$id=~m/$uniquematchregexp/;
        }
        unless ($id){
            $logger->error("KEINE ID");
            next;
        }
        
        if ($have_titleid_ref->{$id}){
            $logger->error("Doppelte ID: $id");
	    next;
        }

        $title_ref->{id} = $id;
        $have_titleid_ref->{$id} = 1;
    }
    else {
        $title_ref->{id} = $titleid++;
    }

    if ($convconfig->{defaultmediatype}){
        push @{$title_ref->{fields}{'4410'}}, {
            mult     => 1,
            subfield => '',
            content  => $convconfig->{defaultmediatype},
        };
    }
    
    foreach my $kateg (keys %{$convconfig->{title}}){
        my $content = $row->{$kateg};
        #my $content = decode($convconfig->{encoding},$row->{$kateg});

        if ($content){
            
            if ($convconfig->{filter}{$kateg}{filter_generic}){
                foreach my $filter (@{$convconfig->{filter}{$kateg}{filter_generic}}){
                    my $from = $filter->{from};
                    my $to   = $filter->{to};
                    $content =~s/$from/$to/g;
                }
            }
            
            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }

            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            my $mult = 1;
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                $content=~s/\n/ /g;
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                $part=~s/uhttp:/http:/;
                my $new_category = $convconfig->{title}{$kateg};

                push @{$title_ref->{fields}{$new_category}}, {
                    mult     => $mult,
                    subfield => '',
                    content  => $part,
                };

                $mult++;
            }
        }
    }

    # Autoren abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{person}}){
        my $content = $row->{$kateg};
        #my $content = decode($convconfig->{encoding},$row->{$kateg});

        if ($content){

            if ($convconfig->{filter}{$kateg}{filter_generic}){
                foreach my $filter (@{$convconfig->{filter}{$kateg}{filter_generic}}){
                    my $from = $filter->{from};
                    my $to   = $filter->{to};
                    
                    $content =~s/$from/$to/g;
                }
            }

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }

            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            my $mult = 1;
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }

            foreach my $part (@parts){
                if ($part){
                    my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($part);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $person_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print PERSON encode_json $item_ref, "\n";
                    }
                    
                    my $new_category = $convconfig->{person}{$kateg};
                    
                    push @{$title_ref->{fields}{$new_category}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $person_id,
                        supplement => '',
                    };
                    
                    $mult++;
                }
            }
        }

    }
    # Autoren abarbeiten Ende
    
    # Koerperschaften abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{corporatebody}}){
        my $content = $row->{$kateg};
        #my $content = decode($convconfig->{encoding},$row->{$kateg});
        
        if ($content){
            if ($convconfig->{filter}{$kateg}{filter_generic}){
                foreach my $filter (@{$convconfig->{filter}{$kateg}{filter_generic}}){
                    my $from = $filter->{from};
                    my $to   = $filter->{to};
                    
                    $content =~s/$from/$to/g;
                }
            }

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }

            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            my $mult = 1;
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                if ($part){
                    my ($corporatebody_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($part);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $corporatebody_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print CORPORATEBODY encode_json $item_ref, "\n";
                    }
                    
                    my $new_category = $convconfig->{corporatebody}{$kateg};
                    
                    push @{$title_ref->{fields}{$new_category}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $corporatebody_id,
                        supplement => '',
                    };

                    $mult++;
                }
            }
        }
    }
    # Koerperschaften abarbeiten Ende


    # Notationen abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{classification}}){
        my $content = $row->{$kateg};
        #my $content = decode($convconfig->{encoding},$row->{$kateg});
        
        if ($content){
            if ($convconfig->{filter}{$kateg}{filter_generic}){
                foreach my $filter (@{$convconfig->{filter}{$kateg}{filter_generic}}){
                    my $from = $filter->{from};
                    my $to   = $filter->{to};
                    
                    $content =~s/$from/$to/g;
                }
            }
            
            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }

            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            my $mult = 1;
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                if ($part){
                    my ($classification_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($part);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $classification_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print CLASSIFICATION encode_json $item_ref, "\n";
                    }
                    
                    my $new_category = $convconfig->{classification}{$kateg};
                    
                    push @{$title_ref->{fields}{$new_category}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $classification_id,
                        supplement => '',
                    };
                    
                    $mult++;
                }
            }
        }
    }
    # Notationen abarbeiten Ende

    # Schlagworte abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{subject}}){
        my $content = $row->{$kateg};
        #my $content = decode($convconfig->{encoding},$row->{$kateg});

        if ($content){
            if ($convconfig->{filter}{$kateg}{filter_generic}){
                foreach my $filter (@{$convconfig->{filter}{$kateg}{filter_generic}}){
                    my $from = $filter->{from};
                    my $to   = $filter->{to};
                    
                    $content =~s/$from/$to/g;
                }
            }

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }

            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }
            
            my $mult = 1;
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                if ($part){
                    my ($subject_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($part);
                    
                    if ($new){
                        my $item_ref = {
                            'fields' => {},
                        };
                        $item_ref->{id} = $subject_id;
                        push @{$item_ref->{fields}{'0800'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $part,
                        };
                        
                        print SUBJECT encode_json $item_ref, "\n";
                    }
                    
                    my $new_category = $convconfig->{subject}{$kateg};
                    
                    push @{$title_ref->{fields}{$new_category}}, {
                        mult       => $mult,
                        subfield   => '',
                        id         => $subject_id,
                        supplement => '',
                    };
                    
                    $mult++;
                }
            }
            
        }
    }
    # Schlagworte abarbeiten Ende


    my %mex = ();
    # Exemplare abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{holding}}){
#        my $content = decode($convconfig->{encoding},$row->{$kateg});
        my $content = $row->{$kateg};

        if ($content){
            if ($convconfig->{filter}{$kateg}{filter_generic}){
                foreach my $filter (@{$convconfig->{filter}{$kateg}{filter_generic}}){
                    my $from = $filter->{from};
                    my $to   = $filter->{to};
                    
                    $content =~s/$from/$to/g;
                }
            }

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }

            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            my $multiple = 1;
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }

            foreach my $part (@parts){
                 $mex{$multiple}{$convconfig->{holding}{$kateg}} = $part; 
            }
        }
    }

    #print YAML::Dump(\%mex);
    foreach my $part (keys %mex){
        my $item_ref = {
            'fields' => {},
        };
        $item_ref->{id} = $mexidn;
        push @{$item_ref->{fields}{'0004'}}, {
            mult     => 1,
            subfield => '',
            content  => $titleid,
        };

        foreach my $category (keys %{$mex{$part}}){
            push @{$item_ref->{fields}{$category}}, {
                mult     => 1,
                subfield => '',
                content  => $mex{$part}{$category},
            };
        }
        
        $mexidn++;
        
        print HOLDING encode_json $item_ref, "\n";
    }

    # Exemplare abarbeiten Ende

    print TITLE encode_json $title_ref, "\n";
}

$logger->info("Excluded titles: $excluded_titles");

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

# Filter

sub filter_junk {
    my ($content) = @_;

    $content=~s/\W/ /g;
    $content=~s/\s+/ /g;
    $content=~s/\s\D\s/ /g;

    
    return $content;
}

sub filter_newline2br {
    my ($content) = @_;

    $content=~s/\n/<br\/>/g;
    
    return $content;
}

sub filter_match {
    my ($content,$regexp) = @_;

    my ($match)=$content=~m/$regexp/g;

    return $match;
}
