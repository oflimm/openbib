#!/usr/bin/perl

#####################################################################
#
#  bcp2meta.pl
#
#  Aufloesung der mit bcp exportierten Blob-Daten in den Normdateien 
#  und Konvertierung in ein Metaformat.
#  Zusaetzlich werden die Daten in einem leicht modifizierten
#  Original-Format ausgegeben.
#
#  Routinen zum Aufloesen der Blobs (das intellektuelle Herz
#  des Programs):
#
#  Copyright 2003 Friedhelm Komossa
#                 <friedhelm.komossa@uni-muenster.de>
#
#  Programm, Konvertierungsroutinen in das Metaformat
#  und generelle Optimierung auf Bulk-Konvertierungen
#
#  Copyright 2003-2005 Oliver Flimm
#                      <flimm@openbib.org>
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

use Getopt::Long;

my $bcppath;

&GetOptions("bcp-path=s" => \$bcppath,
        );

# Konfiguration:

# Wo liegen die bcp-Dateien

$bcppath=($bcppath)?$bcppath:"/tmp";

# Problematische Kategorien in den Titeln:
#
# - 0220.001 Entspricht der Verweisform , die eigentlich zu den
#            Koerperschaften gehoert.
#

###
## Feldstrukturtabelle auswerten
#

open(FSTAB,"$bcppath/sik_fstab.bcp");
while (<FSTAB>){
  ($setnr,$fnr,$name,$kateg,$muss,$fldtyp,$mult,$invert,$stop,$zusatz,$multgr,$refnr,$vorbnr,$pruef,$knuepf,$trenn,$normueber,$bewahrenjn,$pool_cop,$indikator,$ind_bezeicher,$ind_indikator,$sysnr,$vocnr)=split("",$_);
  if ($setnr eq "1"){
    $KATEG[$fnr] = $kateg;
    $FLDTYP[$fnr] = $fldtyp;
    $REFNR[$fnr] = $refnr;
  }
}
close(FSTAB);

###
## Zweigstellen auswerten
#

my %zweigstelle = ();
open(ZWEIG,"bcppath/d50zweig.bcp");
while (<ZWEIG>){
  my ($zwnr,$zwname)=split("",$_);
  $zweigstelle{$zwnr}=$zwname;
}
close(ZWEIG);

###
## Abteilungen auswerten
#

my %abteilung = ();
open(ABT,"$bcppath/d60abteil.bcp");
while (<ABT>){
  my ($zwnr,$abtnr,$abtname)=split("",$_);
  $abteilung{$zwnr}{$abtnr}=$abtname;
}
close(ABT);

###
## Buchdaten auswerten
#

my %buchdaten = ();
open(D01BUCH,"$bcppath/d01buch.bcp");
while (<D01BUCH>){
    my @line = split("",$_);
    my ($d01gsi,$d01ex,$d01zweig,$d01katkey,$d01ort,$d01abtlg)=@line[0,1,2,7,24,31];
    #print "$d01gsi,$d01ex,$d01zweig,$d01katkey,$d01ort,$d01abtlg\n";
    push @{$buchdaten{$d01katkey}}, [$d01zweig,$d01ort,$d01abtlg]; 
}
close(D01BUCH);

###
## titel_exclude Daten auswerten
#

open(TEXCL,"$bcppath/titel_exclude.bcp");
while(<TEXCL>){
  ($junk,$titidn)=split("",$_);
  chomp($titidn);
  $titelexclude{"$titidn"}="excluded";
}
close(TEXCL);

###
## Normdateien einlesen
#

