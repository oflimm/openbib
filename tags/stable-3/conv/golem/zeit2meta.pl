#!/usr/bin/perl

#####################################################################
#
#  zeit2meta.pl
#
#  Konverierung von Golem Zeitschriftenausschnitts-Daten in das Meta-Format
#
#  Dieses File ist (C) 2003-2012 Oliver Flimm <flimm@openbib.org>
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

use vars qw(%config);

*config=\%OpenBib::Config::config;

&GetOptions(
	    "filename=s"       => \$filename,
	    );

if (!$filename){
    print << "HELP";
zeit2meta.pl - Aufrufsyntax

    zeit2meta.pl --filename=xxx
HELP
exit;
}

$bufferidx=0;


%titelkonv=('TITEL' => '0331:',    # Titel
         'Ort'   => '0410:',
	 'EJ'    => '0425:',
        );

%kategorien=(
	     'E-DAT'     => '1',
	     'Medium'    => '1',
	     'Ort'       => '1',
	     'Art'       => '1',
	     'VERF'      => '1',
	     'TITEL'     => '1',
	     'UTIT'      => '1',
	     'ZTG'       => '1',
	     'JG'        => '1',
	     'NR'        => '1',
	     'DATUM'     => '1',
	     'SEITE'     => '1',
	     'FREI'      => '1',
	     'EJ'        => '1',
	     'NTIT'      => '1',
	     'Seite'     => '1',
	     'SERIENTIT' => '1',
	    );






# Einlesen und Reorganisieren

open(DAT,"$filename");

$anfang=1;

while (<DAT>){

  if (/^(\w+): /){
    $kateg=$1;
    if ($kategorien{$kateg} != 1){
      $kateg="";
    }
    else {
      $lastkateg=$kateg;
    }
  }
  else {
    $neukateg=$lastkateg;
  }
  
  if (/^E-DAT:/){
    if ($anfang == 1){
      $buffer[$bufferidx++]=$_;
      $anfang=0;
    }
    else {
      $buffer[$bufferidx++]="ENDE\n";
      $buffer[$bufferidx++]=$_;
    }
    $neukateg="";
  }
  else {
    if ($neukateg){
      if ($neukateg eq "DATUM"){
	chomp($buffer[$bufferidx-1]);
	$buffer[$bufferidx-1]=$buffer[$bufferidx-1].$_;
      }
      else {
	$_=$neukateg.": ".$_;
	$buffer[$bufferidx++]=$_;
      }
      $neukateg="";
    }
    else {
      $buffer[$bufferidx++]=$_;
    }
  }

}

$buffer[$bufferidx++]="ENDE\n";

#######################################################################
# Umwandeln

$titleid=1;
$titleidx=0;

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
    
    $titbuffer[$titleidx++]="0000:".$titleid;
    
    while ($ti < $tempidx){
      ($kateg,$content)=$tempbuffer[$ti]=~/^(.+?): (.*)/;
      
      if ($titelkonv{$kateg}){
	$titbuffer[$titleidx++]=$titelkonv{$kateg}.$content;
	
      }
      
      if ($kateg eq "NTIT" || $kateg eq "UTIT"){
	chomp($content);
	push @zusatzbuffer, $content;
      }
      
      # Autoren abarbeiten Anfang
      
      elsif ($kateg eq "VERF"){
	
	$autidn=get_autidn($content);
	
	if ($autidn > 0){
	  $autbuffer[$autidx++]="0000:".$autidn;
	  $autbuffer[$autidx++]="0001:".$content;
	  $autbuffer[$autidx++]="9999:";
	  
	}
	else {
	  $autidn=(-1)*$autidn;
	}
	
	$titbuffer[$titleidx++]="0100:IDN: ".$autidn;
      }
      # Autoren abarbeiten Ende
      
      
      # Koerperschaften abarbeiten Anfang
      
      elsif ($kateg eq "ZTG"){
	$zeitung="$content";
	chomp($zeitung);
	push @hstquellebuffer, $zeitung;
      }
      elsif ($kateg eq "JG"){
	$jahrgang="Jg $content";
	chomp($jahrgang);
	push @hstquellebuffer, $jahrgang;
      }
      elsif ($kateg eq "NR"){
	$nummer="Nr. $content";
	chomp($nummer);
	push @hstquellebuffer, $nummer;
      }
      elsif ($kateg eq "DATUM"){
	$datum="$content";
	chomp($datum);
	push @hstquellebuffer, $datum;
      }
      elsif ($kateg eq "SEITE"){
	$seite="S. $content";
	chomp($seite);
	push @hstquellebuffer, $seite;
      }

      elsif ($kateg eq "Medium"){
	$medium="$content";
	chomp($medium);
	push @medienartbuffer, $medium;
      }
      elsif ($kateg eq "Art"){
	$art="$content";
	chomp($art);
	push @medienartbuffer, $art;
      }
      
      # Schlagworte abarbeiten Anfang
      
      elsif ($kateg eq "FREI"){
	
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
	
	$titbuffer[$titleidx++]="0710:IDN: ".$swtidn;
	$swtidn++;
	# Schlagworte abarbeiten Ende      
	
      }
      $ti++;	   
    }

    if ($#zusatzbuffer >= 0){
      $zusatz=join(" ; ",@zusatzbuffer);
      $titbuffer[$titleidx++]="0335:".$zusatz;
    }

    if ($#hstquellebuffer >= 0){
      $hstquelle=join(", ",@hstquellebuffer);
      
      $titbuffer[$titleidx++]="0508:".$hstquelle;;
    }
    
    if ($#medienartbuffer >= 0){
      $medienart=join(" / ",@medienartbuffer);
      
      $titbuffer[$titleidx++]="0800:".$medienart;
    }
    
    $titbuffer[$titleidx++]="9999:";
    
    # Serien einordnen
    
    $titleid++;
    $tempidx=0;
    $ti=0;

    undef @tempbuffer;
    undef @medienartbuffer;
    undef @zusatzbuffer;
    undef @hstquellebuffer;
  }
  else {
    if ($buffer[$i]=~/^E-DAT: (\d\d\d\d\d\d)/){
      $date="19$1";
    }

    $tempbuffer[$tempidx++]=$buffer[$i];
  }

  $i++;
}
  
$lasttitleidx=$titleidx;
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
  while ($i < $lasttitleidx){
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

