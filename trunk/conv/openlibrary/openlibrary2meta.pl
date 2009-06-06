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
use JSON;

use OpenBib::Config;

our (@autdubbuf,@kordubbuf,@swtdubbuf,@notdubbuf);

@autdubbuf = ();
@kordubbuf = ();
@swtdubbuf = ();
@notdubbuf = ();

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

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");

my $json = new JSON;

my %author = ();

#tie %author,        'MLDBM', "./data_aut.db"
#        or die "Could not tie data_aut.\n";

print "### Processing Titles: 1st pass - getting authors\n";

open(OL,"<:utf8",$inputfile_titles);

my $count = 1;
while (<OL>){
    my $recordset=undef;    
    
    eval {
        $recordset = $json->jsonToObj($_);
    };

    # Autoren abarbeiten Anfang
    if (exists $recordset->{authors}){
      foreach my $author_ref (@{$recordset->{authors}}){
	my $key     = $author_ref->{key};
        $author{$key}=1;
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

while (<OL>){
    my $recordset=undef;
    
    eval {
        $recordset = $json->jsonToObj($_);
    };

    if (exists $recordset->{key} && exists $author{$recordset->{key}}){
        $author{$recordset->{key}}=$recordset;
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
        $recordset = $json->jsonToObj($_);
    };

#    print YAML::Dump($recordset);

    if (!$recordset->{id} || $have_titid_ref->{$recordset->{id}}){
        print STDERR  "Doppelte ID: ".$recordset->{id}."\n";
        next;
    }

    printf TIT "0000:%d\n", $recordset->{id};
    $have_titid_ref->{$recordset->{id}} = 1;

    if (exists $recordset->{languages}){
        foreach my $item_ref (@{$recordset->{languages}}){
            my $lang = $item_ref->{key};
            $lang =~s/^\/l\///;
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

    print TIT "0800:eBook\n";

    # Autoren abarbeiten Anfang
    if (exists $recordset->{authors}){
      foreach my $author_ref (@{$recordset->{authors}}){
	my $key     = $author_ref->{key};
        
        if (!exists $author{$key}{name}){
	  print STDERR "### Key existiert nicht\n";
	}

	my $content = $author{$key}{name};
	
	if ($content){	  
	  my $autidn=get_autidn($content);
	  
	  if ($autidn > 0){
	    print AUT "0000:$autidn\n";
	    print AUT "0001:$content\n";
	    print AUT "9999:\n";
	  }   
	  else {
	    $autidn=(-1)*$autidn;
	  }
	  
	  print TIT "0100:IDN: $autidn\n";
	}
      }
    }
    # Autoren abarbeiten Ende

    # Personen abarbeiten Anfang
    if (exists $recordset->{contributions}){    
      foreach my $content (@{$recordset->{contributions}}){
	
	if ($content){
	  my $autidn=get_autidn($content);
	  
	  if ($autidn > 0){
	    print AUT "0000:$autidn\n";
	    print AUT "0001:$content\n";
	    print AUT "9999:\n";
	    
	  }
	  else {
	    $autidn=(-1)*$autidn;
	  }
	  
	  print TIT "0101:IDN: $autidn\n";
        }
      }
    }
    # Personen abarbeiten Ende

    # Notationen abarbeiten Anfang
    if (exists $recordset->{dewey_decimal_class}){
      foreach my $content (@{$recordset->{dewey_decimal_class}}){
	if ($content){	  
	  my $notidn=get_notidn($content);
	  
	  if ($notidn > 0){
	    print NOTATION "0000:$notidn\n";
	    print NOTATION "0001:$content\n";
	    print NOTATION "9999:\n";
	    
	  }
	  else {
	    $notidn=(-1)*$notidn;
	  }
	  
	  print TIT "0700:IDN: $notidn\n";
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

	  my $swtidn=get_swtidn($content);
	  
	  if ($swtidn > 0){	  
	    print SWT "0000:$swtidn\n";
	    print SWT "0001:$content\n";
	    print SWT "9999:\n";
	  }
	  else {
	    $swtidn=(-1)*$swtidn;
	  }
	  print TIT "0710:IDN: $swtidn\n";
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

sub get_autidn {
    my ($autans)=@_;

#    print "AUT $autans\n";

    my $autdubidx=1;
    my $autdubidn=0;

#    print "AUT",YAML::Dump(\@autdubbuf),"\n";

    while ($autdubidx <= $#autdubbuf){
        if ($autans eq $autdubbuf[$autdubidx]){
            $autdubidn=(-1)*$autdubidx;      
        }
        $autdubidx++;
    }
    if (!$autdubidn){
        $autdubbuf[$autdubidx]=$autans;
        $autdubidn=$autdubidx;
    }

#    print "AUT",YAML::Dump(\@autdubbuf),"\n";
    
#    print $autdubidn,"\n";
    return $autdubidn;
}

sub get_swtidn {
    my ($swtans)=@_;

#    print "SWT $swtans\n";
    
    my $swtdubidx=1;
    my $swtdubidn=0;

#    print "SWT", YAML::Dump(\@swtdubbuf),"\n";
    
    while ($swtdubidx <= $#swtdubbuf){
        if ($swtans eq $swtdubbuf[$swtdubidx]){
            $swtdubidn=(-1)*$swtdubidx;      
        }
        $swtdubidx++;
    }
    if (!$swtdubidn){
        $swtdubbuf[$swtdubidx]=$swtans;
        $swtdubidn=$swtdubidx;
    }
#    print $swtdubidn,"\n";

#    print "SWT", YAML::Dump(\@swtdubbuf),"\n";
#    print "-----\n";
    return $swtdubidn;
}

sub get_koridn {
    my ($korans)=@_;
    
    my $kordubidx=1;
    my $kordubidn=0;
    
    while ($kordubidx <= $#kordubbuf){
        if ($korans eq $kordubbuf[$kordubidx]){
            $kordubidn=(-1)*$kordubidx;      
        }
        $kordubidx++;
    }
    if (!$kordubidn){
        $kordubbuf[$kordubidx]=$korans;
        $kordubidn=$kordubidx;
    }
    return $kordubidn;
}

sub get_notidn {
    my ($notans)=@_;
    
    my $notdubidx=1;
    my $notdubidn=0;
    
    while ($notdubidx <= $#notdubbuf){
        if ($notans eq $notdubbuf[$notdubidx]){
            $notdubidn=(-1)*$notdubidx;      
        }
        $notdubidx++;
    }
    if (!$notdubidn){
        $notdubbuf[$notdubidx]=$notans;
        $notdubidn=$notdubidx;
    }
    return $notdubidn;
}

