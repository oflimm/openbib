#!/usr/bin/perl

#####################################################################
#
#  simplexml2meta.pl
#
#  Konvertierung eines flachen XML-Formates in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2012-2016 Oliver Flimm <flimm@openbib.org>
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

use utf8;
use strict;
use warnings;

use Encode 'decode';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use XML::Twig::XPath;
use XML::Simple;
use JSON::XS;
use YAML::Syck;
use DBIx::Class::ResultClass::HashRefInflator;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;
use OpenBib::Catalog::Factory;

my ($logfile,$loglevel,$database,$inputfile,$configfile,$persistentnormdataids);

&GetOptions(
    	    "database=s"              => \$database,
            "persistent-normdata-ids" => \$persistentnormdataids,
	    "inputfile=s"             => \$inputfile,
            "configfile=s"            => \$configfile,
            "logfile=s"               => \$logfile,
            "loglevel=s"              => \$loglevel,
	    );

if (!$inputfile || !$configfile){
    print << "HELP";
simplexml2meta.pl - Aufrufsyntax

    simplexml2meta.pl --inputfile=xxx --configfile=yyy.yml

      --inputfile=                 : Name der Eingabedatei
      --configfile=                : Name der Parametrisierungsdaei

      --database=                  : Name der Katalogdatenbank
      -persistent-normdata-ids     : Persistente Normdaten-IDs im Katalog

HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/simplexml2meta.log';
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

our $have_titleid_ref = {};

open (TITLE,         ">:raw","meta.title");
open (PERSON,        ">:raw","meta.person");
open (CORPORATEBODY, ">:raw","meta.corporatebody");
open (CLASSIFICATION,">:raw","meta.classification");
open (SUBJECT,       ">:raw","meta.subject");
open (HOLDING,       ">:raw","meta.holding");

$logger->info("### Record Selector: ".$convconfig->{recordselector});

my $twig= XML::Twig::XPath->new(
    output_filter => 'safe',
    TwigHandlers => {
	"$convconfig->{recordselector}" => \&parse_record
    }
    );

if ($persistentnormdataids){
    unless ($database){
        $logger->error("### Datenbankname fuer Persistente Normdaten-IDs notwendig. Abbruch.");
        exit;
    }

    my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database});
    
    $logger->info("### Persistente Normdaten-IDs");

      $logger->info("### Persistente Normdaten-IDs: Personen");

    my $persons = $catalog->get_schema->resultset("PersonField")->search(
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
        $item_ref->{id} = $person->{person_id};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $person->{content},
        };
        
        print PERSON encode_json $item_ref, "\n";
        
        $count++;
    }

    $logger->info("### Persistente Normdaten-IDs: $count Personen eingelesen");

    my $corporatebodies = $catalog->get_schema->resultset("CorporatebodyField")->search(
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
        $item_ref->{id} = $corporatebody->{corporatebody_id};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $corporatebody->{content},
        };
        
        print CORPORATEBODY encode_json $item_ref, "\n";

        $count++;
    }

    $logger->info("### Persistente Normdaten-IDs: $count Koerperschaften eingelesen");

    my $classifications = $catalog->get_schema->resultset("ClassificationField")->search(
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
        $item_ref->{id} = $classification->{classification_id};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $classification->{content},
        };
        
        print CLASSIFICATION encode_json $item_ref, "\n";

        $count++;
    }

    $logger->info("### Persistente Normdaten-IDs: $count Klassifikationen eingelesen");
    
    my $subjects = $catalog->get_schema->resultset("SubjectField")->search(
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
        $item_ref->{id} = $subject->{subject_id};
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

our $counter = 0;
our $mexidn  = 1;


eval {
    $twig->safe_parsefile($inputfile);
};

if ($@){
    $logger->error($@);
}

print STDERR "All $counter records converted\n";

close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

sub parse_record {
    my($t, $titset)= @_;

    my $logger = get_logger();

    my $title_ref = {
        'fields' => {},
    };

    if ($logger->is_debug){
	$logger->debug($titset->toString);
    }

    my $is_deleted;

    $is_deleted = $titset->findnodes($convconfig->{is_deleted}) if (defined $convconfig->{is_deleted});

    if ($is_deleted){
	$logger->debug("Geloeschte ID");
	$t->purge();
	return;
    }

    my @ids= $titset->findnodes($convconfig->{uniqueidfield});

    # if (@ids){
    # 	$logger->debug("ID: ".YAML::Dump(\@ids));
    # }
    # else {
    # 	$logger->debug("No Title-ID!!!");
    # }


    my $titleid = $ids[0]->first_child()->text();
    
    $titleid=~s/\//_/g;

    if ($titleid){
	$logger->info("Processing ID: $titleid");
    }
    else {
	$logger->debug("NO Title-ID!!!");
    }

    if ($have_titleid_ref->{$titleid}){
        $logger->error("Doppelte ID: $titleid");
	$t->purge();
        return;
    }
        
    $have_titleid_ref->{$titleid} = 1;

    $title_ref->{id} = $titleid; 

    foreach my $kateg (keys %{$convconfig->{title}}){
	$logger->debug("Processing $kateg");


        my @elements = $titset->findnodes($kateg);

        my @parts = ();
        
        foreach my $element (@elements){

            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());

	    $logger->debug("Field $kateg - $content");
	    
            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }

            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            if ($convconfig->{filter}{$kateg}{filter_add_year}){
                my $new_content = filter_match($content,$convconfig->{filter}{$kateg}{filter_add_year}{regexp});

                push @{$title_ref->{fields}{$convconfig->{filter}{$kateg}{filter_add_year}{category}}}, {
                    mult     => 1,
                    subfield => '',
                    content  => $new_content,
                };
            }

            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
    
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $mult = 1;
        foreach my $part (@parts){
            push @{$title_ref->{fields}{$convconfig->{title}{$kateg}}}, {
                mult     => $mult,
                subfield => '',
                content  => $part,
            } if ($part);
        }
    }
    
    # Autoren abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{person}}){
        my @elements = $titset->findnodes($kateg);

        my @parts = ();
        
        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }
                
            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
                                              
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);                    
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $mult = 1;
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
        # Autoren abarbeiten Ende
    }

    # Koerperschaften abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{corporatebody}}){
        my @elements = $titset->findnodes($kateg);
        
        my @parts = ();

        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
                
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $mult = 1;
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
    # Koerperschaften abarbeiten Ende

    # Notationen abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{classification}}){
        my @elements = $titset->findnodes($kateg);
        
        my @parts = ();
        
        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
                
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $mult = 1;
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
    # Notationen abarbeiten Ende
        
    # Schlagworte abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{subject}}){
        my @elements = $titset->findnodes($kateg);

        my @parts = ();
        
        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());

            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }

            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
                
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $mult = 1;
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
    # Schlagworte abarbeiten Ende

    my %mex = ();
    
    # Exemplare abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{holding}}){
        my @elements = $titset->findnodes($kateg);
        
        my @parts = ();
        
        foreach my $element (@elements){
            next unless (defined $element->first_child());
            my $content = konv($element->first_child()->text());
            
            if ($convconfig->{filter}{$kateg}{filter_junk}){
                $content = filter_junk($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_newline2br}){
                $content = filter_newline2br($content);
            }
            
            if ($convconfig->{filter}{$kateg}{filter_match}){
                $content = filter_match($content,$convconfig->{filter}{$kateg}{filter_match});
            }
            
            if ($content){
                $content=decode($convconfig->{encoding},$content) if ($convconfig->{encoding});
                
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
            }
        }

        my $multiple = 1;

        foreach my $part (@parts){
            $mex{$multiple}{$convconfig->{holding}{$kateg}} = $part if ($part); 
        }

    }

    foreach my $part (keys %mex){
        my $item_ref = {
            'fields' => {},
        };
        $item_ref->{id} = $mexidn;
        push @{$item_ref->{fields}{'0004'}}, {
            mult     => 1,
            subfield => '',
            content  => $title_ref->{id},
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

    
    if ($convconfig->{defaultmediatype}){
        push @{$title_ref->{fields}{'4410'}}, {
            mult     => 1,
            subfield => '',
            content  => $convconfig->{defaultmediatype},
        };
    }

    print TITLE encode_json $title_ref, "\n";

    $counter++;

    if ($counter % 1000 == 0){
        print STDERR "$counter records converted\n";
    }
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}
                                   
sub konv {
    my ($content)=@_;

#    $content=~s/\&/&amp;/g;
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    return $content;
}

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

    my ($match)=$content=~m/($regexp)/g;
    
    return $match;
}

