#!/usr/bin/perl

#####################################################################
#
#  youtube2meta.pl
#
#  Konvertierung von YouTube-Metadaten in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode_utf8';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use WebService::GData::YouTube;
use JSON;
use YAML::Syck;
use DBIx::Class::ResultClass::HashRefInflator;
use Time::Seconds;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;
use OpenBib::Catalog::Factory;

my ($logfile,$loglevel,$database,$inputfile,$configfile,$persistentnormdataids);

&GetOptions(
    	    "database=s"              => \$database,
            "persistent-normdata-ids" => \$persistentnormdataids,
            "configfile=s"            => \$configfile,
            "logfile=s"               => \$logfile,
            "loglevel=s"              => \$loglevel,
	    );

if (!$configfile){
    print << "HELP";
youtube2meta.pl - Aufrufsyntax

    youtube2meta.pl --configfile=xxx.yml

      --configfile=                : Name der Parametrisierungsdaei

      -persistent-normdata-ids     : Persistente Normdaten-IDs im Katalog

HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/youtube2meta.log';
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

if ($persistentnormdataids){
    unless ($database){
        $logger->error("### Datenbankname fuer Persistente Normdaten-IDs notwendig. Abbruch.");
        exit;
    }

    my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database});
    
    $logger->info("### Persistente Normdaten-IDs");

      $logger->info("### Persistente Normdaten-IDs: Personen");

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
        $item_ref->{id} = $person->{person_id};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $person->{content},
        };
        
        print PERSON to_json $item_ref, "\n";
        
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
        $item_ref->{id} = $corporatebody->{corporatebody_id};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $corporatebody->{content},
        };
        
        print CORPORATEBODY to_json $item_ref, "\n";

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
        $item_ref->{id} = $classification->{classification_id};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $classification->{content},
        };
        
        print CLASSIFICATION to_json $item_ref, "\n";

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
        $item_ref->{id} = $subject->{subject_id};
        push @{$item_ref->{fields}{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $subject->{content},
        };
        
        print SUBJECT to_json $item_ref, "\n";

        $count++;
    }

    $logger->info("### Persistente Normdaten-IDs: $count Schlagworte eingelesen");
}

my $yt = new WebService::GData::YouTube();
$yt->query->max_results(50);

