#!/usr/bin/perl

#####################################################################
#
#  meta2wais.pl 
#
#  Generierung von Inhalten fuer eine Volltextrecherche, die 
#  z.B. via freeWAIS-sf recherchiert werden koennen und als 
#  Resultat Einsprung-IDN's fuer die SQL-Datenbank liefern
#
#  Dieser Weg ueber WAIS ist historisch gewachsen. Derzeit werden die
#  mit diesem Skript erzeugten Daten nochmals durch ein weiteres Skript
#  bearbeitet, um dann in eine volltextsuchbare mySQL-Tabelle eingeladen
#  zu werden (search). Diese Zwischenstufe als weiteres 'Meta-Format 
#  fuer die Volltextsuche' macht durchaus noch Sinn, da davon ausgehend 
#  Konvertierungen in 'neue' Volltextsuchen, wie z.B. in der 
#  Suchmaschine (P)Lucene, evaluiert werden koennen.
#
#  Dieses File ist (C) 1997-2004 Oliver Flimm <flimm@openbib.org>
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

if ($#ARGV < 0){
    print_help();
}

&GetOptions("aut" => \$aut, 
            "tit" => \$tit,
            "swt" => \$swt,
            "kor" => \$kor,
            "nota" => \$nota,
	    "mex" => \$mex,
            "dos" => \$dos,
            "encoding" => \$encoding,
            "with-umlaut" => \$withumlaut,
	    "idnprefix=s" => \$idnprefix,
	    "all" => \$all,
	    "combined" => \$combined,
	    "help" => \$help
	    );

if ($help){
    print_help();
}

if ((!$tit)&&(!$aut)&&(!$kor)&&(!$swt)&&(!$nota)&&(!$mex)&&(!$combined)){
    $all=1;
}

if ($combined){
  open(COMBI,">data.wais");
}

#####################################################################
# Erzeuge Notationen
#####################################################################

if (($nota)||($all)||($combined)){

    $notexp="not.exp";
    $notwais="not.wais";
    
    open(NOTWAIS,">".$notwais);
    
    open(NOTEXP,$notexp);
    
    $first=1;
    
    while (<NOTEXP>){
	chop;
	chop if (/
$/);
	if (/^     /){	
	    $line=$line.$last.substr($_,5,length($_)-5);
	    $last="";
	    $lasttype="empty";
	}
	else { 
	    if ($lasttype eq "full"){
		$line=$line.$last."\n";
		bearbeite_notline($line);
		$line="";
	    }
	    else {
		if (!$first){
		    $line=$line."\n" unless ($first);
		    bearbeite_notline($line);
		}
		$line="";
		$first=0;
	    }
	    $last=$_;
	    $lasttype="full";
	}
    }
    
    if ($lasttype eq "empty"){
	bearbeite_notline($line."\n");
    }
    else {
	bearbeite_notline($last."\n");
    }
    
    undef $lasttype;
    
    close(NOTEXP);
    close(NOTWAIS);
}

#####################################################################
# Erzeuge Exemplardaten
#####################################################################

if (($mex)||($all)||($combined)){

    $mexexp="mex.exp";
    $mexwais="mex.wais";
    
    open(MEXWAIS,">".$mexwais);
    
    open(MEXEXP,$mexexp);
    
    $first=1;
    
    while (<MEXEXP>){
	chop;
	chop if (/
$/);
	if (/^     /){	
	    $line=$line.$last.substr($_,5,length($_)-5);
	    $last="";
	    $lasttype="empty";
	}
	else { 
	    if ($lasttype eq "full"){
		$line=$line.$last."\n";
		bearbeite_mexline($line);
		$line="";
	    }
	    else {
		if (!$first){
		    $line=$line."\n" unless ($first);
		    bearbeite_mexline($line);
		}
		$line="";
		$first=0;
	    }
	    $last=$_;
	    $lasttype="full";
	}
    }
    
    if ($lasttype eq "empty"){
	bearbeite_mexline($line."\n");
    }
    else {
	bearbeite_mexline($last."\n");
    }
    
    undef $lasttype;
    
    close(MEXEXP);
    close(MEXWAIS);
}

#####################################################################
# Erzeuge Autoren
#####################################################################

if (($aut)||($all)||($combined)){

    $autoren="aut.exp";
    $autwais="aut.wais";
    
    open(AUTWAIS,">".$autwais);
    
    open(AUT,$autoren);
    
    $first=1;
    
    while (<AUT>){
	chop;
	chop if (/
$/);
	if (/^     /){	
	    $line=$line.$last.substr($_,5,length($_)-5);
	    $last="";
	    $lasttype="empty";
	}
	else { 
	    if ($lasttype eq "full"){
		$line=$line.$last."\n";
		bearbeite_autline($line);
		$line="";
	    }
	    else {
		if (!$first){
		    $line=$line."\n" unless ($first);
		    bearbeite_autline($line);
		}
		$line="";
		$first=0;
	    }
	    $last=$_;
	    $lasttype="full";
	}
    }
    
    if ($lasttype eq "empty"){
	bearbeite_autline($line."\n");
    }
    else {
	bearbeite_autline($last."\n");
    }
    
    undef $lasttype;
    
    close(AUT);
    close(AUTWAIS);
}

#####################################################################
# Erzeuge Koerperschaften 
#####################################################################

