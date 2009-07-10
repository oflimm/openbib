#!/usr/bin/perl

#####################################################################
#
#  aleph18seq2meta.pl
#
#  Konverierung von Aleph 18 Sequential MAB Daten in das Meta-Format
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
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

use utf8;

use Getopt::Long;

use OpenBib::Config;
use YAML;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

&GetOptions(
	    "filename=s"       => \$filename,
	    );

if (!$filename){
    print << "HELP";
aleph18seq2meta.pl - Aufrufsyntax

    aleph18seq2meta.pl --filename=xxx
HELP
exit;
}

# Kategorieflags

%autkonv=(
    '1001a'   => '0100', # Verfasser
    '1002a'   => '0100', # Verfasser
    '1003a'   => '0100', # Verfasser
    '1041a'   => '0100', # 2.Verfasser
    '1042a'   => '0100', # 2.Verfasser
    '1081a'   => '0100', # 3.Verfasser
    '1011a'   => '0101', # Person
);

%korkonv=(
    '2001a'   => '0200', #
    '2002a'   => '0200', #
    '2041a'   => '0200', #
    '2081a'   => '0200', #
    '2011a'   => '0201', # 
);

%notkonv=(
    '7001a'   => '0700', # 
);

%swtkonv=(
    '9021a'   => '0710',  #
    '9021g'   => '0710',  #
    '9021f'   => '0710',  #
    '9021s'   => '0710',  #
    '9071a'   => '0710',  #
    '9071g'   => '0710',  #
    '9071f'   => '0710',  #
    '9071s'   => '0710',  #
    '9121a'   => '0710',  #
    '9121g'   => '0710',  #
    '9121f'   => '0710',  #
    '9121s'   => '0710',  #
    '9171a'   => '0710',  #
    '9171g'   => '0710',  #
    '9171f'   => '0710',  #
    '9171s'   => '0710',  #
    '9221a'   => '0710',  #
    '9221g'   => '0710',  #
    '9221f'   => '0710',  #
    '9221s'   => '0710',  #
    '9271a'   => '0710',  #
    '9271g'   => '0710',  #
    '9271f'   => '0710',  #
    '9271s'   => '0710',  #
    '9321a'   => '0710',  #
    '9321g'   => '0710',  #
    '9321f'   => '0710',  #
    '9321s'   => '0710',  #
    '9371a'   => '0710',  #
    '9371g'   => '0710',  #
    '9371f'   => '0710',  #
    '9371s'   => '0710',  #
    '9421a'   => '0710',  #
    '9421g'   => '0710',  #
    '9421f'   => '0710',  #
    '9421s'   => '0710',  #
    '9471a'   => '0710',  #
    '9471g'   => '0710',  #
    '9471f'   => '0710',  #
    '9471s'   => '0710',  #
);

# Kategoriemappings

%titelkonv=(
    '0011a' => '0010', #
    '0371a' => '0015', #
    '3041a' => '0304', #
    '3101a' => '0310', #
    '3311a' => '0331', #
    '3351a' => '0335', #
    '3591a' => '0359', #
    '3601a' => '0360', #
    '3701a' => '0370', #
    '4031a' => '0403', #
    '4051a' => '0405', #
    '4101a' => '0410', # 
    '4121a' => '0412', #
    '4251a' => '0425', #
    '4331a' => '0433', #
    '4341a' => '0434', #
    '4511a' => '0451.001', #
    '4611a' => '0451.004', #
    '4711a' => '0451.009', #
    '4551a' => '0455.001', #
    '4651a' => '0455.004', #
    '4751a' => '0455.009', #
    '5011a' => '0501', #
    '5071a' => '0507', #
    '5331a' => '0533', #
    '5401a' => '0540', #
    '5901a' => '0590', #
    '5951a' => '0595', #
    '5961a' => '0596', #
);

# Einlesen und Reorganisieren

open(DAT,"<","$filename");

my $ht2id_ref={};

# Pass 1: Titel-IDs zu HT-Nummern bestimmen
while (<DAT>){
    if (/^(\d+)\s001-1\sL\s\$\$a(\w+)$/){
        $ht2id_ref->{$2}=$1;
    }
}

