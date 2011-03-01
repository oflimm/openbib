#!/usr/bin/perl

#####################################################################
#
#  openlibrary2meta.pl
#
#  Konverierung der OpenLibrary JSON-Feeds in das Meta-Format
#
#  Dieses File ist (C) 1999-2009 Oliver Flimm <flimm@openbib.org>
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

#use strict;
#use warnings;
use utf8;

use Encode 'decode';
use Getopt::Long;
use DB_File;
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML::Syck;
use JSON::XS;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

my $config = OpenBib::Config->instance;

my ($inputfile_authors,$inputfile_titles);

&GetOptions(
	    "inputfile-authors=s"          => \$inputfile_authors,
            "inputfile-titles=s"           => \$inputfile_titles,
	    );

if (!$inputfile_authors && !$inputfile_titles){
    print << "HELP";
openlibrary2meta.pl - Aufrufsyntax

    openlibrary2meta.pl --inputfile-authors=xxx --inputfile-titles=yyy
HELP
exit;
}

open (TIT,     ">:utf8","meta.title");
open (AUT,     ">:utf8","meta.person");
open (KOR,     ">:utf8","meta.corporatebody");
open (NOTATION,">:utf8","meta.classification");
open (SWT,     ">:utf8","meta.subject");

my %have_author = ();

print "### Processing Titles: 1st pass - getting authors\n";
open(OL,"<:utf8",$inputfile_titles);

my $count = 1;
while (<OL>){
    my $recordset=undef;    
    
    eval {
        $recordset = decode_json $_;
    };

    # Einschraenkung auf Titelaufnahmen mit Digitalisaten
    if (!exists $recordset->{ocaid}){
        next;
    }

    # Autoren abarbeiten Anfang
    if (exists $recordset->{authors}){
      foreach my $author_ref (@{$recordset->{authors}}){
	my $key     = $author_ref->{key};
        $key =~s{/authors/}{};
        $have_author{$key}=1;
      }
    }

    if ($count % 10000 == 0){
        print "$count done\n";
    }

    $count++;
}

close(OL);

print "#### Processing Authors\n";

open(OL,"<:utf8",$inputfile_authors);

$count = 1;

my %author = ();
while (<OL>){
    my $recordset=undef;
    
    eval {
        $recordset = decode_json $_;
    };
    
    my $key = $recordset->{key};
    $key=~s{^/authors/}{};

    if ( $key && $have_author{$key} == 1){
        my $name = $recordset->{name};
        $name = $recordset->{personal_name} if (!$name);

        if ($name){
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
        print "$count done\n";
    }
    
    $count++;
}

close(OL);

print "#### Processing Titles\n";
open(OL,"<:utf8",$inputfile_titles);

my $have_titid_ref = {};

$count = 1;

while (<OL>){
    my $recordset=undef;    
    eval {
        $recordset = decode_json $_;
    };

    my $key = $recordset->{key} ;
    $key =~s{^/books/}{};

#    print YAML::Dump($recordset);

    # Einschraenkung auf Titelaufnahmen mit Digitalisaten
    if (!exists $recordset->{ocaid}){
        next;
    }
    
    if (!$key){
        print STDERR  "Keine ID\n".YAML::Dump($recordset)."\n";
        next;
    }

    if (!$key || $have_titid_ref->{$key}){
        print STDERR  "Doppelte ID: ".$key."\n";
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
        my $title = $recordset->{title};
        if (exists $recordset->{title_prefix}){
            $title=$recordset->{title_prefix}." $title";
        }
        
        print TIT "0331:$title\n";
    }

    if (exists $recordset->{subtitle}){
        print TIT "0335:$recordset->{subtitle}\n";
    }

    if (exists $recordset->{by_statement}){
        print TIT "0359:$recordset->{by_statement}\n";
    }

    if (exists $recordset->{publishing_places}){
        foreach my $item (@{$recordset->{publishing_places}}){
            print TIT "0410:$item\n";
        }
    }

    if (exists $recordset->{publishers}){
        foreach my $item (@{$recordset->{publishers}}){
            print TIT "0412:$item\n";
        }
    }

    if (exists $recordset->{edition_name}){
        print TIT "0403:$recordset->{edition_name}\n";
    }

    if (exists $recordset->{publish_date}){
        print TIT "0425:$recordset->{publish_date}\n";
    }

    if (exists $recordset->{pagination}){
        print TIT "0433:$recordset->{pagination}\n";
    }

    if (exists $recordset->{ocaid}){
        print TIT "0662:$recordset->{ocaid}\n";
    }

    print TIT "0800:ebook\n";

    # Autoren abarbeiten Anfang
    if (exists $recordset->{authors}){
      foreach my $author_ref (@{$recordset->{authors}}){
	my $key     = $author_ref->{key};
        $key =~s{/authors/}{};
 
        print TIT "0100:IDN: $key\n" if ($have_author{$key} == 1);
      }
    }
    # Autoren abarbeiten Ende

    # Personen abarbeiten Anfang
    if (exists $recordset->{contributions}){    
      foreach my $content (@{$recordset->{contributions}}){
	
	if ($content){
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
        foreach my $content (@{$recordset->{dewey_decimal_class}}){
            if ($content){	  
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
    if (exists $recordset->{subjects}){
      foreach my $content (@{$recordset->{subjects}}){
	if ($content){
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
    # Schlagworte abarbeiten Ende
    print TIT "9999:\n";

    if ($count % 10000 == 0){
        print "$count done\n";
    }

    $count++;
}

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);