if (($kor)||($all)||($combined)){
    $koerperschaften="kor.exp";
    $korwais="kor.wais";
    
    open(KORWAIS,">".$korwais);
    
    open(KOR,$koerperschaften);
    
    $first=1;
    
    while (<KOR>){
	chop;
	chop if (/
$/);
	if (/^     /){	 
	    $line=$line.$last.substr($_,5,length($_)-5);
	    $last="";
	    $lasttype="empty";
	}
	else { 
	    if ($lasttype eq "full"){
		$line=$line.$last."\n";
		bearbeite_korline($line);
		$line="";
	    }
	    else {
		if (!$first){
		    $line=$line."\n" unless ($first);
		    bearbeite_korline($line);
		}
		$line="";
		$first=0;
	    }
	    $last=$_;
	    $lasttype="full";
	}
    }
    
    if ($lasttype eq "empty"){
	bearbeite_korline($line."\n");
    }
    else {
	bearbeite_korline($last."\n");
    }
    
    undef $lasttype;
    
    close(KOR);
    close(KORWAIS);
}

#####################################################################
# Erzeuge Schlagworte
#####################################################################

if(($swt)||($all)||($combined)){
    $schlagworte="swt.exp";
    $swtwais="swt.wais";
    
    open(SWTWAIS,">".$swtwais);
    
    open(SWT,$schlagworte);
    
    $first=1;
    
    while (<SWT>){
	chop;
	chop if (/
$/);
	if (/^     /){	 
	    $line=$line.$last.substr($_,5,length($_)-5);
	    $last="";
	    $lasttype="empty";
	}
	else { 
	    if ($lasttype eq "full"){
		$line=$line.$last."\n";
		bearbeite_swtline($line);
		$line="";
	    }
	    else {
		if (!$first){
		    $line=$line."\n" unless ($first);
		    bearbeite_swtline($line);
		}
		$line="";
		$first=0;
	    }
	    $last=$_;
	    $lasttype="full";
	}
    }
    
    if ($lasttype eq "empty"){
	bearbeite_swtline($line."\n");
    }
    else {
	bearbeite_swtline($last."\n");
    }
    
    undef $lasttype;
    
    close(SWT);
    close(SWTWAIS);
}

#####################################################################
# Erzeuge Titel
#####################################################################

if (($tit)||($all)||($combined)){
    $titel="tit.exp";
    $titwais="tit.wais";
    
    open(TITWAIS,">".$titwais);
    
    %bezeich=('h',1);
    
    open(TIT,$titel);
    
    $first=1;
    
    while (<TIT>){
	chop;
	chop if (/
$/);
	if (/^     /){	 
	    $line=$line.$last.substr($_,5,length($_)-5);
	    $last="";
	    $lasttype="empty";
	}
	else { 
	    if ($lasttype eq "full"){
		$line=$line.$last."\n";
		bearbeite_titline($line);
		$line="";
	    }
	    else {
		if (!$first){
		    $line=$line."\n" unless ($first);
		    bearbeite_titline($line);
		}
		$line="";
		$first=0;
	    }
	    $last=$_;
	    $lasttype="full";
	}
    }
    
    if ($lasttype eq "empty"){
	bearbeite_titline($line."\n");
    }
    else {
	bearbeite_titline($last."\n");
    }
    
    undef $lasttype;
    
    close(TIT);
    close(TITWAIS);
}

#####################################################################
#####################################################################

if ($combined){
  close(COMBI);
}

sub grundform {
    my $line=shift @_;

    # Doublequotes haben in WAIS nichts zu suchen

    $line=~s/\"//g;
    $line=~s/'/ /g;
    
    $line=~s/ü/ue/g;
    $line=~s/ä/ae/g;
    $line=~s/ö/oe/g;
    $line=~s/Ü/Ue/g;
    $line=~s/Ö/Oe/g;
    $line=~s/Ä/Ae/g;
    $line=~s/ß/ss/g;
    $line=~s/ª//g;

    $line=~s/è/e/g;
    $line=~s/à/a/g;
    $line=~s/ò/o/g;
    $line=~s/ù/u/g;
    $line=~s/È/e/g;
    $line=~s/À/a/g;
    $line=~s/Ò/o/g;
    $line=~s/Ù/u/g;
    $line=~s/é/e/g;
    $line=~s/É/E/g;
    $line=~s/á/a/g;
    $line=~s/Á/a/g;
    $line=~s/í/i/g;
    $line=~s/Í/I/g;
    $line=~s/ó/o/g;
    $line=~s/Ó/O/g;
    $line=~s/ú/u/g;
    $line=~s/Ú/U/g;
    $line=~s/ý/y/g;
    $line=~s/Ý/Y/g;
    $line=~s/æ/ae/g; # ae
    $line=~s/¬//g;
    $line=~s/>//g;
    $line=~s/<//g;
    
    return $line;
}

