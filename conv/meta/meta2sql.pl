#!/usr/bin/perl

#####################################################################
#
#  meta2sql.pl
#
#  Generierung von SQL-Einladedateien aus dem Meta-Format
#
#  Dieses File ist (C) 1997-2006 Oliver Flimm <flimm@openbib.org>
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
use utf8;

use Getopt::Long;
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use Storable ();

use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;

&GetOptions("reduce-mem"   => \$reducemem,
	    );

my $dir=`pwd`;
chop $dir;

my $listitemcat_ref={
    '0089' => 1,
    '0310' => 1,
    '0331' => 1,
    '0412' => 1,
    '0424' => 1,
    '0425' => 1,
    '0451' => 1,
    '0455' => 1,
    '1203' => 1,
};

my $inverted_aut_ref={
    '0001' => {  # Ansetzung
        string => 1,
        ft     => 1,
        init   => 1,
    },

    '0102' => {  # Verweisform
        string => 1,
        ft     => 1,
        init   => 1,
    },
};

my $inverted_kor_ref={
    '0001' => {  # Ansetzung
        string => 1,
        ft     => 1,
        init   => 1,
    },

    '0102' => {  # Verweisform
        string => 1,
        ft     => 1,
        init   => 1,
    },

    '0103' => {  # Abkuerzung der Verweisform
        string => 1,
        ft     => 1,
        init   => 1,
    },

    '0110' => {  # Abkuerzung der Ansetzung
        string => 1,
        ft     => 1,
        init   => 1,
    },

    '0111' => {  # Frueherer/Spaeterer Name
        string => 1,
        ft     => 1,
        init   => 1,
    },

};

my $inverted_not_ref={
    '0001' => {  # Ansetzung
        string => 1,
        ft     => 1,
        init   => 1,
    },

    '0002' => {  # Ansetzung
        string => 1,
        ft     => 1,
        init   => 1,
    },

    '0102' => {  # Stichwort
        string => 1,
        ft     => 1,
        init   => 1,
    },

    '0103' => {  # Verweisform
        string => 1,
        ft     => 1,
        init   => 1,
    },

};

my $inverted_swt_ref={
    '0001' => {  # Ansetzung
        string => 1,
        ft     => 1,
        init   => 1,
    },

    '0102' => { # Verweisform
        string => 1,
        ft     => 1,
        init   => 1,
    },

};

my $inverted_tit_ref={
    '0002' => { # Aufnahmedatum
        string => 1,
    },
    
    '0304' => { # EST
        string => 1,
        ft     => 1,
    },

    '0310' => { # AST
        string => 1,
        ft     => 1,
    },

    '0331' => { # HST
        string => 1,
        ft     => 1,
    },

    '0335' => { # Zusatz zum HST
        string => 0,
        ft     => 1,
    },

    '0341' => { # PSTVorlage
        string => 1,
        ft     => 1,
    },

    '0370' => { # WST
        string => 1,
        ft     => 1,
    },

    '0540' => { # ISBN
        string => 1,
    },

};

my $inverted_mex_ref={
    '0014' => {  # Signatur
        string => 1,
        ft     => 0,
        init   => 1,
    },

};

# In die initiale Volltextsuche werden neben den bereits definierten
# Normdateikategorien inverted_*_ref folgende weitere Kategorien aus dem
# Titelbereich einbezogen. So koennen z.B. bestimmte im Titelbereich
# angesiedelte Kategorien in den anderen Normdaten-Klassen verf, kor oder
# swt recherchierbar gemacht werden.

my $search_category_ref={

    verf => {
        '0413' => 1, # Drucker
    },

    kor => {
    },

    swt => {
    },
    
    hst => {
        '0304' => 1, # EST
        '0310' => 1, # AST
        '0331' => 1, # HST
        '0335' => 1, # Zusatz zum HST
        '0341' => 1, # PSTVorlage
        '0370' => 1, # WST
        '0412' => 1, # Verlag
        '0750' => 1, # Abstract
    },
    
    isbn => {
        '0540' => 1, # ISBN
    },

    issn => {
        '0543' => 1, # ISSN
    },
    
    artinh => {
        '0800' => 1, # ArtInhalt
    },
    
    sign => {
        '0014' => 1, # Signatur
        '1203' => 1, # Zeitschriftensignatur
    },

    ejahr => {
        '0425' => 1, # Erschjahr
    },
};

