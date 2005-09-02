#!/usr/bin/perl

#####################################################################
#
#  oai2meta.pl
#
#  Konverierung von OAI-Daten in das Meta-Format
#
#  Dieses File ist (C) 2003-2004 Oliver Flimm <flimm@openbib.org>
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

&GetOptions("single-pool=s" => \$singlepool,
	    "mit-schlagworten" => \$mitschlagworten,
	    "oaifile=s" => \$oaifile,
	    );

$datidx=0;
$bufferidx=0;

$viaidn=1;

$date=`date '+%Y%m%d'`;
chop $date;

$starttitidn=1;
$startautidn=1;
$startswtidn=1;
$startkoridn=1;
$startmexidn=1;            

%al2bis=('20 ','3000 ',    # Titel
	 '21 ','2700 ',    # WST
	 '50 ','8050 ',    # URL
	 '51 ','4500 ',    # HSFN
	 '74 ','4000 ',
	 '75 ','4002 ',
	 '76 ','4040 ',
	 '87 ','4600 ',
	 '71 ','3700 ',
	 '77 ','4102 ',
	 '85 ','4240 ',
	 '91 ','7560 ',
	 '99 ','9000 ',
	 'END','END');

$idx=0; 
$oldid=""; 
$temp2idx=0;

open(OAIDAT,"$oaifile");
while (<OAIDAT>){
  chomp;
  sonderzeichen();
  
  if (length($_) == 0){
    buffer_reorg();
  }
  else {
    $_=kategorien($_);
    $buffer[$bufferidx++]=$_;
  }
}

buffer_reorg();
close(OAIDAT);

convert_reorgbuffer();

sub kategorien {
    my $line=shift @_;
    $line=~s/^AU==/40 /;
    $line=~s/^TI==/20 /;
    $line=~s/^WT==/21 /; # Weitere Titel
    $line=~s/^SI==/90 /;
    $line=~s/^UR==/50 /; # URL
    $line=~s/^HS==/51 /; # HSFN
    $line=~s/^OR==/74 /;
    $line=~s/^SO==/75 /;
#    $line=~s/^SE==/ /;
    $line=~s/^KO==/61 /;
    $line=~s/^AS==/71 /;
    $line=~s/^SW==/20a/;
    $line=~s/^EJ==/76 /;
    $line=~s/^IS==/87 /;
    $line=~s/^AB==/99 /;
#    $line=~s/^AK==/91 /;
    $line=~s/^AK==.*/DuMMy/;
    $line=~s/^ID==.*/DuMMy/;
    return $line;
}

sub tidy_buffer {
#  print STDERR "Tidying Buffer\n";
  $i=0;
  while ($i <= $bufferidx){
    if ($buffer[$i]=~m/(..==)\s{5}\s+(.*)/){
      $buffer[$i]=$1.$2;
    }
    $i++;
  }

}

sub buffer_reorg{
#  print STDERR "Reorganizing Buffer\n";
    tidy_buffer();
    $i=0;
#  print STDERR "Copying Buffer\n";
    while ($i < $bufferidx){
	if (length($buffer[$i]) != 4){
	  $bline=$buffer[$i];
	  if ($bline=~/-:-/){
#	    print STDERR $bline."\n";
	    # Sonderbehandlung fuer Verlagsort
	    
	    if ($bline=~/^75../){

	      if ($bline=~/75 Verlag -:-(.*)/){
		$bline=$1;
	      }
	      elsif ($bline=~/75 Verlag(.*)/){
		$bline=$1;
	      }
	      elsif ($bline=~/75 -:-(.*)/){
		$bline=$1;
	      }
	      $bline="75 $bline";
	      $bline=~s/-:-/ ; /g;
#	      print STDERR "B: $bline\n"; 
#	      @so=split("-:-",$bline);
#	      $verlag=$so[0];
	      $reorgbuf[$temp2idx++]=$bline;
	    }
	    else {
	      $basekat=substr($bline,0,3);
	      @splitted=split("-:-",$bline);
	      $m=0;
	      while ($m <= $#splitted){
		if ($m == 0){
		  $reorgbuf[$temp2idx++]=$splitted[$m];
		}
		elsif ($m == $#splitted){
		  $reorgbuf[$temp2idx++]=$basekat.$splitted[$m];
		}
		else {
		  $reorgbuf[$temp2idx++]=$basekat.$splitted[$m];
		}
		$m++;
	      }
	    }
	  }
	  else {
	    $reorgbuf[$temp2idx++]=$buffer[$i];
	  }
	}
	$i++;
    }
    $reorgbuf[$temp2idx++]="ENDE";
    $bufferidx=0;
}