sub speziellegrundform {
    my $line=shift @_;

    # Doublequotes haben in WAIS nichts zu suchen

    $line=~s/\"//g;
    
    if ($dos){
	if ($withumlaut){
	    $line=~s//ü/g;
	    $line=~s/„/ä/g;
	    $line=~s/”/ö/g;
	    $line=~s/š/Ü/g;
	    $line=~s/™/Ö/g;
	    $line=~s/Ž/Ä/g;
	    $line=~s/á/ß/g;
	    $line=~s/ª//g;
	}
	else {
	    $line=~s//ue/g;
	    $line=~s/„/ae/g;
	    $line=~s/”/oe/g;
	    $line=~s/š/Ue/g;
	    $line=~s/™/Oe/g;
	    $line=~s/Ž/Ae/g;
	    $line=~s/á/ss/g;
	    $line=~s/ª//g;
	}
    }
    else {
	if ($withumlaut){
	    $line=~s/\}/ü/g;
	    $line=~s/\{/ä/g;
	    $line=~s/\[/Ä/g;
	    $line=~s/\]/Ü/g;
	    $line=~s/\|/ö/g;
	    $line=~s/\\/Ö/g;
	    $line=~s/\~/ß/g;
	}
	else {
	    $line=~s/\}/ue/g;
	    $line=~s/\{/ae/g;
	    $line=~s/\[/Ae/g;
	    $line=~s/\]/Ue/g;
	    $line=~s/\|/oe/g;
	    $line=~s/\\/Oe/g;
	    $line=~s/\~/ss/g;	    
	}
    }
    
    if ($withumlaut){
	$line=~s/#193e/è/g;
	$line=~s/#193a/à/g;
	$line=~s/#193o/ò/g;
	$line=~s/#193u/ù/g;
	$line=~s/#193E/È/g;
	$line=~s/#193A/À/g;
	$line=~s/#193O/Ò/g;
	$line=~s/#193U/Ù/g;
	$line=~s/#194e/é/g;
	$line=~s/#194a/á/g;
	$line=~s/#194o/ó/g;
	$line=~s/#194u/ú/g;
	$line=~s/#194E/É/g;
	$line=~s/#194A/Á/g;
	$line=~s/#194O/Ó/g;
	$line=~s/#194U/Ú/g;
	
	$line=~s/#208c/c/g;
	
	$line=~s/#193//g;
	$line=~s/#208//g;
	
	$line=~s/#091/\[/g;
	$line=~s/#093/\]/g;
	
	$line=~s/¬//g;
	$line=~s/#123/ä/g;
	$line=~s/#124/ö/g;
	$line=~s/#125/ü/g;
	
	$line=~s/#163//g; # Pound
	$line=~s/#168//g; # Degree
	$line=~s/#203/\'/g;
	$line=~s/#189//g; # ????
	$line=~s/#236/Th/g; # 'grosses' Thorn
	$line=~s/#252/th/g; # 'kleines' Thorn
	
	$line=~s/#196n/ñ/g;
	$line=~s/#196o/õ/g;
	$line=~s/#196a/ã/g;
	
	$line=~s/#223n/ñ/g;
	$line=~s/#223o/õ/g;
	$line=~s/#223a/ã/g;
	
	$line=~s/#171//g;
	$line=~s/#187//g;
	$line=~s/#175//g;
	$line=~s/#209(.)/\1/g;
	$line=~s/#187(.)//g;
	$line=~s/#206(.)/\1/g; # Rechts angesetztes H"ackchen
	$line=~s/#202(.)/\1/g;
	$line=~s/#249/oe/g; # daenisches o strichdurch
	$line=~s/#191//g; # inv. Questionmark
	$line=~s/#183//g; # inv. Questionmark
	$line=~s/#245//g; # Paragraph (tuerkisches i???)
	$line=~s/#250//g; # OE ligatur
	$line=~s/#215//g; # Querstrich
	$line=~s/#216//g; # Unterstreichung
	$line=~s/#205//g; # Doppelacute
	$line=~s/#233/Oe/g; # daenisches O strichdurch
	$line=~s/#197//g; # Makron (Balken)
	$line=~s/#207//g; # Hacek???
	$line=~s/#251/y/g; # Yr-Kapitaelchen
	$line=~s/#213//g; # Halbkreis untergesetzt
	$line=~s/#198//g; # Halbkreis uebergesetzt
	$line=~s/#214//g; # Punkt untergesetzt
	$line=~s/#177//g; # Hamcah
	$line=~s/#210//g; # Sedilla, unten
	$line=~s/#232/L/g; # Polnisches L (durchgestrichen)
	$line=~s/#248/l/g; # Polnisches l (durchgestrichen)
	$line=~s/#182/ /g; # Trennzeichen
	$line=~s/#195(.)/\1/g;
	$line=~s/#234//g; # oe ligatur
    }
    else {
	$line=~s/è/e/g;
	$line=~s/à/a/g;
	$line=~s/ò/o/g;
	$line=~s/ù/u/g;
	$line=~s/È/e/g;
	$line=~s/À/a/g;
	$line=~s/Ò/o/g;
	$line=~s/Ù/u/g;
	$line=~s/é/e/g;
	$line=~s/É/E/g;
	$line=~s/á/a/g;
	$line=~s/Á/a/g;
	$line=~s/í/i/g;
	$line=~s/Í/I/g;
	$line=~s/ó/o/g;
	$line=~s/Ó/O/g;
	$line=~s/ú/u/g;
	$line=~s/Ú/U/g;
	$line=~s/ý/y/g;
	$line=~s/Ý/Y/g;
	$line=~s/#241/ae/g; # ae
 	$line=~s/æ/ae/g; # ae
	$line=~s/#225/ae/g; # ae
	$line=~s/#249/oe/g;
	$line=~s/#233/Oe/g;
	$line=~s/#243/d/g;
	$line=~s/#226/d/g;
	$line=~s/#236/Th/g;
	$line=~s/#252/th/g;

	$line=~s/#193(.)/\1/g;
	$line=~s/#194(.)/\1/g;
	$line=~s/#195(.)/\1/g;
	$line=~s/#196(.)/\1/g;
	$line=~s/#223(.)/\1/g;
	$line=~s/#208c/c/g;
	$line=~s/#091//g;
	$line=~s/#093//g;
	
	$line=~s/#193//g;
	$line=~s/#208//g;
	
  	$line=~s/¬//g;
  	$line=~s/>//g;
  	$line=~s/<//g;
	$line=~s/#123/ae/g;
	$line=~s/#124/oe/g;
	$line=~s/#125/ue/g;
	
	$line=~s/#163//g; # Pound
	$line=~s/#168//g; # Degree
	$line=~s/#203//g;
	$line=~s/#189//g; # ????
	$line=~s/#236/Th/g; # 'grosses' Thorn
	$line=~s/#252/th/g; # 'kleines' Thorn
	
	$line=~s/#171//g;
	$line=~s/#187//g;
	$line=~s/#175//g;
	$line=~s/#209(.)/\1/g;
	$line=~s/#187(.)//g;
	$line=~s/#206(.)/\1/g; # Rechts angesetztes H"ackchen
	$line=~s/#202(.)/\1/g;
	$line=~s/#200(.)/\1/g;
	$line=~s/#249/o/g;
	$line=~s/#191//g; # inv. Questionmark
	$line=~s/#183//g; # inv. Questionmark
	$line=~s/#245//g; # Paragraph (tuerkisches i???)
	$line=~s/#215//g; # Querstrich
	$line=~s/#216//g; # Unterstreichung
	$line=~s/#205//g; # Doppelacute
	$line=~s/#233/o/g; # daenisches OE ligatur
	$line=~s/#197//g; # Makron (Balken)
	$line=~s/#207//g; # Hacek???
	$line=~s/#251/y/g; # Yr-Kapitaelchen
	$line=~s/#213//g; # Halbkreis untergesetzt
	$line=~s/#198//g; # Halbkreis uebergesetzt
	$line=~s/#214//g; # Punkt untergesetzt
	$line=~s/#177//g; # Hamcah
	$line=~s/#210//g; # Sedilla, unten
	$line=~s/#232/L/g; # Polnisches L (durchgestrichen)
	$line=~s/#248/l/g; # Polnisches l (durchgestrichen)
	$line=~s/#182/ /g; # Trennzeichen

        $line=~s/\$403A/A/g; # A mit Unterpunkt
        $line=~s/\$403a/a/g; # a mit Unterpunkt
        $line=~s/\$409A/A/g; # A mit Unterhaken rechts offen
        $line=~s/\$409a/a/g; # a mit Unterhaken rechts offen   
        $line=~s/\$409E/E/g; # E mit Unterhaken rechts offen
        $line=~s/\$409e/e/g; # e mit Unterhaken rechts offen
        $line=~s/\$410A/A/g; # A mit Balken oben
        $line=~s/\$410a/a/g; # a mit Balken oben 
        $line=~s/\$410E/E/g; # E mit Balken oben
        $line=~s/\$410e/e/g; # e mit Balken oben
        $line=~s/\$410I/I/g; # I mit Balken oben
        $line=~s/\$410i/i/g; # i mit Balken oben
        $line=~s/\$410O/O/g; # O mit Balken oben
        $line=~s/\$410o/o/g; # o mit Balken oben
        $line=~s/\$411A/A/g; # A mit Halbkreis oben
        $line=~s/\$411a/a/g; # a mit Halbkreis oben
        $line=~s/\$411U/U/g; # U mit Halbkreis oben
        $line=~s/\$411u/u/g; # u mit Halbkreis oben
        $line=~s/\$400C/C/g; # C mit Accent aigue  
        $line=~s/\$400c/c/g; # c mit Accent aigue
        $line=~s/\$400G/G/g; # G mit Accent aigue
        $line=~s/\$400g/g/g; # g mit Accent aigue
        $line=~s/\$400N/N/g; # N mit Accent aigue
        $line=~s/\$400n/n/g; # n mit Accent aigue
        $line=~s/\$400S/S/g; # S mit Accent aigue
        $line=~s/\$400s/s/g; # s mit Accent aigue
        $line=~s/\$400Z/Z/g; # Z mit Accent aigue
        $line=~s/\$400z/z/g; # z mit Accent aigue
        $line=~s/\$401C/C/g; # C mit Hacek       
        $line=~s/\$401c/c/g; # c mit Hacek
        $line=~s/\$401N/N/g; # N mit Hacek
        $line=~s/\$401n/n/g; # n mit Hacek
        $line=~s/\$401D/D/g; # D mit Hacek
        $line=~s/\$401d/d/g; # d mit Hacek
        $line=~s/\$401E/E/g; # E mit Hacek
        $line=~s/\$401e/e/g; # e mit Hacek
        $line=~s/\$401G/G/g; # G mit Hacek
        $line=~s/\$401g/g/g; # g mit Hacek
        $line=~s/\$401I/I/g; # T mit Hacek
        $line=~s/\$401i/i/g; # t mit Hacek
        $line=~s/\$401R/R/g; # R mit Hacek
        $line=~s/\$401r/r/g; # r mit Hacek
        $line=~s/\$401S/S/g; # S mit Hacek
        $line=~s/\$401s/s/g; # s mit Hacek
        $line=~s/\$401T/T/g; # T mit Hacek
        $line=~s/\$401t/t/g; # t mit Hacek
        $line=~s/\$401Z/Z/g; # Z mit Hacek
        $line=~s/\$401z/z/g; # z mit Hacek
        $line=~s/\$402E/E/g; # E mit Punkt oben
        $line=~s/\$402e/e/g; # e mit Punkt oben
        $line=~s/\$413E/E/g; # E mit Punkt unten
        $line=~s/\$413e/e/g; # e mit Punkt unten
        $line=~s/\$406O/O/g; # O mit Doppelakut 
        $line=~s/\$406o/o/g; # o mit Doppelakut
        $line=~s/\$406U/U/g; # U mit Doppelakut
        $line=~s/\$406u/u/g; # u mit Doppelakut
        $line=~s/\$412S/S/g; # S mit Haken in der Mitte unten
        $line=~s/\$412s/s/g; # s mit Haken in der Mitte unten
        $line=~s/\$412T/T/g; # T mit Haken in der Mitte unten
        $line=~s/\$412t/t/g; # t mit Haken in der Mitte unten
        $line=~s/\$407U/U/g; # U mit Ringel oben
        $line=~s/\$407u/u/g; # u mit Ringel oben
        $line=~s/\$402Z/Z/g; # Z mit einem Punkt oben
        $line=~s/\$402z/z/g; # z mit einem Punkt oben
        $line=~s/\$415/d/g; # d oben durchgestrichen 
        $line=~s/\$416/Oe/g; # OE Ligatur
        $line=~s/\$417/oe/g; # oe Ligatur

    }

    return $line;
}

