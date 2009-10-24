#!/usr/bin/perl

#####################################################################
#
#  simplecsv2meta.pl
#
#  Konverierung der einfach aufgebauter CVS-Daten in das Meta-Format
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

use strict;
use warnings;
use utf8;

use Encode 'decode';
use Getopt::Long;
use DBI;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;


my $config = OpenBib::Config->instance;

my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
simplecsv2meta.pl - Aufrufsyntax

    simplecsv2meta.pl --inputfile=xxx --configfile=yyy.yml
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

# Einlesen und Reorganisieren

if (defined $convconfig->{tracelevel} && $convconfig->{tracelevel} >= 0){
    DBI->trace($convconfig->{tracelevel});
}

my $dbh = DBI->connect("DBI:CSV:");
$dbh->{'csv_tables'}->{'data'} = {
    'eol'         => $convconfig->{csv}{eol},
    'sep_char'    => $convconfig->{csv}{sep_char},
    'quote_char'  => $convconfig->{csv}{quote_char},
    'escape_char' => $convconfig->{csv}{escape_char},
    'file'        => "$inputfile",
};

$dbh->{'RaiseError'} = 1;

our $mexidn=1;

my $request = $dbh->prepare("select * from data") || die $dbh->errstr;
$request->execute();

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

my $titid = 1;
my $have_titid_ref = {};
while (my $result=$request->fetchrow_hashref){
    if ($convconfig->{uniqueidfield}){
        if ($have_titid_ref->{$result->{$convconfig->{uniqueidfield}}}){
            print STDERR  "Doppelte ID: ".$result->{$convconfig->{uniqueidfield}}."\n";
	    next;
        }
        printf TIT "0000:%d\n", $result->{$convconfig->{uniqueidfield}};
        $have_titid_ref->{$result->{$convconfig->{uniqueidfield}}} = 1;
    }
    else {
        printf TIT "0000:%d\n", $titid++;
    }

    foreach my $kateg (keys %{$convconfig->{title}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});

        if ($content){
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
                print TIT $convconfig->{title}{$kateg}.$part."\n";
            }
        }
    }

    # Autoren abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{pers}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});
        
        if ($content){
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                my $autidn=OpenBib::Conv::Common::Util::get_autidn($part);
                
                if ($autidn > 0){
                    print AUT "0000:$autidn\n";
                    print AUT "0001:$part\n";
                    print AUT "9999:\n";
                    
                }
                else {
                    $autidn=(-1)*$autidn;
                }
                
                print TIT $convconfig->{pers}{$kateg}."IDN: $autidn\n";
            }
        }

    }
    # Autoren abarbeiten Ende
    
    # Koerperschaften abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{corp}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});
        
        if ($content){
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                
                my $koridn=OpenBib::Conv::Common::Util::get_koridn($part);
                
                if ($koridn > 0){
                    print KOR "0000:$koridn\n";
                    print KOR "0001:$part\n";
                    print KOR "9999:\n";
                    
                }
                else {
                    $koridn=(-1)*$koridn;
                }
                
                print TIT $convconfig->{corp}{$kateg}."IDN: $koridn\n";
            }
        }
    }
    # Koerperschaften abarbeiten Ende


    # Notationen abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{sys}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});
        
        if ($content){
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                my $notidn=OpenBib::Conv::Common::Util::get_notidn($part);
                
                if ($notidn > 0){	  
                    print NOTATION "0000:$notidn\n";
                    print NOTATION "0001:$part\n";
                    print NOTATION "9999:\n";
                }
                else {
                    $notidn=(-1)*$notidn;
                }
                print TIT $convconfig->{sys}{$kateg}."IDN: $notidn\n";
            }
        }
    }
    # Notationen abarbeiten Ende

    # Schlagworte abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{subj}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});

        if ($content){
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                my $swtidn=OpenBib::Conv::Common::Util::get_swtidn($part);
                
                if ($swtidn > 0){	  
                    print SWT "0000:$swtidn\n";
                    print SWT "0001:$part\n";
                    print SWT "9999:\n";
                }
                else {
                    $swtidn=(-1)*$swtidn;
                }
                print TIT $convconfig->{subj}{$kateg}."IDN: $swtidn\n";
            }
            
        }
    }
    # Schlagworte abarbeiten Ende

    # Exemplare abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{exempl}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});

        if ($content){
            my @parts = ();
            if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                @parts = split($convconfig->{category_split_chars}{$kateg},$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                print MEX "0000:$mexidn\n";
                print MEX "0004:$titid\n";
                print MEX $convconfig->{exempl}{$kateg}.$part."\n";
                print MEX "9999:\n";
                $mexidn++;
            }
        }
    }
    # Exemplare abarbeiten Ende

    print TIT "9999:\n";
}

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);
close(MEX);
