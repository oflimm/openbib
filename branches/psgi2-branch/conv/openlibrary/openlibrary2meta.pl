#!/usr/bin/perl

#####################################################################
#
#  openlibrary2meta.pl
#
#  Konverierung der OpenLibrary JSON-Feeds in das Meta-Format
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
use DB_File;
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML::Syck;
use JSON::XS;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

my $config = OpenBib::Config->instance;

my ($inputfile_authors,$inputfile_titles,$inputfile_works,$logfile,$loglevel);

&GetOptions(
            "inputfile-authors=s"         => \$inputfile_authors,
            "inputfile-titles=s"          => \$inputfile_titles,
            "inputfile-works=s"           => \$inputfile_works,
            "logfile=s"                   => \$logfile,
            "loglevel=s"                  => \$loglevel,
);

if (!$inputfile_authors && !$inputfile_titles && !$inputfile_works){
    print << "HELP";
openlibrary2meta.pl - Aufrufsyntax

    openlibrary2meta.pl --inputfile-authors=xxx --inputfile-titles=yyy --inputfile-works=zzz
HELP
exit;
}

$logfile=($logfile)?$logfile:"/var/log/openbib/ol2meta.log";
$loglevel=($loglevel)?$loglevel:"INFO";

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

open (TIT,     ">:raw","meta.title");
open (AUT,     ">:raw","meta.person");
open (KOR,     ">:raw","meta.corporatebody");
open (NOTATION,">:raw","meta.classification");
open (SWT,     ">:raw","meta.subject");

my %have_author = ();
my %have_work   = ();

$logger->info("### Processing Titles: 1st pass - getting authors and works");
open(OL,"zcat $inputfile_titles |");
binmode(OL,":utf8");

open(OLOUT,">:utf8",$inputfile_titles.".filtered");

my $count = 1;
while (<OL>){
    my ($ol_type,$ol_id,$ol_revision,$ol_date,$ol_data)=split("\t",$_);

    if ($ol_data=~m/Protected DAISY/i){
        next;
    }
    
    my $recordset=undef;
    
    eval {
        $recordset = decode_json $ol_data;
    };

    # Einschraenkung auf Titelaufnahmen mit Digitalisaten
    if (!exists $recordset->{ocaid}){
        next;
    }

    print OLOUT;
    
    # Autoren abarbeiten Anfang
    if (exists $recordset->{authors}){
      foreach my $author_ref (@{$recordset->{authors}}){
        my $key     = $author_ref->{key};
        $key =~s{/authors/}{};
        $have_author{$key}=1;
      }
    }

    # Werke abarbeiten Anfang
    if (exists $recordset->{works}){
        foreach my $works_ref (@{$recordset->{works}}){
            my $key     = $works_ref->{key};
            $key =~s{/works/}{};

            $have_work{$key}=1;
        }
    }

    if ($count % 10000 == 0){
        $logger->info("$count done");
    }

    $count++;
}

close(OL);
close(OLOUT);

$logger->info("#### Processing Authors");

open(OL,"zcat $inputfile_authors |");
binmode(OL,":utf8");

$count = 1;

