#!/usr/bin/perl

#####################################################################
#
#  simple2meta.pl
#
#  Konverierung der einfach aufgebauter Daten in das Meta-Format
#
#  Dieses File ist (C) 1999-2007 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

&GetOptions(
	    "filename=s"       => \$filename,
	    );

if (!$filename){
    print << "HELP";
simple2meta.pl - Aufrufsyntax

    simple2meta.pl --filename=xxx
HELP
exit;
}

$bufferidx=0;

# Kategorieflags

%autkonv=(
    'AutorPerson'   => '0101:', # Person
);

%korkonv=(
    'lok. Bezug'   => 1, # Topographisches Schlagwort: Kopenhagen
);

%notkonv=(
    'prim. Ikon.'   => 1, # Primaeres Ikonographices Schlagwort: 25 I 12  prospect of city, town panorama, silhouette of city
);

%swtkonv=(
    'sek. Ikon.'   => 1,  # Sekundaeres Ikonographisches Schlagwort: Kopenhagen
);

# Kategoriemappings

%titelkonv=(
    'OBJ-Dok-Nr.'  => '0000:',
    'Bez-Verwalt.' => '', # Verwaltung
    'Ort'          => '', # Köln
    'Art'          => '', # (öffentliche) Sammlung
    'Sozietät'     => '', # Universitäts- und Stadtbibliothek Köln
    'Abteilung'    => '', # Altes Buch
    'Invent-Nr.'   => '', # GG4/925-4/5 (v. S. 13)
# Bez-Künstler:Herstellung
# Name:Manesson-Mallet, Alain
# ber. Funkt.:Autor
# Bez-Künstler:Herstellung
# Name:Zunner, Johann David
# ber. Funkt.:Verleger
    'Dat-Art'      => '', # Datierung
    'num. Dat.'    => '0425:', # 1686
    'Entst-Ort'    => '0591:', # Frankfurt a. M.
    'Entst-Lands.' => '0594:', # Hessen
    'Entst-Land'   => '0595:', # Deutschland
    'Obj-Titel'    => '0331:', # Kopenhagen
    'Gattung'      => '', # Druckgraphik
    'U-Gattung'    => '', # Buchillustration
    'Sachbegriff'  => '', # Bild
    'Farbmater.'   => '', # Druckfarbe (schwarz)
    '(Träger-)Mat' => '0334:', # Papier
    'Technik'      => '', # Radierung
    'HöhexBreite'  => '0407:', # 19,9 x 15,4 (Blatt)
    'Höhe'         => '', # 17,4 (Platte)
    'Breite'       => '', # 15,4 (Blatt)
    # Block Anfang
    'Beschr-Art'   => '', # Titel
    'Transkr.'     => '0750:', # COPENHAGVE
    'Anbr-Ort'     => '', # Blatt 
    'Farbmat.'     => '', # Druckfarbe (schwarz)
    'Technik'      => '', # Typendruck
    'Sprache'      => '', # Französisch
    'Übersetz.'    => '', # x
    # Block Ende
    'Foto'         => '', # Reproduktion
    'Aufnahmenr.'  => '', # CD9/09222359/00000004
    'Aufn-Art'     => '', # Microfilm
    'Repro-Nr.'    => '', # <a href="http://sweethardt.ub.uni-koeln.de/retro/archiv/09222359/00000004.jpg"><img src="http://sweethardt.ub.uni-koeln.de/retro/archiv/09222359/00000004.gif"></a>
    'Erhaltung'    => '', # gut
    'Datum'        => '', # 2001.11.12
    'Urh-Instit.'  => '', # Universitäts- und Stadtbibliothek Köln
    'Urh-Autor'    => '', # Beatrix Herling
);

# Einlesen und Reorganisieren

open(DAT,"$filename");

while (<DAT>){
    $buffer[$bufferidx++]=$_;
}

$buffer[$bufferidx++]="ENDE\n";

#######################################################################
# Umwandeln

$titidn=1;
$titidx=0;

$autidn=1;
$autidx=0;

$swtidn=1;
$swtidx=0;

$mexidn=1;
$mexidx=0;

$koridn=1;
$koridx=0;

$notidn=1;
$notidx=0;

$tempidx=0;

$i=0;
$ti=0;

$autdublastidx=1;
$kordublastidx=1;
$notdublastidx=1;
$swtdublastidx=1;

