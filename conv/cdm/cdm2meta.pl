#!/usr/bin/perl

#####################################################################
#
#  cdm2meta.pl
#
#  Konvertierung des CDM XML-Formates in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode';
use Getopt::Long;
use XML::Twig;
use YAML::Syck;

use OpenBib::Config;

our (@autdubbuf,@kordubbuf,@swtdubbuf,@notdubbuf);

@autdubbuf = ();
@kordubbuf = ();
@swtdubbuf = ();
@notdubbuf = ();

my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
cdm2meta.pl - Aufrufsyntax

    cdm2meta.pl --inputfile=xxx --configfile=yyy.yml
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

my $twig= XML::Twig->new(
   TwigHandlers => {
     "/metadata/record" => \&parse_titset
   }
 );


$twig->parsefile($inputfile);

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);
close(MEX);

sub parse_titset {
    my($t, $titset)= @_;
    
    print TIT "0000:".$titset->first_child($convconfig->{uniqueidfield})->text()."\n";

    # Erstellungsdatum
    if(defined $titset->first_child('cdmcreated') && $titset->first_child('cdmcreated')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmcreated')->text());
        print TIT "0002:$day.$month.$year\n";
    }
    
    # Aenderungsdatum
    if(defined $titset->first_child('cdmmodified') && $titset->first_child('cdmmodified')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmmodified')->text());
        print TIT "0003:$day.$month.$year\n";
    }

    foreach my $kateg (keys %{$convconfig->{title}}){
        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
#            my $content = decode($convconfig->{encoding},$titset->first_child($kateg)->text());
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }

                foreach my $part (@parts){
                    print TIT $convconfig->{title}{$kateg}.$part."\n";
                }
            }
        }
    }
    
    # Autoren abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{pers}}){
        if (defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
            #my $content = decode($convconfig->{encoding},$titset->first_child($kateg)->text());
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
                
                foreach my $part (@parts){
                    my $autidn=get_autidn($part);
                    
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
            # Autoren abarbeiten Ende
        }
    }

    # Koerperschaften abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{corp}}){
        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
            #my $content = decode($convconfig->{encoding},$titset->first_child($kateg)->text());
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
                
                foreach my $part (@parts){
                    my $koridn=get_koridn($part);
                
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
    }
    # Koerperschaften abarbeiten Ende

    # Notationen abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{sys}}){
        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
            #my $content = decode($convconfig->{encoding},$titset->first_child($kateg)->text());
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
                
                foreach my $part (@parts){
                    my $notidn=get_notidn($part);
                
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
        }
    }
    # Notationen abarbeiten Ende
        
    # Schlagworte abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{subj}}){
        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
#            $content    = decode($convconfig->{encoding},$content) if (exists $convconfig->{encoding});
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }
                
                foreach my $part (@parts){
                    my $swtidn=get_swtidn($part);
                    
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
    }
    # Schlagworte abarbeiten Ende

    # Exemplardaten abarbeiten Anfang
    foreach my $kateg (keys %{$convconfig->{exempl}}){
        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
            
            if ($content){
                my @parts = ();
                if (exists $convconfig->{category_split_chars}{$kateg} && $content=~/$convconfig->{category_split_chars}{$kateg}/){
                    @parts = split($convconfig->{category_split_chars}{$kateg},$content);
                }
                else {
                    push @parts, $content;
                }

                foreach my $part (@parts){
                    print MEX $convconfig->{exempl}{$kateg}.$part."\n";
                }
            }
        }
    }
    # Exemplardaten abarbeiten Ende

    print TIT "9999:\n";
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}
                                   
sub get_autidn {
    ($autans)=@_;
    
    $autdubidx=1;
    $autdubidn=0;
                                   
    while ($autdubidx < $autdublastidx){
        if ($autans eq $autdubbuf[$autdubidx]){
            $autdubidn=(-1)*$autdubidx;      
            
            # print STDERR "AutIDN schon vorhanden: $autdubidn\n";
        }
        $autdubidx++;
    }
    if (!$autdubidn){
        $autdubbuf[$autdublastidx]=$autans;
        $autdubidn=$autdublastidx;
        #print STDERR "AutIDN noch nicht vorhanden: $autdubidn\n";
        $autdublastidx++;
        
    }
    return $autdubidn;
}
                                   
sub get_swtidn {
    ($swtans)=@_;
    
    $swtdubidx=1;
    $swtdubidn=0;
    #  print "Swtans: $swtans\n";
    
    while ($swtdubidx < $swtdublastidx){
        if ($swtans eq $swtdubbuf[$swtdubidx]){
            $swtdubidn=(-1)*$swtdubidx;      
            
            #            print "SwtIDN schon vorhanden: $swtdubidn, $swtdublastidx\n";
        }
        $swtdubidx++;
    }
    if (!$swtdubidn){
        $swtdubbuf[$swtdublastidx]=$swtans;
        $swtdubidn=$swtdublastidx;
        #        print "SwtIDN noch nicht vorhanden: $swtdubidn, $swtdubidx, $swtdublastidx\n";
        $swtdublastidx++;
        
    }
    return $swtdubidn;
}
                                   
sub get_koridn {
    ($korans)=@_;
    
    $kordubidx=1;
    $kordubidn=0;
    #  print "Korans: $korans\n";
    
    while ($kordubidx < $kordublastidx){
        if ($korans eq $kordubbuf[$kordubidx]){
            $kordubidn=(-1)*$kordubidx;
        }
        $kordubidx++;
    }
    if (!$kordubidn){
        $kordubbuf[$kordublastidx]=$korans;
        $kordubidn=$kordublastidx;
        #    print "KorIDN noch nicht vorhanden: $kordubidn\n";
        $kordublastidx++;
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

sub konv {
    my ($content)=@_;

#    $content=~s/\&/&amp;/g;
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    return $content;
}
