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

my ($logfile,$loglevel,$inputfile,$onlyisil,$withoutdigital);

&GetOptions(
    "inputfile=s"             => \$inputfile,
    "only-isil=s"             => \$onlyisil,
    "without-digital"         => \$withoutdigital,
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

my $persons_done_ref         = {};
my $corporatebodies_done_ref = {};
my $classifications_done_ref = {};
my $subjects_done_ref        = {};
my $recipients_done_ref      = {};

while (my $jsonline = <$input_io>){
    my $record_ref = decode_json($jsonline); 

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($record_ref));
    }
    
    my $title_ref = {
        'fields' => {},
    };

    $multcount_ref = {};

    $title_ref->{id} = $record_ref->{almaMmsId};
    
    # # Gesamter Exportsatz -> 9999
    # push @{$title_ref->{fields}{'9999'}}, {
    # 	mult     => 1,
    # 	subfield => 'a',
    # 	content => $record_ref,
    # };

    ### type -> 0800 HST
    my $is_book = 0;
    my $is_periodical = 0;
    
    if (defined $record_ref->{type}){
	foreach my $type (@{$record_ref->{type}}){
	    $is_book       = 1 if ($type eq "Book");
	    $is_periodical = 1 if ($type eq "Periodical");
	}
    }

    # next unless ($is_book);

    # Hbzid?
    if (defined $record_ref->{hbzId}){
	push @{$title_ref->{fields}{'1001'}}, {
	    content    => $record_ref->{hbzId},
	    mult       => 1,
	    subfield   => 'h',
	};
    }

    # Zdbid?
    if (defined $record_ref->{zdbId}){
	push @{$title_ref->{fields}{'1001'}}, {
	    content    => $record_ref->{zdbId},
	    mult       => 1,
	    subfield   => 'z',
	};
    }
    
    # Personen und Koerperschaften
    if (defined $record_ref->{contribution}){
	my $first_person        = 1;
	my $first_corporatebody = 1;
	
	foreach my $contribution_ref (@{$record_ref->{contribution}}){
	    my $gnd_id         = $contribution_ref->{agent}{gndIdentifier};
	    my $name           = $contribution_ref->{agent}{label};
	    my $role           = $contribution_ref->{role}{label};

	    my $contributor_id = $gnd_id;
	    
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
		elsif ($agent_type eq "CorporateBody"){
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

		    if ($gnd_id){
			push @{$normrecord_ref->{fields}{'0010'}}, {
			    mult     => 1,
			    subfield => '',
			    content  => $gnd_id,
			};
		    }
		    
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
	    
		my $new_category = ($first_person)?"0100":"0700";

		if ($role eq "Autor/in"){
		    $supplement = "";
		}

		push @{$title_ref->{fields}{$new_category}}, {
		    content    => $name,
		    mult       => $mult,
		    subfield   => 'a',
		    id         => $contributor_id,
		};

		push @{$title_ref->{fields}{$new_category}}, {
		    content    => $supplement,
		    mult       => $mult,
		    subfield   => 'e',
		    id         => $contributor_id,
		} if ($supplement);
		
		if ($gnd_id){
		    push @{$title_ref->{fields}{$new_category}}, {
			content    => '(DE-588)'.$gnd_id,
			mult       => $mult,
			subfield   => '0',
		    };
		    
		    push @{$title_ref->{fields}{$new_category}}, {
			content    => $gnd_id,
			mult       => $mult,
			subfield   => '6',
		    };
		}
		
		if ($first_person){
		    $first_person = 0;
		    $mult = 1;
		}
		else {		
		    $mult++;
		}
	    }
	    elsif ($type eq "corporatebody"){
		my $mult = 1;
		
		if (! defined $corporatebodies_done_ref->{$contributor_id}){
		    
		    my $normrecord_ref = {
			'fields' => {},
		    };
		    $normrecord_ref->{id} = $contributor_id;

		    if ($gnd_id){
			push @{$normrecord_ref->{fields}{'0010'}}, {
			    mult     => 1,
			    subfield => '',
			    content  => $gnd_id,
			};
		    }
		    
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

		    print CORPORATEBODY encode_json $normrecord_ref, "\n";
		    
		    $corporatebodies_done_ref->{$contributor_id} = 1;
		}
	    
		my $new_category = ($first_corporatebody)?"0110":"0710";
		
		push @{$title_ref->{fields}{$new_category}}, {
		    content    => $name,
		    mult       => $mult,
		    subfield   => 'a',
		    id         => $contributor_id,
		};

		if ($gnd_id){
		    push @{$title_ref->{fields}{$new_category}}, {
			mult     => $mult,
			subfield => '6',
			content  => $gnd_id,
		    };
		    push @{$title_ref->{fields}{$new_category}}, {
			mult     => $mult,
			subfield => '0',
			content  => '(DE-588)'.$gnd_id,
		    };
		}
		
		push @{$title_ref->{fields}{$new_category}}, {
		    content    => $supplement,
		    mult       => $mult,
		    subfield   => 'e',
		    id         => $contributor_id,
		};

		if ($gnd_id){
		    push @{$title_ref->{fields}{$new_category}}, {
			content    => '(DE-588)'.$gnd_id,
			mult       => $mult,
			subfield   => '0',
		    };
		    
		    push @{$title_ref->{fields}{$new_category}}, {
			content    => $gnd_id,
			mult       => $mult,
			subfield   => '6',
		    };
		}

		if ($first_corporatebody){
		    $first_corporatebody = 0;
		    $mult = 1;
		}
		else {		
		    $mult++;
		}
	    }	
	}
    }

    if (defined $record_ref->{subject}){
	my $subject_mult        = 1;
	my $classification_mult = 1;

    	foreach my $item_ref (@{$record_ref->{subject}}){
	    # Notationen
	    if (defined $item_ref->{notation}){
		my $classification_id;
		my $gnd_id;
		
		if (defined $item_ref->{source} && defined $item_ref->{source}{id} && $item_ref->{source}{id} =~m{https://d-nb.info/gnd/(.+)$}){
		    $gnd_id = $1;
		}

		$classification_id = $gnd_id;

		unless ($classification_id){
		    $classification_id = OpenBib::Conv::Common::Util::normalize_id($item_ref->{notation});
		}
		
		if ($classification_id){
		    if (!defined $classifications_done_ref->{$classification_id}){
			
			my $normrecord_ref = {
			    'fields' => {},
			};
			
			$normrecord_ref->{id} = $classification_id;
			push @{$normrecord_ref->{fields}{'0800'}}, {
			    mult     => 1,
			    subfield => '',
			    content  => $item_ref->{notation},
			};
			
			if (defined $item_ref->{label}){
			    push @{$normrecord_ref->{fields}{'0840'}}, {
				mult     => 1,
				subfield => '',
				content  => $item_ref->{label},
			    };
			}

			print CLASSIFICATION encode_json $normrecord_ref, "\n";
		    
			$classifications_done_ref->{$classification_id} = 1;	
		    }
		    
		    
		    my $new_category = "0983";
		
		    push @{$title_ref->{fields}{$new_category}}, {
			content    => $item_ref->{notation},
			mult       => $classification_mult,
			subfield   => 'b',
			id         => $classification_id,
			supplement => '',
		    };
		
		    $classification_mult++;
		}

	    }
	    # Schlagwortkette
	    elsif (defined $item_ref->{componentList}){
		foreach my $subject_ref (@{$item_ref->{componentList}}){
		    my $subject_id;
		    
		    my $gnd_id = $subject_ref->{gndIdentifier};

		    $subject_id = $gnd_id;
		    
		    unless ($subject_id){
			$subject_id = OpenBib::Conv::Common::Util::normalize_id($subject_ref->{label});
		    }
		    
		    if ($subject_id){
			if (!defined $subjects_done_ref->{$subject_id}){
			    
			    my $normrecord_ref = {
				'fields' => {},
			    };
			    
			    $normrecord_ref->{id} = $subject_id;
			    
			    if ($gnd_id){
				push @{$normrecord_ref->{fields}{'0010'}}, {
				    mult     => 1,
				    subfield => '',
				    content  => $gnd_id,
				};
			    }
			    
			    push @{$normrecord_ref->{fields}{'0800'}}, {
				mult     => 1,
				subfield => '',
				content  => $subject_ref->{label},
			    };

			    if (defined $subject_ref->{altLabel}){
				my $alt_mult = 1;
				foreach my $altlabel (@{$subject_ref->{altLabel}}){
				    push @{$normrecord_ref->{fields}{'0820'}}, {
					mult     => $alt_mult++,
					subfield => '',
					content  => $altlabel,
				    };
				}
			    }
			    
			    print SUBJECT encode_json $normrecord_ref, "\n";
			    
			    $subjects_done_ref->{$subject_id} = 1;	
			    
			}
			
			my $new_category = "0600";
			
			push @{$title_ref->{fields}{$new_category}}, {
			    content    => $subject_ref->{label},
			    mult       => $subject_mult,
			    subfield   => 'a',
			    id         => $subject_id,
			    supplement => '',
			};
			
			if ($gnd_id){
			    push @{$title_ref->{fields}{$new_category}}, {
				mult     => $subject_mult,
				subfield => '6',
				content  => $gnd_id,
			    };
			    push @{$title_ref->{fields}{$new_category}}, {
				mult     => $subject_mult,
				subfield => '0',
				content  => '(DE-588)'.$gnd_id,
			    };
			}
			
			$subject_mult++;
		    }
		}
	    }
	    # Einzelnes Schlagwort
	    elsif (defined $item_ref->{label}){
		my $subject_id;
		
		my $gnd_id = $item_ref->{gndIdentifier};
		
		$subject_id = $gnd_id;
		
		unless ($subject_id){
		    $subject_id = OpenBib::Conv::Common::Util::normalize_id($item_ref->{label});
		}
		
		if ($subject_id){
		    if (!defined $subjects_done_ref->{$subject_id}){
			
			my $normrecord_ref = {
			    'fields' => {},
			};

			if ($gnd_id){
			    push @{$normrecord_ref->{fields}{'0010'}}, {
				mult     => 1,
				subfield => '',
				content  => $gnd_id,
			    };
			}
			
			$normrecord_ref->{id} = $subject_id;
			push @{$normrecord_ref->{fields}{'0800'}}, {
			    mult     => 1,
			    subfield => '',
			    content  => $item_ref->{label},
			};
			
			if (defined $item_ref->{altLabel}){
			    my $alt_mult = 1;
			    foreach my $altlabel (@{$item_ref->{altLabel}}){
				push @{$normrecord_ref->{fields}{'0820'}}, {
				    mult     => $alt_mult++,
				    subfield => '',
				    content  => $altlabel,
				};
			    }
			}
			
			print SUBJECT encode_json $normrecord_ref, "\n";
			
			$subjects_done_ref->{$subject_id} = 1;	
			
		    }
		    
		    my $new_category = "0600";
		    
		    push @{$title_ref->{fields}{$new_category}}, {
			content    => $item_ref->{label},
			mult       => $subject_mult,
			subfield   => 'a',
			id         => $subject_id,
			supplement => '',
		    };

		    if ($gnd_id){
			push @{$title_ref->{fields}{$new_category}}, {
			    mult     => $subject_mult,
			    subfield => '6',
			    content  => $gnd_id,
			};
			push @{$title_ref->{fields}{$new_category}}, {
			    mult     => $subject_mult,
			    subfield => '0',
			    content  => '(DE-588)'.$gnd_id,
			};
		    }
		    
		    $subject_mult++;
		}
	    }	    
    	}
    }
    
    ### title -> 0331/245$a HST
    if (defined $record_ref->{title}){
	push @{$title_ref->{fields}{'0245'}}, {
	    mult     => 1,
	    subfield => 'a',
	    content => $record_ref->{title},
	}
    }

    ### otherTitleInformation -> 0335/245$b Zusatz zum HST
    if ($record_ref->{otherTitleInformation}){
	push @{$title_ref->{fields}{'0245'}}, {
	    mult     => 1,
	    subfield => 'b',
	    content => join(" ; ",@{$record_ref->{otherTitleInformation}}),
	};
    }
    
    ### extent -> 0433/300$a Kollation    
    if (defined $record_ref->{extent}){
	push @{$title_ref->{fields}{'0300'}}, {
	    mult     => 1,
	    subfield => 'a',
	    content => $record_ref->{extent},
	};

	next if ($withoutdigital && $record_ref->{extent} =~m/online resource/);
    }

    # language -> 0015/040$b Sprache
    if (defined $record_ref->{language}){
	my $lang_mult = 1;
	foreach my $lang_ref (@{$record_ref->{language}}){
	    if ($lang_ref->{id} =~m{iso639-2/(.+)$}){
		push @{$title_ref->{fields}{'0040'}}, {
		    mult     => $lang_mult++,
		    subfield => 'b',
		    content => $1,
		};
	    }
	}
    }
	    
    # isbn -> 0540/020$9 ISBN
    if (defined $record_ref->{isbn}){
	my $isbn_mult = 1;
	foreach my $isbn (@{$record_ref->{isbn}}){
	    push @{$title_ref->{fields}{'0020'}}, {
		mult     => $isbn_mult++,
		subfield => '9',
		content => $isbn,
	    };
	}
    }

    # issn -> 0543/022$9 ISSN
    if (defined $record_ref->{issn}){
	my $issn_mult = 1;
	foreach my $issn (@{$record_ref->{issn}}){
	    push @{$title_ref->{fields}{'0022'}}, {
		mult     => $issn_mult++,
		subfield => '9',
		content => $issn,
	    };
	}
    }

    # Reihe/Serie/Gesamttitel isPartOf
    if (defined $record_ref->{isPartOf}){
	my $super_mult = 1;
	foreach my $part_ref (@{$record_ref->{isPartOf}}){
	    if (defined $part_ref->{hasSuperordinate}){
		foreach my $super_ref (@{$part_ref->{hasSuperordinate}}){
		    push @{$title_ref->{fields}{'0490'}}, {
			mult     => $super_mult,
			subfield => 'a',
			content => $super_ref->{label},
		    };

		    if (defined $super_ref->{id}){
			my $super_titleid;
			($super_titleid) = $super_ref->{id} =~m{http://lobid.org/resources/(.+?)#\!$};
			
			if ($super_titleid){
			    push @{$title_ref->{fields}{'0490'}}, {
				mult     => $super_mult,
				subfield => '6', # linkage
				content => $super_titleid,
			    };
			}
		    }
		    
		    last; # Nur erste Ueberordnung wg. Zuordnungsproblematik zur Volume-Angabe
		}
	    }
	    if (defined $part_ref->{numbering}){
		    push @{$title_ref->{fields}{'0490'}}, {
			mult     => $super_mult,
			subfield => 'v',
			content => $part_ref->{numbering},
		    };
	    }
	    $super_mult++;	    
	}
    }
    
    # hasVersion -> 0662/856$u URL
    if (defined $record_ref->{hasVersion}){
	my $url_mult = 1;
	foreach my $url_ref (@{$record_ref->{has_version}}){
	    push @{$title_ref->{fields}{'0856'}}, { # URL
		mult     => $url_mult,
		subfield => 'u',
		content => $url_ref->{id},
	    };
	    push @{$title_ref->{fields}{'0856'}}, { # URL Description
		mult     => $url_mult,
		subfield => '3',
		content => $url_ref->{id},
	    };
	    $url_mult++;
	}
    }

    # tableOfContents -> 4110 URL
    if (defined $record_ref->{tableOfContents}){
	foreach my $toc_ref (@{$record_ref->{tableOfContents}}){
	    my $toc_mult = 1;
	    push @{$title_ref->{fields}{'4110'}}, { # URL
		mult     => $toc_mult,
		subfield => '',
		content => $toc_ref->{id},
	    };
	    $toc_mult++;
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
    
    # responsibilityStatement -> 0359/245$c Vorl. Verfasser/Koerperschaft
    if (defined $record_ref->{responsibilityStatement}){
	push @{$title_ref->{fields}{'0245'}}, {
	    mult     => 1,
	    subfield => 'c',
	    content => join(" ; ",@{$record_ref->{responsibilityStatement}}),
	};
    }
    
    if (defined $record_ref->{publication}){
	foreach my $pub_ref (@{$record_ref->{publication}}){

	    # location -> 0410/260$a Verlagsort
	    if (defined $pub_ref->{location}){
		push @{$title_ref->{fields}{'0260'}}, {
		    mult     => 1,
		    subfield => 'a',
		    content => join(" ; ",@{$pub_ref->{location}}),
		};
	    }

	    # publishedBy -> 0412/260$b Verlag
	    if (defined $pub_ref->{publishedBy} && ref $pub_ref->{publishedBy} eq "ARRAY"){
		my $verlag_mult = 1;
		foreach my $verlag (@{$pub_ref->{publishedBy}}){
		    push @{$title_ref->{fields}{'0260'}}, {
			mult     => $verlag_mult++,
			subfield => 'b',
			content => join(" ; ",@{$pub_ref->{publishedBy}}),
		    };
		    last; # Only first publisher
		}
	    }
	    elsif (defined $pub_ref->{publishedBy}){
		push @{$title_ref->{fields}{'0260'}}, {
		    mult     => 1,
		    subfield => 'b',
		    content => $pub_ref->{publishedBy},
		};
	    }

	    # startDate -> 0425/260$c Erscheinungsjahr
	    if (defined $pub_ref->{startDate}){
		push @{$title_ref->{fields}{'0260'}}, {
		    mult     => 1,
		    subfield => 'c',
		    content => $pub_ref->{startDate},
		};
	    }

	    # publicationHistory -> 0405/362$a Erscheinungsverlauf
	    if (defined $pub_ref->{publicationHistory}){
		push @{$title_ref->{fields}{'0362'}}, {
		    mult     => 1,
		    subfield => 'a',
		    content => $pub_ref->{publicationHistory},
		};
	    }
	    
	}
    }

    ### edition -> 0403/250$a Auflage
    if (defined $record_ref->{edition}){
	push @{$title_ref->{fields}{'0250'}}, {
	    mult     => 1,
	    subfield => 'a',
	    content => $record_ref->{edition}[0],
	}
    }

    # Exemplare

    if (defined $record_ref->{hasItem}){
	foreach my $holding_ref (@{$record_ref->{hasItem}}){

	    next if ($withoutdigital && defined $holding_ref->{type} && grep(/DigitalDocument/,@{$holding_ref->{type}}));
	    
	    my $holding_id;
	    
	    if (defined $holding_ref->{id}){
		my $this_holdingid;
		($this_holdingid) = $holding_ref->{id} =~m{http://lobid.org/items/\d+:[^:]+?:(\d+?)#\!$};
		if ($this_holdingid){
		    $holding_id=$this_holdingid;
		}		
	    }

	    if (!defined $holding_id){
		$logger->error("No holding id in title ".$title_ref->{id}." for item ".YAML::Dump($holding_ref));
		next;
	    }
	    
	    next unless (defined $holding_id);
	    
	    my $item_ref = {
		'fields' => {},
	    };
	    
	    $item_ref->{id} = $holding_id;

	    my $call_number   = $holding_ref->{callNumber};
	    my $library_code  = $holding_ref->{currentLibrary};
	    my $location_code = $holding_ref->{currentLocation};
	    my $held_by_ref   = $holding_ref->{heldBy};
	    my $isil          = "";
	    
	    if (defined $held_by_ref && defined $held_by_ref->{isil}){
		$isil = $held_by_ref->{isil};
	    }

	    if ($isil && $onlyisil && $isil ne $onlyisil){
		next;
	    }
	    
	    if ($call_number || $isil){
		push @{$item_ref->{fields}{'0004'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $title_ref->{id},
		};
		
		push @{$item_ref->{fields}{'0014'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $call_number,
		} if ($call_number);

		push @{$item_ref->{fields}{'0016'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $library_code,
		} if (defined $library_code);
		
		push @{$item_ref->{fields}{'3330'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $isil,
		} if ($isil);

		push @{$item_ref->{fields}{'0024'}}, {
		    mult     => 1,
		    subfield => '',
		    content  => $location_code,
		} if (defined $location_code);
		
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