sub bearbeite_autline {
    ($line)=@_;
    
    if ($encoding){
	$line=speziellegrundform("$line");
    }
    else {
	$line=grundform("$line");
    }
    
    if ($line=~/^IDN  (\d+)/){
	$idn=$1;	
	$autverwidx=0;
    }
    if ($line=~/^6020 (.*)/){
	$autans=$1;
    }
    if ($line=~/^602[1-9] (.*)/){
	$verw=$1;
	$autverwbuf[$autverwidx++]=$verw;
    }
    
    if ($line=~/^ENDE/){
      if ($combined){
	$autbuf[$idn]=$autans."\n";
	if ($autverwidx != 0){
	  foreach $verw (@autverwbuf){
	    $autbuf[$idn]=$autbuf[$idn]."$verw\n";
	  }
	}
      }
      else {
	print AUTWAIS "idn: $idn\n";
	print AUTWAIS "ans: $autans\n";
	if ($autverwidx != 0){
	  foreach $verw (@autverwbuf){
	    print AUTWAIS "ver: $verw\n";
	  }
	}
	print AUTWAIS "\f\n";
      }
      undef @autverwbuf;
      undef $autverwidx;
      undef $verw;
      undef $autans;
      undef $idn;
    }
}

sub bearbeite_notline {
    ($line)=@_;

    if ($encoding){
	$line=speziellegrundform("$line");
    }
    else {
	$line=grundform("$line");
    }
    
    if ($line=~/^IDN  (\d+)/){
	$idn=$1;	
	$notverwidx=0;
    }
    if ($line=~/^8000 (.*)/){
	$notation=$1;
    }
    if ($line=~/^8015 (.*)/){
	$verw=$1;
	$notverwbuf[$notverwidx++]=$verw;
    }
    
    if ($line=~/^ENDE/){
      if ($combined){
	$notbuf[$idn]=$notation."\n";
	if ($notverwidx != 0){
	  foreach $verw (@notverwbuf){
	    $notbuf[$idn]=$notbuf[$idn]."$verw\n";
	  }
	}
      }
      else {
	print NOTWAIS "idn: $idn\n";
	print NOTWAIS "not: $notation\n";
	if ($notverwidx != 0){
	  foreach $verw (@notverwbuf){
	    print NOTWAIS "ver: $verw\n";
	  }
	}
	print NOTWAIS "\f\n";
      }
      undef @notverwbuf;
      undef $notverwidx;
      undef $verw;
      undef $notation;
      undef $idn;
    }
}

