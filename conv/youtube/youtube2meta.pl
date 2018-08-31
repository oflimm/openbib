#!/usr/bin/perl

#####################################################################
#
#  youtube2meta.pl
#
#  Konvertierung von YouTube-Metadaten in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2014-2018 Oliver Flimm <flimm@openbib.org>
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
use JSON;
use Data::Dumper;
use YAML::Syck;
use DBIx::Class::ResultClass::HashRefInflator;
use Time::Seconds;
use LWP::UserAgent;
use LWP::Simple;

use OpenBib::Config::File;
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
our $config = OpenBib::Config::File->instance;

my $convconfig = YAML::Syck::LoadFile($configfile);

our $progname = "KUG-Youtube";
our $version = "0.1";

our $have_titleid_ref = {};

open (TITLE,         ">:utf8","meta.title");
open (PERSON,        ">:utf8","meta.person");
open (CORPORATEBODY, ">:utf8","meta.corporatebody");
open (CLASSIFICATION,">:utf8","meta.classification");
open (SUBJECT,       ">:utf8","meta.subject");
open (HOLDING,       ">:utf8","meta.holding");

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
        
        print PERSON to_json $item_ref, "\n";
        
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
        
        print CORPORATEBODY to_json $item_ref, "\n";

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
        
        print CLASSIFICATION to_json $item_ref, "\n";

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
        
        print SUBJECT to_json $item_ref, "\n";

        $count++;
    }

    $logger->info("### Persistente Normdaten-IDs: $count Schlagworte eingelesen");
}