my $blacklist_aut_ref = {
    '0100' => 1, # Aufnahmedatum
    '0101' => 1, # Aenderungsdatum
};

my $blacklist_kor_ref = {
    '0100' => 1, # Aufnahmedatum
    '0101' => 1, # Aenderungsdatum
};

my $blacklist_not_ref = {
    '0100' => 1, # Aufnahmedatum
    '0101' => 1, # Aenderungsdatum
};

my $blacklist_swt_ref = {
    '0100' => 1, # Aufnahmedatum
    '0101' => 1, # Aenderungsdatum
};

my $blacklist_tit_ref = {
#    '0002' => 1, # Aufnahmedatum
    '0003' => 1, # Aenderungsdatum
    '0005' => 1, # Inventarnummer (in mex vorhanden)
    '0009' => 1, # Herkunft
    '0010' => 1, # Fremdnummer
    '0011' => 1, # Lokale ID
    '0014' => 1, # Signatur (in mex vorhanden)
    '0015' => 1, # Sprache
    '0016' => 1, # Standort (in mex vorhanden)
    '0027' => 1, # Art des Werkes (V oder Leer = Verfasser, S=Sachtitelwerk, U=Urheberwerk)
    '0028' => 1, # Bandkennzeichen (Leer = Stuecktitel, B = Band, G = Gesamtwerk/Ueberordnung)
    '0036' => 1, # Erscheinungsform
    '0038' => 1, # Veroeffentlichungsart
    '0042' => 1, # Publikationsstatus
    '0150' => 1, # HBZ Personen-ID
    '0453' => 1, # Id des GT
    '0454' => 1, # Ansetzungsform GT
    '0572' => 1, # ZDB-ID
    '0715' => 1, # Unbekannt
    '0802' => 1, # Medien-Zustand
    '0905' => 1, # RSWK-ID
    '0910' => 1, # RSWK-ID
    '0915' => 1, # RSWK-ID
    '0920' => 1, # RSWK-ID
    '0925' => 1, # RSWK-ID
    '0930' => 1, # RSWK-ID
    '0935' => 1, # RSWK-ID    
    '0940' => 1, # RSWK-ID
    '0955' => 1, # RSWK-ID    
    '1000' => 1, # Titel beginnend mit 1000
    '1014' => 1, # Unbekannt
    '1025' => 1, # Lokale ZDB-ID
    '1026' => 1, # ZDB Jason-ID
    '1042' => 1, # ZDB Prio
    '1200' => 1, # Bestandzusammenfassung (in mex verwenden wir 1204)
    '1201' => 1, # Bestandsluecken (in mex verwenden wir 1204)
    '1202' => 1, # Bemerkungen zum Bestand
    '1299' => 1, # ZDB Mikro
    '1527' => 1, # ID der Parallelausgabe
    '1529' => 1, # Fortlaufende Beilage Titel?
    '1530' => 1, # ID des Bezugswerkes
    '1531' => 1, # ID der frueheren Ausgabe
    '1532' => 1, # ID fruehrer Hinweis
    '1533' => 1, # ID Titelkonkordanz
    '1533' => 1, # ID spaeterer Hinweis
    '1671' => 1, # Verbreitungsort
    '1672' => 1, # Hochschulort (z.B. Paris)
    '1674' => 1, # Veranstaltungsjahr (TODO)
    '1675' => 1, # ID des Hochschulortes
    '1676' => 1, # ID des Veranstaltungsortes
    '1677' => 1, # ID des Erscheinungsortes
    '1679' => 1, # Jahr Orginal
    '1710' => 1, # MESH-Ketten
    '1751' => 1, # Nicht mehr existent
    '1800' => 1, # Nebeneintragung 1. Person
    '1802' => 1, # Nebeneintragung 2. Koerperschaft
    '1804' => 1, # Nebeneintragung 1. EST
    '1805' => 1, # Nebeneintragung 1. Titelansetzung
    '1806' => 1, # Nebeneintragung 1. Titel in Mischform
    '1814' => 1, # Nicht mehr existent
    '1836' => 1, # Nicht mehr existent
    '1848' => 1, # Nicht mehr existent
    '1850' => 1, # Nebeneintragung 1. Person ID
    '1852' => 1, # Nebeneintragung 1. Koerperschaft ID
    '1978' => 1, # Nicht mehr existent
    '2000' => 1, # Urheber HBZ
    '2001' => 1, # HBZ-ID der Sonstig beteiligten Koerperschaft
    '2010' => 1, # RSWK HBZ
    '2011' => 1, # RSWK HBZ
    '2012' => 1, # RSWK HBZ
    '2013' => 1, # RSWK HBZ
    '2014' => 1, # RSWK HBZ
    '2015' => 1, # RSWK HBZ
    '2016' => 1, # RSWK HBZ
    '2017' => 1, # RSWK HBZ
    '2018' => 1, # RSWK HBZ
    '2019' => 1, # RSWK HBZ
    '2651' => 1, # URL lokal
    '2655' => 1, # URL lokal 
    '3000' => 1, # Erwerbung Intern
    '3002' => 1, # ZDB TitelID alt
    '3003' => 1, # ZDB lokaleID alt
    '3004' => 1, # Kommentar MAB2
    '3005' => 1, # IntNotEx
    '3006' => 1, # IntNotLok
    '3006' => 1, # IntNotLok (z.B. retro)
    '3007' => 1, # Unbekannt (Standort?)
    '3750' => 1, # Nicht mehr existent
    '4711' => 1, # Unbekannt
    '4712' => 1, # Markierung Econbiz (wi, so, wiso)
    '4715' => 1, # Markierung EDZ
    '4717' => 1, # Markierung Fachbibliothek Versicherungswissenschaft
    '4720' => 1, # Testdaten Inhaltsverzeichnis-Scans
    '4725' => 1, # Temporaeres Schlagwort
#    '0800' => 1, # Medianart (TODO: spaeter pro Pool Listen konfigurierbar machen)
#    '1600' => 1, # Hinweis auf Pseudo-Orte (TODO: Zweigstellen, Lesesaaltheke etc.)
#    '1673' => 1, # Veranstaltungsort (TODO)
};