open(PER,"$bcppath/per_daten.bcp");
open(PERSIK,"|gzip > ./unload.PER.gz");
while (($katkey,$aktion,$reserv,$id,$ansetzung,$daten) = split ("",<PER>)){
  next if ($aktion ne "0");
  $BLOB = $daten;
  undef %SATZ;
  undef %SATZn;
  $j = length($BLOB);
  $outBLOB = pack "H$j", $BLOB;
  $j /= 2;
  $i = 0;
  while ( $i < $j ){
    $idup = $i*2;
    $fnr = sprintf "%04d", hex(substr($BLOB,$idup,4));
    $kateg = $KATEG[$fnr];
    $len = hex(substr($BLOB,$idup+4,4));
    if ( $len < 1000 ){
      # nicht multiples Feld
      $inh = substr($outBLOB,$i+4,$len);
      if ( substr($inh,0,1) eq " " ){
	$inh =~ s/^ //;
      }

      $KAT = sprintf "%04d", $kateg;
      $KATn = $autkonv{$KAT};
      if ($inh ne ""){
	$SATZn{$KATn} = $inh if ($KATn ne "");
	$SATZ{$KAT} = $inh;
      }
      $i = $i + 4 + $len;
    }
    else {
      # multiples Feld
      $mlen = 65536 - $len;
      $k = $i + 4;
      $ukat = 1;
      while ( $k < $i + 4 + $mlen ){
	$kdup = $k*2;
	$ulen = hex(substr($BLOB,$kdup,4));
	if ( $ulen > 0 ){
	  $inh = substr($outBLOB,$k+2,$ulen);
	  $uKAT = sprintf "%04d.%03d", $kateg, $ukat;
	  $uKATn = $autkonv{$uKAT};
	  if ( substr($inh,0,1) eq " " ){
	    $inh =~ s/^ //;
	  }
	  if ($inh ne ""){
	    $SATZn{$uKATn} = $inh if ($uKATn ne "");
	    $SATZ{$uKAT} = $inh;
	  }
	}
	$ukat++;
	$k = $k + 2 + $ulen;
      }
      $i = $i + 4 + $mlen;
    }
  }
  printf PERSIK "0000:%0d\n", $katkey;

  foreach $key (sort keys %SATZ){
    print PERSIK $key.":".konv($SATZ{$key})."\n" if ($SATZ{$key} !~ /idn:/);
  }

  print PERSIK "9999:\n\n";

}
close(PERSIK);
close(PER);

open(KOE,"$bcppath/koe_daten.bcp");
open(KOESIK,"| gzip >./unload.KOE.gz");
while (($katkey,$aktion,$reserv,$id,$ansetzung,$daten) = split ("",<KOE>)){
  next if ($aktion ne "0");
  $BLOB = $daten;
  undef %SATZ;
  undef %SATZn;
  $j = length($BLOB);
  $outBLOB = pack "H$j", $BLOB;
  $j /= 2;
  $i = 0;
  while ( $i < $j ){
    $idup = $i*2;
    $fnr = sprintf "%04d", hex(substr($BLOB,$idup,4));
    $kateg = $KATEG[$fnr];
    $len = hex(substr($BLOB,$idup+4,4));
    if ( $len < 1000 ){
      # nicht multiples Feld
      $inh = substr($outBLOB,$i+4,$len);
      if ( substr($inh,0,1) eq " " ){
	$inh =~ s/^ //;
      }

      $KAT = sprintf "%04d", $kateg;
      $KATn = $korkonv{$KAT};
      if ($inh ne ""){
	$SATZ{$KAT} = $inh;
	$SATZn{$KATn} = $inh if ($KATn ne "");
      }
      $i = $i + 4 + $len;
    }
    else {
      # multiples Feld
      $mlen = 65536 - $len;
      $k = $i + 4;
      $ukat = 1;
      while ( $k < $i + 4 + $mlen ){
	$kdup = $k*2;
	$ulen = hex(substr($BLOB,$kdup,4));
	if ( $ulen > 0 ){
	  $inh = substr($outBLOB,$k+2,$ulen);
	  $uKAT = sprintf "%04d.%03d", $kateg, $ukat;
	  $uKATn = $korkonv{$uKAT};
	  if ( substr($inh,0,1) eq " " ){
	    $inh =~ s/^ //;
	  }
	  if ($inh ne ""){
	    $SATZ{$uKAT} = $inh;
	    $SATZn{$uKATn} = $inh if ($uKATn ne "");
	  }
	}
	$ukat++;
	$k = $k + 2 + $ulen;
      }
      $i = $i + 4 + $mlen;
    }
  }
  printf KOESIK "0000:%0d\n", $katkey;

  foreach $key (sort {$b cmp $a} keys %SATZn){
    $outkey=$key;
    $outkey=~s/(\d\d\d\d)\.\d\d\d/$1/;

    # Sonderbehandlung und Aufloesung von 0111/850 inkl. Indikator

    my $konvinhalt=konv($SATZn{$key});
    if ($outkey eq "0111 "){
      if ($konvinhalt=~/^a/){
	$outkey="6130 ";
      }
      elsif ($konvinhalt=~/^b/){
	$outkey="6270 ";
      }
      elsif ($konvinhalt=~/^c/){
	$outkey="6133 ";
      }
      
      $konvinhalt=~s/^.//;
    }

  }

  foreach $key (sort {$b cmp $a} keys %SATZ){
    print KOESIK $key.":".konv($SATZ{$key})."\n" if ($SATZ{$key} !~ /idn:/);
  }

  print KOESIK "9999:\n\n";
}
close(KOESIK);
close(KOE);

