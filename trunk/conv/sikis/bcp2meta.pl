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

# Konfiguration:

# Wo liegen die bcp-Dateien

my $bcppath="/tmp";

# 1:1 Konvertierungen bei den Verfassern/Personen

my %autkonv=(
	     "0001","6020 ",
	     "0100","SDN  ",
	     "0101","SDU  ",
	     "0102.001","6021.001 ",
	     "0102.002","6021.002 ",
	     "0102.003","6021.003 ",
	     "0102.004","6021.004 ",
	     "0102.005","6021.005 ",
	     "0102.006","6021.006 ",
	     "0102.007","6021.007 ",
	     "0102.008","6021.008 ",
	     "0102.009","6021.009 ",
	     "0102.010","6021.010 ",
	    );

# 1:1 Konvertierungen bei den Koerperschaften/Urhebern

my %korkonv=(
	     "0001","6120 ",
	     "0100","SDN  ",
	     "0101","SDU  ",
	     "0102.001","6121.001 ",
	     "0102.002","6121.002 ",
	     "0102.003","6121.003 ",
	     "0102.004","6121.004 ",
	     "0102.005","6121.005 ",
	     "0102.006","6121.006 ",
	     "0102.007","6121.007 ",
	     "0102.008","6121.008 ",
	     "0102.009","6121.009 ",
	     "0102.010","6121.010 ",
	     "0111.001","0111.001 ",
	     "0111.002","0111.002 ",
	     "0111.003","0111.003 ",
	     "0111.004","0111.004 ",
	     "0111.005","0111.005 ",
	    );

# 1:1 Konvertierungen bei den Notationen

my %notkonv=(
	     "0001","8000 ",
	     "0002","8015 ",
	     "0100","SDN  ",
	     "0101","SDU  ",
	     "0103.001","8040.001 ",
	     "0103.002","8040.002 ",
	     "0103.003","8040.003 ",
	     "0103.004","8040.004 ",
	     "0103.005","8040.005 ",
	    );

# 1:1 Konvertierungen bei den Schlagworten

my %swtkonv=(
	     "0001.001","6510.001 ",
	     "0001.002","6510.002 ",
	     "0001.003","6510.003 ",
	     "0001.004","6510.004 ",
	     "0001.005","6510.005 ",
	     "0001.006","6510.006 ",
	     "0102.001","6520.001 ",
	     "0102.002","6520.002 ",
	     "0102.003","6520.003 ",
	     "0102.004","6520.004 ",
	     "0102.005","6520.005 ",
	     "0102.006","6520.006 ",
	     "0102.007","6520.007 ",
	     "0102.008","6520.008 ",
	     "0102.009","6520.009 ",
	     "0102.010","6520.010 ",
             "0113.001","6550.001 ",
             "0113.002","6550.002 ",
             "0113.003","6550.003 ",
             "0113.004","6550.004 ",
             "0113.005","6550.005 ",
             "0115.001","6560.001 ",
             "0115.002","6560.002 ",
             "0115.003","6560.003 ",
             "0115.004","6560.004 ",
             "0115.005","6560.005 ",
             "0117.001","6570.001 ",
             "0117.002","6570.002 ",
             "0117.003","6570.003 ",
             "0117.004","6570.004 ",
             "0117.005","6570.005 ",
             "0119.001","6572.001 ",
             "0119.002","6572.002 ",
             "0119.003","6572.003 ",
             "0119.004","6572.004 ",
             "0119.005","6572.005 ",
	     "0100","SDN  ",
	     "0101","SDU  ",
	    );

# 1:1 Konvertierungen bei den Titeln