sub convert_reorgbuffer {
#  print STDERR "Converting Buffer\n";
  $lastidx=$#reorgbuf+1;

#  print STDERR "LASTIDX: $lastidx\n";

  $titidn=$starttitidn;
  $titidx=0;
  
  $autidn=$startautidn;
  $autidx=0;
  
  $swtidn=$startswtidn;
  $swtidx=0;
  
  $mexidn=$startmexidn;
  $mexidx=0;
  
  $koridn=$startkoridn;
  $koridx=0;
  
  $seridn=1;
  $seridx=0;
  
  $tempidx=0;                        

  $i=0;
  $ti=0;
  
  $havetit=0;
  $haveverf=0;
  $havekor=0;
  $haveort=0;
  $haveverlag=0;
  $havejahr=0;
  
  $autdublastidx=$startautidn;
  $kordublastidx=$startkoridn;
  $swtdublastidx=$startswtidn;
      
  while ($i < $lastidx){
    $kennung=substr($reorgbuf[$i],0,3);
    if ($kennung ne "END")
      {
        if ($kennung eq "20 ")
	  {
            $havetit=1;
	  }
        if (($kennung eq "40 ")||($kennung eq "402")||($kennung eq "403")||($kennung eq "41 ")||($kennung eq "412")||($kennung eq "413"))
	  {
            $haveverf=1;
	  }
        if ($kennung eq "61 ")
	  {
            $havekor=1;
	  }
        if ($kennung eq "74 ")
	  {
            $haveort=1;
            $serort=substr($reorgbuf[$i],3,length($reorgbuf[$i])-3);
	    #           print $serort."\n";
	  }                                                      
        if ($kennung eq "75 ")
	  {
            $haveverlag=1;
            $serverlag=substr($reorgbuf[$i],3,length($reorgbuf[$i])-3);
	    #           print $serverlag."\n";
	  }
        if ($kennung eq "76 ")
	  {
            $havejahr=1;
	  }
	
        $tempbuffer[$tempidx]=$reorgbuf[$i];
        if ($kennung eq "85 ")
	  {
            $serie=1;
	  }
        if ($kennung eq "90 ")
	  {
            $signatur=substr($reorgbuf[$i],3,length($reorgbuf[$i])-3);
	  }
        if ($kennung eq "91 ")
	  {                                 
            $inventar=substr($reorgbuf[$i],3,length($reorgbuf[$i])-3);
	  }
        $tempidx++;
      }
    else {
      $mexnotdone=1;
      if ($viaidn){
	$titbuffer[$titidx++]="IDN  ".$titidn;
	$titbuffer[$titidx++]="SDN  ".$date;
	$titbuffer[$titidx++]="SDU  ".$date;
      }
      else {
	$titbuffer[$titidx++]="IDN                 ".$titidn;
	$titbuffer[$titidx++]="Ident-alt           ".$sigel.$titidn;
	$titbuffer[$titidx++]="SDN                 ".$date;
	$titbuffer[$titidx++]="SDU                 ".$date;
      }
      
      # Vergabe des BIS-LOK Titeltyps 7
      
      if ($viaidn){
	$titbuffer[$titidx++]="1100 7";
      }
      else{
	$titbuffer[$titidx++]="TITEL-TYP           7";
      }
      
      $titeltyp=7;
      
      $havetit=0;
      $haveverf=0;
      $havekor=0;
      $haveort=0;
      $haveverlag=0;
      $havejahr=0;
      
      # Ende Vergabe der Titeltypen
      
      while ($ti < $tempidx){
	  $nkennung=substr($tempbuffer[$ti],0,3);
	  
	  if (($nkennung eq "71 ")||($nkennung eq "74 ")||($nkennung eq "75 ")||($nkennung eq "76 ")||($nkennung eq "77 ")||($nkennung eq "87 ")||($nkennung eq "85 ") || ($nkennung eq "50 ") || ($nkennung eq "51 ") || ($nkennung eq "21 "|| ($nkennung eq "99 ")))
	    {
	      substr($tempbuffer[$ti],0,3)=$al2bis{$nkennung};
	      $titbuffer[$titidx++]=$tempbuffer[$ti];
	      
	    }
	  if ($nkennung eq "20 "){
	    
	    if ($tempbuffer[$ti]=~/ : /){
	      ($hst,$zusatz)=split(" : ",$tempbuffer[$ti]);
	    }
	    else {
	      $hst=$tempbuffer[$ti];
	      $zusatz="";
	    }
	    
	    if ($viaidn){
	      if (length($hst)>0)
		{
		  $titbuffer[$titidx++]="3000*".substr($hst,3,length($hst)-3);
		}
	      if (length($zusatz)>0)
		{
		  $titbuffer[$titidx++]="3040 ".$zusatz;
		}
	    }
	    else {
	      if (length($hst)>0)
		{
		  $titbuffer[$titidx++]="HST                *".substr($hst,3,length($hst)-3);
		}
	      if (length($zusatz)>0)
		{
		  $titbuffer[$titidx++]="ZUSATZ              ".$zusatz;
		}
	    }
	  }

	  # Autoren abarbeiten Anfang
	  
	  if (($nkennung eq "40 ")||($nkennung eq "402")||($nkennung eq "403")||($nkennung eq "41 ")){
	    
	    $autidn=get_autidn(substr($tempbuffer[$ti],3,length($tempbuffer[$ti])-3));
	    
	    if ($viaidn){
	      if ($autidn > 0){
		$autbuffer[$autidx++]="IDN  ".$autidn;
		$autbuffer[$autidx++]="SDN  ".$date ;
		$autbuffer[$autidx++]="SDU  ".$date;
		$autbuffer[$autidx++]="6020 ".substr($tempbuffer[$ti],3,length($tempbuffer[$ti])-3);
		
		$autbuffer[$autidx++]="ENDE";
		
	      }
	      else {
		$autidn=(-1)*$autidn;
	      }
	      
	      if ($nkennung=~/^41/){
		$titbuffer[$titidx++]="2003hIDN: ".$autidn;
	      }
	      if (($nkennung=~/^20[4-9]/)||($nkennung=~/^900/)){
		$titbuffer[$titidx++]="2003 IDN: ".$autidn;
	      }
	      
	      if ($nkennung=~/^40 /){
		$titbuffer[$titidx++]="2000*IDN: ".$autidn;
	      }
	      
	      if ($nkennung=~/^40[2-3]/){
		$titbuffer[$titidx++]="2000*IDN: ".$autidn;
	      }
	      
	    }
	    else {
	      if ($autidn > 0){
		$autbuffer[$autidx++]="IDN        ".$autidn;
		$autbuffer[$autidx++]="Ident-alt  ".$sigel.$autidn;
		$autbuffer[$autidx++]="SDN        ".$date ;
		$autbuffer[$autidx++]="SDU        ".$date;
		$autbuffer[$autidx++]="AUT/Ans.   ".substr($tempbuffer[$ti],3,length($tempbuffer[$ti])-3);
		
		$autbuffer[$autidx++]="ENDE";
	      }
	      else {
		$autidn=(-1)*$autidn;
	      }
	      
	      if ($nkennung=~/^41/){
		$titbuffer[$titidx++]="PERS               h".$sigel.$autidn;
	      }
	      
	      if ($nkennung=~/^40[2-3]/){
		$titbuffer[$titidx++]="VERF               *".$sigel.$autidn;
	      }
	      if ($nkennung=~/^40 /){
		$titbuffer[$titidx++]="VERF               *".$sigel.$autidn;
	      }
	    }
	    #	    $autidn++;
	    $konv=1;
	    
	  }
	  # Autoren abarbeiten Ende
	  
	  # Exemplardaten abarbeiten Anfang
	  
	  if (((length($signatur) > 0)||(length($inventar)>0))&&($mexnotdone == 1)){
	    
	    if ($viaidn){
	      $mexbuffer[$mexidx++]="IDN  ".$mexidn;
	      $mexbuffer[$mexidx++]="SDN  ".$date ;
	      $mexbuffer[$mexidx++]="SDU  ".$date;
	      $mexbuffer[$mexidx++]="7500 ".$sigel if ($sigel);
	      $mexbuffer[$mexidx++]="7502 IDN: ".$titidn;
	      $mexbuffer[$mexidx++]="7620 ".$lokfn if ($lokfn);
	      $mexbuffer[$mexidx++]="7510 ".$signatur if ($signatur);
	      $mexbuffer[$mexidx++]="7560 ".$inventar if ($inventar);
	      $mexbuffer[$mexidx++]="7621 ".$zusgefb if ($zusgefb);
	      $mexbuffer[$mexidx++]="ENDE";
	    }
	    else {
	      $mexbuffer[$mexidx++]="IDN             ".$mexidn;
	      $mexbuffer[$mexidx++]="Ident-alt       ".$sigel.$mexidn;
	      $mexbuffer[$mexidx++]="SDN             ".$date ;
	      $mexbuffer[$mexidx++]="SDU             ".$date;
	      $mexbuffer[$mexidx++]="BIB-Sigel       "."38/$sigel"; #$bibsigel if ($bibsigel);
	      $mexbuffer[$mexidx++]="TITEL           ".$sigel.$titidn;
	      $mexbuffer[$mexidx++]="Lok. FN         ".$lokfn if ($lokfn);
	      $mexbuffer[$mexidx++]="SIGN-lok.       ".$signatur if ($signatur);
	      $mexbuffer[$mexidx++]="INV.NR.         ".$inventar if ($inventar);
	      $mexbuffer[$mexidx++]="Zs.gef. BDE     ".$zusgefb if ($zusgefb);
	      $mexbuffer[$mexidx++]="ENDE";
	    }
	    $mexidn++;
	    $mexnotdone=0;
	    
	  }
	  # Exemplardaten abarbeiten Ende
	  
	  # Koerperschaften abarbeiten Anfang
	  
	  if ($nkennung eq "61 "){
	    
	    $koridn=get_koridn(substr($tempbuffer[$ti],3,length($tempbuffer[$ti])-3));
	    
	    if ($viaidn){
	      if ($koridn > 0){	  
		$korbuffer[$koridx++]="IDN  ".$koridn;
		$korbuffer[$koridx++]="SDN  ".$date ;
		$korbuffer[$koridx++]="SDU  ".$date;
		$korbuffer[$koridx++]="6120 ".substr($tempbuffer[$ti],3,length($tempbuffer[$ti])-3);
		$korbuffer[$koridx++]="ENDE";
	      }
	      else {
		$koridn=(-1)*$koridn;
	      }
	      
	      $titbuffer[$titidx++]="2403 IDN: ".$koridn;
	      $koridn++;
	      $konv=1;
	    }
	    else {
	      if ($koridn > 0){	  
		$korbuffer[$koridx++]="IDN         ".$koridn;
		$korbuffer[$koridx++]="Ident-alt   ".$sigel.$koridn;
		$korbuffer[$koridx++]="SDN         ".$date ;
		$korbuffer[$koridx++]="SDU         ".$date;
		$korbuffer[$koridx++]="KOR/Ans.    ".substr($tempbuffer[$ti],3,length($tempbuffer[$ti])-3);
		$korbuffer[$koridx++]="ENDE";
	      }
	      else {
		$koridn=(-1)*$koridn;
	      }
	      
	      $titbuffer[$titidx++]="KOR                 ".$sigel.$koridn;
	      $koridn++;
	      $konv=1;
	    }
	    
	  }
	  
	  # Koerperschaften abarbeiten Ende
	  
	  # Schlagworte abarbeiten Anfang
	  
	  if (($nkennung=~/20a/)&&($mitschlagworten)){
	    
	    $swtidn=get_swtidn(substr($tempbuffer[$ti],3,length($tempbuffer[$ti])-3));
	    
	    if ($viaidn){
	      if ($swtidn > 0){	  
		$swtbuffer[$swtidx++]="IDN  ".$swtidn;
		$swtbuffer[$swtidx++]="SDN  ".$date ;
		$swtbuffer[$swtidx++]="SDU  ".$date;
		$tempbuffer[$ti]=~s/\*/\//g;
		$swtbuffer[$swtidx++]="6510 ".substr($tempbuffer[$ti],3,length($tempbuffer[$ti])-3);
		$swtbuffer[$swtidx++]="ENDE";
	      }
	      else {
		$swtidn=(-1)*$swtidn;
	      }
	      
	      $titbuffer[$titidx++]="5650 IDN: ".$swtidn;
	      $swtidn++;
	      $konv=1;
	    }
	    else {
	      if ($swtidn > 0){	  
		$swtbuffer[$swtidx++]="IDN           ".$swtidn;
		$swtbuffer[$swtidx++]="Ident-alt     ".$sigel.$swtidn;
		$swtbuffer[$swtidx++]="SDN           ".$date ;
		$swtbuffer[$swtidx++]="SDU           ".$date;
		$tempbuffer[$ti]=~s/\*/\//g;
		$swtbuffer[$swtidx++]="SCHLAGWORT    ".substr($tempbuffer[$ti],3,length($tempbuffer[$ti])-3);
		$swtbuffer[$swtidx++]="ENDE";
	      }
	      else {
		$swtidn=(-1)*$swtidn;
	      }
	      
	      $titbuffer[$titidx++]="SCHLAGWORT-lok.     ".$sigel.$swtidn;
	      $swtidn++;
	      $konv=1;
	    }
	  }
	  
	  # Schlagworte abarbeiten Ende      
	  
	  
	  $ti++;	   
	}
      #	$titbuffer[$titidx++]="Anz. Exempl         1";
      $titbuffer[$titidx++]="ENDE";
      
      # Serien einordnen
      
      if ($habeserie == 1)
	{
	  $blaidx=0;
	  while ($blaidx < $seridx)
	    {
	      $titbuffer[$titidx++]=$serbuffer[$blaidx++];
	    }
	  $seridx=0;
	  $titidn++;
	}
      $habeserie=0;
      $titidn++;
      $tempidx=0;
      $serie=0;
      $ti=0;
      $mexnotdone=1;
      undef @tempbuffer;
      undef $signatur;
      undef $inventar;
      undef $serort;
      undef $serverlag;
    }
    $i++;
  }
  
  $lasttitidx=$titidx;
  $lastautidx=$autidx;
  $lastmexidx=$mexidx;
  $lastkoridx=$koridx;
  $lastswtidx=$swtidx;
  
  #$lastseridx=$seridx;
  
  # Ausgabe der EXP-Dateien
  
  &ausgabetitfile;
  &ausgabeautfile;
  &ausgabemexfile;
  &ausgabeswtfile;
  &ausgabekorfile;
  #&ausgabeserfile;
  
  # Unterprogramme 
  
  $i++;
}

