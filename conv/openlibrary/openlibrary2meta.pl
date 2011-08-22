#!/usr/bin/perl

#####################################################################
#
#  openlibrary2meta.pl
#
#  Konverierung der OpenLibrary JSON-Feeds in das Meta-Format
#
#  Dieses File ist (C) 1999-2011 Oliver Flimm <flimm@openbib.org>
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

open (TIT,     ">:utf8","meta.title");
open (AUT,     ">:utf8","meta.person");
open (KOR,     ">:utf8","meta.corporatebody");
open (NOTATION,">:utf8","meta.classification");
open (SWT,     ">:utf8","meta.subject");

my %have_author = ();
my %have_work   = ();

$logger->info("### Processing Titles: 1st pass - getting authors and works");
open(OL,"<:utf8",$inputfile_titles);
open(OLOUT,">:utf8",$inputfile_titles.".filtered");

my $count = 1;
while (<OL>){
    my ($ol_type,$ol_id,$ol_revision,$ol_date,$ol_data)=split("\t",$_);

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

open(OL,"<:utf8",$inputfile_authors);

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
            print AUT "0000:$key\n";
            print AUT "0001:$name\n";
            print AUT "0304:$recordset->{birth_date}\n" if ($recordset->{birth_date});
            print AUT "0306:$recordset->{death_date}\n" if ($recordset->{death_date});
            print AUT "9999:\n";

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

open(OL,"<:utf8",$inputfile_works);

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

my $have_titid_ref = {};

$count = 1;

while (<OL>){
    my ($ol_type,$ol_id,$ol_revision,$ol_date,$ol_data)=split("\t",$_);
    
    my $recordset=undef;    
    eval {
        $recordset = decode_json $ol_data;
    };

    my $key = $recordset->{key} ;
    $key =~s{^/books/}{};

    $logger->debug(YAML::Dump($recordset));

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
        $logger->error("Keine ID ".YAML::Dump($recordset));
        next;
    }

    if (!$key || $have_titid_ref->{$key}){
        $logger->error("Doppelte ID: ".$key);
        next;
    }

    printf TIT "0000:%s\n", $key;
    $have_titid_ref->{$key} = 1;

    if (exists $recordset->{languages}){
        foreach my $item_ref (@{$recordset->{languages}}){
            my $lang = $item_ref->{key};
            $lang =~s{^/languages/}{};
            print TIT "0015:$lang\n";
        }
    }
    
    if (exists $recordset->{title}){
        my $title = konv($recordset->{title});
        if (exists $recordset->{title_prefix}){
            $title=konv($recordset->{title_prefix})." $title";
        }
        
        print TIT "0331:$title\n";
    }

    if (exists $recordset->{subtitle}){
        print TIT "0335:".konv($recordset->{subtitle})."\n";
    }

    if (exists $recordset->{other_titles}){
        foreach my $item (@{$recordset->{other_titles}}){
            print TIT "0370:".konv($item)."\n";
        }
    }

    if (exists $recordset->{by_statement}){
        print TIT "0359:".konv($recordset->{by_statement})."\n";
    }

    if (exists $recordset->{publishing_places}){
        foreach my $item (@{$recordset->{publishing_places}}){
            print TIT "0410:".konv($item)."\n";
        }
    }

    if (exists $recordset->{series}){
        foreach my $item (@{$recordset->{series}}){
            print TIT "0451:".konv($item)."\n";
        }
    }

    if (exists $recordset->{publishers}){
        foreach my $item (@{$recordset->{publishers}}){
            print TIT "0412:".konv($item)."\n";
        }
    }

    if (exists $recordset->{edition_name}){
        print TIT "0403:".konv($recordset->{edition_name})."\n";
    }

    if (exists $recordset->{publish_date}){
        print TIT "0425:".konv($recordset->{publish_date})."\n";
    }

    if (exists $recordset->{pagination}){
        print TIT "0433:".konv($recordset->{pagination})."\n";
    }

    if (exists $recordset->{ocaid}){
        print TIT "0662:$recordset->{ocaid}\n";
    }

    print TIT "0800:ebook\n";

    # Autoren abarbeiten Anfang
    if (exists $recordset->{authors}){
        my %processed = ();
        foreach my $author_ref (@{$recordset->{authors}}){
            my $key     = $author_ref->{key};
            $key =~s{/authors/}{};
            
            print TIT "0100:IDN: $key\n" if ($have_author{$key} == 1 && !$processed{$key});
            $processed{$key} = 1;
        }
    }
    # Autoren abarbeiten Ende

    # Personen abarbeiten Anfang
    if (exists $recordset->{contributions}){
        my %processed = ();
        
        foreach my $content (@{$recordset->{contributions}}){
            
            if ($content && !$processed{$content}){
                $processed{$content} = 1 ;

                $content = konv($content);
                my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($content);
                
                if ($new){
                    print AUT "0000:$person_id\n";
                    print AUT "0001:$content\n";
                    print AUT "9999:\n";
                    
                }
                
                print TIT "0101:IDN: $person_id\n";
            }
        }
    }
    # Personen abarbeiten Ende

    # Notationen abarbeiten Anfang
    if (exists $recordset->{dewey_decimal_class}){
        my %processed = ();
        foreach my $content (@{$recordset->{dewey_decimal_class}}){
            if ($content && !$processed{$content}){
                $processed{$content} = 1;

                $content = konv($content);
                my ($classification_id,$new) = OpenBib::Conv::Common::Util::get_classification_id($content);
                
                if ($new){
                    print NOTATION "0000:$classification_id\n";
                    print NOTATION "0001:$content\n";
                    print NOTATION "9999:\n";
                    
                }
                
                print TIT "0700:IDN: $classification_id\n";
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
                    print NOTATION "0000:$classification_id\n";
                    print NOTATION "0001:$content\n";
                    print NOTATION "9999:\n";
                    
                }
                
                print TIT "0700:IDN: $classification_id\n";
            }
        }
    }
    # Notationen abarbeiten Ende

    # Schlagworte abarbeiten Anfang    
    {
        my %processed = ();

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
                        print SWT "0000:$subject_id\n";
                        print SWT "0001:$content\n";
                        print SWT "9999:\n";
                    }
                    
                    print TIT "0710:IDN: $subject_id\n";
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
                        print SWT "0000:$subject_id\n";
                        print SWT "0001:$content\n";
                        print SWT "9999:\n";
                    }
                    
                    print TIT "0710:IDN: $subject_id\n";
                }
            }
        }

        
    }
    # Schlagworte abarbeiten Ende
    print TIT "9999:\n";
    
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