my %listitemdata_aut=();
my %listitemdata_kor=();
my %listitemdata_mex=();


if ($reducemem){
    tie %listitemdata_aut, 'MLDBM', "./listitemdata_aut.db"
        or die "Could not tie listitemdata_aut.\n";
    
    tie %listitemdata_kor, 'MLDBM', "./listitemdata_kor.db"
        or die "Could not tie listitemdata_kor.\n";
    
    tie %listitemdata_mex, 'MLDBM', "./listitemdata_mex.db"
        or die "Could not tie listitemdata_mex.\n";
}

my $stammdateien_ref = {
    aut => {
        type           => "aut",
        infile         => "aut.exp",
        outfile        => "aut.mysql",
        outfile_ft     => "aut_ft.mysql",
        outfile_string => "aut_string.mysql",
        inverted_ref   => $inverted_aut_ref,
        blacklist_ref  => $blacklist_aut_ref,
    },
    
    kor => {
        infile         => "kor.exp",
        outfile        => "kor.mysql",
        outfile_ft     => "kor_ft.mysql",
        outfile_string => "kor_string.mysql",
        inverted_ref   => $inverted_kor_ref,
        blacklist_ref  => $blacklist_kor_ref,
    },
    
    swt => {
        infile         => "swt.exp",
        outfile        => "swt.mysql",
        outfile_ft     => "swt_ft.mysql",
        outfile_string => "swt_string.mysql",
        inverted_ref   => $inverted_swt_ref,
        blacklist_ref  => $blacklist_swt_ref,
    },
    
    notation => {
        infile         => "not.exp",
        outfile        => "not.mysql",
        outfile_ft     => "not_ft.mysql",
        outfile_string => "not_string.mysql",
        inverted_ref   => $inverted_not_ref,
        blacklist_ref  => $blacklist_not_ref,
    },
};