sub bearbeite_mexline {
    ($line)=@_;
    
    if ($encoding){
	$line=speziellegrundform("$line");
    }
    else {
	$line=grundform("$line");
    }
    
    if ($line=~/^7502 IDN: (\d+)/){
	$mextitidn=$1;	
    }

    if ($line=~/^7510 (.*)/){
	$sign=$1;
	$signbuf[$mextitidn]=$signbuf[$mextitidn]."$sign\n";
    }

#    if ($line=~/^ENDE/){
#      print "$mextitidn: ".$signbuf[$mextitidn]."\n";
#    }
}

sub bearbeite_korline {
  ($line)=@_;
  
  if ($encoding){
      $line=speziellegrundform("$line");
  }
  else {
      $line=grundform("$line");
  }

  if ($line=~/^IDN  (\d+)/){
    $idn=$1;	
    $korverwidx=0;
    $korfruehidx=0;
    $korspaetidx=0;
  }
  if ($line=~/^6120 (.*)/){
    $korans=$1;
  }
  if ($line=~/^612[1-9] (.*)/){
    $verw=$1;
    $korverwbuf[$korverwidx++]=$verw;
  }
  if ($line=~/^613[0-2] (.*)/){
    $frueh=$1;
    $korfruehbuf[$korfruehidx++]=$frueh;
  }
  if ($line=~/^613[3-5] (.*)/){
    $spaet=$1;
    $korspaetbuf[$korspaetidx++]=$spaet;
  }
  
  if ($line=~/^ENDE/){
    if ($combined){
      $korbuf[$idn]=$korans."\n";
      if ($korverwidx != 0){
	foreach $verw (@korverwbuf){
	  $korbuf[$idn]=$korbuf[$idn]."$verw\n";
	}
      }
    }
    else {
      print KORWAIS "idn: $idn\n";
      print KORWAIS "ans: $ans\n";
      
      if ($korverwidx != 0){
	foreach $verw (@korverwbuf){
	  print KORWAIS "ver: $verw\n";
	}
      }
      if ($korfruehidx != 0){
	foreach $frueh (@korfruehbuf){
	  print KORWAIS "fru: $frueh\n";
	}
      }
      if ($korspaetidx != 0){
	foreach $spaet (@korspaetbuf){
	  print KORWAIS "spa: $spaet\n";
	}
      }
      print KORWAIS "\f\n";
    }
    undef $idn;	
    undef $korverwidx;
    undef $korfruehidx;
    undef $korspaetidx;
    undef @korverwbuf;
    undef @korfruehbuf;
    undef @korspatbuf;
    undef $korans;
    undef $verw;
    undef $frueh;
    undef $spaet;
  }
}



