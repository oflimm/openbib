#!/usr/bin/perl

#####################################################################
#
#  wais2searchSQL.pl
#
#  Konvertierung von Volltextinhalten im WAIS-Format in das
#  Einladeformat fuer mySQL-Volltext-Tabellen
#
#  Dieses File ist (C) 2001-2004 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Common::Stopwords;

open(OUT,">search.sql");

while (<>){
  chomp($_);

  if (/^/){
    # Sonderbehandlung fuer hststring
    $hststring=~s/¬//g;
    $hststring=~s/\s+$//;
    $hststring=~s/\s+<.*?>//g;

    $hststring=OpenBib::Common::Stopwords::strip_first_stopword($hststring);

    print OUT "NULL|$idn|$verf|$hst|$kor|$swt|$notation|$sign|$ejahr|$isbn|$issn|$artinh|$hststring\n";

    $idn="";
    $verf="";
    $kor="";
    $hst="";
    $swt="";
    $sign="";
    $notation="";
    $isbn="";
    $issn="";
    $artinh="";
    $ejahr="";
    $hststring="";
  }
  else {

    # Spitze Klammer sollen auch suchbar sein.
    # Aus Anzeigegruenden, sind sie ueberall ausser
    # in der search-Tabelle in HTML-Schreibweise gegeben.

    s/&lt;/</g;
    s/&gt;/>/g;

    if (/^idn: (\d+)/){
      $idn=$1;
    }


    # Autoren

    if (/^endaut:/){
      $type="";
    }

    if ($type eq "verf"){
      if ($verf){
        $verf="$verf ; $_";
      }
      else {
        $verf="$_";
      }
    }

    if (/^beginaut:/){
      $type="verf";
    }

    # Koerperschaften

    if (/^endkor:/){
      $type="";
    }

    if ($type eq "kor"){
      if ($kor){
        $kor="$kor ; $_";
      }
      else {
        $kor="$_";
      }
    }

    if (/^beginkor:/){
      $type="kor";
    }

    # Schlagwort

    if (/^endswt:/){
      $type="";
    }

    if ($type eq "swt"){
      $swt="$swt ; $_";
    }

    if (/^beginswt:/){
      $type="swt";
    }

    # Notation

    if (/^endnot:/){
      $type="";
    }

    if ($type eq "notation"){
      $notation="$notation ; $_";
    }

    if (/^beginnot:/){
      $type="notation";
    }

    # Signatur

    if (/^endsignatur:/){
      $type="";
    }

    if ($type eq "sign"){
      if ($sign){
        $sign="$sign ; $_";
      }
      else {
        $sign="$_";
      }
    }

    if (/^beginsignatur:/){
      $type="sign";
    }

    # ISBN

    if (/^endisbn:/){
      $type="";
    }

    if ($type eq "isbn"){
      $_=~s/-//g;
      $_=~s/\s+//g;
      $isbn="$isbn ; $_";
    }

    if (/^beginisbn:/){
      $type="isbn";
    }

    # ISSN

    if (/^endissn:/){
      $type="";
    }

    if ($type eq "issn"){
      $_=~s/-//g;
      $_=~s/\s+//g;
      $issn="$issn ; $_";
    }

    if (/^beginissn:/){
      $type="issn";
    }

    # Art/Inhalt

    if (/^endartinh:/){
      $type="";
    }

    if ($type eq "artinh"){
      $artinh="$artinh ; $_";
    }

    if (/^beginartinh:/){
      $type="artinh";
    }

    # Titel

    if (/^endtit:/){
      $type="";
    }

    if ($type eq "hst"){
      if ($hst){
        $hst="$hst ; $_";
      }
      else {
        $hst="$_";
	$hststring="$_";
      }
    }

    if (/^begintit:/){
      $type="hst";
    }

    # Erscheinungsjahr

    if (/^beginerschjahr: (.+)$/){
      $ejahr=$1;
    }

  }

}

close(OUT);