foreach my $type (keys %{$stammdateien_ref}){
  print STDERR "Bearbeite $stammdateien_ref->{$type}{infile} / $stammdateien_ref->{$type}{outfile}\n";

  open(IN ,       "<:utf8",$stammdateien_ref->{$type}{infile} )        || die "IN konnte nicht geoeffnet werden";
  open(OUT,       ">:utf8",$stammdateien_ref->{$type}{outfile})        || die "OUT konnte nicht geoeffnet werden";
  open(OUTFT,     ">:utf8",$stammdateien_ref->{$type}{outfile_ft})     || die "OUTFT konnte nicht geoeffnet werden";
  open(OUTSTRING, ">:utf8",$stammdateien_ref->{$type}{outfile_string}) || die "OUTSTRING konnte nicht geoeffnet werden";

  my $id;
 CATLINE:
  while (my $line=<IN>){
    my ($category,$indicator,$content);
    if ($line=~m/^0000:(\d+)$/){
      $id=$1;
      next CATLINE;
    }
    elsif ($line=~m/^9999:/){
      next CATLINE;
    }
    elsif ($line=~m/^(\d+)\.(\d+):(.*?)$/){
      ($category,$indicator,$content)=($1,$2,$3);
    }
    elsif ($line=~m/^(\d+):(.*?)$/){
      ($category,$content)=($1,$2);
    }

    chomp($content);
    
    next CATLINE if (exists $stammdateien_ref->{$type}{blacklist_ref}->{$category});

    # Ansetzungsformen fuer Kurztitelliste merken
    if ($category == 1){
        if ($type eq "aut"){
            $listitemdata_aut{$id}=$content;
        }
        elsif ($type eq "kor"){
            $listitemdata_kor{$id}=$content;
        }
    }
    
    my $contentnorm   = "";
    my $contentnormft = "";
    if (exists $stammdateien_ref->{$type}{inverted_ref}->{$category}){
       my $contentnormtmp = OpenBib::Common::Util::grundform({
           category => $category,
           content  => $content,
       });

       if ($stammdateien_ref->{$type}{inverted_ref}->{$category}->{string}){
           $contentnorm   = $contentnormtmp;
       }

       if ($stammdateien_ref->{$type}{inverted_ref}->{$category}->{ft}){
           $contentnormft = $contentnormtmp;
       }
       
       if ($stammdateien_ref->{$type}{inverted_ref}->{$category}->{init}){
           push @{$stammdateien_ref->{$type}{data}[$id]}, $contentnormtmp;
       }
   }

    if ($category && $content){
      print OUT       "$id$category$indicator$content\n";
    }
    if ($category && $contentnorm){
      print OUTSTRING "$id$category$contentnorm\n";
    }
    if ($category && $contentnormft){
      print OUTFT     "$id$category$contentnormft\n";
    }
  }
  close(OUT);
  close(OUTFT);
  close(OUTSTRING);
  close(IN);
}


#######################

$stammdateien_ref->{mex} = {
    infile         => "mex.exp",
    outfile        => "mex.mysql",
    outfile_ft     => "mex_ft.mysql",
    outfile_string => "mex_string.mysql",
    inverted_ref   => $inverted_mex_ref,
};

print STDERR "Bearbeite mex.exp\n";

open(IN ,          "<:utf8","mex.exp"         ) || die "IN konnte nicht geoeffnet werden";
open(OUT,          ">:utf8","mex.mysql"       ) || die "OUT konnte nicht geoeffnet werden";
open(OUTFT,        ">:utf8","mex_ft.mysql"    ) || die "OUTFT konnte nicht geoeffnet werden";
open(OUTSTRING,    ">:utf8","mex_string.mysql") || die "OUTSTRING konnte nicht geoeffnet werden";
open(OUTCONNECTION,">:utf8","conn.mysql")       || die "OUTCONNECTION konnte nicht geoeffnet werden";

