#!/usr/bin/perl

#####################################################################
#
#  meta2sql.pl 
#
#  Generierung von SQL-Einladedateien aus dem Meta-Format
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

&GetOptions("mysql" => \$mysql,
	    "adabas" => \$ad,
	    "pg" => \$pg,
	    "plainsql" => \$sql,
            "aut" => \$aut, 
            "tit" => \$tit,
            "swt" => \$swt,
            "not" => \$not,
            "kor" => \$kor,
            "mex" => \$mex,
            "vbu" => \$vbu,
            "dos" => \$dos,
            "encoding" => \$encoding,
	    "all" => \$all,
	    "idn-mode=s" => \$idnmode,
	    "offset=s" => \$offset,
	    "sigel=s" => \$sigel,
	    "adabas-user=s" => \$aduser,
	    "adabas-passwd=s" => \$adpasswd,
	    "adabas-dbname=s" => \$addb,
	    "exp-dir=s" => \$expdir,
	    "help" => \$help
	    );

if ($help){
    print_help();
}

# Es ist keine gleichzeitige Konvertierung in MEHRERE SQL-Ausgabeformate
# moeglich

$exports=$exports|1 if ($mysql);
$exports=$exports|2 if ($pg);
$exports=$exports|4 if ($ad);
$exports=$exports|8 if ($sql);

if (($exports != 1)&&($exports != 2)&&($exports != 4)&&($exports != 8)){
    print "\nBitte geben Sie nur EIN SQL-Ausgabeformat an\n\n";
    exit;
}

# Standardeinstellungen (mysql/alle)

if ((!$msql)&&(!$pg)&&(!$ad)&&(!$sql)){
    $mysql=1;
}

if ((!$tit)&&(!$aut)&&(!$kor)&&(!$not)&&(!$swt)&&(!$mex)){
    $all=1;
}

$aduser="username" unless ($aduser);
$adpasswd="Geheim" unless ($adpasswd);
$addb="openbib" unless ($addb);

$dir=`pwd`;
chop $dir;

pg_init() if ($pg);
ad_init() if ($ad);
mysql_init() if ($mysql);

#####################################################################   
# Erzeuge Autoren
#####################################################################   