open(SYS,"$bcppath/sys_daten.bcp");
open(SYSSIK,"| gzip >./unload.SYS.gz");
while (($katkey,$aktion,$reserv,$ansetzung,$daten) = split ("",<SYS>)){
  next if ($aktion ne "0");
  $BLOB = $daten;
  undef %SATZ;
  undef %SATZn;
  $j = length($BLOB);
  $outBLOB = pack "H$j", $BLOB;
  $j /= 2;
  $i = 0;
  while ( $i < $j ){
    $idup = $i*2;
    $fnr = sprintf "%04d", hex(substr($BLOB,$idup,4));
    $kateg = $KATEG[$fnr];
    $len = hex(substr($BLOB,$idup+4,4));
    if ( $len < 1000 ){
      # nicht multiples Feld
      $inh = substr($outBLOB,$i+4,$len);
      if ( substr($inh,0,1) eq " " ){
	$inh =~ s/^ //;
      }

      $KAT = sprintf "%04d", $kateg;
      $KATn = $notkonv{$KAT};
      if ($inh ne ""){
	$SATZ{$KAT} = $inh;
	$SATZn{$KATn} = $inh if ($KATn ne "");
      }
      $i = $i + 4 + $len;
    }
    else {
      # multiples Feld
      $mlen = 65536 - $len;
      $k = $i + 4;
      $ukat = 1;
      while ( $k < $i + 4 + $mlen ){
	$kdup = $k*2;
	$ulen = hex(substr($BLOB,$kdup,4));
	if ( $ulen > 0 ){
	  $inh = substr($outBLOB,$k+2,$ulen);
	  $uKAT = sprintf "%04d.%03d", $kateg, $ukat;
	  $uKATn = $notkonv{$uKAT};
	  if ( substr($inh,0,1) eq " " ){
	    $inh =~ s/^ //;
	  }
	  if ($inh ne ""){
	    $SATZ{$uKAT} = $inh;
	    $SATZn{$uKATn} = $inh if ($uKATn ne "");
	  }
	}
	$ukat++;
	$k = $k + 2 + $ulen;
      }
      $i = $i + 4 + $mlen;
    }
  }

  printf SYSSIK "0000:%0d\n", $katkey;

  foreach $key (sort keys %SATZ){
    print SYSSIK $key.":".konv($SATZ{$key})."\n" if ($SATZ{$key} !~ /idn:/);
  }
  print SYSSIK "9999:\n\n";
}
close(SYSSIK);
close(SYS);

