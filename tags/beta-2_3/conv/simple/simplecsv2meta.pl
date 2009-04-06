#!/usr/bin/perl

#####################################################################
#
#  simplecsv2meta.pl
#
#  Konverierung der einfach aufgebauter CVS-Daten in das Meta-Format
#
#  Dieses File ist (C) 1999-2008 Oliver Flimm <flimm@openbib.org>
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

our (@autdubbuf,@kordubbuf,@swtdubbuf,@notdubbuf);

@autdubbuf = ();
@kordubbuf = ();
@swtdubbuf = ();
@notdubbuf = ();

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

my $request = $dbh->prepare("select * from data") || die $dbh->errstr;
$request->execute();

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");

my $titid = 1;

while (my $result=$request->fetchrow_hashref){
    if ($convconfig->{uniqueidfield}){
        printf TIT "0000:%d\n", $result->{$convconfig->{uniqueidfield}};
    }
    else {
        printf TIT "0000:%d\n", $titid++;
    }

    foreach my $kateg (keys %{$convconfig->{title}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});

        if ($content){
            $content=~s/uhttp:/http:/;
            print TIT $convconfig->{title}{$kateg}.$content."\n";
        }
    }

    # Autoren abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{pers}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});
        
        if ($content){
            my @authors = ();
            if ($content=~/; /){
                @authors = split('; ',$content);
            }
            else {
                push @authors, $content;
            }
            
            foreach my $singleauthor (@authors){
                my $autidn=get_autidn($singleauthor);
                
                if ($autidn > 0){
                    print AUT "0000:$autidn\n";
                    print AUT "0001:$singleauthor\n";
                    print AUT "9999:\n";
                    
                }
                else {
                    $autidn=(-1)*$autidn;
                }
                
                print TIT $convconfig->{pers}{$kateg}."IDN: $autidn\n";
        }
        }
        # Autoren abarbeiten Ende
    }
    # Koerperschaften abarbeiten Anfang

    foreach my $kateg (keys %{$convconfig->{corp}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});
        
        if ($content){
            my $koridn=get_koridn($content);
            
            if ($koridn > 0){
                print KOR "0000:$koridn\n";
                print KOR "0001:$content\n";
                print KOR "9999:\n";
                
            }
            else {
                $koridn=(-1)*$koridn;
            }
            
            print TIT $convconfig->{corp}{$kateg}."IDN: $koridn\n";
        }
    }
    # Koerperschaften abarbeiten Ende


    # Notationen abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{sys}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});
        
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
            
            print TIT $convconfig->{sys}{$kateg}."IDN: $notidn\n";
        }
    }
    # Notationen abarbeiten Ende

    # Schlagworte abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{subj}}){
        my $content = decode($convconfig->{encoding},$result->{$kateg});

        if ($content){
            my @subjects = ();
            if ($content=~/;\+/){
                @subjects = split(';\s+',$content);
            }
            else {
                push @subjects, $content;
            }
            
            foreach my $singlesubject (@subjects){
                my $swtidn=get_swtidn($singlesubject);
                
                if ($swtidn > 0){	  
                    print SWT "0000:$swtidn\n";
                    print SWT "0001:$singlesubject\n";
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
    print TIT "9999:\n";
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