my $id;
my $titid;
CATLINE:
while (my $line=<IN>){
    my ($category,$indicator,$content);
    if ($line=~m/^0000:(\d+)$/){
        $id=$1;
        $titid=0;
        next CATLINE;
    }
    elsif ($line=~m/^9999:/){
        next CATLINE;
    }
    elsif ($line=~m/^(\d+)\.(\d+):(.*?)$/){
        ($category,$indicator,$content)=($1,$2,$3);
    }
    elsif ($line=~m/^(\d+):(.*?)$/){
        ($category,$content)=($1,$2);
    }

    chomp($content);
    
    # Signatur fuer Kurztitelliste merken
    if ($category == 14 && $titid){
        my $array_ref=exists $listitemdata_mex{$titid}?$listitemdata_mex{$titid}:[];
        push @$array_ref, $content;
        $listitemdata_mex{$titid}=$array_ref;
    }
    
    my $contentnorm   = "";
    my $contentnormft = "";

    if ($category && $content){

        if (exists $stammdateien_ref->{mex}{inverted_ref}->{$category}){
            my $contentnormtmp = OpenBib::Common::Util::grundform({
                category => $category,
                content  => $content,
            });

            if ($stammdateien_ref->{mex}{inverted_ref}->{$category}->{string}){
                $contentnorm   = $contentnormtmp;
            }

            if ($stammdateien_ref->{mex}{inverted_ref}->{$category}->{ft}){
                $contentnormft = $contentnormtmp;
            }

            if ($stammdateien_ref->{mex}{inverted_ref}->{$category}->{init}){
                push @{$stammdateien_ref->{mex}{data}[$titid]}, $contentnormtmp;
            }
	}

        # Verknupefungen
        if ($category=~m/^0004/){
            my ($sourceid) = $content=~m/^(\d+)/;
            my $sourcetype = 1; # TIT
            my $targettype = 6; # MEX
            my $targetid   = $id;
            my $supplement = "";
            my $category   = "";
            $titid         = $sourceid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
    
        if ($category && $content){
            print OUT       "$id$category$indicator$content\n";
        }
        if ($category && $contentnorm){
            print OUTSTRING "$id$category$contentnorm\n";
        }
        if ($category && $contentnormft){
            print OUTFT     "$id$category$contentnormft\n";
        }
    }
}

close(OUT);
close(OUTFT);
close(OUTSTRING);
close(IN);

$stammdateien_ref->{tit} = {
    infile         => "tit.exp",
    outfile        => "tit.mysql",
    outfile_ft     => "tit_ft.mysql",
    outfile_string => "tit_string.mysql",
    inverted_ref   => $inverted_tit_ref,
    blacklist_ref  => $blacklist_tit_ref,
};

print STDERR "Bearbeite tit.exp\n";

open(IN ,           "<:utf8","tit.exp"          ) || die "IN konnte nicht geoeffnet werden";
open(OUT,           ">:utf8","tit.mysql"        ) || die "OUT konnte nicht geoeffnet werden";
open(OUTFT,         ">:utf8","tit_ft.mysql"     ) || die "OUTFT konnte nicht geoeffnet werden";
open(OUTSTRING,     ">:utf8","tit_string.mysql" ) || die "OUTSTRING konnte nicht geoeffnet werden";
open(OUTSEARCH,     ">:utf8","search.mysql"     ) || die "OUT konnte nicht geoeffnet werden";
open(TITLISTITEM,   ">"     ,"titlistitem.mysql") || die "TITLISTITEM konnte nicht goeffnet werden";

my @verf      = ();
my @kor       = ();
my @swt       = ();
my @notation  = ();
my @hst       = ();
my @sign      = ();
my @isbn      = ();
my @issn      = ();
my @artinh    = ();
my @ejahr     = ();
my @titverf   = ();
my @titkor    = ();
my @titswt    = ();
my @autkor    = ();

my $listitem_ref={};

CATLINE:
while (my $line=<IN>){
    my ($category,$indicator,$content);
    my ($ejahr,$sign,$isbn,$issn,$artinh);

    if ($line=~m/^0000:(\d+)$/){
        $id=$1;

        @verf      = ();
        @kor       = ();
        @swt       = ();
        @notation  = ();
        @hst       = ();
        @sign      = ();
        @isbn      = ();
        @issn      = ();
        @artinh    = ();
        @ejahr     = ();
        @titverf   = ();
        @titkor    = ();
        @titswt    = ();
        @autkor    = ();

        $listitem_ref={};

        next CATLINE;
    }
    elsif ($line=~m/^9999:/){

        my @temp=();
        foreach my $item (@verf){
            push @temp, join(" ",@{$stammdateien_ref->{aut}{data}[$item]});
        }
        push @temp, join(" ",@titverf);
        my $verf     = join(" ",@temp);

        @temp=();
        foreach my $item (@kor){
            push @temp, join(" ",@{$stammdateien_ref->{kor}{data}[$item]});
        }
        push @temp, join(" ",@titkor);
        my $kor      = join(" ",@temp);

        @temp=();
        foreach my $item (@swt){
            push @temp, join(" ",@{$stammdateien_ref->{swt}{data}[$item]});
        }
        push @temp, join(" ",@titswt);
        my $swt      = join(" ",@temp);

        @temp=();
        foreach my $item (@notation){
            push @temp, join(" ",@{$stammdateien_ref->{notation}{data}[$item]});
        }
        my $notation = join(" ",@temp);

        @temp=();
	push @temp, join(" ",@{$stammdateien_ref->{mex}{data}[$id]});
        my $mex = join(" ",@temp);
        
        my $hst       = join(" ",@hst);
        my $isbn      = join(" ",@isbn);
        my $issn      = join(" ",@issn);
        my $artinh    = join(" ",@artinh);
        my $ejahr     = join(" ",@ejahr);
        
        print OUTSEARCH "$id$verf$hst$kor$swt$notation$mex$ejahr$isbn$issn$artinh\n";

        # Listitem zusammensetzen

        # Konzeptionelle Vorgehensweise fuer die korrekte Anzeige eines Titel in
        # der Kurztitelliste:
        #
        # 1. Fall: Es existiert ein HST
        #
        # Dann:
        #
        # Unterfall 1.1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Setze diese Bandzahl vor den AST/HST
        #
        # Unterfall 1.2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Setze diese Bandzahl vor den AST/HST
        #
        # 2. Fall: Es existiert kein HST(331)
        #
        # Dann:
        #
        # Unterfall 2.1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.3: Es existieren keine Bandzahlen, aber ein (erster)
        #                Gesamttitel(451)
        #
        # Dann: Verwende diesen GT
        #
        # Unterfall 2.4: Es existieren keine Bandzahlen, kein Gesamttitel(451),
        #                aber eine Zeitschriftensignatur(1203/USB-spezifisch)
        #
        # Dann: Verwende diese Zeitschriftensignatur
        #
        if (exists $listitem_ref->{T0331}){
            # UnterFall 1.1:
            if (exists $listitem_ref->{'T0089'}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0089}[0]{content}.". ".$listitem_ref->{T0331}[0]{content};
            }
            # Unterfall 1.2:
            elsif (exists $listitem_ref->{T0455}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0455}[0]{content}.". ".$listitem_ref->{T0331}[0]{content};
            }
        }
        else {
            # UnterFall 2.1:
            if (exists $listitem_ref->{'T0089'}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0089}[0]{content};
            }
            # Unterfall 2.2:
            elsif (exists $listitem_ref->{T0455}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0455}[0]{content};
            }
            # Unterfall 2.3:
            elsif (exists $listitem_ref->{T0451}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0451}[0]{content};
            }
            # Unterfall 2.4:
            elsif (exists $listitem_ref->{T1203}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T1203}[0]{content};
            }
            else {
                $listitem_ref->{T0331}[0]{content}="Kein HST/AST vorhanden";
            }
        }
        
        # Exemplardaten-Hash zu listitem-Hash hinzufuegen

        foreach my $content (@{$listitemdata_mex{$id}}){
            push @{$listitem_ref->{X0014}}, {
                content => $content,
            };
        }
        
        # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung
        push @{$listitem_ref->{'PC0001'}}, {
            content   => join(" ; ",@autkor),
        };
        # Hinweis: Weder das verpacken via pack "u" noch Base64 koennten
        # eventuell fuer die Recherche schnell genug sein. Allerdings
        # funktioniert es sehr gut.
        # Moegliche Alternativen
        # - Binaere Daten mit load data behandeln koennen
        # - Data::Dumper verwenden, da hier ASCII herauskommt
        # - in MLDB auslagern
        # - Kategorien als eigene Spalten

        
        my $listitem = Storable::freeze($listitem_ref);

        my $encoding_type="base64";
        
        if    ($encoding_type eq "base64"){
            $listitem = MIME::Base64::encode_base64($listitem);
        }
        elsif ($encoding_type eq "uu"){
            $listitem =~s/\\/\\\\/g;
            $listitem =~s/\n/\\n/g;
            $listitem = pack "u",$tit;
        }

        print TITLISTITEM "$id$listitem\n";
        next CATLINE;
    }
    elsif ($line=~m/^(\d+)\.(\d+):(.*?)$/){
        ($category,$indicator,$content)=($1,$2,$3);
    }
    elsif ($line=~m/^(\d+):(.*?)$/){
        ($category,$content)=($1,$2);
    }

    chomp($content);
    
    if ($category && $content){
        
        next CATLINE if (exists $stammdateien_ref->{tit}{blacklist_ref}->{$category});

        if (exists $listitemcat_ref->{$category}){
            push @{$listitem_ref->{"T".$category}}, {
                indicator => $indicator,
                content   => $content,
            };
    
        };
        
        my $contentnorm   = "";
        my $contentnormft = "";

        if (exists $stammdateien_ref->{tit}{inverted_ref}->{$category}){
            my $contentnormtmp = OpenBib::Common::Util::grundform({
                category => $category,
                content  => $content,
            });

            if ($stammdateien_ref->{tit}{inverted_ref}->{$category}->{string}){
                $contentnorm   = $contentnormtmp;
            }

            if ($stammdateien_ref->{tit}{inverted_ref}->{$category}->{ft}){
                $contentnormft = $contentnormtmp;
            }
        }

        # Verknupefungen
        if ($category=~m/^0004/){
            my ($targetid) = $content=~m/^(\d+)/;
            my $targettype = 1; # TIT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "";
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0100/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 2; # AUT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0100";

            push @verf, $targetid;

            my $content = $listitemdata_aut{$targetid};

            push @{$listitem_ref->{P0100}}, {
                id      => $targetid,
                type    => 'aut',
                content => $content,
            };

            push @autkor, $content;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0101/){
            my ($targetid)  = $content=~m/^IDN: (\d+)/;
            my $targettype  = 2; # AUT
            my $sourceid    = $id;
            my $sourcetype  = 1; # TIT
            my $supplement  = "";

            if ($content=~m/^IDN: \d+ ; (.+)/){
                $supplement = $1;
            }
            
            my $category="0101";

            push @verf, $targetid;

            my $content = $listitemdata_aut{$targetid};
            
            push @{$listitem_ref->{P0101}}, {
                id         => $targetid,
                type       => 'aut',
                content    => $content,
                supplement => $supplement,
            };

            push @autkor, $content;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0103/){
            my ($targetid)  = $content=~m/^IDN: (\d+)/;
            my $targettype  = 2; # AUT
            my $sourceid    = $id;
            my $sourcetype  = 1; # TIT
            my $supplement  = "";

            if ($content=~m/^IDN: \d+ ; (.+)/){
                $supplement = $1;
            }

            my $category="0103";

            push @verf, $targetid;

            my $content = $listitemdata_aut{$targetid};
            
            push @{$listitem_ref->{P0103}}, {
                id         => $targetid,
                type       => 'aut',
                content    => $content,
                supplement => $supplement,
            };

            push @autkor, $content;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0200/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 3; # KOR
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0200";

            push @kor, $targetid;

            my $content = $listitemdata_kor{$targetid};
            
            push @{$listitem_ref->{C0200}}, {
                id         => $targetid,
                type       => 'kor',
                content    => $content,
            };

            push @autkor, $content;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0201/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 3; # KOR
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0201";

            push @kor, $targetid;

            my $content = $listitemdata_kor{$targetid};

            push @{$listitem_ref->{C0201}}, {
                id         => $targetid,
                type       => 'kor',
                content    => $content,
            };

            push @autkor, $content;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0700/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 5; # NOTATION
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0700";

            push @notation, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0710/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0710";

            push @swt, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0902/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0902";

            push @swt, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0907/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0907";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0912/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0912";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0917/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0917";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0922/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0922";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0927/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0927";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0932/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0932";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0937/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0937";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0942/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0942";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0947/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0947";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        # Titeldaten
        else {
            if (   exists $search_category_ref->{ejahr    }{$category}){
                push @ejahr, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{hst      }{$category}){
                push @hst, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{isbn     }{$category}){
                push @isbn,      OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{issn     }{$category}){
                push @issn,      OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{artinh   }{$category}){
                push @artinh, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{verf     }{$category}){
                push @titverf, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{kor      }{$category}){
                push @titkor, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $search_category_ref->{swt      }{$category}){
                push @titswt, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }

            if ($category && $content){
                print OUT       "$id$category$indicator$content\n";
            }
            if ($category && $contentnorm){
                print OUTSTRING "$id$category$contentnorm\n";
            }
            if ($category && $contentnormft){
                print OUTFT     "$id$category$contentnormft\n";
            }
        }	
    }
}
close(OUT);
close(OUTFT);
close(OUTSTRING);
close(OUTCONNECTION);
close(OUTSEARCH);
close(TITLISTITEM);
close(IN);