sub ausgabe
  {
    $i=0;
    while ($i < $lastidx)
      {
	if (length($reorgbuf[$i]) > 0)
	  {
	    print $reorgbuf[$i],"\n";
	  } 
	$i++;
      }
  }

sub ausgabetit
  {
    print "Titel Ausgabe erfolgt jetzt\n";
    $i=0;
    while ($i < $lasttitidx)
      {
	print $titbuffer[$i],"\n";
	$i++;
    }
}
sub ausgabeaut
{
    print "Autoren Ausgabe erfolgt jetzt\n";
    $i=0;
    while ($i < $lastautidx)
    {
	print $autbuffer[$i],"\n";
	$i++;
    }
}
sub ausgabemex
{
    print "Autoren Exemplardaten erfolgt jetzt\n";
    $i=0;
    while ($i < $lastmexidx)
    {
	print $mexbuffer[$i],"\n";
	$i++;
    }
}
sub ausgabekor
{
    print "Autoren Koerperschaften erfolgt jetzt\n";
    $i=0;
    while ($i < $lastkoridx)
    {
	print $korbuffer[$i],"\n";
	$i++;
    }
}
sub ausgabetitfile
{
    open (TIT,">"."tit.exp");
    $i=0;
    while ($i < $lasttitidx)
    {
	print TIT $titbuffer[$i],"\n";
	$i++;
    }
    close(TIT);
}
sub ausgabeserfile
{
    open (SER,">"."ser.exp");
    $i=0;
    while ($i < $lastseridx)
    {
	print TIT $serbuffer[$i],"\n";
	$i++;
    }
    close(SER);
}
sub ausgabeautfile
{
    open(AUT,">"."aut.exp");
    $i=0;
    while ($i < $lastautidx)
    {
	print AUT $autbuffer[$i],"\n";
	$i++;
    }
    close(AUT);
}
sub ausgabemexfile
{
    open(MEX,">"."mex.exp");
    $i=0;
    while ($i < $lastmexidx)
    {
	print MEX $mexbuffer[$i],"\n";
	$i++;
    }
    close(MEX);
}