foreach my $channel_ref (@{$convconfig->{channels}}){
    $logger->info("Processing Youtube Channel ".$channel_ref->{description});
    
#    eval {
	my $playlists_ref = get_user_playlists($channel_ref->{id});
        
        foreach my $playlist_ref (@$playlists_ref) {
            
            # Take only playlists, that match the title selector regexp
            if ($channel_ref->{title_selector}){
                my $regexp         = $channel_ref->{title_selector};
                my $playlisttitle  = $playlist_ref->{title};
                next unless ($playlisttitle =~m/$regexp/g);
            }
            
            # Convert Playlist data
            
            my $title_ref = {
                'fields' => {},
            };
	    
            my $titleid = $playlist_ref->{id};
            
            $titleid=~s/\//_/g;
            
            if ($have_titleid_ref->{$titleid}){
                $logger->error("Doppelte ID: $titleid");
                return;
            }
            
            $have_titleid_ref->{$titleid} = 1;
            
            $title_ref->{id} = $titleid; 

	    $logger->info("Processing Playlist: ".$playlist_ref->{title});

            push @{$title_ref->{fields}{'0331'}}, {
                mult     => 1,
                subfield => '',
                content  => $playlist_ref->{title},
            } if ($playlist_ref->{title});
	    
	    
            push @{$title_ref->{fields}{'0750'}}, {
                mult     => 1,
                subfield => '',
                content  => filter_newline2br($playlist_ref->{description}),
            } if ($playlist_ref->{description});
	    
            push @{$title_ref->{fields}{'0800'}}, {
                mult     => 1,
                subfield => '',
                content  => 'Topic',
            };
	    
            # Koerperschaften abarbeiten Anfang
            
            if ($playlist_ref->{channeltitle}){
                my $content = $playlist_ref->{channeltitle};
		
                if ($content){
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
                
            }
            # Koerperschaften abarbeiten Ende
            
            print TITLE to_json $title_ref;
            print TITLE "\n";
            
            my $parentid = $titleid;

	    my $videos_ref = get_videos_by_playlistid($titleid);

	    #$logger->info(YAML::Dump($videos_ref));
	    
            foreach my $video_ref (@$videos_ref){

		$logger->info("Processing videos: ".$video_ref->{title});
		
		my $title_ref = {
		    'fields' => {},
		};
		
		my $titleid = "VD".$video_ref->{id};
		
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

		push @{$title_ref->{fields}{'0089'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $video_ref->{position},
		} if ($video_ref->{position});

		
		push @{$title_ref->{fields}{'0331'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $video_ref->{title},
		} if ($video_ref->{title});
		    
		    
		push @{$title_ref->{fields}{'0750'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => filter_newline2br($video_ref->{description}),
		} if ($video_ref->{description});
		    
		    #                     push @{$title_ref->{fields}{'0662'}}, {
		    #                         mult     => 1,
		    #                         subfield => '',
		    #                         content  => $vid->content->type('flash')->[0]->url,
		    #                     } if ($vid->content->type('flash')->[0]->url);
		    
		if ($video_ref->{id}){
		    push @{$title_ref->{fields}{'0662'}}, {
			mult     => 1,
			subfield => '',
			content  => "https://www.youtube.com/watch?v=".$video_ref->{id},
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
		    content  => $video_ref->{thumbnails}{default}{url},
		} if ($video_ref->{thumbnails}{default}{url});
		
		# Duration
		
		if ($video_ref->{duration}){
		    my $ts = new Time::Seconds $video_ref->{duration};
		    
		    push @{$title_ref->{fields}{'0433'}}, {
			mult     => 1,
			subfield => '',
			content  => $ts->pretty,
		    };
		}
		
		$title_ref->{fields}{'4400'} = [
		    {
			mult     => 1,
			subfield => '',
			content  => "online",
		    },
		    ];
		
		push @{$title_ref->{fields}{'4410'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => 'Online Kurs-Video',
		};
		
		
		# Koerperschaften abarbeiten Anfang
		
		if ($video_ref->{channeltitle}){
		    my $content = $video_ref->{channeltitle};
		    
		    if ($content){
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
		}
		# Koerperschaften abarbeiten Ende
		
		# Schlagworte abarbeiten Anfang
		
		if ($video_ref->{tags}){
		    foreach my $content (@{$video_ref->{tags}}){
			
			if ($content){
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
				
				print SUBJECT to_json $item_ref;
				print SUBJECT "\n";
			    }
			    
			    my $new_category = "0710";
			    
			    push @{$title_ref->{fields}{$new_category}}, {
				mult       => 1,
				subfield   => '',
				id         => $subject_id,
				supplement => '',
			    };
			}
		    }
		    # Schlagworte abarbeiten Ende
		    
		    print TITLE to_json $title_ref;
		    
		    print TITLE "\n";
		}
                
            }
        }
#    };
    
    if ($@){
	$logger->error(YAML::Dump($@));
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

sub get_videos_by_playlistid {
    my ($playlistid) = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $ua = LWP::UserAgent->new();
    
    $ua->agent("$progname/$version");

    my $start = 1;
    my $nextPageToken = "";

    my @videoids = ();

    my $videoid_position_map_ref = {};
    
    while ($start || $nextPageToken){
	
	my $url = 'https://www.googleapis.com/youtube/v3/playlistItems?key='.$config->{youtube_api_key}.'&playlistId='.$playlistid.'&maxResults=50&part=snippet';
	
	if ($nextPageToken){
	    $url.="&pageToken=$nextPageToken";
	}
	
	$logger->debug($url);
	
	my $result = $ua->get($url);
	
	$logger->debug($result->decoded_content);
	
	my $result_ref;
	
	eval {
	    $result_ref = decode_json $result->decoded_content;
	};
	
	if ($@){
	    $logger->error("Fehler: $@");
	}

	$nextPageToken = $result_ref->{nextPageToken};		

	foreach my $thisitem_ref (@{$result_ref->{items}}){
	    my $videoid = $thisitem_ref->{snippet}{resourceId}{videoId};
	    push @videoids, $videoid;
	    $videoid_position_map_ref->{$videoid} = $thisitem_ref->{snippet}{position} + 1;
	}

	$start=0 if ($start);
    }

    $logger->info(YAML::Dump(\@videoids));
    
    my $allvideoid_string = join(',',@videoids);

    my $videos_ref = get_videoinfo($allvideoid_string);

    foreach my $video_ref (@$videos_ref){
	if (defined $videoid_position_map_ref->{$video_ref->{id}}){
	    $video_ref->{position} = $videoid_position_map_ref->{$video_ref->{id}};
	}
    }
    
    #$logger->info(YAML::Dump($videos_ref));
    
    return $videos_ref;

}

sub get_videoinfo {
    my ($videoid) = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $ua = LWP::UserAgent->new();
    
    $ua->agent("$progname/$version");

    my $start = 1;
    my $nextPageToken = "";

    my $items_ref = [];
    
    while ($start || $nextPageToken){
	
	my $url = 'https://www.googleapis.com/youtube/v3/videos?key='.$config->{youtube_api_key}.'&id='.$videoid.'&maxResults=50&part=contentDetails,snippet';
	
	if ($nextPageToken){
	    $url.="&pageToken=$nextPageToken";
	}
	
	$logger->debug($url);
	
	my $result = $ua->get($url);
	
	$logger->debug($result->decoded_content);
	
	my $result_ref;
	
	eval {
	    $result_ref = decode_json $result->decoded_content;
	};
	
	if ($@){
	    $logger->error("Fehler: $@");
	}
	
	$nextPageToken = $result_ref->{nextPageToken};		

	foreach my $thisitem_ref (@{$result_ref->{items}}){
	    push @{$items_ref}, {
		id => $thisitem_ref->{id},
		channeltitle => $thisitem_ref->{channelTitle},
		title => $thisitem_ref->{snippet}{title},
		description => $thisitem_ref->{snippet}{description},
		tags =>  $thisitem_ref->{snippet}{tags},
		thumbnails =>  $thisitem_ref->{snippet}{thumbnails},
		duration =>   $thisitem_ref->{contentDetails}{duration},
		definition =>   $thisitem_ref->{contentDetails}{definition},
	    };
	}

	$start=0 if ($start);
    }
    
    return $items_ref;

}

sub get_user_playlists {
    my ($channel_id) = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $ua = LWP::UserAgent->new();
    $ua->agent("$progname/$version");

    my $start = 1;
    my $nextPageToken = "";

    my $items_ref = [];
    
    while ($start || $nextPageToken){
	
	my $url = 'https://www.googleapis.com/youtube/v3/playlists?key='.$config->{youtube_api_key}.'&channelId='.$channel_id.'&maxResults=50&part=snippet,contentDetails';
	
	if ($nextPageToken){
	    $url.="&pageToken=$nextPageToken";
	}
	
	$logger->debug($url);
	
	my $result = $ua->get($url);
	
	$logger->debug($result->decoded_content);
	
	my $result_ref;
	
	eval {
	    $result_ref = decode_json $result->decoded_content;
	};
	
	if ($@){
	    $logger->error("Fehler: $@");
	}
	
	$nextPageToken = $result_ref->{nextPageToken};		

	foreach my $thisitem_ref (@{$result_ref->{items}}){
	    push @{$items_ref}, {
		id => $thisitem_ref->{id},
		title => $thisitem_ref->{snippet}{title},
		description => $thisitem_ref->{snippet}{description},
		channeltitle => $thisitem_ref->{snippet}{channelTitle},
	    } if ($thisitem_ref->{contentDetails}{itemCount}); # Nur Playlists mit Videos!
	}

	$start=0 if ($start);
    }

    #$logger->info(YAML::Dump($items_ref));
    
    return $items_ref;
}