#######################


open(CONTROL,        ">control.mysql");
open(CONTROLINDEXOFF,">control_index_off.mysql");
open(CONTROLINDEXON, ">control_index_on.mysql");

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROLINDEXOFF << "DISABLEKEYS";
alter table $type        disable keys;
alter table ${type}_ft     disable keys;
alter table ${type}_string disable keys;
DISABLEKEYS
}

print CONTROLINDEXOFF "alter table conn        disable keys;\n";
print CONTROLINDEXOFF "alter table search      disable keys;\n";
print CONTROLINDEXOFF "alter table titlistitem disable keys;\n";

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROL << "ITEM";
truncate table $type;
load data infile '$dir/$stammdateien_ref->{$type}{outfile}'        into table $type        fields terminated by '' ;
truncate table ${type}_ft;
load data infile '$dir/$stammdateien_ref->{$type}{outfile_ft}'     into table ${type}_ft     fields terminated by '' ;
truncate table ${type}_string;
load data infile '$dir/$stammdateien_ref->{$type}{outfile_string}' into table ${type}_string fields terminated by '' ;
ITEM
}

print CONTROL << "TITITEM";
truncate table conn;
truncate table search;
truncate table titlistitem;
load data infile '$dir/conn.mysql'        into table conn   fields terminated by '' ;
load data infile '$dir/search.mysql'      into table search fields terminated by '' ;
load data infile '$dir/titlistitem.mysql' into table titlistitem fields terminated by '' ;
TITITEM

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROLINDEXON << "ENABLEKEYS";
alter table $type          enable keys;
alter table ${type}_ft     enable keys;
alter table ${type}_string enable keys;
ENABLEKEYS
}