open(SWD,"$bcppath/swd_daten.bcp");
open(SWDSIK,"| gzip >./unload.SWD.gz");
while (($katkey,$aktion,$reserv,$id,$ansetzung,$daten) = split ("",<SWD>)){
  next if ($aktion ne "0");
  $BLOB = $daten;
  undef %SATZ;
  undef %SATZn;
  $j = length($BLOB);
  $outBLOB = pack "H$j", $BLOB;
  $j /= 2;
  $i = 0;
  while ( $i < $j ){
    $idup = $i*2;
    $fnr = sprintf "%04d", hex(substr($BLOB,$idup,4));
    $kateg = $KATEG[$fnr];
    $len = hex(substr($BLOB,$idup+4,4));
    if ( $len < 1000 ){
      # nicht multiples Feld
      $inh = substr($outBLOB,$i+4,$len);
      $inh=~s///g;
      if ( substr($inh,0,1) eq " " ){
	$inh =~ s/^ //;
      }

      $KAT = sprintf "%04d", $kateg;
      $KATn = $swtkonv{$KAT};
      if ($inh ne ""){
	$SATZ{$KAT} = $inh;
	$SATZn{$KATn} = $inh if ($KATn ne "");
      }
      $i = $i + 4 + $len;
    }
    else {
      # multiples Feld
      $mlen = 65536 - $len;
      $k = $i + 4;
      $ukat = 1;
      while ( $k < $i + 4 + $mlen ){
	$kdup = $k*2;
	$ulen = hex(substr($BLOB,$kdup,4));
	if ( $ulen > 0 ){
	  $inh = substr($outBLOB,$k+2,$ulen);
	  $inh=~s///g;
	  $uKAT = sprintf "%04d.%03d", $kateg, $ukat;
	  $uKATn = $swtkonv{$uKAT};
	  if ( substr($inh,0,1) eq " " ){
	    $inh =~ s/^ //;
	  }
	  if ($inh ne ""){
	    $SATZ{$uKAT} = $inh;
	    $SATZn{$uKATn} = $inh if ($uKATn ne "");
	  }
	}
	$ukat++;
	$k = $k + 2 + $ulen;
      }
      $i = $i + 4 + $mlen;
    }
  }

  printf SWDSIK "0000:%0d\n", $katkey;


  # Zuerst die Schlagwortkette bzw. das Einzelschlagwort ausgeben

  @swtkette=();
  foreach $key (sort {$b cmp $a} keys %SATZn){
    if ($key =~/^6510/){
       $SATZn{$key}=~s/^[a-z]([A-Z0-9])/$1/;
#      $SATZn{$key}=~s/^[a-z]//;
      push @swtkette, konv($SATZn{$key});
    }
  }

  if ($#swtkette > 0){
    $schlagw=join (" / ",reverse @swtkette);

  }
  else {
    $schlagw=$swtkette[0];
  }

  foreach $key (sort {$b cmp $a} keys %SATZ){
    print SWDSIK $key.":".konv($SATZ{$key})."\n" if ($SATZ{$key} !~ /idn:/);
  }


  print SWDSIK "9999:\n\n";
}
close(SWDSIK);
close(SWD);

open(TITEL,"$bcppath/titel_daten.bcp");
open(TITSIK,"| gzip >./unload.TIT.gz");
open(MEXSIK,"| gzip >./unload.MEX.gz");

binmode(TITSIK, ":utf8");
binmode(MEXSIK, ":utf8");

my $mexid           = 1;