sub ausgabeswtfile {
  open(SWT,">"."swt.exp");
  $i=0;
  while ($i < $lastswtidx) {
    print SWT $swtbuffer[$i],"\n";
    $i++;
  }
  close(SWT);
}

sub ausgabekorfile
{
    open(KOR,">"."kor.exp");
    $i=0;
    while ($i < $lastkoridx)
    {
	print KOR $korbuffer[$i],"\n";
	$i++;
    }
    close(KOR);
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

sub umlaute {
  my ($line)=@_;

  $line=~s/\[/#091/g;
  $line=~s/\]/#093/g;
  $line=~s//\}/g;
  $line=~s/„/\{/g;
  $line=~s/”/\|/g;
  $line=~s/š/\]/g;
  $line=~s/™/\\/g;
  $line=~s/Ž/\[/g;
  $line=~s//\#194E/g; # e aigu
  $line=~s/‚/\#194e/g;
  $line=~s/Š/\#193e/g; # grave
  $line=~s/“/\#195o/g; # circonflex
  $line=~s/…/\#193a/g;
  $line=~s/¢/\#194o/g;
  $line=~s/ƒ/\#195A/g;
  $line=~s/¡/\#194i/g;
  $line=~s/á/\~/g;
  $line=~s/_/¬/g;
  $line=~s/ª//g;

  # zuerst mit Space l"oschen

  $line=~s/\$a\$ //ig;
  $line=~s/\$b\$ //ig;
  $line=~s/\$c\$ //ig;
  $line=~s/\$d\$ //ig;

  # und dann den Rest ohne...

  $line=~s/\$a\$//ig;
  $line=~s/\$b\$//ig;
  $line=~s/\$c\$//ig;
  $line=~s/\$d\$//ig;

  return $line;
}

sub sonderzeichen {
#    $_=~s//ü/g; # ue
#    $_=~s/„/ä/g; # ae
#    $_=~s/”/ö/g; # oe
  $_=~s/\[/#091/g;
  $_=~s/\]/#093/g;

  $_=~s/ú/-:-/g;
  #    $_=~s/š/Ü/g; # Ue
#    $_=~s/™/Ö/g; # Oe
#    $_=~s/á/ß/g;  # sz
  $_=~s/õ/§/g; 
  #    $_=~s/Ž/Ä/g; # Ae
  $_=~s/#C#1#500\.//g;
  $_=~s//\; /g;
}

