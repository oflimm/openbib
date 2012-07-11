#!/usr/bin/perl

#####################################################################
#
#  colonia2meta.pl
#
#  Konverierung der Daten des Ital. Kulturinstituts in das Meta-Format
#
#  Dieses File ist (C) 1999-2012 Oliver Flimm <flimm@openbib.org>
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
use Encode qw(decode_utf8 encode_utf8 decode encode);

&GetOptions(
	    "filename=s"       => \$filename,
	    );

if (!$filename){
    print << "HELP";
colonia2meta.pl - Aufrufsyntax

    colonia2meta.pl --filename=xxx
HELP
exit;
}

$bufferidx=0;


%titelkonv=(
    'ORT'   => '0410:',
    'JAR'   => '0425:',
    'AUF'   => '0403:',
    'VER'   => '0412:',
    'HRG'   => '0359:',
    'KOL'   => '0433:',
    'REI'   => '0451:',
    'ORI'   => '0501:',
    'SIG'   => '0014.001:',
);

print join("\n",@all);

# Einlesen und Reorganisieren

open(DAT,"<:encoding(cp437)", "$filename");

while (<DAT>){
    s///g;
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

$seridn=1;
$seridx=0;

$tempidx=0;                        

$i=0;
$ti=0;

$autdublastidx=1;
$kordublastidx=1;
$swtdublastidx=1;

while ($i < $#buffer){
  if ($buffer[$i]=~/^ENDE/){
    
    $titbuffer[$titidx++]="0000:".$titidn;
    
    while ($ti < $tempidx){
      ($kateg,$content)=$tempbuffer[$ti]=~/^(.+?): (.*)/;

      if ($kateg eq "ART"){
          $hstartikel=$content;
      }
      
      if ($titelkonv{$kateg}){
	$titbuffer[$titidx++]=$titelkonv{$kateg}.$content;
	
      }
      
      if ($kateg eq "SAT"){
          if ($hstartikel){
              $content=$hstartikel." ".$content;
          }     
          $titbuffer[$titidx++]="0331:$content";
      }
      
      # Autoren abarbeiten Anfang
      
      elsif ($kateg eq "AUT"){
	
	$autidn=get_autidn($content);
	
	if ($autidn > 0){
	  $autbuffer[$autidx++]="0000:".$autidn;
	  $autbuffer[$autidx++]="0001:".$content;
	  $autbuffer[$autidx++]="9999:";
	  
	}
	else {
	  $autidn=(-1)*$autidn;
	}
	
	$titbuffer[$titidx++]="0100:IDN: ".$autidn;
      }
      # Autoren abarbeiten Ende
      
      # Schlagworte abarbeiten Anfang
      
      elsif ($kateg eq "SWT"){
	
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
	$swtidn++;
	# Schlagworte abarbeiten Ende      
	
      }

      $ti++;	   
    }

    $titbuffer[$titidx++]="9999:";
    
    # Serien einordnen
    
    $tempidx=0;
    $ti=0;

    undef $hstartikel;
    undef @tempbuffer;
  }
  else {
      if ($buffer[$i]=~m/INV: (\d+)/){
          $titidn=$buffer[$i]=$1;
      }
      $tempbuffer[$tempidx++]=$buffer[$i];
  }

  $i++;
}
  
$lasttitidx=$titidx;
$lastautidx=$autidx;
$lastmexidx=$mexidx;
$lastkoridx=$koridx;
$lastswtidx=$swtidx;

# Ausgabe der EXP-Dateien

ausgabetitfile();
ausgabeautfile();
ausgabeswtfile();

close(DAT);

sub ausgabetitfile {
  open (TIT,">:utf8","meta.title");
  $i=0;
  while ($i < $lasttitidx){
    print TIT $titbuffer[$i],"\n";
    $i++;
  }
  close(TIT);
}

sub ausgabeautfile {
  open(AUT,">:utf8","meta.person");
  $i=0;
  while ($i < $lastautidx){
    print AUT $autbuffer[$i],"\n";
    $i++;
  }
  close(AUT);
}

sub ausgabeswtfile {
  open(SWT,">:utf8","meta.subject");
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