close(DAT);

# Pass 2: Daten konvertieren

my @buffer = ();

$titidn=1;
$autidn=1;
$swtidn=1;
$mexidn=1;
$koridn=1;
$notidn=1;

$autdublastidx=1;
$kordublastidx=1;
$notdublastidx=1;
$swtdublastidx=1;

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");

open(DAT,"<","$filename");
while (<DAT>){
    if (/^\d+\sLDR-1/){
        convert_buffer() if (@buffer);
        @buffer = ();
    }
    else {
        s/<<//g;
        s/>>//g;
        s/\&/&amp;/g;
        s/>/&gt;/g;
        s/</&lt;/g;

        push @buffer, $_;
    }
}
convert_buffer() if (@buffer);

close(TIT);
close(SWT);
close(KOR);
close(NOTATION);
close(AUT);


close(DAT);

sub convert_buffer {
    my $have_id  = 0;
    my $have_lok = 0;

    my $mexidx = 1;
    my $titid  = 0;
    
    #######################################################################
    # Umwandeln
    
    # Titel ID und Existenz Lokaldaten bestimmen
    foreach my $line (@buffer){
        ($titid,$kateg,$indikator,$type,$content)=$line=~/^(\d+)\s(...)(.)(.)\sL\s(.+)$/; # Parsen
        if ($type eq "9"){
            $have_lok=1;
        }
    }

    if ($titid){
        print TIT "0000:".sprintf "%d\n", $titid;
        $have_id=$titid;
    }
    
    return if (!$have_id);

    foreach my $line (@buffer){
        ($kateg,$indikator,$type,$content)=$line=~/^\d+\s(...)(.)(.)\sL\s(.+)$/;
        my $content_ref={};
        
        foreach my $subkat (split('\$\$',$content)){
            if ($subkat=~/^(.)(.+?)\s?$/){
                $content_ref->{$kateg.$type.$1}=$2;
            }
        }
        
        foreach my $kategind (keys %$content_ref){

            # Verweisungen
            if ($kateg eq "453"){
                if ($ht2id_ref->{$content_ref->{"4531a"}}){
                    print TIT "0004:".$ht2id_ref->{$content_ref->{"4531a"}}."\n";
                }
            }

            if (exists $titelkonv{$kategind}){
                print TIT $titelkonv{$kategind}.":".$content_ref->{$kategind}."\n";
            }
            
            # Autoren abarbeiten Anfang
            
            elsif (exists $autkonv{$kategind}){
                my $supplement="";
                my $content = $content_ref->{$kategind};
                if ($content=~/^(.+?)( \[.*?$)/){
                    $content    = $1;
                    $supplement = $2;
                }
                $autidn=get_autidn($content);
                
                if ($autidn > 0){
                    print AUT "0000:$autidn\n";
                    print AUT "0001:$content\n";
                    print AUT "9999:\n";
                    
                }
                else {
                    $autidn=(-1)*$autidn;
                }
                
                if ($supplement){
                    $supplement=" ; $supplement";
                }
                
                print TIT $autkonv{$kategind}.":IDN: ".$autidn.$supplement."\n";
            }
            # Autoren abarbeiten Ende
            
            # Koerperschaften abarbeiten Anfang
            
            elsif (exists $korkonv{$kategind}){
                my $content = $content_ref->{$kategind};
                
                $koridn=get_koridn($content);
                
                if ($koridn > 0){
                    print KOR "0000:$koridn\n";
                    print KOR "0001:$content\n";
                    print KOR "9999:\n";
                    
                }
                else {
                    $koridn=(-1)*$koridn;
                }
                
                print TIT $korkonv{$kategind}.":IDN: ".$koridn."\n";
            }
            # Koerperschaften abarbeiten Ende
            
            # Notationen abarbeiten Anfang
            
            elsif (exists $notkonv{$kategind}){
                my $content = $content_ref->{$kategind};
                
                $notidn=get_notidn($content);
                
                if ($notidn > 0){
                    print NOTATION "0000:$notidn\n";
                    print NOTATION "0001:$content\n";
                    print NOTATION "9999:\n";
                    
                }
                else {
                    $notidn=(-1)*$notidn;
                }
                
                print TIT $notkonv{$kategind}.":IDN: ".$notidn."\n";
            }
            # Notationen abarbeiten Ende
            
            # Schlagworte abarbeiten Anfang            
            elsif (exists $swtkonv{$kategind}){
                my $content = $content_ref->{$kategind};
                $swtidn=get_swtidn($content);
                
                if ($swtidn > 0){	  
                    print SWT "0000:$swtidn\n";
                    print SWT "0001:$content\n";
                    print SWT "9999:\n";
                }
                else {
                    $swtidn=(-1)*$swtidn;
                }
                
                print TIT $swtkonv{$kategind}.":IDN: ".$swtidn."\n";
                # Schlagworte abarbeiten Ende
                
            }
            # Schlagworte abarbeiten Ende
        }

        # Exemplardaten

        if ($kateg eq "Z30"){
#            print YAML::Dump($content_ref),"\n";
            $mexidx=sprintf "%03d", $mexidx;

            # Signatur
            if ($content_ref->{'Z3019'}){
                print TIT "0014.".$mexidx.":".$content_ref->{'Z3019'}."\n";
            }
            elsif ($content_ref->{'Z3013'}){
                print TIT "0014.".$mexidx.":".$content_ref->{'Z3013'}."\n" ;
            }

            # Standort
            if ($content_ref->{'Z301B'}){
                if ($content_ref->{'Z301B'} eq "M"){
                    $content_ref->{'Z301B'}="Magazin";
                }
                elsif ($content_ref->{'Z301B'} eq "F"){
                    $content_ref->{'Z301B'}="Freihand";
                }
                
                print TIT "0016.".$mexidx.":".$content_ref->{'Z301B'}."\n";
            }
            
#            print TIT "0005.".$mexidx.":".$content_ref->{'Z3013'}."\n" if ($content_ref->{'Z3013'});
            $mexidx++;
        }
        
    }
    print TIT "9999:\n";

}

sub get_autidn {
    ($autans)=@_;
    
    $autdubidx=$startautidn;
    $autdubidn=0;
    #  print "Autans: $autans\n";
    
    while ($autdubidx < $autdublastidx){
        if ($autans eq $autdubbuf[$autdubidx]){
            $autdubidn=(-1)*$autdubidx;      
            
            #      print "AutIDN schon vorhanden: $autdubidn\n";
        }
        $autdubidx++;
    }
    if (!$autdubidn){
        $autdubbuf[$autdublastidx]=$autans;
        $autdubidn=$autdublastidx;
        #    print "AutIDN noch nicht vorhanden: $autdubidn\n";
        $autdublastidx++;
        
    }
    return $autdubidn;
}

sub get_swtidn {
    ($swtans)=@_;
    
    $swtdubidx=$startswtidn;
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
    
    $kordubidx=$startkoridn;
    $kordubidn=0;
    #  print "Korans: $korans\n";
    
    while ($kordubidx < $kordublastidx){
        if ($korans eq $kordubbuf[$kordubidx]){
            $kordubidn=(-1)*$kordubidx;      
            
            #      print "KorIDN schon vorhanden: $kordubidn\n";
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
    ($notans)=@_;
    
    $notdubidx=$startnotidn;
    $notdubidn=0;
    #  print "Notans: $notans\n";
    
    while ($notdubidx < $notdublastidx){
        if ($notans eq $notdubbuf[$notdubidx]){
            $notdubidn=(-1)*$notdubidx;      
            
            #      print "NotIDN schon vorhanden: $notdubidn\n";
        }
        $notdubidx++;
    }
    if (!$notdubidn){
        $notdubbuf[$notdublastidx]=$notans;
        $notdubidn=$notdublastidx;
        #    print "NotIDN noch nicht vorhanden: $notdubidn\n";
        $notdublastidx++;
        
    }
    return $notdubidn;
}