foreach my $channel_ref (@{$convconfig->{channels}}){
    $logger->info("Processing Youtube Channel $channel_ref->{description}");
    
    while(my $playlists = $yt->get_user_playlists($channel_ref->{name})) {
        
        foreach my $playlist (@$playlists) {
            
            # Take only playlists, that match the title selector regexp
            if ($channel_ref->{title_selector}){
                my $regexp         = $channel_ref->{title_selector};
                my $playlisttitle  = conv($playlist->title);
                next unless ($playlisttitle =~m/$regexp/g);
            }
            
            # Convert Playlist data
            
            my $title_ref = {
                'fields' => {},
            };

            my $titleid = $playlist->playlist_id;
            
            $titleid=~s/\//_/g;
            
            if ($have_titleid_ref->{$titleid}){
                $logger->error("Doppelte ID: $titleid");
                return;
            }
            
            $have_titleid_ref->{$titleid} = 1;
            
            $title_ref->{id} = $titleid; 

            push @{$title_ref->{fields}{'0331'}}, {
                mult     => 1,
                subfield => '',
                content  => conv($playlist->title),
            } if ($playlist->title);

                   
            push @{$title_ref->{fields}{'0750'}}, {
                mult     => 1,
                subfield => '',
                content  => filter_newline2br(conv($playlist->description)),
            } if ($playlist->description);

            push @{$title_ref->{fields}{'0800'}}, {
                mult     => 1,
                subfield => '',
                content  => 'Topic',
            };

            # Koerperschaften abarbeiten Anfang
            
            if ($playlist->author->[0]->name){
                my $content = $playlist->author->[0]->name;
                
                my ($corporatebody_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($content);
                
                if ($new){
                    my $item_ref = {
                        'fields' => {},
                    };
                    $item_ref->{id} = $corporatebody_id;
                    push @{$item_ref->{fields}{'0800'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => conv($content),
                    };
                    
                    print CORPORATEBODY to_json $item_ref;
                    print CORPORATEBODY "\n";
                }
                
                my $new_category = "0200";
                
                push @{$title_ref->{fields}{$new_category}}, {
                    mult       => 1,
                    subfield   => '',
                    id         => $corporatebody_id,
                    supplement => '',
                };
                
            }
            # Autoren abarbeiten Ende
            
            print TITLE to_json $title_ref;
            print TITLE "\n";
            
            my $parentid = $titleid;
            
            while(my $videos = $yt->get_user_playlist_by_id($playlist->playlist_id)) {
                foreach my $vid (@$videos){

                    eval {
                        my $title_ref = {
                            'fields' => {},
                        };
                        
                        my $titleid = "VD".$vid->video_id;
                        
                        $titleid=~s/\//_/g;
                        
                        if ($have_titleid_ref->{$titleid}){
                            $logger->error("Doppelte ID: $titleid");
                            next;
                        }
                    
                        $have_titleid_ref->{$titleid} = 1;
                        
                        $title_ref->{id} = $titleid; 
                        
                        push @{$title_ref->{fields}{'0004'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $parentid,
                        };
                        
                        push @{$title_ref->{fields}{'0331'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => conv($vid->title),
                        } if ($vid->title);
                        
                        
                        push @{$title_ref->{fields}{'0750'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => filter_newline2br(conv($vid->description)),
                        } if ($vid->description);
                        
                        #                     push @{$title_ref->{fields}{'0662'}}, {
                        #                         mult     => 1,
                        #                         subfield => '',
                        #                         content  => $vid->content->type('flash')->[0]->url,
                        #                     } if ($vid->content->type('flash')->[0]->url);
                        
                        if ($vid->media_player){
                            push @{$title_ref->{fields}{'0662'}}, {
                                mult     => 1,
                                subfield => '',
                                content  => $vid->media_player,
                            };
                            
                            push @{$title_ref->{fields}{'0663'}}, {
                                mult     => 1,
                                subfield => '',
                                content  => "Online Kurs-Video bei YouTube anschauen",
                            };
                        }
                        
                        # Thumbnail
                        
                        push @{$title_ref->{fields}{'4111'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => $vid->thumbnails->[0]->url,
                        } if ($vid->thumbnails->[0]->url);
                        
                        # Duration
                        
                        if ($vid->duration){
                            my $ts = new Time::Seconds $vid->duration;
                            
                            push @{$title_ref->{fields}{'0433'}}, {
                                mult     => 1,
                                subfield => '',
                                content  => $ts->pretty,
                            };
                        }
                        
                        push @{$title_ref->{fields}{'4410'}}, {
                            mult     => 1,
                            subfield => '',
                            content  => 'Online Kurs-Video',
                        };
                        
                        
                        # Koerperschaften abarbeiten Anfang
                        
                        if ($vid->author->[0]->name){
                            my $content = $vid->author->[0]->name;
                            
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
                                
                                print CORPORATEBODY to_json $item_ref;
                                print CORPORATEBODY "\n";
                            }
                            
                            my $new_category = "0200";
                            
                            push @{$title_ref->{fields}{$new_category}}, {
                                mult       => 1,
                                subfield   => '',
                                id         => $corporatebody_id,
                                supplement => '',
                            };
                            
                        }
                        # Autoren abarbeiten Ende
                        
                        print TITLE to_json $title_ref;

                        print TITLE "\n";
                    }
                }
            }
        }
    }

}


close(TITLE);
close(PERSON);
close(CORPORATEBODY);
close(CLASSIFICATION);
close(SUBJECT);
close(HOLDING);

sub conv {
    my $content = shift;

    $content = decode_utf8($content);
    
    return $content;
}

sub filter_newline2br {
    my ($content) = @_;

    $content=~s/\n/<br\/>/g;
    
    return $content;
}