sub bearbeite_swtline {
    ($line)=@_;
    
    if ($encoding){
	$line=speziellegrundform("$line");
    }
    else {
	$line=grundform("$line");
    }

    if ($line=~/^IDN  (\d+)/){
	$idn=$1;	
	$swtverwidx=0;
	$swtueberidx=0;
	$swtassozidx=0;
	$swtfruehidx=0;
	$swtspaetidx=0;
    }
    if ($line=~/^6510 (.*)/){
	$schlagw=$1;
    }
    if ($line=~/^6511 (.*)/){
	$erlaeut=$1;
    }
    if ($line=~/^652[0-9] (.*)/){
	$verw=$1;
	$swtverwbuf[$swtverwidx++]=$verw;
    }
    if ($line=~/^655[0-5] (.*)/){
	$ueber=$1;
	$swtueberbuf[$swtueberidx++]=$ueber;
    }
    if ($line=~/^652[0-9] (.*)/){
	$assoz=$1;
	$swtassozbuf[$swtassozidx++]=$assoz;
    }
    if ($line=~/^657[0-1] (.*)/){
	$frueh=$1;
	$swtfruehbuf[$swtfruehidx++]=$frueh;
    }
    if ($line=~/^657[2-3] (.*)/){
	$spaet=$1;
	$swtspaetbuf[$swtspaetidx++]=$spaet;
    }
    
    if ($line=~/^ENDE/){
      if ($combined){
	$swtbuf[$idn]=$schlagw."\n";
	if ($swtverwidx != 0){
	  foreach $verw (@swtverwbuf){
	    $swtbuf[$idn]=$swtbuf[$idn]."$verw\n";
	  }
	}
      }
      else {

	print SWTWAIS "idn: $idn\n";
        print SWTWAIS "swt: $schlagw\n";
	if ($swtverwidx != 0){
	    foreach $verw (@swtverwbuf){
                print SWTWAIS "ver: $verw\n";
	    }
	}
	if ($swtueberidx != 0){
	    foreach $ueber (@swtueberbuf){
                print SWTWAIS "ueb: $ueber\n";
	    }
	}
	if ($swtassozidx != 0){
	    foreach $assoz (@swtassozbuf){
		print SWTWAIS "ass: $assoz\n";
	    }
	}
	if ($swtfruehidx != 0){
	    foreach $frueh (@swtfruehbuf){
		print SWTWAIS "fru: $frueh\n";
	    }
	}
	if ($swtspaetidx != 0){
	    foreach $spaet (@swtspaetbuf){
		print SWTWAIS "spa: $spaet\n";
	    }
	}
        print SWTWAIS "\f\n";
      }
	undef $idn;	
	undef $swtverwidx;
	undef $swtueberidx;
	undef $swtassozidx;
	undef $swtfruehidx;
	undef $swtspaetidx;
	undef $erlaeut;
	undef $schlagw;
        undef @swtspaetbuf;
        undef @swtfruehbuf;
        undef @swtassozbuf;
        undef @swtueberbuf;
        undef @swtverwbuf;
        undef $verw;
        undef $frueh;
        undef $spaet;
        undef $assoz;
    }
}