%titkonv=(
#	   "0000" => "IDN  ", # IDN
	   "0002" => "SDN  ", # SDN
	   "0003" => "SDU  ", # SDU
#	   "0016" => "7600 ", # Standort
	   "0026.001" => "4700.001 ", # NE/R
	   "0026.002" => "4700.002 ", # NE/R
	   "0026.003" => "4700.003 ", # NE/R
	   "0026.004" => "4700.004 ", # NE/R
	   "0026.005" => "4700.005 ", # NE/R
	   "0100.001" => "2000.001 ", # Verfasser
	   "0100.002" => "2000.002 ", # Verfasser
	   "0100.003" => "2000.003 ", # Verfasser
	   "0100.004" => "2000.004 ", # Verfasser
	   "0100.005" => "2000.005 ", # Verfasser
	   "0101.001" => "2003.001 ", # Person
	   "0101.002" => "2003.002 ", # Person
	   "0101.003" => "2003.003 ", # Person
	   "0101.004" => "2003.004 ", # Person
	   "0101.005" => "2003.005 ", # Person
	   "0101.006" => "2003.006 ", # Person
	   "0101.007" => "2003.007 ", # Person
	   "0101.008" => "2003.008 ", # Person
	   "0101.009" => "2003.009 ", # Person
	   "0101.010" => "2003.010 ", # Person
	   "0103.001" => "2004.001 ", # Gefeierte Person
	   "0103.002" => "2004.002 ", # Gefeierte Person
	   "0103.003" => "2004.003 ", # Gefeierte Person
#	   "0150" => "     ", # ???
#	   "0151" => "     ", # ???
#	   "0153" => "     ", # ???
	   "0200.001" => "2400.001 ", # Urheber
	   "0200.002" => "2400.002 ", # Urheber
	   "0200.003" => "2400.003 ", # Urheber
	   "0200.004" => "2400.004 ", # Urheber
	   "0200.005" => "2400.005 ", # Urheber
	   "0201.001" => "2403.001 ", # Koerperschaft
	   "0201.002" => "2403.002 ", # Koerperschaft
	   "0201.003" => "2403.003 ", # Koerperschaft
	   "0201.004" => "2403.004 ", # Koerperschaft
	   "0201.005" => "2403.005 ", # Koerperschaft
	   "0300.001" => "8060.001 ", # Sammlungsvermerk
	   "0300.002" => "8060.002 ", # Sammlungsvermerk
	   "0300.003" => "8060.003 ", # Sammlungsvermerk
	   "0300.004" => "8060.004 ", # Sammlungsvermerk
	   "0300.005" => "8060.005 ", # Sammlungsvermerk
	   "0304.001" => "4300 ", # EST
	   "0310.001" => "2900 ", # AST
	   "0331.001" => "3000 ", # HST
	   "0331.002" => "3000 ", # HST
	   "0331.003" => "3000 ", # HST
	   "0333.001" => "3030 ", # zu erg. Urheber/HST Urheber
	   "0335.001" => "3040 ", # Zusatz zum HST
	   "0341.001" => "3100 ", # PSTVorlage
	   "0341.002" => "3100 ", # PSTVorlage
	   "0341.003" => "3100 ", # PSTVorlage
	   "0341.004" => "3100 ", # PSTVorlage
	   "0341.005" => "3100 ", # PSTVorlage
	   "0341.006" => "3100 ", # PSTVorlage
	   "0341.007" => "3100 ", # PSTVorlage
	   "0341.008" => "3100 ", # PSTVorlage
	   "0341.009" => "3100 ", # PSTVorlage
	   "0341.010" => "3100 ", # PSTVorlage
	   "0341.011" => "3100 ", # PSTVorlage
	   "0341.012" => "3100 ", # PSTVorlage
	   "0359.001" => "3500 ", # Vorlage Verf/Koerpersch.
	   "0360.001" => "3600 ", # Reihe_Beil
	   "0361.001" => "3615 ", # BeigefWerk
	   "0361.002" => "3615 ", # BeigefWerk
	   "0361.003" => "3615 ", # BeigefWerk
	   "0361.004" => "3615 ", # BeigefWerk
	   "0361.005" => "3615 ", # BeigefWerk
           "0370.001" => "2700.001 ", # WST 
           "0370.002" => "2700.002 ", # WST 
           "0370.003" => "2700.003 ", # WST 
           "0370.004" => "2700.004 ", # WST
           "0370.005" => "2700.005 ", # WST
           "0370.006" => "2700.006 ", # WST
           "0370.007" => "2700.007 ", # WST
           "0370.008" => "2700.008 ", # WST
           "0370.009" => "2700.009 ", # WST
           "0370.010" => "2700.010 ", # WST
	   "0403.001" => "3700 ", # Auflage
	   "0405.001" => "8090 ", # Erscheinungsverlauf
	   "0410.001" => "4000 ", # Verlagsort
	   "0412.001" => "4002 ", # Verlag
	   "0424.001" => "8070 ", # EJAnsetz
	   "0425.001" => "4040 ", # Ersch.Jahr
	   "0433.001" => "4102 ", # Kollat.
	   "0434.001" => "8100.001 ", # Ill_Angabe
	   "0434.002" => "8100.002 ", # Ill_Angabe
	   "0434.003" => "8100.003 ", # Ill_Angabe
	   "0434.004" => "8100.004 ", # Ill_Angabe
	   "0434.005" => "8100.005 ", # Ill_Angabe
#	   "0435" => "     ", # Format

#	   "0451" => "4200 ", # GesTitVorl (Sonderbehandlung, s.u.)
#	   "0453" => "4200 ", # GesTit_ID (Sonderbehandlung, s.u.)
#	   "0454" => "4200 ", # GTAnsetz (Sonderbehandlung, s.u.)
#	   "0455" => "4200 ", # BdAngVorl (Sonderbehandlung, s.u.)

	   #"0501.001" => "4400 ", # Fussnoten
	   "0507.001" => "8080 ", # AngabenHST
#	   "0511" => "     ", # ErschVermF
	   "0519.001" => "4500 ", # HSSVermerk
	   "0523.001" => "8090 ", # Erscheinungsverlauf 2.
	   "0527.001" => "8081.001  ", # ParallAusg.
	   "0527.002" => "8081.002  ", # ParallAusg.
	   "0527.003" => "8081.003  ", # ParallAusg.
	   "0527.004" => "8081.004  ", # ParallAusg.
	   "0527.005" => "8081.005  ", # ParallAusg.

	   "0529.001" => "8082.001  ", # TitBeilage
	   "0529.002" => "8082.002  ", # TitBeilage
	   "0529.003" => "8082.003  ", # TitBeilage
	   "0529.004" => "8082.004  ", # TitBeilage
	   "0529.005" => "8082.005  ", # Titbeilage

	   "0530.001" => "8083.001  ", # Bezugswerk
	   "0530.002" => "8083.002  ", # Bezugswerk
	   "0530.003" => "8083.003  ", # Bezugswerk
	   "0530.004" => "8083.004  ", # Bezugswerk
	   "0530.005" => "8083.005  ", # Bezugswerk

	   "0531.001" => "8084.001  ", # FruehAusg
	   "0531.002" => "8084.002  ", # FruehAusg
	   "0531.003" => "8084.003  ", # FruehAusg
	   "0531.004" => "8084.004  ", # FruehAusg
	   "0531.005" => "8084.005  ", # FruehAusg

	   "0532.001" => "8085.001  ", # FruehTit
	   "0532.002" => "8085.002  ", # FruehTit
	   "0532.003" => "8085.003  ", # FruehTit
	   "0532.004" => "8085.004  ", # FruehTit
	   "0532.005" => "8085.005  ", # FruehTit

	   "0533.001" => "8086.001  ", # SpaetAusg
	   "0533.002" => "8086.002  ", # SpaetAusg
	   "0533.003" => "8086.003  ", # SpaetAusg
	   "0533.004" => "8086.004  ", # SpaetAusg
	   "0533.005" => "8086.005  ", # SpaetAusg

	   "0540.001" => "4600.001 ", # ISBN
	   "0540.002" => "4600.002 ", # ISBN
	   "0540.003" => "4600.003 ", # ISBN
	   "0540.004" => "4600.004 ", # ISBN
	   "0540.005" => "4600.005 ", # ISBN
#	   "0541" => "     ", # ISBNfalsch
#	   "0542" => "     ", # ISBN P_E
	   "0543.001" => "4650.001 ", # ISSN
	   "0543.002" => "4650.002 ", # ISSN
	   "0543.003" => "4650.003 ", # ISSN
	   "0543.004" => "4650.004 ", # ISSN
	   "0543.005" => "4650.005 ", # ISSN
#	   "0568" => "     ", # CIP_Aufn
#	   "0590" => "     ", # HSTQuelle (Sonderbehandlung, s.u.)
	   "0591.001" => "8110 ", # VerfQuelle
	   "0594.001" => "8111 ", # EOrtQuelle
	   "0595.001" => "8112 ", # EJahrQuelle
	   "0662.001" => "8050 ", # EDVurl
	   "0662.002" => "8050 ", # EDVurl
	   "0662.003" => "8050 ", # EDVurl
	   "0662.004" => "8050 ", # EDVurl
	   "0662.005" => "8050 ", # EDVurl
	   "0600.001" => "4270 ", # Bemerkung
	   "0700.001" => "5700.001 ", # Notation
	   "0700.002" => "5700.002 ", # Notation
	   "0700.003" => "5700.003 ", # Notation
	   "0700.004" => "5700.004 ", # Notation
	   "0700.005" => "5700.005 ", # Notation
	   "0700.006" => "5700.006 ", # Notation
	   "0700.007" => "5700.007 ", # Notation
	   "0700.008" => "5700.008 ", # Notation
	   "0700.009" => "5700.009 ", # Notation
	   "0700.010" => "5700.010 ", # Notation
	   "0710.001" => "5650.001 ", # Schlagwort
	   "0710.002" => "5650.002 ", # Schlagwort
	   "0710.003" => "5650.003 ", # Schlagwort
	   "0710.004" => "5650.004 ", # Schlagwort
	   "0710.005" => "5650.005 ", # Schlagwort
	   "0710.006" => "5650.006 ", # Schlagwort
	   "0710.007" => "5650.007 ", # Schlagwort
	   "0710.008" => "5650.008 ", # Schlagwort
	   "0710.009" => "5650.009 ", # Schlagwort
	   "0710.010" => "5650.010 ", # Schlagwort
	   "0710.011" => "5650.011 ", # Schlagwort
	   "0710.012" => "5650.012 ", # Schlagwort
	   "0710.013" => "5650.013 ", # Schlagwort
	   "0710.014" => "5650.014 ", # Schlagwort
	   "0710.015" => "5650.015 ", # Schlagwort
	   "0710.016" => "5650.016 ", # Schlagwort
	   "0710.017" => "5650.017 ", # Schlagwort
	   "0710.018" => "5650.018 ", # Schlagwort
	   "0710.019" => "5650.019 ", # Schlagwort
	   "0710.150" => "5650.200 ", # Schlagwort
	   "0710.151" => "5650.201 ", # Schlagwort
	   "0710.152" => "5650.202 ", # Schlagwort
	   "0710.153" => "5650.203 ", # Schlagwort
	   "0710.154" => "5650.204 ", # Schlagwort
	   "0710.155" => "5650.205 ", # Schlagwort
	   "0710.156" => "5650.206 ", # Schlagwort
	   "0710.157" => "5650.207 ", # Schlagwort
	   "0710.158" => "5650.208 ", # Schlagwort
	   "0710.159" => "5650.209 ", # Schlagwort
	   "0750.001" => "9000.001 ", # Abstract
	   "0750.002" => "9000.002 ", # Abstract
	   "0750.003" => "9000.003 ", # Abstract
	   "0750.004" => "9000.004 ", # Abstract
	   "0750.005" => "9000.005 ", # Abstract
	   "0800.001" => "5260 ", # Art/Inhalt MedienArt
	   "0800.002" => "5260 ", # Art/Inhalt MedienArt
	   "0800.003" => "5260 ", # Art/Inhalt MedienArt
	   "0800.004" => "5260 ", # Art/Inhalt MedienArt
	   "0800.005" => "5260 ", # Art/Inhalt MedienArt
	   "0902.001" => "5650.101 ", # Schlagwort
	   "0902.002" => "5650.102 ", # Schlagwort
	   "0902.003" => "5650.103 ", # Schlagwort
	   "0902.004" => "5650.104 ", # Schlagwort
	   "0902.005" => "5650.105 ", # Schlagwort
	   "0907.001" => "5650.111 ", # Schlagwort
	   "0907.002" => "5650.112 ", # Schlagwort
	   "0907.003" => "5650.113 ", # Schlagwort
	   "0907.004" => "5650.114 ", # Schlagwort
	   "0907.005" => "5650.115 ", # Schlagwort
	   "0912.001" => "5650.121 ", # Schlagwort
	   "0912.002" => "5650.122 ", # Schlagwort
	   "0912.003" => "5650.123 ", # Schlagwort
	   "0912.004" => "5650.124 ", # Schlagwort
	   "0912.005" => "5650.125 ", # Schlagwort
	   "0917.001" => "5650.131 ", # Schlagwort
	   "0917.002" => "5650.132 ", # Schlagwort
	   "0917.003" => "5650.133 ", # Schlagwort
	   "0917.004" => "5650.134 ", # Schlagwort
	   "0917.005" => "5650.135 ", # Schlagwort
	   "0922.001" => "5650.141 ", # Schlagwort
	   "0922.002" => "5650.142 ", # Schlagwort
	   "0922.003" => "5650.143 ", # Schlagwort
	   "0922.004" => "5650.144 ", # Schlagwort
	   "0922.005" => "5650.145 ", # Schlagwort
	   "0927.001" => "5650.151 ", # Schlagwort
	   "0927.002" => "5650.152 ", # Schlagwort
	   "0927.003" => "5650.153 ", # Schlagwort
	   "0927.004" => "5650.154 ", # Schlagwort
	   "0927.005" => "5650.155 ", # Schlagwort
	   "0932.001" => "5650.161 ", # Schlagwort
	   "0932.002" => "5650.162 ", # Schlagwort
	   "0932.003" => "5650.163 ", # Schlagwort
	   "0932.004" => "5650.164 ", # Schlagwort
	   "0932.005" => "5650.165 ", # Schlagwort
	   "0937.001" => "5650.171 ", # Schlagwort
	   "0937.002" => "5650.172 ", # Schlagwort
	   "0937.003" => "5650.173 ", # Schlagwort
	   "0937.004" => "5650.174 ", # Schlagwort
	   "0937.005" => "5650.175 ", # Schlagwort
	   "0942.001" => "5650.181 ", # Schlagwort
	   "0942.002" => "5650.182 ", # Schlagwort
	   "0942.003" => "5650.183 ", # Schlagwort
	   "0942.004" => "5650.184 ", # Schlagwort
	   "0942.005" => "5650.185 ", # Schlagwort
	   "0947.001" => "5650.191 ", # Schlagwort
	   "0947.002" => "5650.192 ", # Schlagwort
	   "0947.003" => "5650.193 ", # Schlagwort
	   "0947.004" => "5650.194 ", # Schlagwort
	   "0947.005" => "5650.195 ", # Schlagwort
#	   "0800" => "     ", # Medienart
	  );