print CONTROLINDEXON "alter table conn        enable keys;\n";
print CONTROLINDEXON "alter table search      enable keys;\n";
print CONTROLINDEXON "alter table titlistitem enable keys;\n";

close(CONTROL);
close(CONTROLINDEXOFF);
close(CONTROLINDEXON);

if ($reducemem){
    untie %listitemdata_aut;
    untie %listitemdata_kor;
    untie %listitemdata_mex;
}

1;

__END__

=head1 NAME

 meta2sql.pl - Generierung von SQL-Einladedateien aus dem Meta-Format

=head1 DESCRIPTION

 Mit dem Programm meta2sql.pl werden Daten, die im MAB2-orientierten
 Meta-Format vorliegen, in Einlade-Dateien fuer das MySQL-Datenbank-
 system umgewandelt. Bei dieser Umwandlung kann durch geeignete
 Aenderung in diesem Programm lenkend eingegriffen werden.

=head1 SYNOPSIS

 In $stammdateien_ref werden die verschiedenen Normdatentypen, ihre
 zugehoerigen Namen der Ein- und Ausgabe-Dateien, sowie die zu
 invertierenden Kategorien.

 Folgende Normdatentypen existieren:

 Titel                 (tit)      -> numerische Typentsprechung: 1
 Verfasser/Person      (aut)      -> numerische Typentsprechung: 2
 Koerperschaft/Urheber (kor)      -> numerische Typentsprechung: 3
 Schlagwort            (swt)      -> numerische Typentsprechung: 4
 Notation/Systematik   (notation) -> numerische Typentsprechung: 5
 Exemplardaten         (mex)      -> numerische Typentsprechung: 6


 Die numerische Entsprechung wird bei der Verknuepfung einzelner Saetze
 zwischen den Normdaten in der Tabelle conn verwendet.

 Der Speicherverbrauch kann ueber die Option -reduce-mem durch
 Auslagerung der fuer den Aufbau der Kurztitel-Tabelle benoetigten
 Informationen reduziert werden.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