if (($aut)||($all)){
    $autoren="aut.exp";
    $autverwcount=0;
    
    pg_aut_init() if ($pg);
    ad_aut_init() if ($ad);
    sql_aut_init() if ($sql);
    mysql_aut_init() if ($mysql);

    open(AUT,$autoren);
    
    $first=1;

    while (<AUT>){
	chop;
	chop if (/
$/);
	if (/^     /){	# 
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
    
    pg_aut_cleanup() if ($pg);
    ad_aut_cleanup() if ($ad);
    sql_aut_cleanup() if ($sql);
    mysql_aut_cleanup() if ($mysql);
}

#####################################################################   
# Erzeuge Koerperschaften 
#####################################################################   

if (($kor)||($all)){
    $koerperschaften="kor.exp";
    
    pg_kor_init() if ($pg);
    ad_kor_init() if ($ad);
    sql_kor_init() if ($sql);
    mysql_kor_init() if ($mysql);
    
    $korspaetcount=0;
    $korfruehcount=0;
    $korverwcount=0;
    $korcount=0;
    
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
		    $line=$line."\n";
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
    
    pg_kor_cleanup() if ($pg);
    ad_kor_cleanup() if ($ad);
    sql_kor_cleanup() if ($sql);
    mysql_kor_cleanup() if ($mysql);
}

#####################################################################   
# Erzeuge Schlagworte
#####################################################################   

if (($swt)||($all)){
    $schlagworte="swt.exp";
    
    pg_swt_init() if ($pg);
    ad_swt_init() if ($ad);
    sql_swt_init() if ($sql);
    mysql_swt_init() if ($mysql);
    
    $swtcount=0;
    $swtverwcount=0;
    $swtuebercount=0;
    $swtassozcount=0;
    $swtfruehcount=0;
    $swtspaetcount=0;
    
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
		    $line=$line."\n";
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
    
    pg_swt_cleanup() if ($pg);
    ad_swt_cleanup() if ($ad);
    sql_swt_cleanup() if ($sql);
    mysql_swt_cleanup() if ($mysql);
}

#####################################################################   
# Erzeuge Notationen
#####################################################################   

if (($not)||($all)){
    $notationen="not.exp";
    
    pg_not_init() if ($pg);
    ad_not_init() if ($ad);
    sql_not_init() if ($sql);
    mysql_not_init() if ($mysql);
    
    $notcount=0;
    $notverwcount=0;
    $notbenverwcount=0;
    
    open(NOT,$notationen);
    
    $first=1;
    
    while (<NOT>){
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
		    $line=$line."\n";
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
    close(NOT);

    pg_not_cleanup() if ($pg);
    ad_not_cleanup() if ($ad);
    sql_not_cleanup() if ($sql);
    mysql_not_cleanup() if ($mysql);
}

#####################################################################   
# Erzeuge Titel
#####################################################################   

if (($tit)||($all)){
    $titel="tit.exp";
    
    pg_tit_init() if ($pg);
    ad_tit_init() if ($ad);
    sql_tit_init() if ($sql);
    mysql_tit_init() if ($mysql);
    
    $titpsthtscount=0;
    $titbeigwrkcount=0;
    $titgtunvcount=0;
    $titisbncount=0;
    $titissncount=0;
    $titnercount=0;
    $titteiluwcount=0;
    $titstichwcount=0;
    $titnrcount=0;
    $titartinhcount=0;
    $titphysformcount=0;
    $titgtmcount=0;
    $titgtfcount=0;
    $titinverkncount=0;
    $titswtlokcount=0;
    $titswtregcount=0;
    $titverfcount=0;
    $titperscount=0;
    $titgperscount=0;
    $titurhcount=0;
    $titkorcount=0;
    $titnotcount=0;
    $titwstcount=0;
    $titurlcount=0;
    $titillangcount=0;
    
# Limits
    
    $lzusatz=1254;
    $lvorlverf=1254;
    $lfussnote=1254;
    $lverlag=1127;
    $lausg=1127;
    $lbemerk=164;
    $lerschjahr=180;
    
    
    %bezeich=('h',1);
    
    open(TIT,$titel);
    $titbufidx=0;
    
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
    
    pg_tit_cleanup() if ($pg);
    ad_tit_cleanup() if ($ad);
    sql_tit_cleanup() if ($sql);
    mysql_tit_cleanup() if ($mysql);
}

#####################################################################   
# Erzeuge Exemplardaten
#####################################################################   

if (($mex)||($all)){
    $exemplardaten="mex.exp";
    
    pg_mex_init() if ($pg);
    ad_mex_init() if ($ad);
    sql_mex_init() if ($sql);
    mysql_mex_init() if ($mysql);

    $mexsigncount=0;
    
    open(MEX,$exemplardaten);
    
    $first=1;
    
    while (<MEX>){
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
		    $line=$line."\n";
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
    
    close(MEX);
    
    pg_mex_cleanup() if ($pg);
    ad_mex_cleanup() if ($ad);
    sql_mex_cleanup() if ($sql);
    mysql_mex_cleanup() if ($mysql);
    
    pg_cleanup() if ($pg);
    ad_cleanup() if ($ad);
    mysql_cleanup() if ($mysql);
}

#####################################################################   
# Erzeuge Verbuchungss"atze
#####################################################################   

if (($vbu)||($all)){
    $verbuchungsdaten="vbu.exp";
    
    sql_vbu_init();

    open(VBU,$verbuchungsdaten);
    
    $first=1;
    
    while (<VBU>){
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
		bearbeite_vbuline($line);
		$line="";
	    }
	    else {
		if (!$first){
		    $line=$line."\n";
		    bearbeite_vbuline($line);
		}
		$line="";
		$first=0;
	    }
	    $last=$_;
	    $lasttype="full";
	}
    }
    
    if ($lasttype eq "empty"){
	bearbeite_vbuline($line."\n");
    }
    else {
	bearbeite_vbuline($last."\n");
    }
    
    undef $lasttype;
    
    close(VBU);
    
    sql_vbu_cleanup();
}

#####################################################################   
#####################################################################   

sub bisumlaut2html {
    my $line=shift @_;

    $line=~s/\&/\&amp\;/g;

    if ($dos){
	$line=~s/Å/\&uuml\;/g;
	$line=~s/Ñ/\&auml\;/g;
	$line=~s/î/\&ouml\;/g;
	$line=~s/ö/\&Uuml\;/g;
	$line=~s/ô/\&Ouml\;/g;
	$line=~s/é/\&Auml\;/g;
	$line=~s/·/\&szlig\;/g;
	$line=~s/™//g;
	$line=~s/#193//g;
	$line=~s/#208//g;
    }
    else {
	$line=~s/\}/\&uuml\;/g;
	$line=~s/\{/\&auml\;/g;
	$line=~s/\[/\&Auml\;/g;
	$line=~s/\]/\&Uuml\;/g;
	$line=~s/\|/\&ouml\;/g;
	$line=~s/\\/\&Ouml\;/g;
	$line=~s/\~/\&szlig\;/g;
	$line=~s/#193(.)/\&\1grave\;/g;
	$line=~s/#208(.)/\&\1cedil\;/g;
    }

    $line=~s/</\&lt\;/g;
    $line=~s/>/\&gt\;/g;
    $line=~s/#091/\[/g;
    $line=~s/#093/\]/g;

    $line=~s/¨//g;
    $line=~s/#123/\&auml\;/g;
    $line=~s/#124/\&ouml\;/g;
    $line=~s/#125/\&uuml\;/g;
    $line=~s/#194(.)/\&\1acute\;/g;

    $line=~s/#163/\&pound\;/g;
    $line=~s/#168/\&deg\;/g;
    $line=~s/#226/\&ETH\;/g;
    $line=~s/#243/\&eth\;/g;
    $line=~s/#233/\&Oslash\;/g;
    $line=~s/#249/\&oslash\;/g;
    $line=~s/#225/\&AElig\;/g;
    $line=~s/#241/\&aelig\;/g;
    $line=~s/#203/\'/g;
    $line=~s/#189//g; # ????
    $line=~s/#236/\&THORN\;/g; # 'grosses' Thorn
    $line=~s/#252/\&thorn\;/g; # 'kleines' Thorn
    $line=~s/#196(.)/\&\1tilde\;/g;
    $line=~s/#223(.)/\&\1tilde\;/g;
    $line=~s/#171/\&laquo\;/g;
    $line=~s/#187/\&raquo\;/g;
    $line=~s/#175/\&reg\;/g;
    $line=~s/#209(.)/\&\1cedil\;/g;
    $line=~s/#187(.)/\&raquo\;/g;
    $line=~s/#200(.)/\&\1uml\;/g;
    $line=~s/#206(.)/\1/g; # Rechts angesetztes H"ackchen
    $line=~s/#202(.)/\&\1ring\;/g;
    $line=~s/#249(.)/\&\1slash\;/g;
    $line=~s/#191/\&iquest\;/g; # inv. Questionmark
    $line=~s/#183/\&middot\;/g; # inv. Questionmark
    $line=~s/#245/\&sect\;/g; # Paragraph (tuerkisches i???)
    $line=~s/#250//g; # OE ligatur
    $line=~s/#215//g; # Querstrich
    $line=~s/#216//g; # Unterstreichung
    $line=~s/#205//g; # Doppelacute
    $line=~s/#233//g; # daenisches OE ligatur
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
    $line=~s/#195(.)/\&\1circ\;/g;
    $line=~s/#234//g; # oe ligatur

    # Eigene Ergaenzungen fuer andere Zeichen
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
    $line=~s/\$402z/z/g; # Z mit einem Punkt oben 
    $line=~s/\$415/d/g; # d oben durchgestrichen
    $line=~s/\$416/\&#140\;/g; # OE Ligatur
    $line=~s/\$417/\&#156\;/g; # oe Ligatur
    $line=~s/\$414/L/g; #
    $line=~s/\$404/l/g; #
    $line=~s/\$408/t/g; #

    $line=~s/∑s/\&#353\;/g; # s hacek

    return $line;
}

sub sisisumlaut2html {
    my $line=shift @_;

    # Caron
    
    $line=~s/∑s/\&#353\;/g; # s hacek
    $line=~s/∑S/\&#352\;/g; # S hacek
    $line=~s/∑c/\&#269\;/g; # c hacek
    $line=~s/∑C/\&#268\;/g; # C hacek
    $line=~s/∑d/\&#271\;/g; # d hacek
    $line=~s/∑D/\&#270\;/g; # D hacek
    $line=~s/∑e/\&#283\;/g; # d hacek
    $line=~s/∑E/\&#282\;/g; # D hacek
    $line=~s/∑l/\&#318\;/g; # l hacek
    $line=~s/∑L/\&#317\;/g; # L hacek
    $line=~s/∑n/\&#328\;/g; # n hacek
    $line=~s/∑N/\&#327\;/g; # N hacek
    $line=~s/∑r/\&#345\;/g; # r hacek
    $line=~s/∑R/\&#344\;/g; # R hacek
    $line=~s/∑t/\&#357\;/g; # t hacek
    $line=~s/∑T/\&#356\;/g; # T hacek
    $line=~s/∑z/\&#382\;/g; # n hacek
    $line=~s/∑Z/\&#381\;/g; # N hacek

    # Macron

    $line=~s/Øe/\&#275\;/g; # e oberstrich
    $line=~s/ØE/\&#274\;/g; # e oberstrich
    $line=~s/Øa/\&#257\;/g; # a oberstrich
    $line=~s/ØA/\&#256\;/g; # A oberstrich
    $line=~s/Øi/\&#299\;/g; # i oberstrich
    $line=~s/ØI/\&#298\;/g; # I oberstrich
    $line=~s/Øo/\&#333\;/g; # o oberstrich
    $line=~s/ØO/\&#332\;/g; # O oberstrich
    $line=~s/Øu/\&#363\;/g; # u oberstrich
    $line=~s/ØU/\&#362\;/g; # U oberstrich

    return $line;
}

sub bearbeite_autline {
    ($line)=@_;

    if ($encoding){
      $line=bisumlaut2html("$line");
    }
    else {
      $line=sisisumlaut2html("$line");
    }

    if ($line=~/^IDN  (\d+)/){
	$idn=$1;	
	$autverwidx=0;
	if (($idnmode eq "offset")&&($offset)) {
	    $idn=$idn+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $idn="$sigel$idn";
	}
    }
    if ($line=~/^6020 (.*)/){
	$autans=$1;
        chop $autans if ($autans=~m/
$/);
    }
    if ($line=~/^602[1-9] (.*)/){
	$verw=$1;
	chop $verw if ($verw=~m/
$/);
	$autverwbuf[$autverwidx++]=$verw;
    }
    
    if ($line=~/^ENDE/){
	print MYSQLAUTL "$idn|0|0|$autans|0|0\n" if ($mysql);
	print PGAUTL "$idn|0|0|$autans|0|0\n" if ($pg);
	print ADAUTL "$idn|0|0|$stringsep$autans$stringsep|0|0\n" if ($ad);
	print SQLAUTL "insert into aut values ($idn,0,0,\'$autans\',0,0);\n" if ($sql);
	if ($autverwidx != 0){
	    foreach $verw (@autverwbuf){
		print MYSQLAUTVERWL "$idn|$verw\n" if ($mysql);
		print PGAUTVERWL "$idn|$verw\n" if ($pg);
		print ADAUTVERWL "$idn|$stringsep$verw$stringsep\n" if ($ad);
		print SQLAUTL "insert into autverw values ($idn,\'$verw\');\n" if ($sql);
		    $autverwcount++;
	    }
	}
	undef @autverwbuf;
	undef $autverwidx;
	undef $verw;
	undef $autans;
	undef $idn;
    }
}

sub bearbeite_korline {
    ($line)=@_;

    if ($encoding){
      $line=bisumlaut2html("$line");
    }
    else {
      $line=sisisumlaut2html("$line");
    }

    if ($line=~/^IDN  (\d+)/){
	$idn=$1;	
	if (($idnmode eq "offset")&&($offset)) {
	    $idn=$idn+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $idn="$sigel$idn";
	}

	$korverwidx=0;
	$korfruehidx=0;
	$korspaetidx=0;
    }
    if ($line=~/^6120 (.*)/){
	$korans=$1;
	chop $korans if ($korans=~m/
$/);
    }
    if ($line=~/^612[1-9] (.*)/){
	$verw=$1;
	chop $verw if ($verw=~m/
$/);
	$korverwbuf[$korverwidx++]=$verw;
    }
    if ($line=~/^613[0-2] (.*)/){
	$frueh=$1;
	chop $frueh if ($frueh=~m/
$/);
	$korfruehbuf[$korfruehidx++]=$frueh;
    }
    if ($line=~/^613[3-5] (.*)/){
	$spaet=$1;
	chop $spaet if ($spaet=~m/
$/);
	$korspaetbuf[$korspaetidx++]=$spaet;
    }
    
    if ($line=~/^ENDE/){
	print MYSQLKORL "$idn|0|$korans|0\n" if ($mysql);
	print PGKORL "$idn|0|$korans|0\n" if ($pg);
	print ADKORL "$idn|0|$stringsep$korans$stringsep|0\n" if ($ad);
	print SQLKORL "insert into kor values ($idn,0,\'$korans\',0);\n" if ($sql);
	$korcount++;
	if ($korverwidx != 0){
	    foreach $verw (@korverwbuf){
		print MYSQLKORVERWL "$idn|$verw\n" if ($mysql);
		print PGKORVERWL "$idn|$verw\n" if ($pg);
		print ADKORVERWL "$idn|$stringsep$verw$stringsep\n" if ($ad);
		print SQLKORL "insert into korverw values ($idn,\'$verw\');\n" if ($sql);
		$korverwcount++;
	    }
	}
	if ($korfruehidx != 0){
	    foreach $frueh (@korfruehbuf){
		print MYSQLKORFRUEHL "$idn|$frueh\n" if ($mysql);
		print PGKORFRUEHL "$idn|$frueh\n" if ($pg);
		print ADKORFRUEHL "$idn|$stringsep$frueh$stringsep\n" if ($ad);
		print SQLKORL "insert into korfrueh values ($idn,\'$frueh\');\n" if ($sql);
		$korfruehcount++;
	    }
	}
	if ($korspaetidx != 0){
	    foreach $spaet (@korspaetbuf){
		print MYSQLKORSPAETL "$idn|$spaet\n" if ($mysql);
		print PGKORSPAETL "$idn|$spaet\n" if ($pg);
		print KORSPAETL "$idn|$stringsep$spaet$stringsep\n" if ($ad);
		print SQLKORL "insert into korspaet values ($idn,\'$spaet\');\n" if ($sql);
		$korspaetcount++;
	    }
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
      $line=bisumlaut2html("$line");
    }
    else {
      $line=sisisumlaut2html("$line");
    }

    if ($line=~/^IDN  (\d+)/){
	$idn=$1;	
	if (($idnmode eq "offset")&&($offset)) {
	    $idn=$idn+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $idn="$sigel$idn";
	}
	$swtverwidx=0;
	$swtueberidx=0;
	$swtassozidx=0;
	$swtfruehidx=0;
	$swtspaetidx=0;
    }
    if ($line=~/^6510 (.*)/){
	$schlagw=$1;
	chop $schlagw if ($schlagw=~m/
$/);
    }
    if ($line=~/^6511 (.*)/){
	$erlaeut=$1;
	chop $erlaeut if ($erlaeut=~m/
$/);
    }
    if ($line=~/^652[0-9] (.*)/){
	$verw=$1;
	chop $verw if ($verw=~m/
$/);
	$swtverwbuf[$swtverwidx++]=$verw;
    }
    if ($line=~/^655[0-5] (.*)/){
	$ueber=$1;
	chop $ueber if ($ueber=~m/
$/);
	$swtueberbuf[$swtueberidx++]=$ueber;
    }
    if ($line=~/^656[0-9] (.*)/){
	$assoz=$1;
	chop $assoz if ($assoz=~m/
$/);
	$swtassozbuf[$swtassozidx++]=$assoz;
    }
    if ($line=~/^657[0-1] (.*)/){
	$frueh=$1;
	chop $verw if ($verw=~m/
$/);
	$swtfruehbuf[$swtfruehidx++]=$frueh;
    }
    if ($line=~/^657[2-3] (.*)/){
	$spaet=$1;
	chop $spaet if ($spaet=~m/
$/);
	$swtspaetbuf[$swtspaetidx++]=$spaet;
    }
    
    if ($line=~/^ENDE/){
	print MYSQLSWTL "$idn|0|$schlagw|$erlaeut|0\n" if ($mysql);
	print PGSWTL "$idn|0|$schlagw|$erlaeut|0\n" if ($pg);
	print ADSWTL "$idn|0|$stringsep$schlagw$stringsep|$stringsep$erlaeut$stringsep|0\n" if ($ad);	
	print SQLSWTL "insert into swt values ($idn,0,\'$schlagw\',\'$erlaeut\',0);\n" if ($sql);
	$swtcount++;
	if ($swtverwidx != 0){
	    foreach $verw (@swtverwbuf){
		print MYSQLSWTVERWL "$idn|$verw\n" if ($mysql);
		print PGSWTVERWL "$idn|$verw\n" if ($pg);
		print ADSWTVERWL "$idn|$stringsep$verw$stringsep\n" if ($ad);
		print SQLSWTL "insert into swtverw values ($idn,\'$verw\');\n" if ($sql);
		$swtverwcount++;
	    }
	}
	if ($swtueberidx != 0){
	    foreach $ueber (@swtueberbuf){
		print MYSQLSWTUEBERL "$idn|$ueber\n" if ($mysql);
		print PGSWTUEBERL "$idn|$ueber\n" if ($pg);
		print ADSWTUEBERL "$idn|$stringsep$ueber$stringsep\n" if ($ad);
		print SQLSWTL "insert into swtueber values ($idn,\'$ueber\');\n" if ($sql);
		$swtuebercount++;
	    }
	}
	if ($swtassozidx != 0){
	    foreach $assoz (@swtassozbuf){
		print MYSQLSWTASSOZL "$idn|$assoz\n" if ($mysql);
		print PGSWTASSOZL "$idn|$assoz\n" if ($pg);
		print ADSWTASSOZL "$idn|$stringsep$assoz$stringsep\n" if ($ad);
		print SQLSWTL "insert into swtassoz values ($idn,\'$assoz\');\n" if ($sql);
		$swtassozcount++;
	    }
	}
	if ($swtfruehidx != 0){
	    foreach $frueh (@swtfruehbuf){
		print MYSQLSWTFRUEHL "$idn|$frueh\n" if ($mysql);
		print PGSWTFRUEHL "$idn|$frueh\n" if ($pg);
		print ADSWTFRUEHL "$idn|$stringsep$frueh$stringsep\n" if ($ad);
		print SQLSWTL "insert into swtfrueh values ($idn,\'$frueh\');\n" if ($sql);
		$swtfruehcount++;
	    }
	}
	if ($swtspaetidx != 0){
	    foreach $spaet (@swtspaetbuf){
		print MYSQLSWTSPAETL "$idn|$spaet\n" if ($mysql);
		print PGSWTSPAETL "$idn|$spaet\n" if ($pg);
		print ADSWTSPAETL "$idn|$stringsep$spaet$stringsep\n" if ($ad);
		print SQLSWTL "insert into swtspaet values ($idn,\'$spaet\');\n" if ($sql);
		$swtspaetcount++;
	    }
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

sub bearbeite_notline {
    ($line)=@_;

    if ($encoding){
      $line=bisumlaut2html("$line");
    }
    else {
      $line=sisisumlaut2html("$line");
    }

    if ($line=~/^IDN  (\d+)/){
	$idn=$1;	
	if (($idnmode eq "offset")&&($offset)) {
	    $idn=$idn+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $idn="$sigel$idn";
	}
	$notverwidx=0;
	$notbenverwidx=0;
    }
    if ($line=~/^8000 (.*)/){
	$notation=$1;
	chop $notation if ($notation=~m/
$/);
    }
    if ($line=~/^8015 (.*)/){
	$benennung=$1;
	chop $benennung if ($benennung=~m/
$/);
    }
    if ($line=~/^8060 IDN: (\d+)/){
	$oberbegriff=$1;
    }
    if ($line=~/^8020 (.*)/){
	$verw=$1;
	chop $verw if ($verw=~m/
$/);
	$verwbuf[$notverw++]=$verw;
    }
    if ($line=~/^8040 (.*)/){
	$benverw=$1;
	chop $benverw if ($benverw=~m/
$/);
	$benverwbuf[$notbenverw++]=$benverw;
    }
    if ($line=~/^8200 (.*)/){
	$abrufzeichen=$1;
	chop $abrufzeichen if ($abrufzeichen=~m/
$/);
    }
    if ($line=~/^8250 (.*)/){
	$beschrnot=$1;
	chop $beschrnot if ($beschrnot=~m/
$/);
    }
    if ($line=~/^8300 (.*)/){
	$abrufr=$1;
	chop $abrufnr if ($abrufnr=~m/
$/);
    }    
    if ($line=~/^ENDE/){
        if (!$oberbegriff){
            $oberbegriff=0;
        }
	if ($idn){
	    print MYSQLNOTL "$idn|0|0|$notation|$benennung|$abrufzeichen|$beschrnot|$abrufnr|$oberbegriff\n" if ($mysql);
	    print PGNOTL "$idn|0|0|$notation|$benennung|$abrufzeichen|$beschrnot|$abrufnr|$oberbegriff\n" if ($pg);
	    print ADNOTL "$idn|0|0|$stringsep$notation$stringsep|$stringsep$benennung$stringsep|$stringsep$abrufzeichen$stringsep|$stringsep$beschrnot$stringsep|$stringsep$abrufr$stringsep|$oberbegriff\n" if ($ad);
	    print SQLNOTL "insert into notation values ($idn,0,0,\'$notation\',\'$benennung\',\'$abrufzeiche\',\'$beschrnot\',\'$abrufr\',$oberbegriff);\n" if ($sql);
	    $notcount++;
	}
	if ($notverwidx != 0){
	    foreach $verw (@notverwbuf){
		print MYSQLNOTVERWL "$idn|$verw\n" if ($mysql);
		print PGNOTVERWL "$idn|$verw\n" if ($pg);
		print ADNOTVERWL "$idn|$stringsep$verw$stringsep\n" if ($ad);
		print SQLNOTL "insert into notverw values ($idn,\'$verw\');\n" if ($sql);
		$notverwcount++;
	    }
	}
	if ($notbenverwidx != 0){
	    foreach $benverw (@notbenverwbuf){
		print MYSQLNOTBENVERWL "$idn|$benverw\n" if ($mysql);
		print PGNOTBENVERWL "$idn|$benverw\n" if ($pg);
		print ADNOTBENVERWL "$idn|$stringsep$benverw$stringsep\n" if ($ad);
		print SQLNOTL "insert into notbenverw values ($idn,\'$benverw\')\n" if ($sql);

		$notbenverwcount++;
	    }
	}
	undef $idn;	
	undef $notverwidx;
	undef $notbenverwidx;
        undef @notverwbuf;
        undef @notbenverwbuf;
        undef $verw;
        undef $benverw;
        undef $abrufr;
        undef $abrufzeichen;
        undef $beschrnot;
        undef $notation;
        undef $benennung;
        undef $oberbegriff;
    }
}

sub bearbeite_titline {
    ($line)=@_;

    if ($encoding){
      $line=bisumlaut2html("$line");
    }
    else {
      $line=sisisumlaut2html("$line");
    }

    if ($line=~/^IDN  (\d+)/){
	$idn=$1;	
	if (($idnmode eq "offset")&&($offset)) {
	    $idn=$idn+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $idn="$sigel$idn";
	}
    }
    if ($line=~/^1100 (\d)/){
	$titeltyp=$1;
    }
    if ($line=~/^2000.IDN: (\d+)/){
	$verfverw=$1;
	if (($idnmode eq "offset")&&($offset)) {
	    $verfverw=$verfverw+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $verfverw="$sigel$verfverw";
	}

	print MYSQLTITVERFL "$idn|$verfverw\n" if ($mysql);
	print PGTITVERFL "$idn|$verfverw\n" if ($pg);
	print ADTITVERFL "$idn|$verfverw\n" if ($ad);
	print SQLTITL "insert into titverf values ($idn,$verfverw);\n" if ($sql);
	$titverfcount++;
    }
    if ($line=~/^2003(.)IDN: (\d+)/){
	$bez=$1;	
	$pers=$2;
	if (($idnmode eq "offset")&&($offset)) {
	    $pers=$pers+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $pers="$sigel$pers";
	}

        if ($bezeich{$bez} ne "") {
	    print MYSQLTITPERSL "$idn|$pers|$bezeich{$bez}\n" if ($mysql);
	    print PGTITPERSL "$idn|$pers|$bezeich{$bez}\n" if ($pg);
	    print ADTITPERSL "$idn|$pers|$bezeich{$bez}\n" if ($ad);  
	    print SQLTITL "insert into titpers values ($idn,$pers,$bezeich{$bez});\n" if ($sql);
	}
        else {
	    print MYSQLTITPERSL "$idn|$pers\n" if ($mysql);
	    print PGTITPERSL "$idn|$pers\n" if ($pg);
	    print ADTITPERSL "$idn|$pers\n" if ($ad);	    
	    print SQLTITL "insert into titpers values ($idn,$pers,0);\n" if ($sql);
        }
	$titperscount++;
    }
    if ($line=~/^2004(.)IDN: (\d+)/){
	$bez=$1;	
	$pers=$2;
	if (($idnmode eq "offset")&&($offset)) {
	    $pers=$pers+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $pers="$sigel$pers";
	}

        if ($bezeich{$bez} ne "") {
	    print MYSQLTITGPERSL "$idn|$pers|$bezeich{$bez}\n" if ($mysql);
	    print PGTITGPERSL "$idn|$pers|$bezeich{$bez}\n" if ($pg);
	}
        else {
	    print MYSQLTITGPERSL "$idn|$pers\n" if ($mysql);
	    print PGTITGPERSL "$idn|$pers\n" if ($pg);
        }
	$titgperscount++;
    }
    if ($line=~/^2400.IDN: (\d+)/){
	$urh=$1;
	if (($idnmode eq "offset")&&($offset)) {
	    $urh=$urh+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $urh="$sigel$urh";
	}

	print MYSQLTITURHL "$idn|$urh\n" if ($mysql);
	print PGTITURHL "$idn|$urh\n" if ($pg);
	print ADTITURHL "$idn|$urh\n" if ($ad);
	print SQLTITL "insert into titurh values ($idn,$urh);\n" if ($sql);
	$titurhcount++;
    }
    if ($line=~/^2403.IDN: (\d+)/){
	$kor=$1;
	if (($idnmode eq "offset")&&($offset)) {
	    $kor=$kor+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $kor="$sigel$kor";
	}

	print MYSQLTITKORL "$idn|$kor\n" if ($mysql);
	print PGTITKORL "$idn|$kor\n" if ($pg);
	print ADTITKORL "$idn|$kor\n" if ($ad);
	print SQLTITL "insert into titkor values ($idn,$kor);\n" if ($sql);
	$titkorcount++;
    }
    if ($line=~/^2800.(.*)/){
	$esthe=$1;
	chop $esthe if ($esthe=~m/
$/);
    }
    if ($line=~/^2900.(.*)/){
	$ast=$1;
	chop $ast if ($ast=~m/
$/);
    }
    if ($line=~/^3000.(.*)/){
	$hst=$1;
	chop $hst if ($hst=~m/
$/);
    }
    if ($line=~/^3030.(.*)/){
	$zuergurh=$1;
	chop $zuergurh if ($zuergurh=~m/
$/);
    }
    if ($line=~/^3040.(.*)/){
	$titzusatz=$1;
	chop $titzusatz if ($titzusatz=~m/
$/);
    }
    if ($line=~/^3100.(.*)/){
	$psthts=$1;
	chop $psthts if ($psthts=~m/
$/);

	print MYSQLTITPSTHTSL "$idn|$psthts\n" if ($mysql);
	print PGTITPSTHTSL "$idn|$psthts\n" if ($pg);

	$titpsthtscount++;

    }
    if ($line=~/^3500.(.*)/){
	$vorlverf=$1;
	chop $vorlverf if ($vorlverf=~m/
$/);
    }
    if ($line=~/^3600.(.*)/){
	$vorlunter=$1;
	chop $vorlunter if ($vorlunter=~m/
$/);
    }
    if ($line=~/^3610.(.*)/){
	$vorlbeigwerk=$1;
	chop $vorlbeigwerk if ($vorlbeigwerk=~m/
$/);
    }
    if ($line=~/^3615.(.*)/){
	$beigwerk=$1;
	chop $beigwerk if ($beigwerk=~m/
$/);

	print MYSQLTITBEIGWERKL "$idn|$beigwerk\n" if ($mysql);
	print PGTITBEIGWERKL "$idn|$beigwerk\n" if ($pg);

	$titbeigwerkcount++;

    }
    if ($line=~/^3650.(.*)/){
	$gemeinsang=$1;
	chop $gemeinsang if ($gemeinsang=~m/
$/);
    }
    if ($line=~/^3700.(.*)/){
	$ausg=$1;
	chop $ausg if ($ausg=~m/
$/);
    }
    if ($line=~/^3750.(.*)/){
	$mass=$1;
	chop $mass if ($mass=~m/
$/);
    }
    if ($line=~/^4000.(.*)/){
	$verlagsort=$1;
	chop $verlagsort if ($verlagsort=~m/
$/);
    }
    if ($line=~/^4002 (.*)/){
	$verlag=$1;
	chop $verlag if ($verlag=~m/
$/);
    }
    if ($line=~/^4004.(.*)/){
	$weitereort=$1;
	chop $weitereort if ($weitereort=~m/
$/);
    }
    if ($line=~/^4015.(.*)/){
	$aufnahmeort=$1;
	chop $aufnahmeort if ($aufnahmeort=~m/
$/);
    }
    if ($line=~/^4020.(.*)/){
	$aufnahmejahr=$1;
	chop $aufnahmejahr if ($aufnahmejahr=~m/
$/);
    }
    if ($line=~/^4025 (.*)/){
	$bindpreis=$1;
	chop $bindpreis if ($bindpreis=~m/
$/);
    }
    if ($line=~/^4040 (.*)/){
	$erschjahr=$1;
	chop $erschjahr if ($erschjahr=~m/
$/);
    }
    if ($line=~/^8070 (.*)/){
	$anserschjahr=$1;
	chop $anserschjahr if ($anserschjahr=~m/
$/);
    }
    if ($line=~/^4102 (.*)/){
	$kollation=$1;
	chop $kollation if ($kollation=~m/
$/);
    }
    if ($line=~/^4115.(.*)/){
	$matbenennung=$1;
	chop $matbenennung if ($matbenennung=~m/
$/);
    }
    if ($line=~/^4112.(.*)/){
	$sonstmatben=$1;
	chop $sonstmatben if ($sonstmatben=~m/
$/);
    }
    if ($line=~/^4115.(.*)/){
	$sonstang=$1;
	chop $sonstang if ($sonstang=~m/
$/);
    }
    if ($line=~/^4125.(.*)/){
	$begleitmat=$1;
	chop $begleitmat if ($begleitmat=~m/
$/);
    }
    if ($line=~/^4200 IDN: (\d+)$/){
	$gtf=$1;
	if (($idnmode eq "offset")&&($offset)) {
	    $gtf=$gtf+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $gtf="$sigel$gtf";
	}

	print MYSQLTITGTFL "$idn|$gtf|\n" if ($mysql);
	print PGTITGTFL "$idn|$gtf|\n" if ($pg);
	print ADTITGTFL "$idn|$gtf|\n" if ($ad);
	print SQLTITL "insert into titgtf values ($idn,$gtf,'');\n" if ($sql);
	$titgtfcount++;
    }
    if ($line=~/^4200 IDN: (\d+) ; (.*)$/){
	$gtf=$1;
	if (($idnmode eq "offset")&&($offset)) {
	    $gtf=$gtf+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $gtf="$sigel$gtf";
	}

        $zusatz=$2;
        chop $zusatz if ($zusatz=~m/
$/);
	print MYSQLTITGTFL "$idn|$gtf|$zusatz\n" if ($mysql);
	print PGTITGTFL "$idn|$gtf|$zusatz\n" if ($pg);
	print ADTITGTFL "$idn|$gtf|$stringsep$zusatz$stringsep\n" if ($ad);
	print SQLTITL "insert into titgtf values ($idn,$gtf,\'$zusatz\');\n" if ($sql);
	$titgtfcount++;
    }
    if ($line=~/^4203 IDN: (\d+)$/){
	$gtm=$1;
	if (($idnmode eq "offset")&&($offset)) {
	    $gtm=$gtm+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $gtm="$sigel$gtm";
	}

	print MYSQLTITGTML "$idn|$gtm|\n" if ($mysql);
	print PGTITGTML "$idn|$gtm|\n" if ($pg);
	print ADTITGTML "$idn|$gtm|$stringsep$stringsep\n" if ($ad);	
	print SQLTITL "insert into titgtm values ($idn,\'$gtm\','');\n" if ($sql);
	$titgtmcount++;
    }
    if ($line=~/^4203 IDN: (\d+) ; (.*)$/){
	$gtm=$1;
	if (($idnmode eq "offset")&&($offset)) {
	    $gtm=$gtm+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $gtm="$sigel$gtm";
	}

        $zusatz=$2;
        chop $zusatz if ($zusatz=~m/
$/);
	print MYSQLTITGTML "$idn|$gtm|$zusatz\n" if ($mysql);
	print PGTITGTML "$idn|$gtm|$zusatz\n" if ($pg);
	print ADTITGTML "$idn|$gtm|$stringsep$zusatz$stringsep\n" if ($ad);
	print SQLTITL "insert into titgtm values ($idn,$gtm,\'$zusatz\');\n" if ($sql);
	$titgtmcount++;
    }
    if ($line=~/^4240 (.*)/){
	$gtu=$1;
	chop $gtu if ($gtu=~m/
$/);
	print MYSQLTITGTUNVL "$idn|$gtu\n" if ($mysql);
	print PGTITGTUNVL "$idn|$gtu\n" if ($pg);
	print ADTITGTUNVL "$idn|$gtu\n" if ($ad);
	print SQLTITL "insert into titgtunv values ($idn,\'$gtu\');\n" if ($sql);
	$titgtunvcount++;
    }
    if ($line=~/^4260 IDN: (\d+) ; (.*)$/){
	$inverkn=$1;
	$zusatz=$2;

	if (($idnmode eq "offset")&&($offset)) {
	    $inverkn=$inverkn+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $inverkn="$sigel$inverkn";
	}

	chop $inverkn if ($inverkn=~m/
$/);
	print MYSQLTITINVERKNL "$idn|$inverkn|$zusatz\n" if ($mysql);
	print PGTITINVERKNL "$idn|$inverkn|$zusatz\n" if ($pg);
	print ADTITINVERKNL "$idn|$inverkn|$zusatz\n" if ($ad);
	print SQLTITL "insert into titinverkn values ($idn,\'$inverkn\',\'$zusatz\');\n" if ($sql);
	$titinverkncount++;
    }
    if ($line=~/^4260 IDN: (\d+)$/){
	$inverkn=$1;

	if (($idnmode eq "offset")&&($offset)) {
	    $inverkn=$inverkn+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $inverkn="$sigel$inverkn";
	}

	chop $inverkn if ($inverkn=~m/
$/);
	print MYSQLTITINVERKNL "$idn|$inverkn|\n" if ($mysql);
	print PGTITINVERKNL "$idn|$inverkn|\n" if ($pg);
	print ADTITINVERKNL "$idn|$inverkn|\n" if ($ad);
	print SQLTITL "insert into titinverkn values ($idn,\'$inverkn\',\'\');\n" if ($sql);
	$titinverkncount++;
    }
    if ($line=~/^4270.(.*)/){
	$bemerk=$1;
	chop $bemerk if ($bemerk=~m/
$/);
    }
    if ($line=~/^4300.(.*)/){
	$estfn=$1;
	chop $estfn if ($estfn=~m/
$/);
    }
    if ($line=~/^4330 (.*)/){
	$uebershst=$1;
	chop $uebershst if ($uebershst=~m/
$/);
    }
    if ($line=~/^4400.(.*)/){
	$fussnote=$1;
	chop $fussnote if ($fussnote=~m/
$/);
    }
    if ($line=~/^4500.(.*)/){
	$hsfn=$1;
	chop $hsfn if ($hsfn=~m/
$/);
    }
    if ($line=~/^4506.(.*)/){
	$inunverkn=$1;
	chop $inunverkn if ($inunverkn=~m/
$/);
    }
    if ($line=~/^4600 (.*)/){
	$isbn=$1;
	chop $isbn if ($isbn=~m/
$/);
	print MYSQLTITISBNL "$idn|$isbn\n" if ($mysql);
	print PGTITISBNL "$idn|$isbn\n" if ($pg);
	print ADTITISBNL "$idn|$isbn\n" if ($ad);
	print SQLTITL "insert into titisbn values ($idn,\'$isbn\');\n" if ($sql);
	$titisbncount++;
    }
    if ($line=~/^4650 (.*)/){
	$issn=$1;
	chop $issn if ($issn=~m/
$/);
	print MYSQLTITISSNL "$idn|$issn\n" if ($mysql);
	print PGTITISSNL "$idn|$issn\n" if ($pg);
	print ADTITISSNL "$idn|$issn\n" if ($ad);
	print SQLTITL "insert into titissn values ($idn,\'$issn\');\n" if ($sql);
	$titissncount++;
    }

    if ($line=~/^4700 (.*)/){
	$ner=$1;
	chop $ner if ($ner=~m/
$/);
	print MYSQLTITNERL "$idn|$ner\n" if ($mysql);
	$titnercount++;
    }

    if ($line=~/^9000 (.*)/){
	$abstract=$1;
	chop $abstract if ($abstract=~m/
$/);
	print MYSQLTITABSTRACTL "$idn|$abstract\n" if ($mysql);
	$titabstractcount++;
    }


    if ($line=~/^8060 (.*)/){
	$sammelverm=$1;
	chop $sammelverm if ($sammelverm=~m/
$/);
	print MYSQLTITSAMMELVERML "$idn|$sammelverm\n" if ($mysql);
	$titsammelvermcount++;
    }

    if ($line=~/^8080 (.*)/){
	$anghst=$1;
	chop $anghst if ($anghst=~m/
$/);
	print MYSQLTITANGHSTL "$idn|$anghst\n" if ($mysql);
	$titanghstcount++;
    }

    if ($line=~/^8081 (.*)/){
	$pausg=$1;
	chop $pausg if ($pausg=~m/
$/);
	print MYSQLTITPAUSGL "$idn|$pausg\n" if ($mysql);
	$titpausgcount++;
    }

    if ($line=~/^8082 (.*)/){
	$titbeil=$1;
	chop $titbeil if ($titbeil=~m/
$/);
	print MYSQLTITTITBEILL "$idn|$titbeil\n" if ($mysql);
	$tittitbeilcount++;
    }

    if ($line=~/^8083 (.*)/){
	$bezwerk=$1;
	chop $bezwerk if ($bezwerk=~m/
$/);
	print MYSQLTITBEZWERKL "$idn|$bezwerk\n" if ($mysql);
	$titbezwerkcount++;
    }

    if ($line=~/^8084 (.*)/){
	$fruehausg=$1;
	chop $fruehausg if ($fruehausg=~m/
$/);
	print MYSQLTITFRUEHAUSGL "$idn|$fruehausg\n" if ($mysql);
	$titfruehausgcount++;
    }

    if ($line=~/^8085 (.*)/){
	$fruehtit=$1;
	chop $fruehtit if ($fruehtit=~m/
$/);
	print MYSQLTITFRUEHTITL "$idn|$fruehtit\n" if ($mysql);
	$titfruehtitcount++;
    }

    if ($line=~/^8086 (.*)/){
	$spaetausg=$1;
	chop $spaetausg if ($spaetausg=~m/
$/);
	print MYSQLTITSPAETAUSGL "$idn|$spaetausg\n" if ($mysql);
	$titspaetausgcount++;
    }

    if ($line=~/^8090 (.*)/){
	$erscheinungsverlauf=$1;
	chop $erscheinungsverlauf if ($erscheinungsverlauf=~m/
$/);
    }

    if ($line=~/^2700 (.*)/){
	$wst=$1;
	chop $wst if ($wst=~m/
$/);
	print MYSQLTITWSTL "$idn|$wst\n" if ($mysql);
	$titwstcount++;
    }
    if ($line=~/^8050 (.*)/){
	$url=$1;
	chop $url if ($url=~m/
$/);
	print MYSQLTITURLL "$idn|$url\n" if ($mysql);
	$titurlcount++;
    }

    if ($line=~/^8100 (.*)/){
	$illang=$1;
	chop $illang if ($illang=~m/
$/);
	print MYSQLTITILLANGL "$idn|$illang\n" if ($mysql);
	$titillangcount++;
    }

    if ($line=~/^8110 (.*)/){
	$verfquelle=$1;
	chop $verfquelle if ($verfquelle=~m/
$/);
    }

    if ($line=~/^8111 (.*)/){
	$eortquelle=$1;
	chop $eortquelle if ($eortquelle=~m/
$/);
    }

    if ($line=~/^8112 (.*)/){
	$ejahrquelle=$1;
	chop $ejahrquelle if ($ejahrquelle=~m/
$/);
    }

    if ($line=~/^5050 (.*)/){
	$sachlben=$1;
	chop $sachlben if ($sachlben=~m/
$/);
    }

    if ($line=~/^5246.(.*)/){
	$sprache=$1;
	chop $sprache if ($sprache=~m/
$/);
    }
    if ($line=~/^5260.(.*)/){
	$artinh=$1;
	chop $artinh if ($artinh=~m/
$/);

	print MYSQLTITARTINHL "$idn|$artinh\n" if ($mysql);
	print PGTITARTINHL "$idn|$artinh\n" if ($pg);

	$titartinhcount++;

    }
    if ($line=~/^5650.(IDN:.+)$/){
	$swtlok=$1;

	my @allswts;
	my @singleswts=split(";",$swtlok);
	my @sallswts=sort @singleswts;

#	print MYSQLTITSWTLOKL "\n" if ($mysql);
#	print MYSQLTITSWTLOKL @sallswts if ($mysql);
#	print MYSQLTITSWTLOKL "\n" if ($mysql);

	my $prev = 'nonesuch';
	my @usingleswts = grep($_ ne $prev && ($prev = $_), @sallswts);

	foreach $singleswt (@usingleswts) {
	  ($swtlok)=$singleswt=~/^IDN: (\d+)/;

	  if (($idnmode eq "offset")&&($offset)) {
	    $swtlok=$swtlok+$offset;
	  }
	  if (($idnmode eq "sigel")&&($sigel)){
	    $swtlok="$sigel$swtlok";
	  }

	  print MYSQLTITSWTLOKL "$idn|$swtlok\n" if ($mysql);
	  print PGTITSWTLOKL "$idn|$swtlok\n" if ($pg);
	  print ADTITSWTLOKL "$idn|$swtlok\n" if ($ad);
	  print SQLTITL "insert into titswtlok values ($idn,$swtlok);\n" if ($sql);
	  $titswtlokcount++;
	}
    }
    if ($line=~/^5700 IDN: (\d+)/){
	$titnot=$1;
	if (($idnmode eq "offset")&&($offset)) {
	    $titnot=$titnot+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $titnot="$sigel$titnot";
	}

	print MYSQLTITNOTL "$idn|$titnot\n" if ($mysql);
	print PGTITNOTL "$idn|$titnot\n" if ($pg);
	print ADTITNOTL "$idn|$titnot\n" if ($ad);
	print SQLTITL "insert into titnot values ($idn,$titnot);\n" if ($sql);
	$titnotcount++;
    }
    if ($line=~/^5801.(.*)/){
	$rem=$1;
	chop $rem if ($rem=~m/
$/);
    }
    if ($line=~/^ENDE/){
	print MYSQLTITL "$idn|0|$titeltyp|0|$ast|$esthe|$estfn|$hst|$zuergurh|".substr($titzusatz,0,$lzusatz)."|$vorlbeigwerk|$gemeinsang|$sachlben|".substr($vorlverf,0,$lvorlverf)."|$vorlunter|".substr($ausg,0,$lausg)."|$verlagsort|$verlag|$weitereort|$aufnahmeort|$aufnahmejahr|$erschjahr|$anserschjahr|$erscheinungsverlauf|$verfquelle|$eortquelle|$ejahrquelle|$kollation|$matbenennung|$sonstmatben|$sonstang|$begleitmat|".substr($fussnote,0,$lfussnote)."|$bindpreis|$hsfn|$sprache|$mass||$uebershst|$inunverkn|0|$rem|$bemerk\n" if ($mysql);
	print PGTITL "$idn|0|$titeltyp|0|$ast|$esthe|$estfn|$hst|$zuergurh|".substr($titzusatz,0,$lzusatz)."|$vorlbeigwerk|$gemeinsang|$sachlben|".substr($vorlverf,0,$lvorlverf)."|$vorlunter|".substr($ausg,0,$lausg)."|$verlagsort|$verlag|$weitereort|$aufnahmeort|$aufnahmejahr|$erschjahr|$kollation|$matbenennung|$sonstmatben|$sonstang|$begleitmat|".substr($fussnote,0,$lfussnote)."|$bindpreis|$hsfn|$sprache|$mass||$uebershst|$inunverkn|0|$rem|$bemerk\n" if ($pg);
	    print ADTITL "$idn|0|$titeltyp|0|$stringsep".substr($ast,0,$last-1)."$stringsep|$stringsep".substr($esthe,0,$lesthe-1)."$stringsep|$stringsep".substr($estfn,0,$lestfn-1)."$stringsep|$stringsep".substr($hst,0,$lhst-1)."$stringsep|$stringsep".substr($zuergurh,0,$lzuergurh-1)."$stringsep|$stringsep".substr($titzusatz,0,$lzusatz-1)."$stringsep|$stringsep".substr($vorlbeigwerk,0,$lvorlbeigwerk-1)."$stringsep|$stringsep".substr($gemeinsang,0,$lgemeinsang-1)."$stringsep|$stringsep".substr($sachlben,0,$lsachlben-1)."$stringsep|$stringsep".substr($vorlverf,0,$lvorlverf)."$stringsep|$stringsep".substr($vorlunter,0,$lvorlunter-1)."$stringsep|$stringsep".substr($ausg,0,$lausg-1)."$stringsep|$stringsep".substr($verlagsort,0,$lverlagsort-1)."$stringsep|$stringsep".substr($verlag,0,$lverlag-1)."$stringsep|$stringsep".substr($weitereort,0,$lweitereort-1)."$stringsep|$stringsep$aufnahmeort$stringsep|$stringsep$aufnahmejahr$stringsep|$stringsep".substr($erschjahr,0,$lerschjahr-1)."$stringsep|$stringsep".substr($kollation,0,$lkollation-1)."$stringsep|$stringsep".substr($matbenennung,0,$lmatbenennung-1)."$stringsep|$stringsep".substr($sonstmatben,0,$lsonstmatben-1)."$stringsep|$stringsep".substr($sonstang,0,$lsonstang-1)."$stringsep|$stringsep".substr($begleitmat,0,$lbegleitmat-1)."$stringsep|$stringsep".substr($fussnote,0,$lfussnote-1)."$stringsep|$stringsep".substr($bindpreis,0,$lbindpreis-1)."$stringsep|$stringsep".substr($hsfn,0,$lhsfn-1)."$stringsep|$stringsep".substr($sprache,0,$lsprache-1)."$stringsep|$stringsep".substr($mass,0,$lmass-1)."$stringsep|$stringsep$stringsep|$stringsep".substr($uebershst,0,$luebershst-1)."$stringsep|$stringsep".substr($inunverkn,0,$linunverkn-1)."$stringsep|0|$stringsep".substr($rem,0,$lrem-1)."$stringsep|$stringsep".substr($bemerk,0,$lbemerk-1)."$stringsep\n" if ($ad);
	print SQLTITL "insert into tit values ($idn,0,$titeltyp,0,\'$ast\',\'$esthe\',\'$estfn\',\'$hst\',\'$zuergurh\',\'$zusatz\',\'$vorlbeigwerk\',\'$gemeinsang\',\'$sachlben\',\'$vorlverf\',\'$vorlunter\',\'$ausg\',\'$verlagsort\',\'$verlag\',\'$weitereort\',\'$aufnahmeort\',\'$aufnahmejahr\',\'$erschjahr\',\'$kollation\',\'$matbenennung\',\'$sonstmatben\',\'$sonstang\',\'$begleitmat\',\'$fussnote\',\'$bindpreis\',\'$hsfn\',\'$sprache\',\'$mass\','',\'$uebershst\',\'$inunverkn\',0,\'$rem\',\'$bemerk\');\n" if ($sql);
        undef $hst;
        undef $zusatz;
        undef $titzusatz;
        undef $sachlben;
        undef $vorlverf;
        undef $ausg;
        undef $verlagsort;
        undef $verlag;
        undef $erschjahr;
        undef $anserschjahr;
        undef $erscheinungsverlauf;
	undef $eortquelle;
	undef $ejahrquelle;
	undef $verfquelle;
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

sub bearbeite_mexline {
    ($line)=@_;

    if ($encoding){
      $line=bisumlaut2html("$line");
    }
    else {
      $line=sisisumlaut2html("$line");
    }

    if ($line=~/^IDN  (\d+)/){
	$idn=$1;	
	if (($idnmode eq "offset")&&($offset)) {
	    $idn=$idn+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $idn="$sigel$idn";
	}

	$mexverwidx=0;
    }
    if ($line=~/^7500 (.*)/){
	$bibsigel=$1;
	chop $bibsigel if ($bibsigel=~m/
$/);
    }

    if ($line=~/^7502 IDN: (\d+)/){
	$titverw=$1;
	if (($idnmode eq "offset")&&($offset)) {
	    $titverw=$titverw+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $titverw="$sigel$titverw";
	}

    }

    if ($line=~/^7510 (.*)/){
	$signlok=$1;
	chop $signlok if ($signlok=~m/
$/);
	$mexverwbuf[$mexverwidx++]=$signlok;
    }

    if ($line=~/^7560 (.*)/){
	$invnr=$1;
	chop $invnr if ($invnr=~m/
$/);
    }

    if ($line=~/^7600 (.*)/){
	$standort=$1;
	chop $standort if ($standort=~m/
$/);
    }

    if ($line=~/^7620 (.*)/){
	$lokfn=$1;
	chop $lokfn if ($lokfn=~m/
$/);
    }

    if ($line=~/^7670 (.*)/){
	$medienart=$1;
	chop $medienart if ($medienart=~m/
$/);
    }

    if ($line=~/^7700 (.*)/){
	$erschverl=$1;
	chop $erschverl if ($erschverl=~m/
$/);
    }

    if ($line=~/^ENDE/){
	if ($idn){
	    print MYSQLMEXL "$idn|0|$titverw|$bibsigel|0|$standort|$invnr|$lokfn||$medienart|0|||$erschverl\n" if ($mysql);
	    print PGMEXL "$idn|0|$titverw|$bibsigel|0|$standort|$invnr|$lokfn||$medienart|0|||$erschverl\n" if ($pg);
	    print ADMEXL "$idn|0|$titverw|$stringsep$bibsigel$stringsep|0|$stringsep$standort$stringsep|$stringsep$invnr$stringsep|$stringsep$lokfn$stringsep|$stringsep$stringsep|$stringsep$medienart$stringsep|0|||$stringsep$erschlverl$stringsep\n" if ($ad);
	    print SQLMEXL "insert into mex values ($idn,0,$titverw,\'$bibsigel\',0,\'$standort\',\'$invnr\',\'$lokfn\','',\'$medienart\',0,'','','$erschverl');\n" if ($sql);
	    $mexcount++;
	}
	if ($mexverwidx != 0){
	    foreach $verw (@mexverwbuf){
		print MYSQLMEXSIGNL "$idn|$verw\n" if ($mysql);
		print PGMEXSIGNL "$idn|$verw\n" if ($pg);
		print ADMEXSIGNL "$idn|$stringsep$verw$stringsep\n" if ($ad);
		print SQLMEXL "insert into mexsign values ($idn,\'$verw\');\n" if ($sql);
		$mexsigncount++;
	    }
	}
        undef $idn;
        undef $mexverwidx;
        undef $bibsigel;
        undef $titverw;
        undef $signlok;
        undef @mexverwbuf;
        undef $invnr;
        undef $lokfn;
        undef $medienart;
        undef $standort;        
        undef $erschverl;        
    }

}

sub bearbeite_vbuline {
    ($line)=@_;

    if ($encoding){
      $line=bisumlaut2html("$line");
    }
    else {
      $line=sisisumlaut2html("$line");
    }

    if ($line=~/^9210 IDN: (\d+)/){
	$mexidn=$1;	
	if (($idnmode eq "offset")&&($offset)) {
	    $mexidn=$mexidn+$offset;
	}
	if (($idnmode eq "sigel")&&($sigel)){
	    $mexidn="$sigel$mexidn";
	}
    }
    if ($line=~/^9220 (.*)/){
	$ausleihstatus=$1;
	chop $ausleihstatus if ($ausleihstatus=~m/
$/);
    }

    if ($line=~/^9200 (.*)/){
	$faellig=$1;
	chop $faellig if ($faellig=~m/
$/);
    }

    if ($line=~/^9270 (.*)/){
	$buchung=$1;
	chop $buchung if ($buchung=~m/
$/);
    }

    if ($line=~/^ENDE/){
	if ($mexidn){
	    print SQLVBUL "update mex set ausleihstat=\'$ausleihstatus\', faellig=\'$faellig\', buchung=\'$buchung\' where idn=$mexidn;\n";
	  }
        undef $mexidn;
        undef $ausleihstatus;
        undef $faellig;
        undef $buchung;
    }
}

#####################################################################   
# MYSQL
#####################################################################   

sub mysql_init {
    $mysqlcontrolfile="control.mysql";
    open(MYSQLCONTROL,">".$mysqlcontrolfile);
}

sub mysql_cleanup {
    close(MYSQLCONTROL);
}


sub mysql_aut_init {
    $mysqlautl="aut.mysql";
    $mysqlautverwl="autverw.mysql";
    
    open(MYSQLAUTL,">".$mysqlautl);
    
    print MYSQLCONTROL "load data infile \'$dir/$mysqlautl\' into table aut fields terminated by \'|\';\n";
    
    open(MYSQLAUTVERWL,">".$mysqlautverwl);
}

sub mysql_aut_cleanup {
    close(MYSQLAUTL);
    close(MYSQLAUTVERWL);
    
    if ($autverwcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlautverwl\' into table autverw fields terminated by \'|\';\n";    
    }    
}

sub mysql_kor_init {
    $mysqlkorl="kor.mysql";
    $mysqlkorverwl="korverw.mysql";
    $mysqlkorfruehl="korfrueh.mysql";
    $mysqlkorspaetl="korspaet.mysql";

    open(MYSQLKORL,">".$mysqlkorl);
    open(MYSQLKORVERWL,">".$mysqlkorverwl);
    open(MYSQLKORFRUEHL,">".$mysqlkorfruehl);
    open(MYSQLKORSPAETL,">".$mysqlkorspaetl);
}

sub mysql_kor_cleanup {
    close(MYSQLKORL);
    close(MYSQLKORVERWL);
    close(MYSQLKORFRUEHL);
    close(MYSQLKORSPAETL);
    
    if ($korcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlkorl\' into table kor fields terminated by \'|\';\n";
    }
    
    if ($korverwcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlkorverwl\' into table korverw fields terminated by \'|\';\n";
    }
    
    if ($korfruehcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlkorfruehl\' into table korfrueh fields terminated by \'|\';\n";
    }
    
    if ($korspaetcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlkorspaetl\' into table korspaet fields terminated by \'|\';\n";
    }
}

sub mysql_swt_init {
    $mysqlswtl="swt.mysql";
    $mysqlswtverwl="swtverw.mysql";
    $mysqlswtueberl="swtueber.mysql";
    $mysqlswtassozl="swtassoz.mysql";
    $mysqlswtfruehl="swtfrueh.mysql";
    $mysqlswtspaetl="swtspaet.mysql";
    
    open(MYSQLSWTL,">".$mysqlswtl);
    open(MYSQLSWTVERWL,">".$mysqlswtverwl);
    open(MYSQLSWTUEBERL,">".$mysqlswtueberl);
    open(MYSQLSWTASSOZL,">".$mysqlswtassozl);
    open(MYSQLSWTFRUEHL,">".$mysqlswtfruehl);
    open(MYSQLSWTSPAETL,">".$mysqlswtspaetl);
}

sub mysql_swt_cleanup {
    close(MYSQLSWTL);
    close(MYSQLSWTVERWL);
    close(MYSQLSWTUEBERL);
    close(MYSQLSWTASSOZL);
    close(MYSQLSWTFRUEHL);
    close(MYSQLSWTSPAETL);
    
    if ($swtcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlswtl\' into table swt fields terminated by \'|\';\n";
    }
    if ($swtverwcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlswtverwl\' into table swtverw fields terminated by \'|\';\n";
    }
    
    if ($swtfruehcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlswtfruehl\' into table swtfrueh fields terminated by \'|\';\n";
    }
    
    if ($swtspaetcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlswtspaetl\' into table swtspaet fields terminated by \'|\';\n";
    }
    
    if ($swtassozcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlswtassozl\' into table swtassoz fields terminated by \'|\';\n";
    }
    
    if ($swtuebercount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlswtueberl\' into table swtueber fields terminated by \'|\';\n";
    }
}

sub mysql_not_init {
    $mysqlnotl="not.mysql";
    $mysqlnotverwl="notverw.mysql";
    $mysqlnotbenverwl="notbenverw.mysql";
    
    open(MYSQLNOTL,">".$mysqlnotl);
    open(MYSQLNOTVERWL,">".$mysqlnotverwl);
    open(MYSQLNOTBENVERWL,">".$mysqlnotbenverwl);
}

sub mysql_not_cleanup {
    close(MYSQLNOTL);
    close(MYSQLNOTVERWL);
    close(MYSQLNOTBENVERWL);
    
    if ($notcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlnotl\' into table notation fields terminated by \'|\';\n";
    }
    
    if ($notverwcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlnotverwl\' into table notverw fields terminated by \'|\';\n";
    }
    
    if ($notbenverwcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlnotbenverwl\' into table notbenverw fields terminated by \'|\';\n";
    }    
}

sub mysql_tit_init {
    $mysqltitl="tit.mysql";

    $mysqltitabstractl="titabstract.mysql";
    $mysqltitsammelverml="titsammelverm.mysql";
    $mysqltitanghstl="titanghst.mysql";
    $mysqltitpausgl="titpausg.mysql";
    $mysqltittitbeill="tittitbeil.mysql";
    $mysqltitbezwerkl="titbezwerk.mysql";
    $mysqltitfruehausgl="titfruehausg.mysql";
    $mysqltitfruehtitl="titfruehtit.mysql";
    $mysqltitspaetausgl="titspaetausg.mysql";
    $mysqltitillangl="titillang.mysql";

    $mysqltitpsthtsl="titpsthts.mysql";
    $mysqltitbeigwerkl="titbeigwerk.mysql";
    $mysqltitgtunvl="titgtunv.mysql";
    $mysqltitisbnl="titisbn.mysql";
    $mysqltitissnl="titissn.mysql";
    $mysqltitnerl="titner.mysql";
    $mysqltitteiluwl="titteiluw.mysql";
    $mysqltitstichwl="titstichw.mysql";
    $mysqltitnrl="titnr.mysql";
    $mysqltitartinhl="titartinh.mysql";
    $mysqltitphysforml="titphysform.mysql";
    $mysqltitgtml="titgtm.mysql";
    $mysqltitgtfl="titgtf.mysql";
    $mysqltitinverknl="titinverkn.mysql";
    $mysqltitswtlokl="titswtlok.mysql";
    $mysqltitswtregl="titswtreg.mysql";
    $mysqltitverfl="titverf.mysql";
    $mysqltitpersl="titpers.mysql";
    $mysqltitgpersl="titgpers.mysql";
    $mysqltiturhl="titurh.mysql";
    $mysqltitkorl="titkor.mysql";
    $mysqltitnotl="titnot.mysql";
    $mysqltitwstl="titwst.mysql";
    $mysqltiturll="titurl.mysql";


    open(MYSQLTITL,">".$mysqltitl);
    
    print MYSQLCONTROL "load data infile \'$dir/$mysqltitl\' into table tit fields terminated by \'|\';\n";

    open(MYSQLTITABSTRACTL,">".$mysqltitabstractl);
    open(MYSQLTITSAMMELVERML,">".$mysqltitsammelverml);
    open(MYSQLTITANGHSTL,">".$mysqltitanghstl);
    open(MYSQLTITPAUSGL,">".$mysqltitpausgl);
    open(MYSQLTITTITBEILL,">".$mysqltittitbeill);
    open(MYSQLTITBEZWERKL,">".$mysqltitbezwerkl);
    open(MYSQLTITFRUEHAUSGL,">".$mysqltitfruehausgl);
    open(MYSQLTITFRUEHTITL,">".$mysqltitfruehtitl);
    open(MYSQLTITSPAETAUSGL,">".$mysqltitspaetausgl);
    open(MYSQLTITURLL,">".$mysqltiturll);
    open(MYSQLTITILLANGL,">".$mysqltitillangl);

    open(MYSQLTITPSTHTSL,">".$mysqltitpsthtsl);
    open(MYSQLTITBEIGWERKL,">".$mysqltitbeigwerkl);
    open(MYSQLTITGTUNVL,">".$mysqltitgtunvl);
    open(MYSQLTITISBNL,">".$mysqltitisbnl);
    open(MYSQLTITISSNL,">".$mysqltitissnl);
    open(MYSQLTITNERL,">".$mysqltitnerl);
    open(MYSQLTITTEILUWL,">".$mysqltitteiluwl);
    open(MYSQLTITSTICHWL,">".$mysqltitstichwl);
    open(MYSQLTITNRL,">".$mysqltitnrl);
    open(MYSQLTITARTINHL,">".$mysqltitartinhl);
    open(MYSQLTITPHYSFORML,">".$mysqltitphysforml);
    open(MYSQLTITGTML,">".$mysqltitgtml);
    open(MYSQLTITGTFL,">".$mysqltitgtfl);
    open(MYSQLTITINVERKNL,">".$mysqltitinverknl);
    open(MYSQLTITSWTLOKL,">".$mysqltitswtlokl);
    open(MYSQLTITSWTREGL,">".$mysqltitswtregl);
    open(MYSQLTITVERFL,">".$mysqltitverfl);
    open(MYSQLTITPERSL,">".$mysqltitpersl);
    open(MYSQLTITGPERSL,">".$mysqltitgpersl);
    open(MYSQLTITURHL,">".$mysqltiturhl);
    open(MYSQLTITKORL,">".$mysqltitkorl);
    open(MYSQLTITNOTL,">".$mysqltitnotl);
    open(MYSQLTITWSTL,">".$mysqltitwstl);
}

sub mysql_tit_cleanup {
    close(MYSQLTITL);

    close(MYSQLTITABSTRACTL);
    close(MYSQLTITSAMMELVERML);
    close(MYSQLTITANGHSTL);
    close(MYSQLTITPAUSGL);
    close(MYSQLTITTITBEILL);
    close(MYSQLTITBEZWERKL);
    close(MYSQLTITFRUEHAUSGL);
    close(MYSQLTITFRUEHTITL);
    close(MYSQLTITSPAETAUSGL);
    close(MYSQLTITILLANGL);

    close(MYSQLTITPSTHTSL);
    close(MYSQLTITBEIGWERKL);
    close(MYSQLTITGTUNVL);
    close(MYSQLTITISBNL);
    close(MYSQLTITISSNL);
    close(MYSQLTITNERL);
    close(MYSQLTITTEILUWL);
    close(MYSQLTITSTICHWL);
    close(MYSQLTITNRL);
    close(MYSQLTITARTINHL);
    close(MYSQLTITPHYSFORML);
    close(MYSQLTITGTML);
    close(MYSQLTITGTFL);
    close(MYSQLTITINVERKNL);
    close(MYSQLTITSWTLOKL);
    close(MYSQLTITSWTREGL);
    close(MYSQLTITVERFL);
    close(MYSQLTITPERSL);
    close(MYSQLTITGPERSL);
    close(MYSQLTITURHL);
    close(MYSQLTITKORL);
    close(MYSQLTITNOTL);
    close(MYSQLTITWSTL);
    close(MYSQLTITURLL);

    if($titabstractcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitabstractl\' into table titabstract fields terminated by \'|\';\n";
    }

    if($titsammelvermcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitsammelverml\' into table titsammelverm fields terminated by \'|\';\n";
    }
    if($titanghstcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitanghstl\' into table titanghst fields terminated by \'|\';\n";
    }
    if($titpausgcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitpausgl\' into table titpausg fields terminated by \'|\';\n";
    }
    if($tittitbeilcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltittitbeill\' into table tittitbeil fields terminated by \'|\';\n";
    }
    if($titbezwerkcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitbezwerkl\' into table titbezwerk fields terminated by \'|\';\n";
    }
    if($titfruehausgcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitfruehausgl\' into table titfruehausg fields terminated by \'|\';\n";
    }
    if($titfruehtitcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitfruehtitl\' into table titfruehtit fields terminated by \'|\';\n";
    }

    if($titspaetausgcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitspaetausgl\' into table titspaetausg fields terminated by \'|\';\n";
    }

    if($titillangcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitillangl\' into table titillang fields terminated by \'|\';\n";
    }    

    
    if($titpsthtscount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitpsthtsl\' into table titpsthts fields terminated by \'|\';\n";
    }
    if($titbeigwerkcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitbeigwerkl\' into table titbeigwerk fields terminated by \'|\';\n";
    }
    if($titgtunvcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitgtunvl\' into table titgtunv fields terminated by \'|\';\n";
    }
    if($titisbncount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitisbnl\' into table titisbn fields terminated by \'|\';\n";
    }
    if($titissncount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitissnl\' into table titissn fields terminated by \'|\';\n";
    }
    if($titnercount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitnerl\' into table titner fields terminated by \'|\';\n";
    }
    if($titteiluwcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitteiluwl\' into table titteiluw fields terminated by \'|\';\n";
    }
    if($titstichwcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitstichwl\' into table titstichw fields terminated by \'|\';\n";
    }
    if($titnrcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitnrl\' into table titnr fields terminated by \'|\';\n";
    }
    if($titartinhcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitartinhl\' into table titartinh fields terminated by \'|\';\n";
    }
    if($titphysformcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitphysforml\' into table titphysform fields terminated by \'|\';\n";
    }
    if($titgtmcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitgtml\' into table titgtm fields terminated by \'|\';\n";
    }
    if($titgtfcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitgtfl\' into table titgtf fields terminated by \'|\';\n";
    }
    if($titinverkncount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitinverknl\' into table titinverkn fields terminated by \'|\';\n";
    }
    if($titswtlokcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitswtlokl\' into table titswtlok fields terminated by \'|\';\n";
    }
    if($titswtregcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitswtregl\' into table titswtreg fields terminated by \'|\';\n";
    }
    if($titverfcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitverfl\' into table titverf fields terminated by \'|\';\n";
    }
    if($titperscount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitpersl\' into table titpers fields terminated by \'|\';\n";
    }
    if($titgperscount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitgpersl\' into table titgpers fields terminated by \'|\';\n";
    }
    if($titurhcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltiturhl\' into table titurh fields terminated by \'|\';\n";
    }
    if($titkorcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitkorl\' into table titkor fields terminated by \'|\';\n";
    }
    if($titnotcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitnotl\' into table titnot fields terminated by \'|\';\n";
    }    
    if($titwstcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltitwstl\' into table titwst fields terminated by \'|\';\n";
    }    
    if($titurlcount!=0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqltiturll\' into table titurl fields terminated by \'|\';\n";
    }    

}

sub mysql_mex_init {
    $mysqlmexl="mex.mysql";
    $mysqlmexsignl="mexsign.mysql";

    open(MYSQLMEXL,">".$mysqlmexl);
    open(MYSQLMEXSIGNL,">".$mysqlmexsignl);
}

sub mysql_mex_cleanup {
    close(MYSQLMEXL);
    close(MYSQLMEXSIGNL);
    
    if ($mexcount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlmexl\' into table mex fields terminated by \'|\';\n";
    }
    
    if ($mexsigncount != 0){
	print MYSQLCONTROL "load data infile \'$dir/$mysqlmexsignl\' into table mexsign fields terminated by \'|\';\n";
    }    
}

#####################################################################   
# POSTGRESQL
#####################################################################   

sub pg_init {
    $pgcontrolfile="control.pg";
    open(PGCONTROL,">".$pgcontrolfile);

    print PGCONTROL "delete from aut where idn < 99999999;\n";
    print PGCONTROL "delete from autverw where autidn < 999999;\n";
    print PGCONTROL "delete from kor where idn < 99999999;\n";
    print PGCONTROL "delete from korverw where koridn < 99999999;\n";
    print PGCONTROL "delete from korfrueh where koridn < 99999999;\n";
    print PGCONTROL "delete from korspaet where koridn < 99999999;\n";
    print PGCONTROL "delete from swt where idn < 99999999;\n";
    print PGCONTROL "delete from swtverw where swtidn < 99999999;\n";
    print PGCONTROL "delete from swtueber where swtidn < 99999999;\n";
    print PGCONTROL "delete from swtassoz where swtidn < 99999999;\n";
    print PGCONTROL "delete from swtfrueh where swtidn < 99999999;\n";
    print PGCONTROL "delete from swtspaet where swtidn < 99999999;\n";
    print PGCONTROL "delete from tit where idn < 99999999;\n";
    print PGCONTROL "delete from titpsthts where titidn < 99999999;\n";
    print PGCONTROL "delete from titbeigwerk where titidn < 99999999;\n";
    print PGCONTROL "delete from titgtunv where titidn < 99999999;\n";
    print PGCONTROL "delete from titisbn where titidn < 99999999;\n";
    print PGCONTROL "delete from titissn where titidn < 99999999;\n";
    print PGCONTROL "delete from titner where titidn < 99999999;\n";
    print PGCONTROL "delete from titteiluw where titidn < 99999999;\n";
    print PGCONTROL "delete from titstichw where titidn < 99999999;\n";
    print PGCONTROL "delete from titnr where titidn < 99999999;\n";
    print PGCONTROL "delete from titartinh where titidn < 99999999;\n";
    print PGCONTROL "delete from titphysform where titidn < 99999999;\n";   
    print PGCONTROL "delete from titgtm where titidn < 99999999;\n";
    print PGCONTROL "delete from titgtf where titidn < 99999999;\n";
    print PGCONTROL "delete from titinverkn where titidn < 99999999;\n";
    print PGCONTROL "delete from titswtlok where titidn < 99999999;\n";
    print PGCONTROL "delete from titswtreg where titidn < 99999999;\n";
    print PGCONTROL "delete from titverf where titidn < 99999999;\n";
    print PGCONTROL "delete from titpers where titidn < 99999999;\n";
    print PGCONTROL "delete from titurh where titidn < 99999999;\n";
    print PGCONTROL "delete from titkor where titidn < 99999999;\n";
    print PGCONTROL "delete from mex where idn < 99999999;\n";
    print PGCONTROL "delete from mexsign where mexidn < 99999999;\n";
    print PGCONTROL "delete from bib where idn < 99999999;\n";
    print PGCONTROL "delete from notation where idn < 99999999;\n";
    print PGCONTROL "delete from notbenverw where notidn < 99999999;\n";
    print PGCONTROL "delete from notverw where notidn < 99999999;\n";
    print PGCONTROL "delete from titnot where notidn < 99999999;\n";      
}

sub pg_cleanup {
    close(PGCONTROL);
}

sub pg_aut_init {
    $pgautl="aut.pg";
    $pgautverwl="autverw.pg";
    
    open(PGAUTL,">".$pgautl);
    
    print PGCONTROL "copy aut from \'$dir/$pgautl\' using delimiters \'|\';\n";
    
    open(PGAUTVERWL,">".$pgautverwl);
}

sub pg_aut_cleanup {
    close(PGAUTL);
    close(PGAUTVERWL);
    
    if ($autverwcount != 0){
	print PGCONTROL "copy autverw from \'$dir/$pgautverwl\' using delimiters \'|\';\n";    
    }    
}

sub pg_kor_init {
    $pgkorl="kor.pg";
    $pgkorverwl="korverw.pg";
    $pgkorfruehl="korfrueh.pg";
    $pgkorspaetl="korspaet.pg";

    open(PGKORL,">".$pgkorl);
    open(PGKORVERWL,">".$pgkorverwl);
    open(PGKORFRUEHL,">".$pgkorfruehl);
    open(PGKORSPAETL,">".$pgkorspaetl);
}

sub pg_kor_cleanup {
    close(PGKORL);
    close(PGKORVERWL);
    close(PGKORFRUEHL);
    close(PGKORSPAETL);
    
    if ($korcount != 0){
	print PGCONTROL "copy kor from \'$dir/$pgkorl\' using delimiters \'|\';\n";
    }
    
    if ($korverwcount != 0){
	print PGCONTROL "copy korverw from \'$dir/$pgkorverwl\' using delimiters \'|\';\n";
    }
    
    if ($korfruehcount != 0){
	print PGCONTROL "copy korfrueh from \'$dir/$pgkorfruehl\' using delimiters \'|\';\n";
    }
    
    if ($korspaetcount != 0){
	print PGCONTROL "copy korspaet from \'$dir/$pgkorspaetl\' using delimiters \'|\';\n";
    }
}

sub pg_swt_init {
    $pgswtl="swt.pg";
    $pgswtverwl="swtverw.pg";
    $pgswtueberl="swtueber.pg";
    $pgswtassozl="swtassoz.pg";
    $pgswtfruehl="swtfrueh.pg";
    $pgswtspaetl="swtspaet.pg";
    
    open(PGSWTL,">".$pgswtl);
    open(PGSWTVERWL,">".$pgswtverwl);
    open(PGSWTUEBERL,">".$pgswtueberl);
    open(PGSWTASSOZL,">".$pgswtassozl);
    open(PGSWTFRUEHL,">".$pgswtfruehl);
    open(PGSWTSPAETL,">".$pgswtspaetl);
}

sub pg_swt_cleanup {
    close(PGSWTL);
    close(PGSWTVERWL);
    close(PGSWTUEBERL);
    close(PGSWTASSOZL);
    close(PGSWTFRUEHL);
    close(PGSWTSPAETL);
    
    if ($swtcount != 0){
	print PGCONTROL "copy swt from \'$dir/$pgswtl\' using delimiters \'|\';\n";
    }
    if ($swtverwcount != 0){
	print PGCONTROL "copy swtverw from \'$dir/$pgswtverwl\' using delimiters \'|\';\n";
    }
    
    if ($swtfruehcount != 0){
	print PGCONTROL "copy swtfrueh from \'$dir/$pgswtfruehl\' using delimiters \'|\';\n";
    }
    
    if ($swtspaetcount != 0){
	print PGCONTROL "copy swtspaet from \'$dir/$pgswtspaetl\' using delimiters \'|\';\n";
    }
    
    if ($swtassozcount != 0){
	print PGCONTROL "copy swtassoz from \'$dir/$pgswtassozl\' using delimiters \'|\';\n";
    }
    
    if ($swtuebercount != 0){
	print PGCONTROL "copy swtueber from \'$dir/$pgswtueberl\' using delimiters \'|\';\n";
    }
}

sub pg_not_init {
    $pgnotl="not.pg";
    $pgnotverwl="notverw.pg";
    $pgnotbenverwl="notbenverw.pg";
    
    open(PGNOTL,">".$pgnotl);
    open(PGNOTVERWL,">".$pgnotverwl);
    open(PGNOTBENVERWL,">".$pgnotbenverwl);
}

sub pg_not_cleanup {
    close(PGNOTL);
    close(PGNOTVERWL);
    close(PGNOTBENVERWL);
    
    if ($notcount != 0){
	print PGCONTROL "copy notation from \'$dir/$pgnotl\' using delimiters \'|\';\n";
    }
    
    if ($notverwcount != 0){
	print PGCONTROL "copy notverw from \'$dir/$pgnotverwl\' using delimiters \'|\';\n";
    }
    
    if ($notbenverwcount != 0){
	print PGCONTROL "copy notbenverw from \'$dir/$pgnotbenverwl\' using delimiters \'|\';\n";
    }    
}

sub pg_tit_init {
    $pgtitl="tit.pg";
    $pgtitpsthtsl="titpsthts.pg";
    $pgtitbeigwerkl="titbeigwerk.pg";
    $pgtitgtunvl="titgtunv.pg";
    $pgtitisbnl="titisbn.pg";
    $pgtitissnl="titissn.pg";
    $pgtitnerl="titner.pg";
    $pgtitteiluwl="titteiluw.pg";
    $pgtitstichwl="titstichw.pg";
    $pgtitnrl="titnr.pg";
    $pgtitartinhl="titartinh.pg";
    $pgtitphysforml="titphysform.pg";
    $pgtitgtml="titgtm.pg";
    $pgtitgtfl="titgtf.pg";
    $pgtitinverknl="titinverkn.pg";
    $pgtitswtlokl="titswtlok.pg";
    $pgtitswtregl="titswtreg.pg";
    $pgtitverfl="titverf.pg";
    $pgtitpersl="titpers.pg";
    $pgtitgpersl="titgpers.pg";
    $pgtiturhl="titurh.pg";
    $pgtitkorl="titkor.pg";
    $pgtitnotl="titnot.pg";

    open(PGTITL,">".$pgtitl);
    
    print PGCONTROL "copy tit from \'$dir/$pgtitl\' using delimiters \'|\';\n";

    open(PGTITPSTHTSL,">".$pgtitpsthtsl);
    open(PGTITBEIGWERKL,">".$pgtitbeigwerkl);
    open(PGTITGTUNVL,">".$pgtitgtunvl);
    open(PGTITISBNL,">".$pgtitisbnl);
    open(PGTITISSNL,">".$pgtitissnl);
    open(PGTITNERL,">".$pgtitnerl);
    open(PGTITTEILUWL,">".$pgtitteiluwl);
    open(PGTITSTICHWL,">".$pgtitstichwl);
    open(PGTITNRL,">".$pgtitnrl);
    open(PGTITARTINHL,">".$pgtitartinhl);
    open(PGTITPHYSFORML,">".$pgtitphysforml);
    open(PGTITGTML,">".$pgtitgtml);
    open(PGTITGTFL,">".$pgtitgtfl);
    open(PGTITINVERKNL,">".$pgtitinverknl);
    open(PGTITSWTLOKL,">".$pgtitswtlokl);
    open(PGTITSWTREGL,">".$pgtitswtregl);
    open(PGTITVERFL,">".$pgtitverfl);
    open(PGTITPERSL,">".$pgtitpersl);
    open(PGTITGPERSL,">".$pgtitgpersl);
    open(PGTITURHL,">".$pgtiturhl);
    open(PGTITKORL,">".$pgtitkorl);
    open(PGTITNOTL,">".$pgtitnotl);
}

sub pg_tit_cleanup {
    close(PGTITL);
    close(PGTITPSTHTSL);
    close(PGTITBEIGWERKL);
    close(PGTITGTUNVL);
    close(PGTITISBNL);
    close(PGTITISSNL);
    close(PGTITNERL);
    close(PGTITTEILUWL);
    close(PGTITSTICHWL);
    close(PGTITNRL);
    close(PGTITARTINHL);
    close(PGTITPHYSFORML);
    close(PGTITGTML);
    close(PGTITGTFL);
    close(PGTITINVERKNL);
    close(PGTITSWTLOKL);
    close(PGTITSWTREGL);
    close(PGTITVERFL);
    close(PGTITPERSL);
    close(PGTITGPERSL);
    close(PGTITURHL);
    close(PGTITKORL);
    close(PGTITNOTL);
    
    if($titpsthtscount!=0){
	print PGCONTROL "copy psthts from \'$dir/$pgtitpsthtsl\' using delimiters \'|\';\n";
    }
    if($titbeigwerkcount!=0){
	print PGCONTROL "copy beigwerk from \'$dir/$pgtitbeigwerkl\' using delimiters \'|\';\n";
    }
    if($titgtunvcount!=0){
	print PGCONTROL "copy titgtunv from \'$dir/$pgtitgtunvl\' using delimiters \'|\';\n";
    }
    if($titisbncount!=0){
	print PGCONTROL "copy titisbn from \'$dir/$pgtitisbnl\' using delimiters \'|\';\n";
    }
    if($titissncount!=0){
	print PGCONTROL "copy titissn from \'$dir/$pgtitissnl\' using delimiters \'|\';\n";
    }
    if($titnercount!=0){
	print PGCONTROL "copy titner from \'$dir/$pgtitnerl\' using delimiters \'|\';\n";
    }
    if($titteiluwcount!=0){
	print PGCONTROL "copy titteiluw from \'$dir/$pgtitteiluwl\' using delimiters \'|\';\n";
    }
    if($titstichwcount!=0){
	print PGCONTROL "copy titstichw from \'$dir/$pgtitstichwl\' using delimiters \'|\';\n";
    }
    if($titnrcount!=0){
	print PGCONTROL "copy titnr from \'$dir/$pgtitnrl\' using delimiters \'|\';\n";
    }
    if($titartinhcount!=0){
	print PGCONTROL "copy titartinh from \'$dir/$pgtitartinhl\' using delimiters \'|\';\n";
    }
    if($titphysformcount!=0){
	print PGCONTROL "copy titphysform from \'$dir/$pgtitphysforml\' using delimiters \'|\';\n";
    }
    if($titgtmcount!=0){
	print PGCONTROL "copy titgtm from \'$dir/$pgtitgtml\' using delimiters \'|\';\n";
    }
    if($titgtfcount!=0){
	print PGCONTROL "copy titgtf from \'$dir/$pgtitgtfl\' using delimiters \'|\';\n";
    }
    if($titinverkncount!=0){
	print PGCONTROL "copy titinverkn from \'$dir/$pgtitinverknl\' using delimiters \'|\';\n";
    }
    if($titswtlokcount!=0){
	print PGCONTROL "copy titswtlok from \'$dir/$pgtitswtlokl\' using delimiters \'|\';\n";
    }
    if($titswtregcount!=0){
	print PGCONTROL "copy titswtreg from \'$dir/$pgtitswtregl\' using delimiters \'|\';\n";
    }
    if($titverfcount!=0){
	print PGCONTROL "copy titverf from \'$dir/$pgtitverfl\' using delimiters \'|\';\n";
    }
    if($titperscount!=0){
	print PGCONTROL "copy titpers from \'$dir/$pgtitpersl\' using delimiters \'|\';\n";
    }
    if($titgperscount!=0){
	print PGCONTROL "copy titgpers from \'$dir/$pgtitgpersl\' using delimiters \'|\';\n";
    }
    if($titurhcount!=0){
	print PGCONTROL "copy titurh from \'$dir/$pgtiturhl\' using delimiters \'|\';\n";
    }
    if($titkorcount!=0){
	print PGCONTROL "copy titkor from \'$dir/$pgtitkorl\' using delimiters \'|\';\n";
    }
    if($titnotcount!=0){
	print PGCONTROL "copy titnot from \'$dir/$pgtitnotl\' using delimiters \'|\';\n";
    }    
}

sub pg_mex_init {
    $pgmexl="mex.pg";
    $pgmexsignl="mexsign.pg";

    open(PGMEXL,">".$pgmexl);
    open(PGMEXSIGNL,">".$pgmexsignl);
}

sub pg_mex_cleanup {
    close(PGMEXL);
    close(PGMEXSIGNL);
    
    if ($mexcount != 0){
	print PGCONTROL "copy mex from \'$dir/$pgmexl\' using delimiters \'|\';\n";
    }
    
    if ($mexsigncount != 0){
	print PGCONTROL "copy mexsign from \'$dir/$pgmexsignl\' using delimiters \'|\';\n";
    }    
}


#####################################################################   
# ADABAS
#####################################################################   

sub ad_init {
    $continuelines=0;
    $continuesep="#";
    $stringsep="@";

    $adcontrolfile="control.ad";
    open(ADCONTROL,">".$adcontrolfile);
}

sub ad_cleanup {
    close(ADCONTROL);
}

sub ad_aut_init {
    $adautl="aut.ad";
    $adautverwl="autverw.ad";
    
    open(ADAUTL,">".$adautl);
    print ADAUTL "DATALOAD TABLE aut\n";
    print ADAUTL "     UPDATE DUPLICATES\n";
    print ADAUTL "            idn    1\n";
    print ADAUTL "            ida    2\n";
    print ADAUTL "            versnr 3\n";
    print ADAUTL "            ans    4\n";
    print ADAUTL "            pndnr  5\n";
    print ADAUTL "            verbnr 6\n";
    print ADAUTL "        INFILE *\n";

    if ($continuelines == 1){
	print ADAUTL "            CONTINUEIF LAST = '\$continuesep'\n";
    }

    print ADAUTL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADAUTL "* Data follows\n";

    print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adautl\'\n";    
    
    open(ADAUTVERWL,">".$adautverwl);
    print ADAUTVERWL "DATALOAD TABLE autverw\n";
    print ADAUTVERWL "     UPDATE DUPLICATES\n";
    print ADAUTVERWL "            autidn    1\n";
    print ADAUTVERWL "            verw      2\n";
    print ADAUTVERWL "        INFILE *\n";

    if ($continuelines == 1){
	print ADAUTVERWL "            CONTINUEIF LAST = '\$continuesep'\n";
    }

    print ADAUTVERWL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADAUTVERWL "* Data follows\n";

}

sub ad_aut_cleanup {
    close(ADAUTL);
    close(ADAUTVERWL);
    
    if ($autverwcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adautverwl\'\n";    
    }    
}

sub ad_kor_init {
    $adkorl="kor.ad";
    $adkorverwl="korverw.ad";
    $adkorfruehl="korfrueh.ad";
    $adkorspaetl="korspaet.ad";

    open(ADKORL,">".$adkorl);

    print ADKORL "DATALOAD TABLE kor\n";
    print ADKORL "     UPDATE DUPLICATES\n";
    print ADKORL "            idn    1\n";
    print ADKORL "            ida    2\n";
    print ADKORL "            korans 3\n";
    print ADKORL "            gkdident 4\n";
    print ADKORL "        INFILE *\n";

    if ($continuelines == 1){
	print ADKORL "            CONTINUEIF LAST = '\$continuesep'\n";
    }

    print ADKORL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADKORL "* Data follows\n";

    open(ADKORVERWL,">".$adkorverwl);

    print ADKORVERWL "DATALOAD TABLE korverw\n";
    print ADKORVERWL "     UPDATE DUPLICATES\n";
    print ADKORVERWL "            koridn    1\n";
    print ADKORVERWL "            verw      2\n";
    print ADKORVERWL "        INFILE *\n";
    print ADKORVERWL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADKORVERWL "* Data follows\n";

    open(ADKORFRUEHL,">".$adkorfruehl);

    print ADKORFRUEHL "DATALOAD TABLE korfrueh\n";
    print ADKORFRUEHL "     UPDATE DUPLICATES\n";
    print ADKORFRUEHL "            koridn    1\n";
    print ADKORFRUEHL "            frueher   2\n";
    print ADKORFRUEHL "        INFILE *\n";
    print ADKORFRUEHL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADKORFRUEHL "* Data follows\n";

    open(ADKORSPAETL,">".$adkorspaetl);

    print ADKORSPAETL "DATALOAD TABLE korspaet\n";
    print ADKORSPAETL "     UPDATE DUPLICATES\n";
    print ADKORSPAETL "            koridn    1\n";
    print ADKORSPAETL "            spaeter   2\n";
    print ADKORSPAETL "        INFILE *\n";
    print ADKORSPAETL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADKORSPAETL "* Data follows\n";

}

sub ad_kor_cleanup {
    close(ADKORL);
    close(ADKORVERWL);
    close(ADKORFRUEHL);
    close(ADKORSPAETL);
    
    if ($korcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adkorl\'\n";
    }
    
    if ($korverwcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adkorverwl\'\n";
    }
    
    if ($korfruehcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adkorfruehl\'\n";
    }
    
    if ($korspaetcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adkorspaetl\'\n";
    }
}

sub ad_swt_init {
    $adswtl="swt.ad";
    $adswtverwl="swtverw.ad";
    $adswtueberl="swtueber.ad";
    $adswtassozl="swtassoz.ad";
    $adswtfruehl="swtfrueh.ad";
    $adswtspaetl="swtspaet.ad";
    
    open(ADSWTL,">".$adswtl);

    print ADSWTL "DATALOAD TABLE swt\n";
    print ADSWTL "     UPDATE DUPLICATES\n";
    print ADSWTL "            idn    1\n";
    print ADSWTL "            ida    2\n";
    print ADSWTL "            schlagw 3\n";
    print ADSWTL "            erlaeut 4\n";
    print ADSWTL "            verbidn 5\n";
    print ADSWTL "        INFILE *\n";
    print ADSWTL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADSWTL "* Data follows\n";

    open(ADSWTVERWL,">".$adswtverwl);

    print ADSWTVERWL "DATALOAD TABLE swtverw\n";
    print ADSWTVERWL "     UPDATE DUPLICATES\n";
    print ADSWTVERWL "            swtidn    1\n";
    print ADSWTVERWL "            verw      2\n";
    print ADSWTVERWL "        INFILE *\n";
    print ADSWTVERWL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADSWTVERWL "* Data follows\n";

    open(ADSWTUEBERL,">".$adswtueberl);

    print ADSWTUEBERL "DATALOAD TABLE swtueber\n";
    print ADSWTUEBERL "     UPDATE DUPLICATES\n";
    print ADSWTUEBERL "            swtidn    1\n";
    print ADSWTUEBERL "            ueber      2\n";
    print ADSWTUEBERL "        INFILE *\n";
    print ADSWTUEBERL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADSWTUEBERL "* Data follows\n";

    open(ADSWTASSOZL,">".$adswtassozl);

    print ADSWTASSOZL "DATALOAD TABLE swtassoz\n";
    print ADSWTASSOZL "     UPDATE DUPLICATES\n";
    print ADSWTASSOZL "            swtidn    1\n";
    print ADSWTASSOZL "            assoz      2\n";
    print ADSWTASSOZL "        INFILE *\n";
    print ADSWTASSOZL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADSWTASSOZL "* Data follows\n";

    open(ADSWTFRUEHL,">".$adswtfruehl);

    print ADSWTFRUEHL "DATALOAD TABLE swtfrueh\n";
    print ADSWTFRUEHL "     UPDATE DUPLICATES\n";
    print ADSWTFRUEHL "            swtidn    1\n";
    print ADSWTFRUEHL "            frueher   2\n";
    print ADSWTFRUEHL "        INFILE *\n";
    print ADSWTFRUEHL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADSWTFRUEHL "* Data follows\n";

    open(ADSWTSPAETL,">".$adswtspaetl);

    print ADSWTSPAETL "DATALOAD TABLE swtspaet\n";
    print ADSWTSPAETL "     UPDATE DUPLICATES\n";
    print ADSWTSPAETL "            swtidn    1\n";
    print ADSWTSPAETL "            spaeter   2\n";
    print ADSWTSPAETL "        INFILE *\n";
    print ADSWTSPAETL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADSWTSPAETL "* Data follows\n";

}

sub ad_swt_cleanup {
    close(ADSWTL);
    close(ADSWTVERWL);
    close(ADSWTUEBERL);
    close(ADSWTASSOZL);
    close(ADSWTFRUEHL);
    close(ADSWTSPAETL);
    
    if ($swtcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adswtl\'\n";
    }
    if ($swtverwcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adswtverwl\'\n";
    }
    
    if ($swtfruehcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adswtfruehl\'\n";
    }
    
    if ($swtspaetcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adswtspaetl\'\n";
    }
    
    if ($swtassozcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adswtassozl\'\n";
    }
    
    if ($swtuebercount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adswtueberl\'\n";
    }
}

sub ad_not_init {
    $adnotl="not.ad";
    $adnotverwl="notverw.ad";
    $adnotbenverwl="notbenverw.ad";
    
    open(ADNOTL,">".$adnotl);

    print ADNOTL "DATALOAD TABLE notation\n";
    print ADNOTL "     UPDATE DUPLICATES\n";
    print ADNOTL "            idn    1\n";
    print ADNOTL "            ida    2\n";
    print ADNOTL "            versnr 3\n";
    print ADNOTL "            notation 4\n";
    print ADNOTL "            benennung 5\n";
    print ADNOTL "            abrufzeichen 6\n";
    print ADNOTL "            beschrnot 7\n";
    print ADNOTL "            abrufr 9\n";
    print ADNOTL "            oberbegriff 9\n";
    print ADNOTL "        INFILE *\n";
    print ADNOTL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADNOTL "* Data follows\n";

    open(ADNOTVERWL,">".$adnotverwl);

    print ADNOTVERWL "DATALOAD TABLE notverw\n";
    print ADNOTVERWL "     UPDATE DUPLICATES\n";
    print ADNOTVERWL "            notidn    1\n";
    print ADNOTVERWL "            verw      2\n";
    print ADNOTVERWL "        INFILE *\n";
    print ADNOTVERWL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADNOTVERWL "* Data follows\n";

    open(ADNOTBENVERWL,">".$adnotbenverwl);
    print ADNOTBENVERWL "DATALOAD TABLE notbenverw\n";
    print ADNOTBENVERWL "     UPDATE DUPLICATES\n";
    print ADNOTBENVERWL "            notidn    1\n";
    print ADNOTBENVERWL "            benverw      2\n";
    print ADNOTBENVERWL "        INFILE *\n";
    print ADNOTBENVERWL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADNOTBENVERWL "* Data follows\n";
}

sub ad_not_cleanup {
    close(ADNOTL);
    close(ADNOTVERWL);
    close(ADNOTBENVERWL);
    
    if ($notcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adnotl\'\n";
    }
    
    if ($notverwcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adnotverwl\'\n";
    }
    
    if ($notbenverwcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adnotbenverwl\'\n";
    }    
}

sub ad_tit_init {
    $adtitl="tit.ad";
    $adtitpsthtsl="titpsthts.ad";
    $adtitgtunvl="titgtunv.ad";
    $adtitisbnl="titisbn.ad";
    $adtitissnl="titissn.ad";
    $adtitnerl="titner.ad";
    $adtitteiluwl="titteiluw.ad";
    $adtitstichwl="titstichw.ad";
    $adtitnrl="titnr.ad";
    $adtitartinhl="titartinh.ad";
    $adtitphysforml="titphysform.ad";
    $adtitgtml="titgtm.ad";
    $adtitgtfl="titgtf.ad";
    $adtitinverknl="titinverkn.ad";
    $adtitswtlokl="titswtlok.ad";
    $adtitswtregl="titswtreg.ad";
    $adtitverfl="titverf.ad";
    $adtitpersl="titpers.ad";
    $adtiturhl="titurh.ad";
    $adtitkorl="titkor.ad";
    $adtitnotl="titnot.ad";

    # Limits

    $last=125;
    $lesthe=125;
    $lestfn=125;
    $lhst=243;
    $lzuergurh=125;
    $lzusatz=252;
    $lvorlbeigwerk=125;
    $lgemeinsang=78;
    $lsachlben=243;
    $lvorlverf=252;
    $lvorlunter=125;
    $lausg=125;
    $lverlagsort=62;
    $lverlag=125;
    $lweitereort=62;
    $lerschjahr=78;
    $lkollation=78;
    $lmatbenennung=62;
    $lsonstmatben=62;
    $lsonstang=62;
    $lbegleitmat=62;
    $lfussnote=252;
    $lbindpreis=30;
    $lhsfn=252;
    $lsprache=30;
    $lmass=30;
    $lausg=125;
    $luebershst=125;
    $linunverkn=125;
    $lrem=2;
    $lbemerk=62;

    open(ADTITL,">".$adtitl);

    print ADTITL "DATALOAD TABLE tit\n";
    print ADTITL "     UPDATE DUPLICATES\n";
    print ADTITL "            idn    1\n";
    print ADTITL "            ida    2\n";
    print ADTITL "            titeltyp 3\n";
    print ADTITL "            versnr 4\n";
    print ADTITL "            ast 5\n";
    print ADTITL "            esthe 6\n";
    print ADTITL "            estfn 7\n";
    print ADTITL "            hst 8\n";
    print ADTITL "            zuergurh 9\n";
    print ADTITL "            zusatz 10\n";
    print ADTITL "            vorlbeigwerk 11\n";
    print ADTITL "            gemeinsang 12\n";
    print ADTITL "            sachlben 13\n";
    print ADTITL "            vorlverf 14\n";
    print ADTITL "            vorlunter 15\n";
    print ADTITL "            ausg 16\n";
    print ADTITL "            verlagsort 17\n";
    print ADTITL "            verlag 18\n";
    print ADTITL "            weitereort 19\n";
    print ADTITL "            aufnahmeort 20\n";
    print ADTITL "            aufnahmejahr 21\n";
    print ADTITL "            erschjahr 22\n";
    print ADTITL "            kollation 23\n";
    print ADTITL "            matbenennung 24\n";
    print ADTITL "            sonstmatben 25\n";
    print ADTITL "            sonstang 26\n";
    print ADTITL "            begleitmat 27\n";
    print ADTITL "            fussnote 28\n";
    print ADTITL "            bindpreis 29\n";
    print ADTITL "            hsfn 30\n";
    print ADTITL "            sprache 31\n";
    print ADTITL "            mass 32\n";
    print ADTITL "            biblid 33\n";
    print ADTITL "            uebershst 34\n";
    print ADTITL "            inunverkn 35\n";
    print ADTITL "            verbidn 36\n";
    print ADTITL "            rem 37\n";
    print ADTITL "            bemerk 38\n";
    print ADTITL "        INFILE *\n";

    if ($continuelines == 1){
	print ADTITL "            CONTINUEIF LAST = '\$continuesep'\n";
    }

    print ADTITL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITL "* Data follows\n";
    
    print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitl\'\n";

    open(ADTITPSTHTSL,">".$adtitpsthtsl);

    print ADTITPSTHTSL "DATALOAD TABLE titpsthts\n";
    print ADTITPSTHTSL "     UPDATE DUPLICATES\n";
    print ADTITPSTHTSL "            titidn    1\n";
    print ADTITPSTHTSL "            psthts      2\n";
    print ADTITPSTHTSL "        INFILE *\n";
    print ADTITPSTHTSL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITPSTHTSL "* Data follows\n";

    open(ADTITGTUNVL,">".$adtitgtunvl);

    print ADTITGTUNVL "DATALOAD TABLE titgtunv\n";
    print ADTITGTUNVL "     UPDATE DUPLICATES\n";
    print ADTITGTUNVL "            titidn    1\n";
    print ADTITGTUNVL "            gtunv      2\n";
    print ADTITGTUNVL "        INFILE *\n";
    print ADTITGTUNVL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITGTUNVL "* Data follows\n";

    open(ADTITISBNL,">".$adtitisbnl);

    print ADTITISBNL "DATALOAD TABLE titisbn\n";
    print ADTITISBNL "     UPDATE DUPLICATES\n";
    print ADTITISBNL "            titidn    1\n";
    print ADTITISBNL "            isbn      2\n";
    print ADTITISBNL "        INFILE *\n";
    print ADTITISBNL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITISBNL "* Data follows\n";

    open(ADTITISSNL,">".$adtitissnl);

    print ADTITISSNL "DATALOAD TABLE titissn\n";
    print ADTITISSNL "     UPDATE DUPLICATES\n";
    print ADTITISSNL "            titidn    1\n";
    print ADTITISSNL "            issn      2\n";
    print ADTITISSNL "        INFILE *\n";
    print ADTITISSNL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITISSNL "* Data follows\n";

    open(ADTITNERL,">".$adtitnerl);

    print ADTITNERL "DATALOAD TABLE titner\n";
    print ADTITNERL "     UPDATE DUPLICATES\n";
    print ADTITNERL "            titidn    1\n";
    print ADTITNERL "            ner      2\n";
    print ADTITNERL "        INFILE *\n";
    print ADTITNERL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITNERL "* Data follows\n";

    open(ADTITTEILUWL,">".$adtitteiluwl);

    print ADTITTEILUWL "DATALOAD TABLE titteiluw\n";
    print ADTITTEILUWL "     UPDATE DUPLICATES\n";
    print ADTITTEILUWL "            titidn    1\n";
    print ADTITTEILUWL "            teiluw      2\n";
    print ADTITTEILUWL "        INFILE *\n";
    print ADTITTEILUWL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITTEILUWL "* Data follows\n";

    open(ADTITSTICHWL,">".$adtitstichwl);

    print ADTITSTICHWL "DATALOAD TABLE titstichw\n";
    print ADTITSTICHWL "     UPDATE DUPLICATES\n";
    print ADTITSTICHWL "            titidn    1\n";
    print ADTITSTICHWL "            stichwort 2\n";
    print ADTITSTICHWL "        INFILE *\n";
    print ADTITSTICHWL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITSTICHWL "* Data follows\n";

    open(ADTITNRL,">".$adtitnrl);

    print ADTITNRL "DATALOAD TABLE titnr\n";
    print ADTITNRL "     UPDATE DUPLICATES\n";
    print ADTITNRL "            titidn    1\n";
    print ADTITNRL "            nr      2\n";
    print ADTITNRL "        INFILE *\n";
    print ADTITNRL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITNRL "* Data follows\n";

    open(ADTITARTINHL,">".$adtitartinhl);

    print ADTITARTINHL "DATALOAD TABLE titartinh\n";
    print ADTITARTINHL "     UPDATE DUPLICATES\n";
    print ADTITARTINHL "            titidn    1\n";
    print ADTITARTINHL "            artinhalt 2\n";
    print ADTITARTINHL "        INFILE *\n";
    print ADTITARTINHL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITARTINHL "* Data follows\n";

    open(ADTITPHYSFORML,">".$adtitphysforml);

    print ADTITPHYSFORML "DATALOAD TABLE titphysform\n";
    print ADTITPHYSFORML "     UPDATE DUPLICATES\n";
    print ADTITPHYSFORML "            titidn    1\n";
    print ADTITPHYSFORML "            physform      2\n";
    print ADTITPHYSFORML "        INFILE *\n";
    print ADTITPHYSFORML "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITPHYSFORML "* Data follows\n";

    open(ADTITGTML,">".$adtitgtml);

    print ADTITGTML "DATALOAD TABLE titgtm\n";
    print ADTITGTML "     UPDATE DUPLICATES\n";
    print ADTITGTML "            titidn    1\n";
    print ADTITGTML "            verwidn      2\n";
    print ADTITGTML "            zus      3\n";
    print ADTITGTML "        INFILE *\n";
    print ADTITGTML "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITGTML "* Data follows\n";

    open(ADTITGTFL,">".$adtitgtfl);

    print ADTITGTFL "DATALOAD TABLE titgtf\n";
    print ADTITGTFL "     UPDATE DUPLICATES\n";
    print ADTITGTFL "            titidn    1\n";
    print ADTITGTFL "            verwidn   2\n";
    print ADTITGTFL "            zus      3\n";
    print ADTITGTFL "        INFILE *\n";
    print ADTITGTFL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITGTFL "* Data follows\n";

    open(ADTITINVERKNL,">".$adtitinverknl);

    print ADTITINVERKNL "DATALOAD TABLE titinverkn\n";
    print ADTITINVERKNL "     UPDATE DUPLICATES\n";
    print ADTITINVERKNL "            titidn    1\n";
    print ADTITINVERKNL "            titverw   2\n";
    print ADTITINVERKNL "        INFILE *\n";
    print ADTITINVERKNL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print ADTITINVERKNL "* Data follows\n";

    open(ADTITSWTLOKL,">".$adtitswtlokl);

    print ADTITSWTLOKL "DATALOAD TABLE titswtlok\n";
    print ADTITSWTLOKL "     UPDATE DUPLICATES\n";
    print ADTITSWTLOKL "            titidn    1\n";
    print ADTITSWTLOKL "            swtverw      2\n";
    print ADTITSWTLOKL "        INFILE *\n";
    print ADTITSWTLOKL "            COMPRESS SEPARATOR '|'\n";
    print ADTITSWTLOKL "* Data follows\n";

    open(ADTITSWTREGL,">".$adtitswtregl);

    print ADTITSWTREGL "DATALOAD TABLE titswtreg\n";
    print ADTITSWTREGL "     UPDATE DUPLICATES\n";
    print ADTITSWTREGL "            titidn    1\n";
    print ADTITSWTREGL "            swtverw      2\n";
    print ADTITSWTREGL "        INFILE *\n";
    print ADTITSWTREGL "            COMPRESS SEPARATOR '|'\n";
    print ADTITSWTREGL "* Data follows\n";

    open(ADTITVERFL,">".$adtitverfl);

    print ADTITVERFL "DATALOAD TABLE titverf\n";
    print ADTITVERFL "     UPDATE DUPLICATES\n";
    print ADTITVERFL "            titidn    1\n";
    print ADTITVERFL "            verfverw  2\n";
    print ADTITVERFL "        INFILE *\n";
    print ADTITVERFL "            COMPRESS SEPARATOR '|'\n";
    print ADTITVERFL "* Data follows\n";

    open(ADTITPERSL,">".$adtitpersl);

    print ADTITPERSL "DATALOAD TABLE titpers\n";
    print ADTITPERSL "     UPDATE DUPLICATES\n";
    print ADTITPERSL "            titidn    1\n";
    print ADTITPERSL "            persverw      2\n";
    print ADTITPERSL "            bez      3\n";
    print ADTITPERSL "        INFILE *\n";
    print ADTITPERSL "            COMPRESS SEPARATOR '|'\n";
    print ADTITPERSL "* Data follows\n";

    open(ADTITURHL,">".$adtiturhl);

    print ADTITURHL "DATALOAD TABLE titurh\n";
    print ADTITURHL "     UPDATE DUPLICATES\n";
    print ADTITURHL "            titidn    1\n";
    print ADTITURHL "            urhverw      2\n";
    print ADTITURHL "        INFILE *\n";
    print ADTITURHL "            COMPRESS SEPARATOR '|'\n";
    print ADTITURHL "* Data follows\n";

    open(ADTITKORL,">".$adtitkorl);

    print ADTITKORL "DATALOAD TABLE titkor\n";
    print ADTITKORL "     UPDATE DUPLICATES\n";
    print ADTITKORL "            titidn    1\n";
    print ADTITKORL "            korverw      2\n";
    print ADTITKORL "        INFILE *\n";
    print ADTITKORL "            COMPRESS SEPARATOR '|'\n";
    print ADTITKORL "* Data follows\n";

    open(ADTITNOTL,">".$adtitnotl);

    print ADTITNOTL "DATALOAD TABLE titnot\n";
    print ADTITNOTL "     UPDATE DUPLICATES\n";
    print ADTITNOTL "            titidn    1\n";
    print ADTITNOTL "            notidn      2\n";
    print ADTITNOTL "        INFILE *\n";
    print ADTITNOTL "            COMPRESS SEPARATOR '|'\n";
    print ADTITNOTL "* Data follows\n";

}

sub ad_tit_cleanup {
    close(ADTITL);
    close(ADTITPSTHTSL);
    close(ADTITGTUNVL);
    close(ADTITISBNL);
    close(ADTITISSNL);
    close(ADTITNERL);
    close(ADTITTEILUWL);
    close(ADTITSTICHWL);
    close(ADTITNRL);
    close(ADTITARTINHL);
    close(ADTITPHYSFORML);
    close(ADTITGTML);
    close(ADTITGTFL);
    close(ADTITINVERKNL);
    close(ADTITSWTLOKL);
    close(ADTITSWTREGL);
    close(ADTITVERFL);
    close(ADTITPERSL);
    close(ADTITURHL);
    close(ADTITKORL);
    close(ADTITNOTL);
    
    if($titpsthtscount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitpsthtsl\'\n";
    }
    if($titgtunvcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitgtunvl\'\n";
    }
    if($titisbncount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitisbnl\'\n";
    }
    if($titissncount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitissnl\'\n";
    }
    if($titnercount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitnerl\'\n";
    }
    if($titteiluwcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitteiluwl\'\n";
    }
    if($titstichwcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitstichwl\'\n";
    }
    if($titnrcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitnrl\'\n";
    }
    if($titartinhcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitartinhl\'\n";
    }
    if($titphysformcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitphysforml\'\n";
    }
    if($titgtmcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitgtml\'\n";
    }
    if($titgtfcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitgtfl\'\n";
    }
    if($titinverkncount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitinverknl\'\n";
    }
    if($titswtlokcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitswtlokl\'\n";
    }
    if($titswtregcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitswtregl\'\n";
    }
    if($titverfcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitverfl\'\n";
    }
    if($titperscount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitpersl\'\n";
    }
    if($titurhcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtiturhl\'\n";
    }
    if($titkorcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitkorl\'\n";
    }
    if($titnotcount!=0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$adtitnotl\'\n";
    }    
}

sub ad_mex_init {
    $admexl="mex.ad";
    $admexsignl="mexsign.ad";

    open(ADMEXL,">".$admexl);

    print MEXL "DATALOAD TABLE mex\n";
    print MEXL "     UPDATE DUPLICATES\n";
    print MEXL "            idn    1\n";
    print MEXL "            ida    2\n";
    print MEXL "            titidn 3\n";
    print MEXL "            sigel  4\n";
    print MEXL "            verbnr 5\n";
    print MEXL "            standort 6\n";
    print MEXL "            invnr 7\n";
    print MEXL "            lokfn 8\n";
    print MEXL "            ausleihstat 9\n";
    print MEXL "            medienart 10\n";
    print MEXL "            verbundidn 11\n";
    print MEXL "            buchung 12\n";
    print MEXL "            faellig 13\n";
    print MEXL "        INFILE *\n";
    print MEXL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print MEXL "* Data follows\n";

    open(ADMEXSIGNL,">".$admexsignl);
    print MEXSIGNL "DATALOAD TABLE mexsign\n";
    print MEXSIGNL "     UPDATE DUPLICATES\n";
    print MEXSIGNL "            mexidn    1\n";
    print MEXSIGNL "            signlok   2\n";
    print MEXSIGNL "        INFILE *\n";
    print MEXSIGNL "            COMPRESS SEPARATOR '|' DELIMITER '$stringsep'\n";
    print MEXSIGNL "* Data follows\n";
}

sub ad_mex_cleanup {
    close(ADMEXL);
    close(ADMEXSIGNL);
    
    if ($mexcount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$admexl\'\n";
    }
    
    if ($mexsigncount != 0){
	print ADCONTROL "xload -u $aduser,$adpasswd -d $addb -b  \'$dir/$admexsignl\'\n";
    }    
}

#####################################################################   
# PLAIN SQL
#####################################################################   

sub sql_aut_init {
    $sqlautl="aut.sql";
    
    open(SQLAUTL,">".$sqlautl);
    print SQLAUTL "delete from aut where idn < 99999999;\n";
    print SQLAUTL "delete from autverw where autidn < 99999999;\n"; 
}

sub sql_aut_cleanup {
    close(SQLAUTL);
}

sub sql_kor_init {
    $sqlkorl="kor.sql";

    open(SQLKORL,">".$sqlkorl);
    print SQLKORL "delete from kor where idn < 99999999;\n";
    print SQLKORL "delete from korverw where koridn < 99999999;\n";
    print SQLKORL "delete from korfrueh where koridn < 99999999;\n";
    print SQLKORL "delete from korspaet where koridn < 99999999;\n"; 
}

sub sql_kor_cleanup {
    close(SQLKORL);
}

sub sql_swt_init {
    $sqlswtl="swt.sql";
    
    open(SQLSWTL,">".$sqlswtl);
    print SQLSWTL "delete from swt where idn < 99999999;\n";
    print SQLSWTL "delete from swtverw where swtidn < 99999999;\n";
    print SQLSWTL "delete from swtueber where swtidn < 99999999;\n";
    print SQLSWTL "delete from swtassoz where swtidn < 99999999;\n";
    print SQLSWTL "delete from swtfrueh where swtidn < 99999999;\n";
    print SQLSWTL "delete from swtspaet where swtidn < 99999999;\n";  
}

sub sql_swt_cleanup {
    close(SQLSWTL);
}

sub sql_not_init {
    $sqlnotl="not.sql";
    
    open(SQLNOTL,">".$sqlnotl);
    print SQLNOTL "delete from notation where idn < 99999999;\n";
    print SQLNOTL "delete from notverw where notidn < 99999999;\n";
    print SQLNOTL "delete from notbenverw where notidn < 99999999;\n";
}

sub sql_not_cleanup {
    close(SQLNOTL);
}

sub sql_tit_init {
    $sqltitl="tit.sql";

    open(SQLTITL,">".$sqltitl);    
    print SQLTITL "delete from tit where idn < 99999999;\n";
    print SQLTITL "delete from titpsthts where titidn < 99999999;\n";
    print SQLTITL "delete from titgtunv where titidn < 99999999;\n";
    print SQLTITL "delete from titisbn where titidn < 99999999;\n";
    print SQLTITL "delete from titissn where titidn < 99999999;\n";
    print SQLTITL "delete from titner where titidn < 99999999;\n";
    print SQLTITL "delete from titteiluw where titidn < 99999999;\n";
    print SQLTITL "delete from titstichw where titidn < 99999999;\n";
    print SQLTITL "delete from titnr where titidn < 99999999;\n";
    print SQLTITL "delete from titartinh where titidn < 99999999;\n";
    print SQLTITL "delete from titphysform where titidn < 99999999;\n";
    print SQLTITL "delete from titgtm where titidn < 99999999;\n";
    print SQLTITL "delete from titgtf where titidn < 99999999;\n";
    print SQLTITL "delete from titinverkn where titidn < 99999999;\n";
    print SQLTITL "delete from titswtlok where titidn < 99999999;\n";
    print SQLTITL "delete from titswtreg where titidn < 99999999;\n";
    print SQLTITL "delete from titverf where titidn < 99999999;\n";
    print SQLTITL "delete from titpers where titidn < 99999999;\n";
    print SQLTITL "delete from titurh where titidn < 99999999;\n";
    print SQLTITL "delete from titkor where titidn < 99999999;\n";
    print SQLTITL "delete from titnot where titidn < 99999999;\n";
}

sub sql_tit_cleanup {
    close(SQLTITL);
}

sub sql_mex_init {
    $sqlmexl="mex.sql";

    open(SQLMEXL,">".$sqlmexl);
    print SQLMEXL "delete from mex where idn < 99999999;\n";
    print SQLMEXL "delete from mexsign where mexidn < 99999999;\n";
}

sub sql_mex_cleanup {
    close(SQLMEXL);
}

sub sql_vbu_init {
    $sqlvbul="vbu.sql";

    open(SQLVBUL,">".$sqlvbul);
    print SQLVBUL "update mex set ausleihstat='',faellig='',buchung='' where idn < 99999999;\n";
}

sub sql_vbu_cleanup {
    close(SQLVBUL);
}


sub print_help {
    print "meta2sql.pl - Generierung von SQL-Einladedateien aus dem Meta-Format\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n\n";

    print " SQL-Einladeformate: \n";
    print "  -mysql                  : MySQL\n";
    print "  -pg                     : PostgreSQL\n";
    print "  -adabas                 : Adabas D\n";
    print "  -plainsql               : Plain SQL\n\n";
    print " Zu bearbeitende Stammdateien: \n";
    print "  -all                    : Alle\n";
    print "  -aut                    : Autoren\n";
    print "  -kor                    : Koerperschaften\n";
    print "  -not                    : Notationen\n";
    print "  -swt                    : Schlagworte\n";
    print "  -tit                    : Titel\n";
    print "  -mex                    : Exemplardaten\n\n";

    print " IDN-Modes: \n";
    print "  --idn-mode=...          : normal, prefix oder sigel\n";
    print "  --sigel=...             : sigel\n";
    print "  --offset=...             : offset\n";

    print " CharEncoding: \n";
    print "  -dos                    : DOS Encoding\n";
    print "  -encoding               : Generelles Encoding\n";
    exit;
}