# Problematische Kategorien in den Titeln:
#
# - 0220.001 Entspricht der Verweisform , die eigentlich zu den
#            Koerperschaften gehoert.
#
# - Die Verknuepfungsnummer in 0004.00x korreliert nicht 
#   notwendigerweise mit den 451'ern und 455'ern. Damit 
#   koennen die 455'er zu den falschen 0004.00x zugeordnet werden.
#   Das Problem kann nur bei mehr als einer Verknuepfung auftreten

$mexidn=1;

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
open(AUT,"|gzip >./aut.exp.gz");
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
  printf AUT "IDN  %0d\n", $katkey;
  printf PERSIK "0000:%0d\n", $katkey;

  foreach $key (sort {$b cmp $a} keys %SATZn){
    $outkey=$key;
    $outkey=~s/(\d\d\d\d)\.\d\d\d/$1/;
    printf AUT $outkey.konv($SATZn{$key})."\n" if ($SATZn{$key} !~ /idn:/);
  }


  foreach $key (sort keys %SATZ){
    printf PERSIK $key.":".konv($SATZ{$key})."\n" if ($SATZ{$key} !~ /idn:/);
  }

  printf PERSIK "9999:\n\n";
  print AUT "ENDE\n";

}
close(AUT);
close(PERSIK);
close(PER);