while (($katkey,$aktion,$fcopy,$reserv,$vsias,$vsiera,$vopac,$daten) = split ("",<TITEL>)){
  next if ($aktion ne "0");
  next if ($titelexclude{"$katkey"} eq "excluded");

  $BLOB = $daten;
  undef %SATZ;
  $j = length($BLOB);
  $outBLOB = pack "H$j", $BLOB;
  $j /= 2;
  $i = 0;
  while ( $i < $j ){
    $idup = $i*2;
    $fnr = sprintf "%04d", hex(substr($BLOB,$idup,4));
    $kateg = $KATEG[$fnr];
    $len = hex(substr($BLOB,$idup+4,4));
    if ( $len < 1000 ){
      # nicht multiples Feld
      $inh = substr($outBLOB,$i+4,$len);
      if ( $FLDTYP[$fnr] eq "V" ){
	$inh = hex(substr($BLOB,$idup+8,8));
	$inh="IDN: $inh";
      }
      if ( substr($inh,0,1) eq " " ){
	$inh =~ s/^ //;
      }

      $KAT = sprintf "%04d", $kateg;
      $SATZ{$KAT} = $inh;
      $i = $i + 4 + $len;
    }
    else {
      # multiples Feld
      $mlen = 65536 - $len;
      $k = $i + 4;
      $ukat = 1;
      while ( $k < $i + 4 + $mlen ){
	$kdup = $k*2;
	$ulen = hex(substr($BLOB,$kdup,4));
	if ( $ulen > 0 ){
	  $inh = substr($outBLOB,$k+2,$ulen);
	  if ( $FLDTYP[$fnr] eq "V" ){
             $verwnr = hex(substr($BLOB,$kdup+4,8));
	     my $zusatz="";
             if ($ulen > 4){
                $zusatz=substr($inh,4,$ulen);
                $inh="IDN: $verwnr ;$zusatz";
             }
             else {
                $inh="IDN: $verwnr";
             }
	  }
	  $uKAT = sprintf "%04d.%03d", $kateg, $ukat;
	  if ( substr($inh,0,1) eq " " ){
	    $inh =~ s/^ //;
	  }
	  if ($inh ne ""){
	    $SATZ{$uKAT} = $inh;
	  }
	}
	$ukat++;
	$k = $k + 2 + $ulen;
      }
      $i = $i + 4 + $mlen;
    }
  }

  $treffer="";
  $active=0;
  $verwcount=0;
  $verkncount=0;
  $idx=0;
  my @fussnbuf=();


  printf TITSIK "0000:%0d\n", $katkey;

  foreach $key (sort keys %SATZ){
    if ($key !~/^0000/){
      $newkat=$titkonv{$key};
      $newkat=~s/^(\d\d\d\d)\.\d\d\d/$1/;

      print TITSIK $key.":".konv($SATZ{$key})."\n" if ($SATZ{$key} !~ /idn:/);
      # 1:1 Konvertierungen

      if ($newkat ne ""){
	$line=$newkat.konv($SATZ{$key});

	if ($line=~/^SDN  (\d\d)\.(\d\d)\.(\d\d\d\d)/) {
	  $line="SDN  $3$2$1";
	}

	if ($line=~/^SDU  (\d\d)\.(\d\d)\.(\d\d\d\d)/) {
	  $line="SDU  $3$2$1";
	}
      }

      # Kompliziertere Konvertierungen

      else {
	$line=$key.":".konv($SATZ{$key});

	if ($line=~/^0501\.(...):(.*)$/) {
	  my $fussn=$2;
	  $fussn=~s/\n//;
	  push @fussnbuf, $fussn;
	}

	if ($line=~/^0004\.(...):(\d+)/) {
	  $verwidn[$1-1][0]=$2;
	  $verwcount++;
	}
      
        if ($line=~/^0451\.(\d\d\d):(.+?)$/) {
	  $position=int($1/4);
	  $verwidn[$position][2]=$2;

	  my ($bandinfo)=$2=~/^.* ; (.+?)$/;

	  $bandinfo=~s///g;

	  $verwidn[$position][3]=$bandinfo;
	  $verwidn[$position][1]=4;

	  
	  if ($position > $maxpos){
	    $maxpos=$position+1;
	  }
	  
	  $verkncount++;
	}
	
	if ($line=~/^0455\.(\d\d\d):(.+?)$/) {
	  $position=int($1/4);

	  if ($verwidn[$position][3] eq ""){
	    $verwidn[$position][3]="$2";
	    
	    if ($position > $maxpos){
	      $maxpos=$position+1;
	    }
	  }
	}

	if ($line=~/^0089\.001:(.+?)$/) {
	  $bandangvorl=$1;
	}

	if ($line=~/^0590\....:(.+)/) {
	  my $inhalt=$1;
	  my $restinhalt="";

	  # Wenn 590 besetzt ist, dann handelt es sich um einen
	  # Aufsatz und 451er werden gar nicht ausgewertet. Eine
	  # 004 wird dann immer mit der 590 assoziiert.

	  # Daher erst einmal eine etwaige Verknuepfung sichern

	  my $verknidn=$verwidn[0][0];

	  # Dann alle bestehenden (falschen) Verknuepfungen loeschen

	  @verwidn=();

	  # und wieder eintragen

	  $verwidn[0][0]=$verknidn;

	  if ($verwidn[0][0]){
	    if ($inhalt=~/^.*?[.:\/;](.+)$/){
	      $zusatz=$1;
	    }
	    else {
	      $zusatz="...\n";
	    }


	    $verwidn[0][1]="5";
	    $verwidn[0][2]="";
	    $verwidn[0][3]="$zusatz";
	  }
	  else {

	    print STDERR "590NORMAL - $inhalt\n";

	    $verwidn[0][0]="";
	    $verwidn[0][1]="5";
	    $verwidn[0][2]="$inhalt";
	    $verwidn[0][3]="";
	  }
#	  $maxpos++;
	}

	# Anfang: Exemplardaten fuer Zeitschriften ZDB-Aufnahme
	
	# Grundsignatur ZDB-Aufnahme
	if ($line=~/^1204\.(\d\d\d):(.*$)/){
	  $zaehlung=$1;
          $inhalt=$2;
          $signaturbuf{$zaehlung}=$inhalt;
          if ($maxmex <= $zaehlung) {
	    $maxmex=$zaehlung;
	  }
        }

        if ($line=~/^1201\.(\d\d\d):(.*$)/){
      	  $zaehlung=$1;
      	  $inhalt=$2;
       	  $erschverlbufpos{$zaehlung}=$inhalt;
       	  if ($maxmex <= $zaehlung) {
       	    $maxmex=$zaehlung;
       	  }
       	}

        if ($line=~/^1202\.(\d\d\d):(.*$)/){
      	  $zaehlung=$1;
      	  $inhalt=$2;
       	  $erschverlbufneg{$zaehlung}=$inhalt;
       	  if ($maxmex <= $zaehlung) {
       	    $maxmex=$zaehlung;
       	  }
       	}

        if ($line=~/^0012\.(\d\d\d):(.*$)/){
          $zaehlung=$1;
          $inhalt=$2;
          $besbibbuf{$zaehlung}=$inhalt;
	  if ($maxmex <= $zaehlung) {
             $maxmex=$zaehlung
	  }
	}
	# Ende: Exemplardaten fuer Zeitschriften ZDB-Aufnahme
      }
    }
  } # Ende foreach

  # 089er verwenden, wenn genau eine 004 besetzt, aber keine 455/590

  if ($bandangvorl && $maxpos < 1 && $verwidn[0][3] eq ""){
    $verwidn[0][3]=$bandangvorl;
  }

  # Exemplardaten abarbeiten Anfang

  # Wenn ZDB-Aufnahmen gefunden wurden, dann diese Ausgeben
  if ($maxmex && !exists $buchdaten{$katkey}){
      my $k=1;
      while ($k <= $maxmex) {	  
	  $key=sprintf "%03d",$k;
	  
	  $signatur=$signaturbuf{$key};
	  $standort=$standortbuf{$key};
	  $inventar=$inventarbuf{$key};
	  $sigel=$besbibbuf{$key};
	  $sigel=~s!^38/!!;
	  $erschverl=$erschverlbufpos{$key};
	  $erschverl.=" ".$erschverlbufneg{$key} if (exists $erschverlbufneg{$key});

	  print MEXSIK "0000:$mexid\n";
	  print MEXSIK "0004:$katkey\n";
	  print MEXSIK "0014:$signatur\n"  if ($signatur);
	  print MEXSIK "1204:$erschverl\n" if ($erschverl);
	  print MEXSIK "3330:$sigel\n"     if ($sigel);
	  print MEXSIK "9999:\n";
	  
	  $mexid++;
	  $k++;
      }
  }
  elsif (exists $buchdaten{$katkey}){
      foreach my $buchsatz_ref (@{$buchdaten{$katkey}}){
	  $signatur=$buchsatz_ref->[1];
	  $standort=$zweigstelle{$buchsatz_ref->[0]}." / ".$abteilung{$buchsatz_ref->[0]}{$buchsatz_ref->[2]};
	  chomp($standort);

	  print MEXSIK "0000:$mexid\n";
	  print MEXSIK "0004:$katkey\n";
	  print MEXSIK "0014:$signatur\n"  if ($signatur);
	  print MEXSIK "0016:$standort\n"  if ($standort);
	  print MEXSIK "9999:\n";      
	  $mexid++;
      }
  }
   
   # Exemplardaten abarbeiten Ende

   # Sonstiges abarbeiten Anfang

   # Sonstiges abarbeiten Ende


  print TITSIK "9999:\n\n";

      
  @verwidn=();
  %inventarbuf=();
  %signaturbuf=();
  %standortbuf=();
  %besbibbuf=();
  %erschverlbuf=();
  undef $inventar;
  undef $maxmex;
  undef $maxpos;
  undef $bandangvorl;

} # Ende einzelner Satz in while

close(TITSIK);
close(TITEL);
close(MEXSIK);

#######################################################################
########################################################################

sub konv {
  my ($line)=@_;

  $line=~s/\&/&amp;/g;
  $line=~s/>/&gt;/g;
  $line=~s/</&lt;/g;

  return $line;
}