sub bearbeite_titline {
  ($line)=@_;
  
  if ($encoding){
      $line=speziellegrundform("$line");
  }
  else {
      $line=grundform("$line");
  }

  if ($line=~/^IDN  (\d+)/){
    $idn=$1;	
    $autidx=0;
    $koridx=0;
    $swtidx=0;
    $notidx=0;
    $isbnidx=0;
    $issnidx=0;
    $wstidx=0;
    $abstractidx=0;
    $psthtsidx=0;
    $beigwerkidx=0;
    $artinhidx=0;
  }
  
  if (($line=~/^2000.IDN: (\d+)/)||($line=~/^2003.IDN: (\d+)/)||($line=~/^2004.IDN: (\d+)/)){
    $autor[$autidx++]=$1;
  }
  
  if (($line=~/^2400.IDN: (\d+)/)||($line=~/^2403.IDN: (\d+)/)){
    $koerperschaft[$koridx++]=$1;
  }
  
  if ($line=~/^4600.(.*)/){
    $isbn[$isbnidx++]=$1;
  }

  if ($line=~/^4650.(.*)/){
    $issn[$issnidx++]=$1;
  }

  if ($line=~/^5650.(IDN:.+)$/){
    $schlagwort[$swtidx++]=$1;
  }

  if ($line=~/^5700.IDN: (\d+)/){
    $nota[$notidx++]=$1;
  }

  if ($line=~/^5260.(.*)/){
    $artinh[$artinhidx++]=$1;
  }

  if ($line=~/^2700.(.*)/){
    $wst[$wstidx++]=$1;
  }
  
  if ($line=~/^2800.(.*)/){
    $esthe=$1;
  }
  if ($line=~/^2900.(.*)/){
    $ast=$1;
  }
  if ($line=~/^3000.(.*)/){
    $hst=$1;
  }
  if ($line=~/^3030.(.*)/){
    $zuergurh=$1;
  }
  if ($line=~/^3040.(.*)/){
    $zusatz=$1;
  }
  if ($line=~/^3100.(.*)/){
    $psthts[$psthtsidx++]=$1;
  }
  if ($line=~/^3500.(.*)/){
    $vorlverf=$1;
  }
  if ($line=~/^3600.(.*)/){
    $vorlunter=$1;
  }
  if ($line=~/^3610.(.*)/){
    $vorlbeigwerk=$1;
  }
  if ($line=~/^3615.(.*)/){
    $beigwerk[$beigwerkidx++]=$1;
  }
  if ($line=~/^3650.(.*)/){
    $gemeinsang=$1;
  }
  if ($line=~/^3700.(.*)/){
    $ausg=$1;
  }
  if ($line=~/^3750.(.*)/){
    $mass=$1;
  }
  if ($line=~/^4000.(.*)/){
    $verlagsort=$1;
  }
  if ($line=~/^4002 (.*)/){
    $verlag=$1;
  }
  if ($line=~/^4004.(.*)/){
    $weitereort=$1;
  }
  if ($line=~/^4015.(.*)/){
    $aufnahmeort=$1;
  }
  if ($line=~/^4020.(.*)/){
    $aufnahmejahr=$1;
  }
  if ($line=~/^4025 (.*)/){
    $bindpreis=$1;
  }
  if ($line=~/^4040 (.*)/){
    $erschjahr=$1;
  }
  if ($line=~/^4102 (.*)/){
    $kollation=$1;
  }
  if ($line=~/^4115.(.*)/){
    $matbenennung=$1;
  }
  if ($line=~/^4112.(.*)/){
    $sonstmatben=$1;
  }
  if ($line=~/^4115.(.*)/){
    $sonstang=$1;
  }
  if ($line=~/^4125.(.*)/){
    $begleitmat=$1;
  }
  if ($line=~/^4240 (.*?) ;/){
    $gtu=$1;
  }
  if ($line=~/^4270.(.*)/){
    $bemerk=$1;
  }
  if ($line=~/^4300.(.*)/){
    $estfn=$1;
  }
  if ($line=~/^4330 (.*)/){
    $uebershst=$1;
  }
  if ($line=~/^4400.(.*)/){
    $fussnote=$1;
  }
  if ($line=~/^4500.(.*)/){
    $hsfn=$1;
  }
  if ($line=~/^4506.(.*)/){
    $inunverkn=$1;
  }
  if ($line=~/^5050 (.*)/){
    $sachlben=$1;
  }
  if ($line=~/^5246.(.*)/){
    $sprache=$1;
  }
  if ($line=~/^5801.(.*)/){
    $rem=$1;
  }

  if ($line=~/^9000.(.*)/){
    $abstract[$abstractidx++]=$1;
  }

  if ($line=~/^ENDE/){
    if ($combined){

      $pureidn=$idn;
      
      if ($idnprefix){
	$idn="$idnprefix$idn";
      }
      
      print COMBI "idn: $idn\n";
      print COMBI "endidn:\n";
      
      if ($autidx != 0){
	print COMBI "beginaut:\n";
	foreach $verwidn (@autor){
	  print COMBI $autbuf[$verwidn];
	}
	print COMBI "endaut:\n";
      }
      if ($koridx != 0){
	print COMBI "beginkor:\n";
	foreach $verwidn (@koerperschaft){
	  print COMBI $korbuf[$verwidn];
	}
	print COMBI "endkor:\n";
      }

      if ($isbnidx != 0){
	print COMBI "beginisbn:\n";
	foreach $singleisbn (@isbn){
	  print COMBI "$singleisbn\n";
	}
	print COMBI "endisbn:\n";
      }

      if ($issnidx != 0){
	print COMBI "beginissn:\n";
	foreach $singleissn (@issn){
	  print COMBI "$singleissn\n";
	}
	print COMBI "endissn:\n";
      }

      if ($artinhidx != 0){
	print COMBI "beginartinh:\n";
	foreach $singleartinh (@artinh){
	  print COMBI "$singleartinh\n";
	}
	print COMBI "endartinh:\n";
      }

      if (defined($signbuf[$pureidn])){
	print COMBI "beginsignatur:\n";
	print COMBI $signbuf[$pureidn];
	print COMBI "endsignatur:\n";
      }      
      
      print COMBI "begintit:\n";
      
      if ($ast){
	print COMBI "$ast\n";
      }
      
      if ($hst){
	print COMBI "$hst\n";
      }

      if ($wstidx != 0){
	foreach $singlewst (@wst){
	  print COMBI "$singlewst\n";
	}
      }


      if ($abstractidx != 0){
        foreach $singleabstract (@abstract){
          print COMBI "$singleabstract\n";
        }
      }


      if ($psthtsidx != 0){
	foreach $singlepsthts (@psthts){
	  print COMBI "$singlepsthts\n";
	}
      }

      if ($beigwerkidx != 0){
	foreach $singlebeigwerk (@beigwerk){
	  print COMBI "$singlebeigwerk\n";
	}
      }
      
      if ($zusatz){
	print COMBI "$zusatz\n";
      }
      
      if ($estfn){
	print COMBI "$estfn\n";
      }
      
      if ($hsfn){
	print COMBI "$hsfn\n";
      }
      
      if ($sachlben){
	print COMBI "$sachlben\n";
      }
      
      if ($gtu){
	print COMBI "$gtu\n";
      }
      
      if ($inunverkn){
	print COMBI "$inunverkn\n";
      }
      
      if ($uebershst){
	print COMBI "$uebershst\n";
      }
      
      print COMBI "endtit:\n";
      
      if ($erschjahr){
	($ejahr)=$erschjahr=~/.*(\d\d\d\d).*/;

	print COMBI "beginerschjahr: $ejahr\n";
	print COMBI "enderschjahr:\n";
      }
      
      
      if ($swtidx != 0){
	print COMBI "beginswt:\n";

	my $singleswt;
	my @singleswts;
	my @allswts;

	foreach $singleswt (@schlagwort){
	  @singleswts=split(";",$singleswt);
	  push @allswts, @singleswts;
	}

	my @sallswts=sort @allswts;

	my $prev = 'gibbetnit';
	my @usingleswts = grep($_ ne $prev && ($prev = $_), @sallswts);

	foreach $singleswt (@usingleswts) {
	  ($verwidn)=$singleswt=~/^IDN: (\d+)/;
	  print COMBI $swtbuf[$verwidn];
	}

	print COMBI "endswt:\n";
      }

      if ($notidx != 0){
	print COMBI "beginnot:\n";
	foreach $verwidn (@nota){
	  print COMBI $notbuf[$verwidn];
	}
	print COMBI "endnot:\n";
      }
      
      print COMBI "\f\n";
    }
    else {
      print TITWAIS "idn: $idn\n";
      print TITWAIS "hst: $hst\n" unless (!$hst);
      print TITWAIS "slb: $sachlben\n" unless (!$sachlben);
      print TITWAIS "zus: $zusatz\n" unless (!$zusatz);
      print TITWAIS "ast: $ast\n" unless (!$ast);
      print TITWAIS "\f\n";
    }
    undef $autidx;
    undef $swtidx;
    undef $koridx;
    undef $isbnidx;
    undef $issnidx;
    undef $wstidx;
    undef $abstractidx;
    undef $psthtsidx;
    undef $beigwerkidx;
    undef $artinhidx;
    undef $singleartinh;
    undef $singleisbn;
    undef $singleissn;
    undef $ejahr;
    undef @autor;
    undef @koerperschaft;
    undef @schlagwort;
    undef @nota;
    undef @artinh;
    undef @isbn;
    undef @issn;
    undef @wst;
    undef @abstract;
    undef @psthts;
    undef @beigwerk;
    undef $singlewst;
    undef $singleabstract;
    undef $singlepsthts;
    undef $singlebeigwerk;
    undef $hst;
    undef $zusatz;
    undef $sachlben;
    undef $vorlverf;
    undef $ausg;
    undef $verlagsort;
    undef $verlag;
    undef $erschjahr;
    undef $kollation;
    undef $bindpreis;
    undef $uebershst;
    undef $issn;
    undef $isbn;
    undef $verwverw;
    undef $bez;
    undef $pers;
    undef $urh;
    undef $kor;
    undef $titnot;
    undef $gtf;
    undef $zusatz;
    undef $gtm;
    undef $gtu;
    undef $uebershst;
    undef $swtlok;
    undef $ast;
    undef $esthe;
    undef $estfn;
    undef $zuergurh;
    undef $vorlbeigwerk;
    undef $gemeinsang;
    undef $sachlben;
    undef $vorlunter;
    undef $weitereort;
    undef $aufnahmeort;
    undef $aufnahmejahr;
    undef $matbenennung;
    undef $sonstmatben;
    undef $sonstang;
    undef $begleitmat;
    undef $fussnote;
    undef $hsfn;
    undef $sprache;
    undef $mass;
    undef $inunverkn;
    undef $rem;
    undef $bemerk;
  }
}

sub print_help {
    print "meta2wais.pl - Generierung von Einlade-Dateien fuer eine Volltextrecherche\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n\n";

    print " Zu bearbeitende Stammdateien: \n";
    print "  -all                    : Alle\n";
    print "  -aut                    : Autoren\n";
    print "  -kor                    : Koerperschaften\n";
    print "  -swt                    : Schlagworte\n";
    print "  -tit                    : Titel\n";
    print "  -combined               : Alles in eine Datei data.wais\n";
    print "  --idnprefix=abc         : Verwende diesen Prefix bei IDNs\n";
    print " CharEncoding: \n";
    print "  -dos                    : DOS Encodingn"; 
    print "  -encoding               : Generelles Encoding\n";
    print "  -with-umlaut            : Mit Umlauten";

    exit;
}