open(KOE,"$bcppath/koe_daten.bcp");
open(KOR,"| gzip >./kor.exp.gz");
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
  printf KOR "IDN  %0d\n", $katkey;
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

    printf KOR $outkey.$konvinhalt."\n" if ($SATZn{$key} !~ /idn:/);
  }

  foreach $key (sort {$b cmp $a} keys %SATZ){
    printf KOESIK $key.":".konv($SATZ{$key})."\n" if ($SATZ{$key} !~ /idn:/);
  }

  print KOESIK "9999:\n\n";
  print KOR "ENDE\n";


}
close(KOR);
close(KOESIK);
close(KOE);

open(SYS,"$bcppath/sys_daten.bcp");
open(NOTA,"| gzip >./not.exp.gz");
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

  printf NOTA "IDN  %0d\n", $katkey;
  printf SYSSIK "0000:%0d\n", $katkey;

  foreach $key (sort {$b cmp $a} keys %SATZn){
    $outkey=$key;
    $outkey=~s/(\d\d\d\d)\.\d\d\d/$1/;
    printf NOTA $outkey.konv($SATZn{$key})."\n" if ($SATZn{$key} !~ /idn:/);
  }

  foreach $key (sort keys %SATZ){
    printf SYSSIK $key.":".konv($SATZ{$key})."\n" if ($SATZ{$key} !~ /idn:/);
  }
  print SYSSIK "9999:\n\n";
  print NOTA "ENDE\n";


}
close(NOTA);
close(SYSSIK);
close(SYS);