while ($i < $#buffer){
    if ($buffer[$i]=~/^ENDE/){
        
        #    $titbuffer[$titidx++]="0000:".$titidn;
        
        while ($ti < $tempidx){
            ($kateg,$content)=$tempbuffer[$ti]=~/^(.+?):(.*?)$/;
            
            if ($titelkonv{$kateg}){
                if ($titelkonv{$kateg} eq "0000:"){
                    $content=sprintf "%d", $content;
                }
                $titbuffer[$titidx++]=$titelkonv{$kateg}.$content;
                
            }
            
            # Autoren abarbeiten Anfang
            
            elsif (exists $autkonv{$kateg}){
                my $supplement="";
                if ($content =~/^(.+?)( ; \[.*?$)/){
                   $content    = $1;
                   $supplement = $2;
                }
                $autidn=get_autidn($content);
                
                if ($autidn > 0){
                    $autbuffer[$autidx++]="0000:".$autidn;
                    $autbuffer[$autidx++]="0001:".$content;
                    $autbuffer[$autidx++]="9999:";
                    
                }
                else {
                    $autidn=(-1)*$autidn;
                }
                
                $titbuffer[$titidx++]="0101:IDN: ".$autidn.$supplement;
            }
            # Autoren abarbeiten Ende
            
            # Koerperschaften abarbeiten Anfang
            
            elsif (exists $korkonv{$kateg}){
                
                $koridn=get_koridn($content);
                
                if ($koridn > 0){
                    $korbuffer[$koridx++]="0000:".$koridn;
                    $korbuffer[$koridx++]="0001:".$content;
                    $korbuffer[$koridx++]="9999:";
                    
                }
                else {
                    $koridn=(-1)*$koridn;
                }
                
                $titbuffer[$titidx++]="0200:IDN: ".$koridn;
            }
            # Koerperschaften abarbeiten Ende

            # Notationen abarbeiten Anfang
            
            elsif (exists $notkonv{$kateg}){
                
                $notidn=get_notidn($content);
                
                if ($notidn > 0){
                    $notbuffer[$notidx++]="0000:".$notidn;
                    $notbuffer[$notidx++]="0001:".$content;
                    $notbuffer[$notidx++]="9999:";
                    
                }
                else {
                    $notidn=(-1)*$notidn;
                }
                
                $titbuffer[$titidx++]="0700:IDN: ".$notidn;
            }
            # Notationen abarbeiten Ende

            # Schlagworte abarbeiten Anfang

            elsif (exists $swtkonv{$kateg}){
                $swtidn=get_swtidn($content);
                
                if ($swtidn > 0){	  
                    $swtbuffer[$swtidx++]="0000:".$swtidn;
                    $tempbuffer[$ti]=~s/\*/\//g;
                    $swtbuffer[$swtidx++]="0001:".$content;
                    $swtbuffer[$swtidx++]="9999:";
                }
                else {
                    $swtidn=(-1)*$swtidn;
                }
                
                $titbuffer[$titidx++]="0710:IDN: ".$swtidn;
                # Schlagworte abarbeiten Ende
                
            }
            
            $ti++;
        }
        
        $titbuffer[$titidx++]="9999:";
        
        # Serien einordnen
        
        #$titidn++;
        $tempidx=0;
        $ti=0;
        
        undef @tempbuffer;
    }
    else {
        $tempbuffer[$tempidx++]=$buffer[$i];
    }
    
    $i++;
}
  
$lasttitidx=$titidx;
$lastautidx=$autidx;
$lastnotidx=$notidx;
$lastmexidx=$mexidx;
$lastkoridx=$koridx;
$lastswtidx=$swtidx;

# Ausgabe der EXP-Dateien

ausgabetitfile();
ausgabeautfile();
ausgabekorfile();
ausgabenotfile();
ausgabeswtfile();

close(DAT);

sub ausgabetitfile {
  open (TIT,">:utf8","unload.TIT");
  $i=0;
  while ($i < $lasttitidx){
    print TIT $titbuffer[$i],"\n";
    $i++;
  }
  close(TIT);
}

sub ausgabeautfile {
  open(AUT,">:utf8","unload.PER");
  $i=0;
  while ($i < $lastautidx){
    print AUT $autbuffer[$i],"\n";
    $i++;
  }
  close(AUT);
}

sub ausgabekorfile {
  open(KOR,">:utf8","unload.KOE");
  $i=0;
  while ($i < $lastkoridx){
    print KOR $korbuffer[$i],"\n";
    $i++;
  }
  close(KOR);
}

sub ausgabenotfile {
  open(NOTATION,">:utf8","unload.SYS");
  $i=0;
  while ($i < $lastnotidx){
    print NOTATION $notbuffer[$i],"\n";
    $i++;
  }
  close(NOTATION);
}

sub ausgabeswtfile {
  open(SWT,">:utf8","unload.SWD");
  $i=0;
  while ($i < $lastswtidx) {
    print SWT $swtbuffer[$i],"\n";
    $i++;
  }
  close(SWT);
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