my %author = ();
while (<OL>){
    my ($ol_type,$ol_id,$ol_revision,$ol_date,$ol_data)=split("\t",$_);

    my $recordset=undef;
    
    eval {
        $recordset = decode_json $ol_data;
    };
    
    my $key = $recordset->{key};
    $key=~s{^/authors/}{};

    if ( $key && defined $have_author{$key} && $have_author{$key} == 1){
        my $name = $recordset->{name};
        $name = $recordset->{personal_name} if (!$name);

        if ($name){
            $name = konv($name);
            
            my $item_ref = {
                'fields' => {},
            };
            $item_ref->{id} = $key;
            push @{$item_ref->{fields}{'0800'}}, {
                mult     => 1,
                subfield => '',
                content  => $name,
            };

            if (exists $recordset->{alternate_names}){
                my $mult = 1;
                foreach my $alt_name (@{$recordset->{alternate_names}}){
                    next unless ($alt_name);
                    push @{$item_ref->{fields}{'0830'}}, {
                        mult     => $mult,
                        subfield => '',
                        content  => $alt_name,
                    };
                    $mult++;
                }
            }

            if ($recordset->{bio}) { # Kurzbeschreibung
                my $bio = "";
                if (ref $recordset->{bio} eq "HASH"){
                    $bio = $recordset->{bio}->{value};
                }
                else {
                    $bio = $recordset->{bio};
                }

                $bio =~s{\n}{<br/>}g;
                $bio =~s{}{}g;
                
                if ($bio){
                    push @{$item_ref->{fields}{'0302'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $bio,
                    };
                }
            }

            push @{$item_ref->{fields}{'0304'}}, {
                mult     => 1,
                subfield => '',
                content  => $recordset->{birth_date},
            } if ($recordset->{birth_date});

            
            push @{$item_ref->{fields}{'0306'}}, {
                mult     => 1,
                subfield => '',
                content  => $recordset->{death_date},
            } if ($recordset->{death_date});

            if (exists $recordset->{photos}){
                my $mult = 1;
                foreach my $photo_id (@{$recordset->{photos}}){
                    next unless ($photo_id > 0);
                    push @{$item_ref->{fields}{'0308'}}, {
                        mult     => $mult,
                        subfield => '',
                        content  => $photo_id,
                    };
                    $mult++;
                }
            }

            push @{$item_ref->{fields}{'0309'}}, {
                mult     => 1,
                subfield => '',
                content  => $recordset->{wikipedia},
            } if ($recordset->{wikipedia});

            push @{$item_ref->{fields}{'0313'}}, {
                mult     => 1,
                subfield => '',
                content  => $recordset->{website},
            } if ($recordset->{website});


            push @{$item_ref->{fields}{'0314'}}, {
                mult     => 1,
                subfield => '',
                content  => $recordset->{location},
            } if ($recordset->{location});

            print AUT encode_json $item_ref, "\n";

            # ID merken fuer andere Personenfelder, die nicht mit der
            # Authors-ID verknuepft werden, sondern Verbatim vorliegen
            OpenBib::Conv::Common::Util::set_person_id($key,$name);
        }
        else {
            $have_author{$key} = 0;
        }
    }

    if ($count % 10000 == 0){
        $logger->info("$count done");
    }
    
    $count++;
}

close(OL);

$logger->info("#### Processing Works");

open(OL,"zcat $inputfile_works |");
binmode(OL,":utf8");

$count = 1;

my $work_subjects_ref = {};
my $work_blacklist_ref = {};

while (<OL>){
    my ($ol_type,$ol_id,$ol_revision,$ol_date,$ol_data)=split("\t",$_);
    my $recordset=undef;
    
    eval {
        $recordset = decode_json $ol_data;
    };
    
    my $key = $recordset->{key};
    $key=~s{^/works/}{};

    if ( $key && defined $have_work{$key} && $have_work{$key} == 1){
        if (exists $recordset->{subjects}){
            push @{$work_subjects_ref->{$key}}, @{$recordset->{subjects}}
        }

        foreach my $subject (@{$recordset->{subjects}}){
            if ($subject =~/Protected DAISY/i){
                $work_blacklist_ref->{$key}=1;
            }
        }
    }
    
    if ($count % 10000 == 0){
        $logger->info("$count done");
    }
    
    $count++;
}

close(OL);

$logger->info("#### Processing Titles");

open(OL,"<:utf8",$inputfile_titles.".filtered");

my $have_titleid_ref = {};

$count = 1;

while (<OL>){
    my ($ol_type,$ol_id,$ol_revision,$ol_date,$ol_data)=split("\t",$_);

    my $recordset=undef;

    eval {
        $recordset = decode_json $ol_data;
    };

    my $key = $recordset->{key} ;
    $key =~s{^/books/}{};

    my $title_ref = {
        'fields' => {},
    };
    
    if ($logger->is_debug){
        $logger->debug(YAML::Dump($recordset));
    }
    
    # Einschraenkung auf Titelaufnahmen mit Digitalisaten
    if (!exists $recordset->{ocaid}){
        next;
    }

    my @works = ();
    my $is_blacklisted = 0;
    if (exists $recordset->{works}){
        foreach my $work_ref (@{$recordset->{works}}){
            my $work = $work_ref->{key};
            $work=~s{^/works/}{};
            
            push @works, $work;
            if (defined $work_blacklist_ref->{$work} && $work_blacklist_ref->{$work} == 1){
                $is_blacklisted = 1;
            }
        }
    }

    if ($is_blacklisted){
        $logger->debug("Blacklisted: Work ".join(';',@works)." of Title $key");
        next;
    }
    
    if (!$key){
        if ($logger->is_debug){
            $logger->error("Keine ID ".YAML::Dump($recordset));
        }
        next;
    }

    if (!$key || $have_titleid_ref->{$key}){
        $logger->error("Doppelte ID: ".$key);
        next;
    }

    $title_ref->{id} = $key;

    $have_titleid_ref->{$key} = 1;

    if (exists $recordset->{languages}){
        my $mult=1;
        foreach my $item_ref (@{$recordset->{languages}}){
            my $lang = $item_ref->{key};
            $lang =~s{^/languages/}{};

            push @{$title_ref->{fields}{'0015'}}, {
                mult     => $mult,
                subfield => '',
                content  => $lang,
            };
            $mult++;
        }
    }
    
    if (exists $recordset->{title}){
        my $title = konv($recordset->{title});
        if (exists $recordset->{title_prefix}){
            $title=konv($recordset->{title_prefix})." $title";
        }

        push @{$title_ref->{fields}{'0331'}}, {
            mult     => 1,
            subfield => '',
            content  => $title,
        };
    }

    if (exists $recordset->{subtitle}){
        push @{$title_ref->{fields}{'0335'}}, {
            mult     => 1,
            subfield => '',
            content  => konv($recordset->{subtitle}),
        };
    }

    if (exists $recordset->{other_titles}){
        my $mult=1;
        foreach my $item (@{$recordset->{other_titles}}){
            push @{$title_ref->{fields}{'0370'}}, {
                mult     => $mult,
                subfield => '',
                content  => konv($item),
            };
            $mult++;
        }
    }

    if (exists $recordset->{by_statement}){
        push @{$title_ref->{fields}{'0359'}}, {
            mult     => 1,
            subfield => '',
            content  => konv($recordset->{by_statement}),
        };
    }

    if (exists $recordset->{publishing_places}){
        my $mult=1;
        foreach my $item (@{$recordset->{publishing_places}}){
            push @{$title_ref->{fields}{'0410'}}, {
                mult     => $mult,
                subfield => '',
                content  => konv($item),
            };
            $mult++;
        }
    }

    if (exists $recordset->{series}){
        my $mult=1;
        foreach my $item (@{$recordset->{series}}){
            push @{$title_ref->{fields}{'0451'}}, {
                mult     => $mult,
                subfield => '',
                content  => konv($item),
            };
            $mult++;
        }
    }

    if (exists $recordset->{publishers}){
        my $mult=1;
        foreach my $item (@{$recordset->{publishers}}){
            push @{$title_ref->{fields}{'0412'}}, {
                mult     => $mult,
                subfield => '',
                content  => konv($item),
            };
            $mult++;
        }
    }

    if (exists $recordset->{edition_name}){
        push @{$title_ref->{fields}{'0403'}}, {
            mult     => 1,
            subfield => '',
            content  => konv($recordset->{edition_name}),
        };
    }

    if (exists $recordset->{publish_date}){
        push @{$title_ref->{fields}{'0425'}}, {
            mult     => 1,
            subfield => '',
            content  => konv($recordset->{publish_date}),
        };
    }

    if (exists $recordset->{pagination}){
        push @{$title_ref->{fields}{'0433'}}, {
            mult     => 1,
            subfield => '',
            content  => konv($recordset->{pagination}),
        };
    }

    if (exists $recordset->{ocaid}){
        push @{$title_ref->{fields}{'0662'}}, {
            mult     => 1,
            subfield => '',
            content  => 'http://archive.org/details/'.$recordset->{ocaid},
        };
        push @{$title_ref->{fields}{'2662'}}, {
            mult     => 1,
            subfield => '',
            content  => $recordset->{ocaid},
        };
    }

    push @{$title_ref->{fields}{'4410'}}, {
        mult     => 1,
        subfield => '',
        content  => 'Digital',
    };

    # Autoren abarbeiten Anfang
    if (exists $recordset->{authors}){
        my %processed = ();
        my $mult=1;
        foreach my $author_ref (@{$recordset->{authors}}){
            my $key     = $author_ref->{key};
            $key =~s{/authors/}{};

            push @{$title_ref->{fields}{'0100'}}, {
                mult       => $mult,
                subfield   => '',
                id         => $key,
                supplement => '',
            } if ($have_author{$key} == 1 && !$processed{$key});
            $mult++;

            $processed{$key} = 1;
        }
    }
    # Autoren abarbeiten Ende

    # Personen abarbeiten Anfang
    if (exists $recordset->{contributions}){
        my %processed = ();

        my $mult=1;
        foreach my $content (@{$recordset->{contributions}}){
            
            if ($content && !$processed{$content}){
                $processed{$content} = 1 ;

                $content = konv($content);
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

                    print AUT encode_json $item_ref, "\n";
                }
                
                push @{$title_ref->{fields}{'0101'}}, {
                    mult       => $mult,
                    subfield   => '',
                    id         => $person_id,
                    supplement => '',
                };
            }
        }
    }
    # Personen abarbeiten Ende

    my $classification_mult=1;
    
    # Notationen abarbeiten Anfang
    if (exists $recordset->{dewey_decimal_class}){
        my %processed = ();
        foreach my $content (@{$recordset->{dewey_decimal_class}}){
            if ($content && !$processed{$content}){
                $processed{$content} = 1;

                $content = konv($content);
                my ($classification_id,$new) = OpenBib::Conv::Common::Util::get_classification_id($content);
                
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

                    print NOTATION encode_json $item_ref, "\n";
                }

                push @{$title_ref->{fields}{'0700'}}, {
                    mult       => $classification_mult,
                    subfield   => '',
                    id         => $classification_id,
                    supplement => '',
                };
                $classification_mult++;
            }
        }
    }
    if (exists $recordset->{lc_classifications}){
        my %processed = ();
        foreach my $content (@{$recordset->{lc_classifications}}){
            if ($content && !$processed{$content}){
                $processed{$content} = 1;

                $content = konv($content);
                my ($classification_id,$new) = OpenBib::Conv::Common::Util::get_classification_id($content);
                
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

                    print NOTATION encode_json $item_ref, "\n";
                }
                
                push @{$title_ref->{fields}{'0700'}}, {
                    mult       => $classification_mult,
                    subfield   => '',
                    id         => $classification_id,
                    supplement => '',
                };
                $classification_mult++;
            }
        }
    }
    # Notationen abarbeiten Ende

    # Schlagworte abarbeiten Anfang    
    {
        my %processed = ();

        my $subject_mult=1;
        # Schlagworte aus den Titeldaten
        if (exists $recordset->{subjects}){
            
            foreach my $content (@{$recordset->{subjects}}){
                if ($content && !$processed{$content}){
                    $processed{$content} = 1;

                    $content = konv($content);
                    # Punkt am Ende entfernen
                    $content=~s/\.\s*$//;
                    
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
                        
                        print SWT encode_json $item_ref, "\n";
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

        # Schlagworte aus den Werk-Daten
        foreach my $work (@works){
            
            foreach my $content (@{$work_subjects_ref->{$work}}){                
                if ($content && !$processed{$content}){

                    $processed{$content} = 1;

                    $logger->debug("Adding Work Subject $content for Work $work");
                    
                    $content = konv($content);
                    # Punkt am Ende entfernen
                    $content=~s/\.\s*$//;
                    
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
                        
                        print SWT encode_json $item_ref, "\n";
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

        
    }
    # Schlagworte abarbeiten Ende
    print TIT encode_json $title_ref, "\n";
    
    if ($count % 10000 == 0){
        $logger->info("$count done");
    }

    $count++;
}

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);


sub konv {
    my ($content)=@_;

    $content=~s/\&amp;/&/g; # zuerst etwaige &amp; auf & normieren 
    $content=~s/\&/&amp;/g; # dann erst kann umgewandet werden (sonst &amp;amp;) 
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    return $content;
}