open(SWD,"$bcppath/swd_daten.bcp");
open(SWT,"| gzip >./swt.exp.gz");
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

  printf SWT "IDN  %0d\n", $katkey;
  printf SWDSIK "0000:%0d\n", $katkey;


  # Zuerst die Schlagwortkette bzw. das Einzelschlagwort ausgeben

  @swtkette=();
  foreach $key (sort {$b cmp $a} keys %SATZn){
    if ($key =~/^6510/){
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

  printf SWT "6510 $schlagw\n" if ($schlagw !~ /idn:/);


  # Jetzt den Rest ausgeben.

  foreach $key (sort {$b cmp $a} keys %SATZn){
    next if ($key=~/^6510/);
    $outkey=$key;
    $outkey=~s/(\d\d\d\d)\.\d\d\d/$1/;
 #   $SATZn{$key}=~s/^[a-z]// if ($key=~/^6520/);
    printf SWT $outkey.konv($SATZn{$key})."\n" if ($SATZn{$key} !~ /idn:/);
  }

  foreach $key (sort {$b cmp $a} keys %SATZ){
    printf SWDSIK $key.":".konv($SATZ{$key})."\n" if ($SATZ{$key} !~ /idn:/);
  }


  print SWDSIK "9999:\n\n";
  print SWT "ENDE\n";

}

close(SWT);
close(SWDSIK);
close(SWD);

open(TITEL,"$bcppath/titel_daten.bcp");
open(TIT,"| gzip >./tit.exp.gz");
open(TITSIK,"| gzip >./unload.TIT.gz");
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
	    $inh = hex(substr($BLOB,$kdup+4,8));
	    $inh="IDN: $inh";
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


  printf TIT "IDN  %0d\n", $katkey;
  printf TITSIK "0000:%0d\n", $katkey;
  printf TIT "1100 8\n";
#  print  TIT "SDU  $sdu\n";
#  print  TIT "SDN  %sdn\n";

  foreach $key (sort keys %SATZ){
    if ($key !~/^000[01]/){
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

	print TIT "$line\n" if ($line !~ /idn:/);
      }

      # Kompliziertere Konvertierungen

      else {
	$line=$key.":".konv($SATZ{$key});
	

	if ($line=~/^SDN  .(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
	  $sdn="$3$2$1";
	}

	if ($line=~/^SDU  .(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
	  $sdu="$3$2$1";
	}

      
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

	  # Wenn es ein verknuepfter Satz ist
	  # (erkennbar daran, dass es noch eine 'freie' Verknuepfung gibt)
	  # Nur dann wird $restinhalt bestueckt.

	  print STDERR "VERWCOUNT $verwcount - VERKNCOUNT $verkncount - INHALT $inhalt \n";

	  if ($verwcount > $verkncount){
	    if ($inhalt=~/^.*?[.:\/;](.+)$/){
	      $zusatz=$1;
	    }
	    else {
	      $zusatz="...\n";
	    }


	    $verwidn[$maxpos][1]="5";
	    $verwidn[$maxpos][2]="";
	    $verwidn[$maxpos][3]="$zusatz";
	  }
	  else {

	    print STDERR "590NORMAL - $inhalt\n";
	    # Die 590er werden via maxpos hinten drangehaengt
	    $verwidn[$maxpos][0]="";
	    $verwidn[$maxpos][1]="5";
	    $verwidn[$maxpos][2]="$inhalt";
	    $verwidn[$maxpos][3]="";
	  }
	  $maxpos++;
	}
      
	if ($line=~/^0016.(\d\d\d):(.*$)/){
	  $zaehlung=$1;
	  $inhalt=$2;
	  $standortbuf{$zaehlung}=$inhalt;
	  if ($maxmex <= $zaehlung) {
	    $maxmex=$zaehlung;
	  }
	}
	
	if ($line=~/^0014\.(\d\d\d):(.*$)/){
          $zaehlung=$1;
          $inhalt=$2;
          $signaturbuf{$zaehlung}=$inhalt;
          if ($maxmex <= $zaehlung) {
	    $maxmex=$zaehlung;
	  }
        }

	# Zeitschriftensignaturen USB Koeln

	if ($line=~/^1203\.(\d\d\d):(.*$)/){
          $zaehlung=$1;
          $inhalt=$2;
          $signaturbuf{$zaehlung}=$inhalt;
          if ($maxmex <= $zaehlung) {
	    $maxmex=$zaehlung;
	  }
        }
		
        if ($line=~/^1204\.(\d\d\d):(.*$)/){
      	  $zaehlung=$1;
      	  $inhalt=$2;
       	  $erschverlbuf{$zaehlung}=$inhalt;
       	  if ($maxmex <= $zaehlung) {
       	    $maxmex=$zaehlung;
       	  }
       	}

        if ($line=~/^3330\.(\d\d\d):(.*$)/){
          $zaehlung=$1;
          $inhalt=$2;
          $besbibbuf{$zaehlung}=$inhalt;
	  if ($maxmex <= $zaehlung) {
             $maxmex=$zaehlung
	  }
	}

	if ($line=~/^0005\.(\d\d\d):(.*$)/){
	  $zaehlung=$1;
	  $inhalt=$2;
	  $inventarbuf{$zaehlung}=$inhalt;
	  if ($maxmex <= $zaehlung) {
	    $maxmex=$zaehlung;
	  }
	}

	print STDERR "--> $line\n";
      }
    }
  } # Ende foreach

  # 089er verwenden, wenn genau eine 004 besetzt, aber keine 455/590

  if ($bandangvorl && $maxpos < 1 && $verwidn[0][3] eq ""){
    $verwidn[0][3]=$bandangvorl;
  }

  # Exemplardaten abarbeiten Anfang

  my $k=1;
  while ($k <= $maxmex) {

    $key=sprintf "%03d",$k;

     $signatur=$signaturbuf{$key};
     $standort=$standortbuf{$key};
     $inventar=$inventarbuf{$key};
     $sigel=$besbibbuf{$key};
     $sigel=~s!^38/!!;
     $erschverl=$erschverlbuf{$key};

	      
    $mexbuffer[$mexidx++]="IDN  ".$mexidn;
    $mexbuffer[$mexidx++]="SDN  ".$sdn ;
    $mexbuffer[$mexidx++]="SDU  ".$sdu;
    $mexbuffer[$mexidx++]="7500 ".$sigel if ($sigel);
    $mexbuffer[$mexidx++]="7502 IDN: ".$katkey;
    #$mexbuffer[$mexidx++]="7620 ".$lokfn if ($lokfn);
    $mexbuffer[$mexidx++]="7510 ".$signatur if ($signatur);
    $mexbuffer[$mexidx++]="7600 ".$standort if ($standort);
    $mexbuffer[$mexidx++]="7560 ".$inventar if ($inventar);
    $mexbuffer[$mexidx++]="7700 ".$erschverl if ($erschverl);

    #$mexbuffer[$mexidx++]="7621 ".$zusgefb if ($zusgefb);
    $mexbuffer[$mexidx++]="ENDE";

    $mexidn++;
    $k++;
   }
   
   # Exemplardaten abarbeiten Ende

   # Verknuepfungen abarbeiten Anfang

   foreach $verkn (@verwidn){
     $jverkn=join("",@$verkn);
     
     ($verknidn,$typ,$gesamt,$zusatz)=split("",$jverkn);
     
     $string="$verknidn:$typ:$gesamt:$zusatz\n";
     
     print STDERR "$verknidn:$typ:$gesamt:$zusatz\n";
     
     if ( ($verknidn ne "" ) && ($typ eq "4") && ($zusatz ne "")){
       $verknline="4200 IDN: $verknidn ; $zusatz";
       print STDERR "IDN $katkey - 4200 IDN: $verknidn ; $zusatz\n";
     }
     elsif ( ($verknidn ne "" ) && ($typ eq "4") && ($zusatz eq "")){
       $verknline="4200 IDN: $verknidn ; ...";
       print STDERR "IDN $katkey - 4200 IDN: $verknidn ; ...\n";
     }
     elsif ( ($verknidn eq "") && ($typ eq "4") && ($zusatz ne "")){
       $verknline="4240 $gesamt ; $zusatz";
       print STDERR "IDN $katkey - 4240 $gesamt ; $zusatz\n";
     }
     elsif ( ($verknidn eq "") && ($typ eq "4") && ($zusatz eq "")){
       $verknline="4240 $gesamt";
       print STDERR "IDN $katkey - 4240 $gesamt\n";
     }
     elsif ( ($verknidn ne "") && ($typ eq "") && ($zusatz eq "")){
       $verknline="4200 IDN: $verknidn";
     }
     elsif ( ($verknidn ne "" ) && ($typ eq "5") && ($zusatz ne "")){
       $verknline="4260 IDN: $verknidn ; $zusatz";
       print STDERR "IDN $katkey - 4260 IDN: $verknidn\n";
     }
     elsif ( ($verknidn ne "" ) && ($typ eq "5") && ($gesamt ne "")){
       $verknline="4260 IDN: $verknidn";
       print STDERR "IDN $katkey - 4260 IDN: $verknidn\n";
     }
     elsif ( ($verknidn eq "" ) && ($typ eq "5") && ($gesamt ne "")){
       $verknline="4506 $gesamt";
       print STDERR "IDN $katkey - 4506 $gesamt\n";
     }
     elsif ( ($verknidn ne "" ) && ($typ eq "") && ($gesamt eq "")  && ($zusatz ne "") ){
       $verknline="4200 IDN: $verknidn ; $zusatz";
       print STDERR "IDN $katkey - 4200 IDN: $verknidn ; $zusatz\n";
       
     }
     elsif ( ($verknidn eq "" ) && ($typ eq "") && ($gesamt ne "")  && ($zusatz eq "") ){
       # Dann ist nichts zu tun...
     }
     else {
       print STDERR "IDN $katkey Nicht abgefangen!!!\n--->$string<---\n";
     }
     
     print TIT "$verknline\n" if ($verknline ne "");     
   }

   # Verknuepfungen abarbeiten Ende

   # Sonstiges abarbeiten Anfang

   # Fussnoten zusammenfuegen, wenn welche da sind
   if ($#fussnbuf >= 0){
      my $fussnote=join(" ; ",@fussnbuf);
      print TIT "4400 $fussnote\n";
   }

   # Sonstiges abarbeiten Ende


  print TITSIK "9999:\n\n";
  print TIT "ENDE\n";

      
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

close(TIT);
close(TITSIK);
close(TITEL);

&ausgabemexfile;

#######################################################################
########################################################################

sub ausgabemexfile {
  open(MEX,"| gzip > mex.exp.gz");
  $i=0;
  while ($i < $#mexbuffer) {
    print MEX $mexbuffer[$i],"\n";
    $i++;
  }
  print MEX "ENDE\n";
  close(MEX);
}

sub konv {
  my ($line)=@_;

  $line=~s///g;
  $line=~s/\&/&amp;/g;
  $line=~s/>/&gt;/g;
  $line=~s/</&lt;/g;

  return $line;
}
