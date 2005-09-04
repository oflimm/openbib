#####################################################################
#
#  OpenBib::Search::Util
#
#  Dieses File ist (C) 2004-2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Util;

use strict;
use warnings;
no warnings 'redefine';

use Apache::Request ();
use DBI;
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config=\%OpenBib::Config::config;

if ($OpenBib::Config::config{benchmark}){
    use Benchmark ':hireswallclock';
}

#####################################################################
## get_aut_ans_by_idn(autidn,...): Gebe zu autidn geh"oerende
##                                 Ansetzungsform aus Autorenstammsatz 
##                                 aus
##
## autidn: IDN des Autorenstammsatzes

sub get_aut_ans_by_idn {
    my ($autidn,$dbh)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $autstatement1="select * from aut where idn = ?";

    my ($atime,$btime,$timeall);

    if ($config{benchmark}) {
	$atime=new Benchmark;
    }

    my $autresult1=$dbh->prepare("$autstatement1") or $logger->error($DBI::errstr);
    $autresult1->execute($autidn) or $logger->error($DBI::errstr);

    my $autres1=$autresult1->fetchrow_hashref;

    $autresult1->finish();

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $autstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    my $autans;

    if ($autres1->{ans}) {
        $autans=$autres1->{ans};
    }

    return $autans;
}

#####################################################################
## get_aut_set_by_idn(autidn,...): Gebe zu autidn geh"oerenden
##                                 Autorenstammsatz aus inkl.
##                                 Anzahl verkn. Titeldaten
##
## autidn: IDN des Autorenstammsatzes

sub get_aut_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $autidn            = exists $arg_ref->{autidn}
        ? $arg_ref->{autidn}            : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $searchmultipleaut = exists $arg_ref->{searchmultipleaut}
        ? $arg_ref->{searchmultipleaut} : undef;
    my $searchmode        = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}        : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : undef;
    my $rating            = exists $arg_ref->{rating}
        ? $arg_ref->{rating}            : undef;
    my $bookinfo          = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}          : undef;
    my $sorttype          = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}          : undef;
    my $sortorder         = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}         : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;
    
    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my @normset=();

    my $autstatement1="select * from aut where idn = ?";
    my $autstatement2="select * from autverw where autidn = ?";

    my ($atime,$btime,$timeall);

    if ($config{benchmark}) {
	$atime=new Benchmark;
    }

    my $autresult1=$dbh->prepare("$autstatement1") or $logger->error($DBI::errstr);
    $autresult1->execute($autidn);

    my $autres1=$autresult1->fetchrow_hashref;

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $autstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    # Ausgabe diverser Informationen
    
    push @normset, set_simple_category("Ident-Nr" ,"$autres1->{idn}");
    push @normset, set_simple_category("Ident-Alt","$autres1->{ida}") if ($autres1->{ida});
    push @normset, set_simple_category("Versnr"   ,"$autres1->{versnr}") if ($autres1->{versnr});
    push @normset, set_simple_category("Ansetzung","$autres1->{ans}") if ($autres1->{ans});
    push @normset, set_simple_category("Pndnr"    ,"$autres1->{pndnr}") if ($autres1->{pndnr});
    push @normset, set_simple_category("Verbnr"   ,"$autres1->{verbnr}") if ($autres1->{verbnr});
    
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
    
    # Ausgabe der Verweisformen
    my $autresult2=$dbh->prepare("$autstatement2") or $logger->error($DBI::errstr);
    $autresult2->execute($autidn) or $logger->error($DBI::errstr);
    
    while (my $autres2=$autresult2->fetchrow_hashref) {
        push @normset, set_simple_category("Verweis","$autres2->{verw}");
    }    
    
    $autresult2->finish();
    
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $autstatement2 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    # Ausgabe der Anzahl verk"upfter Titel
    my @requests=("select titidn from titverf where verfverw=$autres1->{idn}","select titidn from titpers where persverw=$autres1->{idn}","select titidn from titgpers where persverw=$autres1->{idn}");

    my $titelnr=get_number(\@requests,$dbh);
    
    push @normset, set_url_category({
        desc     => "Anzahl Titel",
        url      => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;searchtitofaut=$autres1->{idn}",
        contents => $titelnr,
    });

    $autresult1->finish();

    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
    # dieses angewendet werden
    if (exists $config{categorymapping}{$database}) {
        for (my $i=0; $i<=$#normset; $i++) {
            my $normdesc=$normset[$i]{desc};
      
            # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
            if (exists $config{categorymapping}{$database}{$normdesc}) {
                $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
            }
        }
    }

    return \@normset;
}

#####################################################################
## get_kor_ans_by_idn(koridn,dbh): Gebe zu koridn gehoerende 
##                                 Ansetzungsform in
##                                 Koerperschaftsstammsatz aus
##
## koridn: IDN des Koerperschaftsstammsatzes

sub get_kor_ans_by_idn {
    my ($koridn,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $korstatement1="select * from kor where idn = ?";
  
    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $korresult1=$dbh->prepare("$korstatement1") or $logger->error($DBI::errstr);
    $korresult1->execute($koridn) or $logger->error($DBI::errstr);
    my $korres1=$korresult1->fetchrow_hashref;
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $korstatement1 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    my $korans;

    if ($korres1->{korans}) {
        $korans=$korres1->{korans};
    }

    $korresult1->finish();

    return $korans;
}

#####################################################################
## get_kor_set_by_idn(koridn,...): Gebe zu koridn gehoerenden 
##                                 Koerperschaftsstammsatz +
##                                 Anzahl verknuepfter Titeldaten 
##                                 aus
##
## koridn: IDN des Koerperschaftsstammsatzes

sub get_kor_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $koridn            = exists $arg_ref->{koridn}
        ? $arg_ref->{koridn}            : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $searchmultiplekor = exists $arg_ref->{searchmultiplekor}
        ? $arg_ref->{searchmultiplekor} : undef;
    my $searchmode        = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}        : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : undef;
    my $rating            = exists $arg_ref->{rating}
        ? $arg_ref->{rating}            : undef;
    my $bookinfo          = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}          : undef;
    my $sorttype          = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}          : undef;
    my $sortorder         = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}         : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @normset=();

    my $korstatement1="select * from kor where idn = ?";
    my $korstatement2="select * from korverw where koridn = ?";
    my $korstatement3="select * from korfrueh where koridn = ?";
    my $korstatement4="select * from korspaet where koridn = ?";

    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $korresult1=$dbh->prepare("$korstatement1") or $logger->error($DBI::errstr);
    $korresult1->execute($koridn) or $logger->error($DBI::errstr);

    my $korres1=$korresult1->fetchrow_hashref;
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $korstatement1 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    push @normset, set_simple_category("Ident-Nr" ,"$korres1->{idn}");
    push @normset, set_simple_category("Ident-Alt","$korres1->{ida}") if ($korres1->{ida});
    push @normset, set_simple_category("Ansetzung","$korres1->{korans}") if ($korres1->{korans});
    push @normset, set_simple_category("GK-Ident" ,"$korres1->{gkdident}") if ($korres1->{gkdident});
  
    # Verweisungsformen ausgeben
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $korresult2=$dbh->prepare("$korstatement2") or $logger->error($DBI::errstr);
    $korresult2->execute($koridn) or $logger->error($DBI::errstr);
  
    while (my $korres2=$korresult2->fetchrow_hashref) {
        push @normset, set_simple_category("Verweis","$korres2->{verw}");
    }
  
    $korresult2->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $korstatement2 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Fruehere Form ausgeben
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $korresult3=$dbh->prepare("$korstatement3") or $logger->error($DBI::errstr);
    $korresult3->execute($koridn) or $logger->error($DBI::errstr);
  
    while (my $korres3=$korresult3->fetchrow_hashref) {
        push @normset, set_simple_category("Fr&uuml;her","$korres3->{frueher}");
    }
  
    $korresult3->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $korstatement3 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    # Form fuer Spaeter ausgeben
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $korresult4=$dbh->prepare("$korstatement4") or $logger->error($DBI::errstr);
    $korresult4->execute($koridn) or $logger->error($DBI::errstr);
  
    while (my $korres4=$korresult4->fetchrow_hashref) {
        push @normset, set_simple_category("Sp&auml;ter","$korres4->{spaeter}");
    }
  
    $korresult4->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $korstatement4 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    my @requests=("select titidn from titurh where urhverw=$korres1->{idn}","select titidn from titkor where korverw=$korres1->{idn}");
    my $titelnr=get_number(\@requests,$dbh);

    push @normset, set_url_category({
        desc     => "Anzahl Titel",
        url      => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;searchtitofurhkor=$korres1->{idn}",
        contents => $titelnr,
    });

    $korresult1->finish();

  
    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
    # dieses angewendet werden
    if (exists $config{categorymapping}{$database}) {
        for (my $i=0; $i<=$#normset; $i++) {
            my $normdesc=$normset[$i]{desc};
      
            # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
            if (exists $config{categorymapping}{$database}{$normdesc}) {
                $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
            }
        }
    }
  
    return \@normset;
}

#####################################################################
## get_swt_ans_by_idn(swtidn,dbh): Gebe zu swtidn gehoerendes Schlagwort
##                                 in Schlagwortstammsatz aus
##
## swtidn: IDN des Schlagwortstammsatzes

sub get_swt_ans_by_idn {
    my ($swtidn,$dbh)=@_;
  
    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my $swtstatement1="select * from swt where idn = ?";
  
    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $swtresult1=$dbh->prepare("$swtstatement1") or $logger->error($DBI::errstr);
    $swtresult1->execute($swtidn) or $logger->error($DBI::errstr);
  
    my $swtres1=$swtresult1->fetchrow_hashref;
  
    my $schlagwort;
  
    if ($swtres1->{schlagw}) {
        $schlagwort=$swtres1->{schlagw};
    }
  
    $swtresult1->finish();
  
    return $schlagwort;
}

#####################################################################
## get_swt_set_by_idn(swtidn,...): Gebe zu swtidn gehoerenden
##                                 Schlagwortstammsatz + Anzahl
##                                 verknuepfter Titel aus
##
## swtidn: IDN des Schlagwortstammsatzes

sub get_swt_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $swtidn            = exists $arg_ref->{swtidn}
        ? $arg_ref->{swtidn}            : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $searchmultipleswt = exists $arg_ref->{searchmultipleswt}
        ? $arg_ref->{searchmultipleswt} : undef;
    my $searchmode        = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}        : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : undef;
    my $rating            = exists $arg_ref->{rating}
        ? $arg_ref->{rating}            : undef;
    my $bookinfo          = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}          : undef;
    my $sorttype          = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}          : undef;
    my $sortorder         = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}         : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @normset=();

    my $swtstatement1="select * from swt where idn = ?";
    my $swtstatement2="select * from swtverw where swtidn = ?";
  
    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $swtresult1=$dbh->prepare("$swtstatement1") or $logger->error($DBI::errstr);
    $swtresult1->execute($swtidn) or $logger->error($DBI::errstr);
  
    my $swtres1=$swtresult1->fetchrow_hashref;

    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $swtstatement1 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe diverser Informationen
    push @normset, set_simple_category("Ident-Nr"  ,"$swtres1->{idn}");
    push @normset, set_simple_category("Ident-Alt" ,"$swtres1->{ida}") if ($swtres1->{ida});
    push @normset, set_simple_category("Schlagwort","$swtres1->{schlagw}") if ($swtres1->{schlagw});
    push @normset, set_simple_category("Erlaeut"   ,"$swtres1->{erlaeut}") if ($swtres1->{erlaeut});
    push @normset, set_simple_category("Verbidn"   ,"$swtres1->{verbidn}") if ($swtres1->{verbidn});
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $swtresult2=$dbh->prepare("$swtstatement2") or $logger->error($DBI::errstr);
    $swtresult2->execute($swtidn) or $logger->error($DBI::errstr);
  
    while (my $swtres2=$swtresult2->fetchrow_hashref) {
        push @normset, set_simple_category("Verweis","$swtres2->{verw}") if ($swtres2->{verw});
    }    
    $swtresult2->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $swtstatement2 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
  
    my @requests=("select titidn from titswtlok where swtverw=$swtres1->{idn}");
    my $titelnr=get_number(\@requests,$dbh);

    push @normset, set_url_category({
        desc     => "Anzahl Titel",
        url      => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;searchtitofswt=$swtres1->{idn}",
        contents => $titelnr,
    });
  
    $swtresult1->finish();

    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss
    # dieses angewendet werden
    if (exists $config{categorymapping}{$database}) {
        for (my $i=0; $i<=$#normset; $i++) {
            my $normdesc=$normset[$i]{desc};
      
            # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
            if (exists $config{categorymapping}{$database}{$normdesc}) {
                $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
            }
        }
    }
    
    return \@normset;
}

#####################################################################
## get_not_ans_by_idn(notidn,dbh): Gebe zu notidn gehoerende Notation in
##                                Notationsstammsatz aus
##
## notidn: IDN des Notationsstammsatzes

sub get_not_ans_by_idn {
    my ($notidn,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $notstatement1="select * from notation where idn = ?";

    my ($atime,$btime,$timeall);
    
    if ($config{benchmark}) {
	$atime=new Benchmark;
    }

    my $notresult1=$dbh->prepare("$notstatement1") or $logger->error($DBI::errstr);
    $notresult1->execute($notidn) or $logger->error($DBI::errstr);

    my $notres1=$notresult1->fetchrow_hashref;

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $notstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }
    
    # Zuruecklieferung der Notation
    my $notation;
    
    if ($notres1->{notation}) {
        $notation=$notres1->{notation};
    }

    $notresult1->finish();

    return $notation;
}

#####################################################################
## get_not_set_by_idn(notidn,...): Gebe zu notidn gehoerenden
##                                 Notationsstammsatz + Anzahl
##                                 verknuepfter Titel aus
##
## notidn: IDN des Notationsstammsatzes

sub get_not_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $notidn            = exists $arg_ref->{notidn}
        ? $arg_ref->{notidn}            : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $searchmultiplenot = exists $arg_ref->{searchmultiplenot}
        ? $arg_ref->{searchmultiplenot} : undef;
    my $searchmode        = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}        : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : undef;
    my $rating            = exists $arg_ref->{rating}
        ? $arg_ref->{rating}            : undef;
    my $bookinfo          = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}          : undef;
    my $sorttype          = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}          : undef;
    my $sortorder         = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}         : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @normset=();

    my $notstatement1="select * from notation where idn = ?";
    my $notstatement2="select * from notverw where notidn = ?";
    my $notstatement3="select * from notbenverw where notidn = ?";

    my ($atime,$btime,$timeall);
    
    if ($config{benchmark}) {
	$atime=new Benchmark;
    }

    my $notresult1=$dbh->prepare("$notstatement1") or $logger->error($DBI::errstr);
    $notresult1->execute($notidn) or $logger->error($DBI::errstr);

    my $notres1=$notresult1->fetchrow_hashref;

    if ($config{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $notstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }
    
    # Ausgabe diverser Informationen
    push @normset, set_simple_category("Ident-Nr" ,"$notres1->{idn}");
    push @normset, set_simple_category("Ident-Alt","$notres1->{ida}") if ($notres1->{ida});
    push @normset, set_simple_category("Vers-Nr"  ,"$notres1->{versnr}") if ($notres1->{versnr});
    push @normset, set_simple_category("Notation" ,"$notres1->{notation}") if ($notres1->{notation});
    push @normset, set_simple_category("Benennung","$notres1->{benennung}") if ($notres1->{benennung});
    
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
    
    # Ausgabe der Verweise
    my $notresult2=$dbh->prepare("$notstatement2") or $logger->error($DBI::errstr);
    $notresult2->execute($notidn) or $logger->error($DBI::errstr);
    
    while (my $notres2=$notresult2->fetchrow_hashref) {
        push @normset, set_simple_category("Verweis","$notres2->{verw}");
    }
    $notresult2->finish();

    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $notstatement2 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
    
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
    
    # Ausgabe von Benverw
    my $notresult3=$dbh->prepare("$notstatement3") or $logger->error($DBI::errstr);
    $notresult3->execute($notidn) or $logger->error($DBI::errstr);
    
    while (my $notres3=$notresult3->fetchrow_hashref) {
        push @normset, set_simple_category("Ben.Verweis","$notres3->{benverw}");
    }    
    $notresult3->finish();
    
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $notstatement3 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
    
    # Ausgabe diverser Informationen
    push @normset, set_simple_category("Abrufzeichen","$notres1->{abrufzeichen}") if ($notres1->{abrufzeichen});
    push @normset, set_simple_category("Beschr-Not." ,"$notres1->{beschrnot}") if ($notres1->{beschrnot});
    push @normset, set_simple_category("Abrufr"      ,"$notres1->{abrufr}") if ($notres1->{abrufr});
    
    # 	if ($notres1[8]){
    # 	    print "<tr><td bgcolor=\"lightblue\"><strong>Oberbegriff</strong></td>\n";
    # 	    print "<td>$notres1[8]";
    # 	    print "</td>";
    # 	    print "<td><input type=radio name=searchsinglenot value=$notres1[8] ";
    # 	    if ($firstselection == 1){
    # 		print "checked";
    # 		$firstselection=0;
    # 	    }
    # 	    print "></td></tr>";
    # 	}    

    # Ausgabe der Anzahl verknuepfter Titel
    my @requests=("select titidn from titnot where notidn=$notres1->{idn}");
    my $titelnr=get_number(\@requests,$dbh);
    
    push @normset, set_url_category({
        desc     => "Anzahl Titel",
        url      => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;searchtitofnot=$notres1->{idn}",
        contents => $titelnr,
    });
    
    $notresult1->finish();

    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
    # dieses angewendet werden
    if (exists $config{categorymapping}{$database}) {
        for (my $i=0; $i<=$#normset; $i++) {
            my $normdesc=$normset[$i]{desc};
      
            # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
            if (exists $config{categorymapping}{$database}{$normdesc}) {
                $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
            }
        }
    }

    return \@normset;
}

sub get_tit_listitem_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $titidn            = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}            : undef;
    my $hint              = exists $arg_ref->{hint}
        ? $arg_ref->{hint}               : undef;
    my $mode              = exists $arg_ref->{mode}
        ? $arg_ref->{mode}               : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $sessiondbh        = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}        : undef;
    my $searchmultipleaut = exists $arg_ref->{searchmultipleaut}
        ? $arg_ref->{searchmultipleaut} : undef;
    my $searchmultiplekor = exists $arg_ref->{searchmultiplekor}
        ? $arg_ref->{searchmultiplekor} : undef;
    my $searchmultipleswt = exists $arg_ref->{searchmultipleswt}
        ? $arg_ref->{searchmultipleswt} : undef;
    my $searchmultiplenot = exists $arg_ref->{searchmultiplenot}
        ? $arg_ref->{searchmultiplenot} : undef;
    my $searchmultipletit = exists $arg_ref->{searchmultipletit}
        ? $arg_ref->{searchmultipletit} : undef;
    my $searchmode        = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}        : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : undef;
    my $rating            = exists $arg_ref->{rating}
        ? $arg_ref->{rating}            : undef;
    my $bookinfo          = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}          : undef;
    my $sorttype          = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}          : undef;
    my $sortorder         = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}         : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my $titstatement1="select * from tit where idn = ?";
  
    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult1=$dbh->prepare("$titstatement1") or $logger->error($DBI::errstr);
    $titresult1->execute($titidn) or $logger->error($DBI::errstr);
  
    my $titres1=$titresult1->fetchrow_hashref;
    $titresult1->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement1 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall; 
    }
  
    my %listitem=();
  
    my $retval="";
  
    my @verfasserarray=();
  
    my @signaturarray=();
  
    my $mexstatement1="select idn from mex where titidn=$titidn";
  
    my @requests=($mexstatement1);
    my @verknmex=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  
    foreach my $mexidn (@verknmex) {
        my $mexstatement2="select signlok from mexsign where mexidn=$mexidn";	
        @requests=($mexstatement2);
        my @sign=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
    
        push @signaturarray, @sign;
    
    }
  
    $listitem{signatur}=join(" ; ", @signaturarray);
  
    # Verfasser etc. zusammenstellen
  
    # Ausgabe der Verfasser
    @requests=("select verfverw from titverf where titidn=$titidn");
    my @titres8=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

    foreach my $titidn8 (@titres8) {
        push @verfasserarray, get_aut_ans_by_idn("$titidn8",$dbh);
    }
  
    # Ausgabe der Personen
    {
        my $reqstring="select persverw,bez from titpers where titidn=?";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
        while (my $res=$request->fetchrow_hashref) {	    
            my $persverw=$res->{persverw};
            my $bez=$res->{bez};
      
            if ($bez) {
                push @verfasserarray, get_aut_ans_by_idn("$persverw",$dbh)." $bez";
            }
            else {
                push @verfasserarray, get_aut_ans_by_idn("$persverw",$dbh);
            }
      
        }
        $request->finish();
    }
  
    # Ausgabe der gefeierten Personen
    @requests=("select persverw from titgpers where titidn=$titidn");
    my @titres19=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
    foreach my $titidn19 (@titres19) {
        push @verfasserarray, get_aut_ans_by_idn("$titidn19",$dbh);
    }
  
    # Ausgabe der Urheber
    @requests=("select urhverw from titurh where titidn=$titidn");
    my @titres10=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
    foreach my $titidn10 (@titres10) {
        push @verfasserarray, get_kor_ans_by_idn("$titidn10",$dbh);
    }
  
    # Ausgabe der K"orperschaften
    @requests=("select korverw from titkor where titidn=$titidn");
    my @titres11=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
    foreach my $titidn11 (@titres11) {
        push @verfasserarray, get_kor_ans_by_idn("$titidn11",$dbh);
    }
  
    $listitem{verfasser} = join(" ; ",@verfasserarray);
  
    my $erschjahr=$titres1->{erschjahr};
  
    if ($erschjahr eq "") {
        $erschjahr=$titres1->{anserschjahr};
    }
  
    $listitem{erschjahr} = $erschjahr;
    $listitem{idn}       = $titres1->{idn};
    $listitem{publisher} = $titres1->{verlag};
    $listitem{database}  = $database;

    # Ab jetzt hochhangeln zum uebergeordneten Titel, wenn im lokalen keine
    # Sachl. Ben. bzw. HST vorhanden
    if (($titres1->{sachlben} eq "")&&($titres1->{hst} eq "")) {
        # Wenn bei Titeln des Typs 4 (Bandauff"uhrungen) die Kategorien 
        # Sachliche Benennung und HST nicht besetzt sind, dann verwende als
        # Ausgabetext stattdessen den HST des *ersten* "ubergeordneten Werkes und
        # den Zusatz/Laufende Z"ahlung
        if ($hint eq "none") {
            # Finde anhand GTM
            my @requests=("select verwidn from titgtm where titidn=$titidn limit 1");
            my @tempgtmidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
      
            # in @tempgtmidns sind die IDNs der "ubergeordneten Werke
            foreach my $tempgtmidn (@tempgtmidns) {
	
                my @requests=("select hst from tit where idn=$tempgtmidn"); 
                my @tithst=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
                @requests=("select ast from tit where idn=$tempgtmidn"); 
                my @titast=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
                # Der AST hat Vorrang ueber den HST
                if ($titast[0]) {
                    $tithst[0]=$titast[0];
                }
	
                @requests=("select zus from titgtm where verwidn=$tempgtmidn");
                my @gtmzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
                $listitem{hst}   = $tithst[0];
                $listitem{zus}   = $gtmzus[0];
                $listitem{title} = "$listitem{hst} ; $listitem{zus}";
            }
            # obsolete ?????
      
            @requests=("select verwidn from titgtf where titidn=$titidn");
            my @tempgtfidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
      
            my $tempgtfidn;
      
            if ($#tempgtfidns >= 0) {
                $tempgtfidn=$tempgtfidns[0];
                # Problem: Mehrfachausgabe in Kurztrefferausgabe eines Titels...
                # Loesung: Nur der erste wird ausgegeben
                #		foreach $tempgtfidn (@tempgtfidns){
	
                my @requests=("select hst from tit where idn=$tempgtfidn");
	
                my @tithst=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
                @requests=("select ast from tit where idn=$tempgtfidn");
	
                my @titast=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
                # Der AST hat Vorrang ueber den HST
	
                if ($titast[0]) {
                    $tithst[0]=$titast[0];
                }
	
                @requests=("select zus from titgtf where verwidn=$tempgtfidn");
	
                my @gtfzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
                $listitem{hst}   = $tithst[0];
                $listitem{zus}   = $gtfzus[0];
                $listitem{title} = "$listitem{hst} ; $listitem{zus}";	
            }
        }
        else {
            my @requests=("select hst from tit where idn=$hint");
            my @tithst=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
            
            @requests=("select ast from tit where idn=$hint");
            my @titast=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
      
            # Der AST hat Vorrang ueber den HST
            if ($titast[0]) {
                $tithst[0]=$titast[0];
            }
      
            if ($mode == 6) {
                my @requests=("select zus from titgtf where verwidn=$hint and titidn=$titidn");
                my @gtfzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
                $listitem{hst}   = $tithst[0];
                $listitem{zus}   = $gtfzus[0];
                $listitem{title} = "$listitem{hst} ; $listitem{zus}";	
            }
            if ($mode == 7) {
                my $showerschjahr=$titres1->{erschjahr};
	
                if ($showerschjahr eq "") {
                    $showerschjahr=$titres1->{anserschjahr};
                }
	
                my @requests=("select zus from titgtm where verwidn=$hint and titidn=$titidn");
                my @gtmzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
                $listitem{hst}   = $tithst[0];
                $listitem{zus}   = $gtmzus[0];
                $listitem{title} = "$listitem{hst} ; $listitem{zus}";
            }
            if ($mode == 8) {
                my $showerschjahr=$titres1->{erschjahr};
	
                if ($showerschjahr eq "") {
                    $showerschjahr=$titres1->{anserschjahr};
                }
	
                my @requests=("select zus from titinverkn where titverw=$hint and titidn=$titidn");
                my @invkzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

                $listitem{hst}   = $tithst[0];
                $listitem{zus}   = $invkzus[0];
                $listitem{title} = "$listitem{hst} ; $listitem{zus}";
            }
        }
    }
    # Falls HST oder Sachlben existieren, dann gebe ganz normal aus:
    else {
        # Der AST hat Vorrang ueber den HST
        if ($titres1->{ast}) {
            $titres1->{hst}=$titres1->{ast};
        }
    
        if ($titres1->{hst} eq "") {
            $titres1->{hst}="Kein HST/AST vorhanden";
        }
    
        my $titstring="";
    
        if ($titres1->{hst}) {
            $titstring=$titres1->{hst};
        }
        elsif ($titres1->{sachlben}) {
            $titstring=$titres1->{sachlben};
        }
    
        $listitem{hst}   = $titstring;
        $listitem{zus}   = "";
        $listitem{title} = $titstring;
    }

    return \%listitem;
}

sub print_tit_list_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $itemlist_ref      = exists $arg_ref->{itemlist_ref}
        ? $arg_ref->{itemlist_ref}      : undef;
    my $targetdbinfo_ref  = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}  : undef;
    my $searchmode        = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}        : undef;
    my $rating            = exists $arg_ref->{rating}
        ? $arg_ref->{rating}            : undef;
    my $bookinfo          = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}          : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;
    my $r                 = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}         : undef;
    my $stylesheet        = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}        : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : undef;
    my $offset            = exists $arg_ref->{offset}
        ? $arg_ref->{offset}            : undef;
    my $view              = exists $arg_ref->{view}
        ? $arg_ref->{view}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @itemlist=@$itemlist_ref;

    my $hits=$#itemlist;

    # Navigationselemente erzeugen
    my %args=$r->args;
    delete $args{offset};
    delete $args{hitrange};
    my @args=();
    while (my ($key,$value)=each %args) {
        push @args,"$key=$value";
    }

    my $baseurl="http://$config{servername}$config{search_loc}?".join(";",@args);

    my @nav=();

    if ($hitrange > 0) {
        for (my $i=1; $i <= $hits; $i+=$hitrange) {
            my $active=0;

            if ($i == $offset) {
                $active=1;
            }

            my $item={
		start  => $i,
		end    => ($i+$hitrange>$hits)?$hits+1:$i+$hitrange-1,
		url    => $baseurl.";hitrange=$hitrange;offset=$i",
		active => $active,
            };
            push @nav,$item;
        }
    }

    my $hostself="http://".$r->hostname.$r->uri;

    my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'',0);

    # TT-Data erzeugen
    my $ttdata={
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $sessionID,
	      
        database       => $database,

        hits           => $hits,
	      
        searchmode     => $searchmode,
        rating         => $rating,
        bookinfo       => $bookinfo,
        sessionID      => $sessionID,
	      
        dbinfo         => $targetdbinfo_ref->{dbinfo},
        itemlist       => \@itemlist,
        hostself       => $hostself,
        queryargs      => $queryargs,
        baseurl        => $baseurl,
        thissortstring => $thissortstring,
        sortselect     => $sortselect,
	      
        hitrange       => $hitrange,
        offset         => $offset,
        nav            => \@nav,

        utf2iso        => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            return $string;
        },
	      
        show_corporate_banner => 0,
        show_foot_banner      => 1,
        config         => \%config,
    };
  
    OpenBib::Common::Util::print_page($config{tt_search_showtitlist_tname},$ttdata,$r);

    return;
}

sub print_tit_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $titidn             = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}             : undef;
    my $hint               = exists $arg_ref->{hint}
        ? $arg_ref->{hint}               : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $searchmultipleaut  = exists $arg_ref->{searchmultipleaut}
        ? $arg_ref->{searchmultipleaut}  : undef;
    my $searchmultiplekor  = exists $arg_ref->{searchmultiplekor}
        ? $arg_ref->{searchmultiplekor}  : undef;
    my $searchmultipleswt  = exists $arg_ref->{searchmultipleswt}
        ? $arg_ref->{searchmultipleswt}  : undef;
    my $searchmultiplenot  = exists $arg_ref->{searchmultiplenot}
        ? $arg_ref->{searchmultiplenot}  : undef;
    my $searchmultipletit  = exists $arg_ref->{searchmultipletit}
        ? $arg_ref->{searchmultipletit}  : undef;
    my $searchmode         = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}         : undef;
    my $targetdbinfo_ref   = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}   : undef;
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $hitrange           = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}           : undef;
    my $rating             = exists $arg_ref->{rating}
        ? $arg_ref->{rating}             : undef;
    my $bookinfo           = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}           : undef;
    my $sorttype           = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}           : undef;
    my $sortorder          = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}          : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $titeltyp_ref       = exists $arg_ref->{titeltyp_ref}
        ? $arg_ref->{titeltyp_ref}       : undef;
    my $sessionID          = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}          : undef;
    my $r                  = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}          : undef;
    my $stylesheet         = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}         : undef;
    my $view               = exists $arg_ref->{view}
        ? $arg_ref->{view}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
        titidn             => $titidn,
        hint               => $hint,
        dbh                => $dbh,
        sessiondbh         => $sessiondbh,
        searchmultipleaut  => $searchmultipleaut,
        searchmultiplekor  => $searchmultiplekor,
        searchmultipleswt  => $searchmultipleswt,
        searchmultiplekor  => $searchmultiplekor,
        searchmultipletit  => $searchmultipletit,
        searchmode         => $searchmode,
        targetdbinfo_ref   => $targetdbinfo_ref,
        targetcircinfo_ref => $targetcircinfo_ref,
        hitrange           => $hitrange,
        rating             => $rating,
        bookinfo           => $bookinfo,
        sorttype           => $sorttype,
        sortorder          => $sortorder,
        database           => $database,
        titeltyp_ref       => $titeltyp_ref,
        sessionID          => $sessionID
    });

    my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation({
        sessiondbh => $sessiondbh,
        database   => $database,
        titidn     => $titidn,
        sessionID  => $sessionID,
        searchmode => $searchmode,
        rating     => $rating,
        bookinfo   => $bookinfo,
        hitrange   => $hitrange,
        sortorder  => $sortorder,
        sorttype   => $sorttype
    });

    my $poolname=$targetdbinfo_ref->{sigel}{
        $targetdbinfo_ref->{dbases}{$database}};

    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $sessionID,
	      
        database   => $database,
	  
        poolname   => $poolname,

        prevurl    => $prevurl,
        nexturl    => $nexturl,

        searchmode => $searchmode,
        hitrange   => $hitrange,
        rating     => $rating,
        bookinfo   => $bookinfo,
        sessionID  => $sessionID,
	
        titidn     => $titidn,
        normset    => $normset,
        mexnormset => $mexnormset,
        circset    => $circset,

        utf2iso    => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            return $string;
        },
	      
        show_corporate_banner => 0,
        show_foot_banner => 1,
        config     => \%config,
    };
  
    OpenBib::Common::Util::print_page($config{tt_search_showtitset_tname},$ttdata,$r);

    return;
}

sub print_mult_tit_set_by_idn { 
    my ($arg_ref) = @_;

    # Set defaults
    my $titidns_ref        = exists $arg_ref->{titidns_ref}
        ? $arg_ref->{titidns_ref}        : undef;
    my $hint               = exists $arg_ref->{hint}
        ? $arg_ref->{hint}               : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $searchmultipleaut  = exists $arg_ref->{searchmultipleaut}
        ? $arg_ref->{searchmultipleaut}  : undef;
    my $searchmultiplekor  = exists $arg_ref->{searchmultiplekor}
        ? $arg_ref->{searchmultiplekor}  : undef;
    my $searchmultipleswt  = exists $arg_ref->{searchmultipleswt}
        ? $arg_ref->{searchmultipleswt}  : undef;
    my $searchmultiplenot  = exists $arg_ref->{searchmultiplenot}
        ? $arg_ref->{searchmultiplenot}  : undef;
    my $searchmultipletit  = exists $arg_ref->{searchmultipletit}
        ? $arg_ref->{searchmultipletit}  : undef;
    my $searchmode         = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}         : undef;
    my $targetdbinfo_ref = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref} : undef;
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $hitrange           = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}           : undef;
    my $rating             = exists $arg_ref->{rating}
        ? $arg_ref->{rating}             : undef;
    my $bookinfo           = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}           : undef;
    my $sorttype           = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}           : undef;
    my $sortorder          = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}          : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $titeltyp_ref       = exists $arg_ref->{titeltyp_ref}
        ? $arg_ref->{titeltyp_ref}       : undef;
    my $sessionID          = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}          : undef;
    my $r                  = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}          : undef;
    my $stylesheet         = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}         : undef;
    my $view               = exists $arg_ref->{view}
        ? $arg_ref->{view}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my @titidns=@$titidns_ref;

    my @titsets=();

    foreach my $titidn (@titidns) {
        my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
            titidn             => $titidn,
            hint               => $hint,
            dbh                => $dbh,
            sessiondbh         => $sessiondbh,
            searchmultipleaut  => $searchmultipleaut,
            searchmultiplekor  => $searchmultiplekor,
            searchmultipleswt  => $searchmultipleswt,
            searchmultiplekor  => $searchmultiplekor,
            searchmultipletit  => $searchmultipletit,
            searchmode         => $searchmode,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => $targetcircinfo_ref,
            hitrange           => $hitrange,
            rating             => $rating,
            bookinfo           => $bookinfo,
            sorttype           => $sorttype,
            sortorder          => $sortorder,
            database           => $database,
            titeltyp_ref       => $titeltyp_ref,
            sessionID          => $sessionID
        });
        
        my $thisset={
            titidn     => $titidn,
            normset    => $normset,
            mexnormset => $mexnormset,
            circset    => $circset,
        };
        push @titsets, $thisset;
    }

    my $poolname=$targetdbinfo_ref->{sigel}{
        $targetdbinfo_ref->{dbases}{$database}};

    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $sessionID,
	      
        database   => $database,
	  
        poolname   => $poolname,

        searchmode => $searchmode,
        hitrange   => $hitrange,
        rating     => $rating,
        bookinfo   => $bookinfo,
        sessionID  => $sessionID,
	
        titsets    => \@titsets,

        utf2iso    => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            return $string;
        },
	      
        show_corporate_banner => 0,
        show_foot_banner      => 1,
        config     => \%config,
    };
  
    OpenBib::Common::Util::print_page($config{tt_search_showmulttitset_tname},$ttdata,$r);

    return;
}

sub get_tit_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $titidn             = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}             : undef;
    my $hint               = exists $arg_ref->{hint}
        ? $arg_ref->{hint}               : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $searchmultipleaut  = exists $arg_ref->{searchmultipleaut}
        ? $arg_ref->{searchmultipleaut}  : undef;
    my $searchmultiplekor  = exists $arg_ref->{searchmultiplekor}
        ? $arg_ref->{searchmultiplekor}  : undef;
    my $searchmultipleswt  = exists $arg_ref->{searchmultipleswt}
        ? $arg_ref->{searchmultipleswt}  : undef;
    my $searchmultiplenot  = exists $arg_ref->{searchmultiplenot}
        ? $arg_ref->{searchmultiplenot}  : undef;
    my $searchmultipletit  = exists $arg_ref->{searchmultipletit}
        ? $arg_ref->{searchmultipletit}  : undef;
    my $searchmode         = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}         : undef;
    my $targetdbinfo_ref   = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}   : undef;
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $hitrange           = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}           : undef;
    my $rating             = exists $arg_ref->{rating}
        ? $arg_ref->{rating}             : undef;
    my $bookinfo           = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}           : undef;
    my $sorttype           = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}           : undef;
    my $sortorder          = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}          : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $titeltyp_ref       = exists $arg_ref->{titeltyp_ref}
        ? $arg_ref->{titeltyp_ref}       : undef;
    my $sessionID          = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}          : undef;
  
    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my @normset=();
  
    my %titeltyp = %$titeltyp_ref;
  
    my $titstatement1  = "select * from tit where idn = ?";
    my $titstatement2  = "select * from titgtunv where titidn = ?";
    my $titstatement3  = "select * from titisbn where titidn = ?";
    my $titstatement4  = "select * from titgtm where titidn = ?";
    my $titstatement5  = "select * from titgtf where titidn = ?";
    my $titstatement6  = "select * from titinverkn where titidn = ?";
    my $titstatement7  = "select * from titswtlok where titidn = ?";
    my $titstatement8  = "select * from titverf where titidn = ?";
    my $titstatement9  = "select * from titpers where titidn = ?";
    my $titstatement10 = "select * from titurh where titidn = ?";
    my $titstatement11 = "select * from titkor where titidn = ?";
    my $titstatement12 = "select * from titnot where titidn = ?";
    my $titstatement13 = "select * from titissn where titidn = ?";
    my $titstatement14 = "select * from titwst where titidn = ?";
    my $titstatement15 = "select * from titurl where titidn = ?";
    my $titstatement16 = "select * from titpsthts where titidn = ?";
    my $titstatement17 = "select * from titbeigwerk where titidn = ?";
    my $titstatement18 = "select * from titartinh where titidn = ?";
    my $titstatement19 = "select * from titsammelverm where titidn = ?";
    my $titstatement20 = "select * from titanghst where titidn = ?";
    my $titstatement21 = "select * from titpausg where titidn = ?";
    my $titstatement22 = "select * from tittitbeil where titidn = ?";
    my $titstatement23 = "select * from titbezwerk where titidn = ?";
    my $titstatement24 = "select * from titfruehausg where titidn = ?";
    my $titstatement25 = "select * from titfruehtit where titidn = ?";
    my $titstatement26 = "select * from titspaetausg  where titidn = ?";
    my $titstatement27 = "select * from titabstract  where titidn = ?";
    my $titstatement28 = "select * from titner where titidn = ?";
    my $titstatement29 = "select * from titillang where titidn = ?";
    my $titstatement30 = "select * from titdrucker where titidn = ?";
    my $titstatement31 = "select * from titerschland where titidn = ?";
    my $titstatement32 = "select * from titformat where titidn = ?";
    my $titstatement33 = "select * from titquelle where titidn = ?";
  
    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult1=$dbh->prepare("$titstatement1") or $logger->error($DBI::errstr);
    $titresult1->execute($titidn) or $logger->error($DBI::errstr);
  
    my $titres1=$titresult1->fetchrow_hashref;
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement1 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    # Setzen diverser Informationen
    push @normset, set_simple_category("Ident-Nr" ,"$titres1->{idn}");
    push @normset, set_simple_category("Ident-Alt","$titres1->{ida}") if ($titres1->{ida});
    #    push @normset, set_simple_category("Titeltyp","<i>$titeltyp{$titres1->{titeltyp}}</i>") if ($titres1->{titeltyp});
    push @normset, set_simple_category("Versnr"   ,"$titres1->{versnr}") if ($titres1->{versnr});
  
  
    # Ausgabe der Verfasser
    {
        my ($atime,$btime,$timeall);
        
        if ($config{benchmark}) {
            $atime=new Benchmark;
        }

        my $reqstring="select verfverw from titverf where titidn=?";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
        
        while (my $res=$request->fetchrow_hashref) {
            my $verfverw = $res->{verfverw};
            
            push @normset, set_url_category_global({
                desc      => "Verfasser",
                url       => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;verf=$verfverw;generalsearch=verf",
                contents  => get_aut_ans_by_idn("$verfverw",$dbh),
                type      => "verf",
                sorttype  => $sorttype,
                sessionID => $sessionID,
            });
        }
        $request->finish();

        if ($config{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }

    # Ausgabe der Personen
    {
        my ($atime,$btime,$timeall);
        
        if ($config{benchmark}) {
            $atime=new Benchmark;
        }

        my $reqstring="select persverw,bez from titpers where titidn=?";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
        while (my $res=$request->fetchrow_hashref) {
            my $persverw = $res->{persverw};
            my $bez      = $res->{bez};
      
            push @normset, set_url_category_global({
                desc       => "Person",
                url        => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;pers=$persverw;generalsearch=pers",
                contents   => get_aut_ans_by_idn("$persverw",$dbh),
                supplement => $bez,
                type       => "verf",
                sorttype   => $sorttype,
                sessionID  => $sessionID,
            });
        }
        $request->finish();

        if ($config{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }

    # Ausgabe der gefeierten Personen
    {
        my ($atime,$btime,$timeall);
        
        if ($config{benchmark}) {
            $atime=new Benchmark;
        }

        my $reqstring="select persverw from titgpers where titidn=?";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
        while (my $res=$request->fetchrow_hashref) {
            my $persverw = $res->{persverw};

            push @normset, set_url_category_global({
                desc      => "Gefeierte Person",
                url       => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;pers=$persverw;generalsearch=pers",
                contents  => get_aut_ans_by_idn("$persverw",$dbh),
                type      => "verf",
                sorttype  => $sorttype,
                sessionID => $sessionID,
            });
        }
        $request->finish();

        if ($config{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }
    
    # Ausgabe der Urheber
    {
        my ($atime,$btime,$timeall);
        
        if ($config{benchmark}) {
            $atime=new Benchmark;
        }
        
        my $reqstring="select urhverw from titurh where titidn=?";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
        while (my $res=$request->fetchrow_hashref) {
            my $urhverw = $res->{urhverw};

            push @normset, set_url_category_global({
                desc      => "Urheber",
                url       => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;urh=$urhverw;generalsearch=urh",
                contents  => get_kor_ans_by_idn("$urhverw",$dbh),
                type      => "kor",
                sorttype  => $sorttype,
                sessionID => $sessionID,
            });
        }
        $request->finish();
        
        if ($config{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }
    
    # Ausgabe der Koerperschaften
    {
        my ($atime,$btime,$timeall);
        
        if ($config{benchmark}) {
            $atime=new Benchmark;
        }
        
        my $reqstring="select korverw from titkor where titidn=?";
        my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
        $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
        while (my $res=$request->fetchrow_hashref) {
            my $korverw = $res->{korverw};

            push @normset, set_url_category_global({
                desc      => "K&ouml;rperschaft",
                url       => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;kor=$korverw;generalsearch=kor",
                contents  => get_kor_ans_by_idn("$korverw",$dbh),
                type      => "kor",
                sorttype  => $sorttype,
                sessionID => $sessionID,
            });
        }
        $request->finish();

        if ($config{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : $reqstring : ist ".timestr($timeall));
        }
    }
    
    # Ausgabe diverser Informationen
    push @normset, set_simple_category("AST"   ,"$titres1->{ast}") if ($titres1->{ast});    
    push @normset, set_simple_category("Est-He","$titres1->{esthe}") if ($titres1->{esthe});    
    push @normset, set_simple_category("Est-Fn","$titres1->{estfn}") if ($titres1->{estfn});
    push @normset, set_simple_category("HST"   ,"<strong>$titres1->{hst}</strong>") if ($titres1->{hst});
  
    # Ausgabe der Sammlungsvermerke
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult19=$dbh->prepare("$titstatement19") or $logger->error($DBI::errstr);
    $titresult19->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres19=$titresult19->fetchrow_hashref) {
        push @normset, set_simple_category("SammelVermerk","$titres19->{'sammelverm'}");
    }
    $titresult19->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement19 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der WST's
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult14=$dbh->prepare("$titstatement14") or $logger->error($DBI::errstr);
    $titresult14->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres14=$titresult14->fetchrow_hashref) {
        push @normset, set_simple_category("WST","$titres14->{'wst'}");
    }
    $titresult14->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement14 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der PSTHTS
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult16=$dbh->prepare("$titstatement16") or $logger->error($DBI::errstr);
    $titresult16->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres16=$titresult16->fetchrow_hashref) {
        push @normset, set_simple_category("PST Vorl.","$titres16->{'psthts'}");
    }
    $titresult16->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement16 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der Beigefuegten Werke
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult17=$dbh->prepare("$titstatement17") or $logger->error($DBI::errstr);
    $titresult17->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres17=$titresult17->fetchrow_hashref) {
        push @normset, set_simple_category("Beig.Werke","$titres17->{'beigwerk'}");
    }
    $titresult17->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement17 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der URL's
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult15=$dbh->prepare("$titstatement15") or $logger->error($DBI::errstr);
    $titresult15->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres15=$titresult15->fetchrow_hashref) {
        push @normset, set_simple_category("URL","<a href=\"$titres15->{'url'}\" target=_blank>$titres15->{'url'}</a>");
    }
    $titresult15->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement15 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    push @normset, set_simple_category("Zuerg. Urh"       ,"$titres1->{zuergurh}") if ($titres1->{zuergurh});
    push @normset, set_simple_category("Zusatz"           ,"$titres1->{zusatz}") if ($titres1->{zusatz});
    push @normset, set_simple_category("Vorl.beig.Werk"   ,"$titres1->{vorlbeigwerk}") if ($titres1->{vorlbeigwerk});
    push @normset, set_simple_category("Gemeins.Angaben"  ,"$titres1->{gemeinsang}") if ($titres1->{gemeinsang});
    push @normset, set_simple_category("Sachl.Ben."       ,"<strong>$titres1->{sachlben}</strong>") if ($titres1->{sachlben});
    push @normset, set_simple_category("Vorl.Verfasser"   ,"$titres1->{vorlverf}") if ($titres1->{vorlverf});
    push @normset, set_simple_category("Vorl.Unterreihe"  ,"$titres1->{vorlunter}") if ($titres1->{vorlunter});    
    push @normset, set_simple_category("Ausgabe"          ,"$titres1->{ausg}") if ($titres1->{ausg});    
    push @normset, set_simple_category("Verlagsort"       ,"$titres1->{verlagsort}") if ($titres1->{verlagsort});    
    push @normset, set_simple_category("Verlag"           ,"$titres1->{verlag}") if ($titres1->{verlag});    
    push @normset, set_simple_category("Weitere Orte"     ,"$titres1->{weitereort}") if ($titres1->{weitereort});    
    push @normset, set_simple_category("Aufnahmeort"      ,"$titres1->{aufnahmeort}") if ($titres1->{aufnahmeort});    
    push @normset, set_simple_category("Aufnahmejahr"     ,"$titres1->{aufnahmejahr}") if ($titres1->{aufnahmejahr});    
    push @normset, set_simple_category("Ersch. Jahr"      ,"$titres1->{erschjahr}") if ($titres1->{erschjahr});    
    push @normset, set_simple_category("Ans. Ersch. Jahr" ,"$titres1->{anserschjahr}") if ($titres1->{anserschjahr});    
    push @normset, set_simple_category("Ersch. Verlauf"   ,"$titres1->{erschverlauf}") if ($titres1->{erschverlauf});    
  
    push @normset, set_simple_category("Verfasser Quelle" ,"$titres1->{verfquelle}") if ($titres1->{verfquelle});    
    push @normset, set_simple_category("Ersch.Ort Quelle" ,"$titres1->{eortquelle}") if ($titres1->{eortquelle});    
    push @normset, set_simple_category("Ersch.Jahr Quelle","$titres1->{ejahrquelle}") if ($titres1->{ejahrquelle});    
  
    # Ausgabe der Illustrationsangaben
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult29=$dbh->prepare("$titstatement29") or $logger->error($DBI::errstr);
    $titresult29->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres29=$titresult29->fetchrow_hashref) {
        push @normset, set_simple_category("Ill.Angaben",$titres29->{'illang'});
    }
    $titresult29->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement29 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    # Ausgabe des Druckers
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult30=$dbh->prepare("$titstatement30") or $logger->error($DBI::errstr);
    $titresult30->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres30=$titresult30->fetchrow_hashref) {
        push @normset, set_simple_category("Drucker",$titres30->{'drucker'});
    }
    $titresult30->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement30 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    # Ausgabe des Erscheinungslandes
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult31=$dbh->prepare("$titstatement31") or $logger->error($DBI::errstr);
    $titresult31->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres31=$titresult31->fetchrow_hashref) {
        push @normset, set_simple_category("Ersch.Land",$titres31->{'erschland'});
    }
    $titresult31->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement31 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    # Ausgabe des Formats
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult32=$dbh->prepare("$titstatement32") or $logger->error($DBI::errstr);
    $titresult32->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres32=$titresult32->fetchrow_hashref) {
        push @normset, set_simple_category("Format",$titres32->{'format'});
    }
    $titresult32->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement32 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    # Ausgabe der Quelle
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult33=$dbh->prepare("$titstatement33") or $logger->error($DBI::errstr);
    $titresult33->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres33=$titresult33->fetchrow_hashref) {
        push @normset, set_simple_category("Quelle",$titres33->{'quelle'});
    }
    $titresult33->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement33 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    push @normset, set_simple_category("Kollation","$titres1->{kollation}") if ($titres1->{kollation});    
  
    # Ausgabe GTM
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult4=$dbh->prepare("$titstatement4") or $logger->error($DBI::errstr);
    $titresult4->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres4=$titresult4->fetchrow_hashref) {
        my $titstatement="select hst from tit where idn = ?";
        my $titresult=$dbh->prepare("$titstatement") or $logger->error($DBI::errstr);
        $titresult->execute($titres4->{verwidn}) or $logger->error($DBI::errstr);
        my $titres=$titresult->fetchrow_hashref;
    
        push @normset, set_url_category({
            desc       => "Gesamttitel",
            url        => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;singlegtm=$titres4->{verwidn};generalsearch=singlegtm",
            contents   => $titres->{hst},
            supplement => " ; $titres4->{zus}",
        });
    
    }
    $titresult4->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement4 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
  
    # Augabe GTF
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult5=$dbh->prepare("$titstatement5") or $logger->error($DBI::errstr);
    $titresult5->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres5=$titresult5->fetchrow_hashref) {
        my $titstatement="select hst,ast,vorlverf,zuergurh,vorlunter from tit where idn = ?";
        my $titresult=$dbh->prepare("$titstatement") or $logger->error($DBI::errstr);
        $titresult->execute($titres5->{verwidn}) or $logger->error($DBI::errstr);
        my $titres=$titresult->fetchrow_hashref;
    
        my $asthst   = $titres->{hst};
        my $verfurh  = $titres->{zuergurh};
    
        if ($titres->{vorlverf}) {
            $verfurh = $titres->{vorlverf};
        }
    
        if (!$asthst && $titres->{ast}) {
            $asthst  = $titres->{ast};
        }
    
        my $vorlunter=$titres->{vorlunter};
    
        if ($vorlunter) {
            $asthst="$asthst : $vorlunter";
        }
    
    
        if ($verfurh) {
            $asthst=$asthst." / ".$verfurh;
        }
    
        push @normset, set_url_category({
            desc       => "Gesamttitel",
            url        => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;singlegtf=$titres5->{verwidn};generalsearch=singlegtf",
            contents   => $asthst,
            supplement => " ; $titres5->{zus}",
        });
    }
    $titresult5->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement5 ++ : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe IN Verkn.
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult6=$dbh->prepare("$titstatement6") or $logger->error($DBI::errstr);
    $titresult6->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres6=$titresult6->fetchrow_hashref) {
        my $titverw=$titres6->{titverw};
    
        my $titstatement="select hst,sachlben from tit where idn = ?";
        my $titresult=$dbh->prepare("$titstatement") or $logger->error($DBI::errstr);
        $titresult->execute($titverw) or $logger->error($DBI::errstr);
        my $titres=$titresult->fetchrow_hashref;
    
        # Wenn HST vorhanden, dann nimm ihn, sonst Sachlben.
        my $verkn=($titres->{hst})?$titres->{hst}:$titres->{sachlben};
    
        # Wenn weder HST, noch Sachlben vorhanden, dann haben wir
        # einen Titeltyp4 ohne irgendeine weitere Information und wir m"ussen
        # uns f"ur HST/Sachlben-Informationen eine Suchebene tiefer 
        # hangeln :-(
        if (!$verkn) {
            my $gtmidnresult1=$dbh->prepare("select verwidn from titgtm where titidn = ?") or $logger->error($DBI::errstr);
            $gtmidnresult1->execute($titverw) or $logger->error($DBI::errstr);
            my $gtmidnres1=$gtmidnresult1->fetchrow_hashref;
            my $gtmidn=$gtmidnres1->{verwidn};
            $gtmidnresult1->finish();
      
            if ($gtmidn) {
                my $gtmidnresult2=$dbh->prepare("select hst,sachlben from tit where idn = ?") or $logger->error($DBI::errstr);
                $gtmidnresult2->execute($gtmidn) or $logger->error($DBI::errstr);
                my $gtmidnres2=$gtmidnresult2->fetchrow_hashref;
                $verkn=($gtmidnres2->{hst})?$gtmidnres2->{hst}:$gtmidnres2->{sachlben};
                $gtmidnresult2->finish();
            }
        }
    
        if (!$verkn) {
            my $gtfidnresult1=$dbh->prepare("select verwidn, zus from titgtf where titidn = ?") or $logger->error($DBI::errstr);
            $gtfidnresult1->execute($titverw) or $logger->error($DBI::errstr);
            my $gtfidnres1=$gtfidnresult1->fetchrow_hashref;
            my $gtfidn=$gtfidnres1->{verwidn};
            my $gtfzus=$gtfidnres1->{zus};
            $gtfidnresult1->finish();
      
            if ($gtfidn) {
                my $gtfidnresult2=$dbh->prepare("select hst,sachlben from tit where idn = ?") or $logger->error($DBI::errstr);
                $gtfidnresult2->execute($gtfidn) or $logger->error($DBI::errstr);
                my $gtfidnres2=$gtfidnresult2->fetchrow_hashref;
                $verkn=($gtfidnres2->{hst})?$gtfidnres2->{hst}:$gtfidnres2->{sachlben};
                $gtfidnresult2->finish();
            }
            if ($gtfzus) {
                $verkn="$verkn ; $gtfzus";
            }
        }
    
        # Der Zusatz wird doppelt ausgegeben. In der Verknuepfung und
        # auch im Zusatz. Es wird nun ueberprueft, ob doppelte Information
        # bis/vom Semikolon vorhanden ist und gegebenenfalls geloescht.
        my ($check1)=$titres6->{zus}=~/^(.+?) \;/;
        my ($check2)=$verkn=~/^.+\;(.+)$/;
    
        my $zusatz=$titres6->{zus};
    
        # Doppelte Information ist vorhanden, dann ...
        if ($check1 eq $check2) {
            $zusatz=~s/^.+? \; (.+?)$/$1/;
        }
    
        push @normset, set_url_category({
            desc       => "In:",
            url        => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;singlegtf=$titverw;generalsearch=singlegtf",
            contents   => $verkn,
            supplement => " ; $zusatz ",
        });
    }
  
    $titresult6->finish();	
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement6 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe GT unverkn.
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult2=$dbh->prepare("$titstatement2") or $logger->error($DBI::errstr);
    $titresult2->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres2=$titresult2->fetchrow_hashref) {
        push @normset, set_simple_category("GT unverkn","$titres2->{gtunv}");
    }
    $titresult2->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement2 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe diverser Informationen
    push @normset, set_simple_category("IN unverkn"     ,"$titres1->{inunverkn}") if ($titres1->{inunverkn});    
    push @normset, set_simple_category("Mat.Benennung"  ,"$titres1->{matbenennung}") if ($titres1->{matbenennung});    
    push @normset, set_simple_category("Sonst.Mat.ben"  ,"$titres1->{sonstmatben}") if ($titres1->{sonstmatben});    
    push @normset, set_simple_category("Sonst.Angaben"  ,"$titres1->{sonstang}") if ($titres1->{sonstang});    
    push @normset, set_simple_category("Begleitmaterial","$titres1->{begleitmat}") if ($titres1->{begleitmat});    
    push @normset, set_simple_category("Fu&szlig;note"  ,"$titres1->{fussnote}") if ($titres1->{fussnote});    
  
    # Ausgabe der AngabenHST
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult20=$dbh->prepare("$titstatement20") or $logger->error($DBI::errstr);
    $titresult20->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres20=$titresult20->fetchrow_hashref) {
        push @normset, set_simple_category("AngabenHST","$titres20->{'anghst'}");
    }
    $titresult20->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement20 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der ParallelAusgabe
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult21=$dbh->prepare("$titstatement21") or $logger->error($DBI::errstr);
    $titresult21->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres21=$titresult21->fetchrow_hashref) {
        push @normset, set_simple_category("Parallele Ausg.","$titres21->{'pausg'}");
    }
    $titresult21->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement21 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der TitBeilage
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult22=$dbh->prepare("$titstatement22") or $logger->error($DBI::errstr);
    $titresult22->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres22=$titresult22->fetchrow_hashref) {
        push @normset, set_simple_category("Titel Beilage","$titres22->{'titbeil'}");
    }
    $titresult22->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement22 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der Bezugswerk
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult23=$dbh->prepare("$titstatement23") or $logger->error($DBI::errstr);
    $titresult23->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres23=$titresult23->fetchrow_hashref) {
        push @normset, set_simple_category("Bezugswerk","$titres23->{'bezwerk'}");
    }
    $titresult23->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement23 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der FruehAusg
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult24=$dbh->prepare("$titstatement24") or $logger->error($DBI::errstr);
    $titresult24->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres24=$titresult24->fetchrow_hashref) {
        push @normset, set_simple_category("Fr&uuml;here Ausg.","$titres24->{'fruehausg'}");
    }
    $titresult24->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement24 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe des FruehTit
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult25=$dbh->prepare("$titstatement25") or $logger->error($DBI::errstr);
    $titresult25->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres25=$titresult25->fetchrow_hashref) {
        push @normset, set_simple_category("Fr&uuml;herer Titel","$titres25->{'fruehtit'}");
    }
    $titresult25->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement25 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der SpaetAusg
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult26=$dbh->prepare("$titstatement26") or $logger->error($DBI::errstr);
    $titresult26->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres26=$titresult26->fetchrow_hashref) {
        push @normset, set_simple_category("Sp&auml;tere Ausg.","$titres26->{'spaetausg'}");
    }
    $titresult26->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement26 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    push @normset, set_simple_category("Bind-Preis","$titres1->{bindpreis}") if ($titres1->{bindpreis});    
    push @normset, set_simple_category("Hsfn"      ,"$titres1->{hsfn}") if ($titres1->{hsfn});    
    push @normset, set_simple_category("Sprache"   ,"$titres1->{sprache}") if ($titres1->{sprache});    
  
  
    # Ausgabe der Abstracts
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult27=$dbh->prepare("$titstatement27") or $logger->error($DBI::errstr);
    $titresult27->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres27=$titresult27->fetchrow_hashref) {
        push @normset, set_simple_category("Abstract","$titres27->{'abstract'}");
    }
    $titresult27->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement27 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    push @normset, set_simple_category("Mass."          ,"$titres1->{mass}") if ($titres1->{mass});
    push @normset, set_simple_category("&Uuml;bers. HST","$titres1->{uebershst}") if ($titres1->{uebershst});

    #    push @normset, set_simple_category("Bemerkung","$titres1->{rem}") if ($titres1->{rem});
    #    push @normset, set_simple_category("Bemerkung","$titres1->{bemerk}") if ($titres1->{bemerk});
  
    # Ausgabe der NER
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult28=$dbh->prepare("$titstatement28") or $logger->error($DBI::errstr);
    $titresult28->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres28=$titresult28->fetchrow_hashref) {
        push @normset, set_simple_category("Nebeneintr.","$titres28->{'ner'}");
    }
    $titresult28->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement28 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der Medienart/Art-Inhalt
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult18=$dbh->prepare("$titstatement18") or $logger->error($DBI::errstr);
    $titresult18->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres18=$titresult18->fetchrow_hashref) {
        push @normset, set_simple_category("Medienart","$titres18->{'artinhalt'}");
    }
    $titresult18->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement18 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der Schlagworte
    my @requests=("select swtverw from titswtlok where titidn=$titidn");
    my @titres7=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
    foreach my $titidn7 (@titres7) {
        push @normset, set_url_category_global({
            desc      => "Schlagwort",
            url       => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;swt=$titidn7;generalsearch=swt",
            contents  => get_swt_ans_by_idn("$titidn7",$dbh),
            type      => "swt",
            sorttype  => $sorttype,
            sessionID => $sessionID,
        });
    }
  
    # Augabe der Notationen
    @requests=("select notidn from titnot where titidn=$titidn");
    my @titres12=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
    foreach my $titidn12 (@titres12) {
        push @normset, set_url_category({
            desc     => "Notation",
            url      => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;notation=$titidn12;generalsearch=not",
            contents => get_not_ans_by_idn("$titidn12",$dbh),
        });
    }
  
    # Ausgabe der ISBN's
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult3=$dbh->prepare("$titstatement3") or $logger->error($DBI::errstr);
    $titresult3->execute($titidn) or $logger->error($DBI::errstr);
  
    my $isbn;
    while (my $titres3=$titresult3->fetchrow_hashref) {
        push @normset, set_simple_category("ISBN","$titres3->{isbn}");
        $isbn=$titres3->{isbn};
    }
    $titresult3->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement3 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der ISSN's
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $titresult13=$dbh->prepare("$titstatement13") or $logger->error($DBI::errstr);
    $titresult13->execute($titidn) or $logger->error($DBI::errstr);
  
    while (my $titres13=$titresult13->fetchrow_hashref) {
        push @normset, set_simple_category("ISSN","$titres13->{issn}");
    }
    $titresult13->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $titstatement13 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    # Ausgabe der Anzahl verkn"upfter GTM
    @requests=("select titidn from titgtm where verwidn=$titres1->{idn}");
    my $verkntit=get_number(\@requests,$dbh);
    if ($verkntit > 0) {
        push @normset, set_url_category({
            desc     => "B&auml;nde",
            url      => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;gtmtit=$titres1->{idn};generalsearch=gtmtit",
            contents => $verkntit,
        });
    }
  
    # Ausgabe der Anzahl verkn"upfter GTF
    @requests=("select titidn from titgtf where verwidn=$titres1->{idn}");
    $verkntit=get_number(\@requests,$dbh);
    if ($verkntit > 0) {
        push @normset, set_url_category({
            desc     => "St&uuml;cktitel",
            url      => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;gtftit=$titres1->{idn};generalsearch=gtftit",
            contents => $verkntit,
        });
    }
  
    # Ausgabe der Anzahl verkn"upfter IN verkn.
    @requests=("select titidn from titinverkn where titverw=$titres1->{idn}");
    $verkntit=get_number(\@requests,$dbh);
    if ($verkntit > 0) {
        push @normset, set_url_category({
            desc     => "Teile",
            url      => "$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;invktit=$titres1->{idn};generalsearch=invktit",
            contents => $verkntit,
        });
    }
  
    @requests=("select idn from mex where titidn=$titres1->{idn}");
    my @verknmex=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

    my @mexnormset=();

    if ($#verknmex >= 0) {
        foreach my $mexsatz (@verknmex) {
            get_mex_set_by_idn({
                mexidn             => $mexsatz,
                dbh                => $dbh,
                searchmode         => $searchmode,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                hitrange           => $hitrange,
                rating             => $rating,
                bookinfo           => $bookinfo,
                sorttype           => $sorttype,
                sortorder          => $sortorder,
                database           => $database,
                sessionID          => $sessionID,
                mexnormset_ref     => \@mexnormset,
            });
        }
    }

    # Gegebenenfalls bestimmung der Ausleihinfo fuer Exemplare
    my $circexlist=undef;

    if (exists $targetcircinfo_ref->{$database}{circ}) {

        my $soap = SOAP::Lite
            -> uri("urn:/MediaStatus")
                -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
        my $result = $soap->get_mediastatus(
            $titres1->{idn},$targetcircinfo_ref->{$database}{circdb});
      
        unless ($result->fault) {
            $circexlist=$result->result;
        }
        else {
            $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
        }
    }

    # Bei einer Ausleihbibliothek haben - falls Exemplarinformationen
    # in den Ausleihdaten vorhanden sind -- diese Vorrange ueber die
    # titelbasierten Exemplardaten
    my @circexemplarliste = ();

    if (defined($circexlist)) {
        @circexemplarliste = @{$circexlist};
    }

    if (exists $targetcircinfo_ref->{$database}{circ}
            && $#circexemplarliste >= 0) {
        for (my $i=0; $i <= $#circexemplarliste; $i++) {
            $circexemplarliste[$i]{'Standort' }=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            $circexemplarliste[$i]{'Signatur' }=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            $circexemplarliste[$i]{'Status'   }=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            $circexemplarliste[$i]{'Rueckgabe'}=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            $circexemplarliste[$i]{'Exemplar' }=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
	
            # Zusammensetzung von Signatur und Exemplar

            $circexemplarliste[$i]{'Signatur'}=$circexemplarliste[$i]{'Signatur'}.$circexemplarliste[$i]{'Exemplar'};

            # Ein im Exemplar-Datensatz gefundenes Sigel geht vor

            my $bibliothek="";

            my $sigel=$targetdbinfo_ref->{dbases}{$database};

            if (length($sigel)>0) {
                if (exists $targetdbinfo_ref->{sigel}{$sigel}) {
                    $bibliothek=$targetdbinfo_ref->{sigel}{$sigel};
                }
                else {
                    $bibliothek="Unbekannt (38/$sigel)";
                }
            }
            else {
                if (exists $targetdbinfo_ref->{sigel}{$targetdbinfo_ref->{dbases}{$database}}) {
                    $bibliothek=$targetdbinfo_ref->{sigel}{
                        $targetdbinfo_ref->{dbases}{$database}};
                }
                else {
                    $bibliothek="Unbekannt (38/$sigel)";
                }
            }
            $circexemplarliste[$i]{'Bibliothek'}=$bibliothek;

            my $bibinfourl=$targetdbinfo_ref->{bibinfo}{
                $targetdbinfo_ref->{dbases}{$database}};

            $circexemplarliste[$i]{'Bibinfourl'}=$bibinfourl;

            my $ausleihstatus=$circexemplarliste[$i]{'Ausleihstatus'};

            my $ausleihstring;
            if ($circexemplarliste[$i]{'Ausleihstatus'} eq "bestellbar") {
                $ausleihstring="ausleihen?";
            }
            elsif ($circexemplarliste[$i]{'Ausleihstatus'} eq "bestellt") {
                $ausleihstring="vormerken?";
            }
            elsif ($circexemplarliste[$i]{'Ausleihstatus'} eq "entliehen") {
                $ausleihstring="vormerken/verl&auml;ngern?";
            }
            elsif ($circexemplarliste[$i]{'Ausleihstatus'} eq "bestellbar") {
                $ausleihstring="ausleihen?";
            }
            else {
                $ausleihstring="WebOPAC?";
            }

            $circexemplarliste[$i]{'Ausleihstring'}=$ausleihstring;

            if ($circexemplarliste[$i]{'Standort'}=~/Erziehungswiss/ || $circexemplarliste[$i]{'Standort'}=~/Heilp.*?dagogik-Magazin/) {
                $circexemplarliste[$i]{'Ausleihurl'}=$targetcircinfo_ref->{$database}{circurl}."&branch=4&KatKeySearch=$titidn";
            }
            else {
                if ($database eq "inst001" || $database eq "poetica") {
                    $circexemplarliste[$i]{'Ausleihurl'}=$targetcircinfo_ref->{$database}{circurl}."&branch=0&KatKeySearch=$titidn";
                }
                else {
                    $circexemplarliste[$i]{'Ausleihurl'}=$targetcircinfo_ref->{$database}{circurl}."&KatKeySearch=$titidn";
                }
            }
        }
    }
    else {
        @circexemplarliste=();
    }

    $titresult1->finish();

    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
    # dieses angewendet werden
    if (exists $config{categorymapping}{$database}) {
        for (my $i=0; $i<=$#normset; $i++) {
            my $normdesc=$normset[$i]{desc};

            # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
            if (exists $config{categorymapping}{$database}{$normdesc}) {
                $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
            }
        }
    }
    return (\@normset,\@mexnormset,\@circexemplarliste);
}

#####################################################################
## get_mex_set_by_idn(mexidn,mode): Bestimme zu mexidn geh"oerenden
##                                  Exemplardatenstammsatz
##
## mexidn: IDN des Exemplardatenstammsatzes
##         Anzeige als tabellarische Auflistung
##
## Und nun jede Menge Variablen, damit mod_perl keine Probleme macht
##
## $dbh
## $searchmode
## $showmexintit
## $hitrange
## $sorttype
## $database
## $rsigel - Referenz auf %sigel
## $rdbases
## $rbibinfo

sub get_mex_set_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $mexidn             = exists $arg_ref->{mexidn}
        ? $arg_ref->{mexidn}             : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $searchmode         = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}         : undef;
    my $targetdbinfo_ref   = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}   : undef;
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $hitrange           = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}           : undef;
    my $rating             = exists $arg_ref->{rating}
        ? $arg_ref->{rating}             : undef;
    my $bookinfo           = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}           : undef;
    my $sorttype           = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}           : undef;
    my $sortorder          = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}          : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $sessionID          = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}          : undef;
    my $mexnormset_ref     = exists $arg_ref->{mexnormset_ref}
        ? $arg_ref->{mexnormset_ref}     : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my $mexstatement1="select * from mex where idn = ?";
    my $mexstatement2="select * from mexsign where mexidn = ?";

    my ($atime,$btime,$timeall);
  
    my @requests=("select titidn from mex where idn = $mexidn");
    my @verkntit=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }
  
    my $mexresult1=$dbh->prepare("$mexstatement1") or $logger->error($DBI::errstr);
    $mexresult1->execute($mexidn) or $logger->error($DBI::errstr);
    my $mexres1=$mexresult1->fetchrow_hashref;
  
    my $sigel          = $mexres1->{'sigel'};
    my $standort       = $mexres1->{'standort'}  || " - ";
    my $inventarnummer = $mexres1->{'invnr'}     || " - ";
    my $erschverl      = $mexres1->{'erschverl'} || " - ";
    my $buchung        = $mexres1->{'buchung'}   || " - ";
    my $fallig         = $mexres1->{'fallig'}    || " - ";
    my $ida            = $mexres1->{'ida'};
    my $verbnr         = $mexres1->{'verbnr'};
    my $lokfn          = $mexres1->{'lokfn'};
    my $titidn1        = $mexres1->{'titidn'};
  
    $mexresult1->finish();
  
    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $mexstatement1 : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    my $bibliothek="";
  
    # Ein im Exemplar-Datensatz gefundenes Sigel geht vor
    if (length($sigel)>0) {
    
        if (exists $targetdbinfo_ref->{sigel}{$sigel}) {
            $bibliothek=$targetdbinfo_ref->{sigel}{$sigel};
        }
        else {
            $bibliothek="Unbekannt (38/$sigel)";
        }
    }
    else {
        if (exists $targetdbinfo_ref->{sigel}{$targetdbinfo_ref->{dbases}{$database}}) {
            $bibliothek=$targetdbinfo_ref->{sigel}{$targetdbinfo_ref->{dbases}{$database}};
        }
        else {
            $bibliothek="Unbekannt (38/$sigel)";
        }
    }
  
    my $bibinfourl="";
  
    if (exists $targetdbinfo_ref->{bibinfo}{$sigel}) {
        $bibinfourl=$targetdbinfo_ref->{bibinfo}{$sigel};
    }
    else {
        $bibinfourl="http://www.ub.uni-koeln.de/dezkat/bibfuehrer.html";
    }
  
    my $mexresult2=$dbh->prepare("$mexstatement2") or $logger->error($DBI::errstr);
    $mexresult2->execute($mexidn) or $logger->error($DBI::errstr);
  
    # Keine Signatur am Exemplarsatz
    if ($mexresult2->rows == 0) {
        my %mex=();
        $mex{bibinfourl}     = $bibinfourl;
        $mex{bibliothek}     = $bibliothek;
        $mex{standort}       = $standort;
        $mex{inventarnummer} = $inventarnummer;
        $mex{signatur}       = "-";
        $mex{erschverl}      = $erschverl;
        push @$mexnormset_ref,\%mex;
    }
    # Mindestens eine Signatur:
    # Es werden einzelne Zeilen fuer jede Signatur erzeugt
    else {
        while (my @mexres2=$mexresult2->fetchrow) {
            my $signatur=$mexres2[1];
      
            my %mex=();
            $mex{bibinfourl}     = $bibinfourl;
            $mex{bibliothek}     = $bibliothek;
            $mex{standort}       = $standort;
            $mex{inventarnummer} = $inventarnummer;
            $mex{signatur}       = $signatur;
            $mex{erschverl}      = $erschverl;
            push @$mexnormset_ref,\%mex;
        }
    }
    $mexresult2->finish();

    return;
}

#####################################################################
## get_number(rreqarray): Suche anhand der in reqarray enthaltenen
##                       SQL-Statements, fasse die Ergebnisse zusammen
##                       und liefere deren Anzahl zur"uck
##

sub get_number {
    my ($rreqarray,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my %metaidns;
    my @idns;

    my ($atime,$btime,$timeall);
    
    my @reqarray=@$rreqarray;

    foreach my $numberrequest (@reqarray) {
	if ($config{benchmark}) {
	    $atime=new Benchmark;
	}

	my $numberresult=$dbh->prepare("$numberrequest") or $logger->error($DBI::errstr);
	$numberresult->execute() or $logger->error("Request: $numberrequest - ".$DBI::errstr);

	while (my @numberres=$numberresult->fetchrow) {
	    $metaidns{$numberres[0]}=1;
	}
	$numberresult->execute();
	$numberresult->finish();
	if ($config{benchmark}) {
	    $btime   = new Benchmark;
	    $timeall = timediff($btime,$atime);
	    $logger->info("Zeit fuer Nummer zu : $numberrequest : ist ".timestr($timeall));
	}
	
    }
    my $i=0;
    while (my ($key,$value)=each %metaidns) {
	$idns[$i++]=$key;
    }
    
    return $#idns+1;
}

#####################################################################
## input2sgml(line,initialsearch): Wandle die Eingabe line
##                   nach SGML um.Wwenn die
##                   Anfangs-Suche via SQL-Datenbank stattfindet
##                   Keine Umwandlung bei Anfangs-Suche

sub input2sgml {
    my ($line,$initialsearch)=@_;

    # Bei der initialen Suche via Volltext wird eine Normierung auf
    # ausgeschriebene Umlaute und den Grundbuchstaben bei Diakritika
    # vorgenommen
    if ($initialsearch) {
        $line=~s/ü/ue/g;
        $line=~s/ä/ae/g;
        $line=~s/ö/oe/g;
        $line=~s/Ü/Ue/g;
        $line=~s/Ä/Ae/g;
        $line=~s/Ö/Oe/g;
        $line=~s/ß/ss/g;
    
        # Weitere Diakritika
        $line=~s/è/e/g;
        $line=~s/à/a/g;
        $line=~s/ò/o/g;
        $line=~s/ù/u/g;
        $line=~s/È/e/g;
        $line=~s/À/a/g;
        $line=~s/Ò/o/g;
        $line=~s/Ù/u/g;
        $line=~s/é/e/g;
        $line=~s/É/E/g;
        $line=~s/á/a/g;
        $line=~s/Á/a/g;
        $line=~s/í/i/g;
        $line=~s/Í/I/g;
        $line=~s/ó/o/g;
        $line=~s/Ó/O/g;
        $line=~s/ú/u/g;
        $line=~s/Ú/U/g;
        $line=~s/ý/y/g;
        $line=~s/Ý/Y/g;
    
        if ($line=~/\"/) {
            $line=~s/`/ /g;
        }
        else {
            $line=~s/`/ +/g;
        }
        return $line;
    }
  
    $line=~s/ü/\&uuml\;/g;	
    $line=~s/ä/\&auml\;/g;
    $line=~s/ö/\&ouml\;/g;
    $line=~s/Ü/\&Uuml\;/g;
    $line=~s/Ä/\&Auml\;/g;
    $line=~s/Ö/\&Ouml\;/g;
    $line=~s/ß/\&szlig\;/g;
  
    $line=~s/É/\&Eacute\;/g;	
    $line=~s/È/\&Egrave\;/g;	
    $line=~s/Ê/\&Ecirc\;/g;	
    $line=~s/Á/\&Aacute\;/g;	
    $line=~s/À/\&Agrave\;/g;	
    $line=~s/Â/\&Acirc\;/g;	
    $line=~s/Ó/\&Oacute\;/g;	
    $line=~s/Ò/\&Ograve\;/g;	
    $line=~s/Ô/\&Ocirc\;/g;	
    $line=~s/Ú/\&Uacute\;/g;	
    $line=~s/Ù/\&Ugrave\;/g;	
    $line=~s/Û/\&Ucirc\;/g;	
    $line=~s/Í/\&Iacute\;/g;
    $line=~s/Ì/\&Igrave\;/g;	
    $line=~s/Î/\&Icirc\;/g;	
    $line=~s/Ñ/\&Ntilde\;/g;	
    $line=~s/Õ/\&Otilde\;/g;	
    $line=~s/Ã/\&Atilde\;/g;	
  
    $line=~s/é/\&eacute\;/g;	
    $line=~s/è/\&egrave\;/g;	
    $line=~s/ê/\&ecirc\;/g;	
    $line=~s/á/\&aacute\;/g;	
    $line=~s/à/\&agrave\;/g;	
    $line=~s/â/\&acirc\;/g;	
    $line=~s/ó/\&oacute\;/g;	
    $line=~s/ò/\&ograve\;/g;	
    $line=~s/ô/\&ocirc\;/g;	
    $line=~s/ú/\&uacute\;/g;	
    $line=~s/ù/\&ugrave\;/g;	
    $line=~s/û/\&ucirc\;/g;	
    $line=~s/í/\&iacute\;/g;
    $line=~s/ì/\&igrave\;/g;	
    $line=~s/î/\&icirc\;/g;	
    $line=~s/ñ/\&ntilde\;/g;	
    $line=~s/õ/\&otilde\;/g;	
    $line=~s/ã/\&atilde\;/g;	
  
    $line=~s/\"u/\&uuml\;/g;
    $line=~s/\"a/\&auml\;/g;
    $line=~s/\"o/\&ouml\;/g;
    $line=~s/\"U/\&Uuml\;/g;
    $line=~s/\"A/\&Auml\;/g;
    $line=~s/\"O/\&Ouml\;/g;
    $line=~s/\"s/\&szlig\;/g;
    $line=~s/\'/\\'/g;
    $line=~s/\*/\%/g;
    return $line;
}

sub get_global_contents {
    my ($globalcontents)=@_;

    $globalcontents=~s/<\/a>//;
    $globalcontents=~s/¬//g;
    $globalcontents=~s/\"//g;

    $globalcontents=~s/&lt;//g;
    $globalcontents=~s/&gt;//g;
    $globalcontents=~s/<//g;
    $globalcontents=~s/>//g;

    # Caron
    $globalcontents=~s/\&#353\;/s/g;  # s hacek
    $globalcontents=~s/\&#352\;/S/g;  # S hacek
    $globalcontents=~s/\&#269\;/c/g;  # c hacek
    $globalcontents=~s/\&#268\;/C/g;  # C hacek
    $globalcontents=~s/\&#271\;/d/g;  # d hacek
    $globalcontents=~s/\&#270\;/D/g;  # D hacek
    $globalcontents=~s/\&#283\;/e/g;  # e hacek
    $globalcontents=~s/\&#282\;/E/g;  # E hacek
    $globalcontents=~s/\&#318\;/l/g;  # l hacek
    $globalcontents=~s/\&#317\;/L/g;  # L hacek
    $globalcontents=~s/\&#328\;/n/g;  # n hacek
    $globalcontents=~s/\&#327\;/N/g;  # N hacek
    $globalcontents=~s/\&#345\;/r/g;  # r hacek
    $globalcontents=~s/\&#344\;/R/g;  # R hacek
    $globalcontents=~s/\&#357\;/t/g;  # t hacek
    $globalcontents=~s/\&#356\;/T/g;  # T hacek
    $globalcontents=~s/\&#382\;/n/g;  # n hacek
    $globalcontents=~s/\&#381\;/N/g;  # N hacek
  
    # Macron
    $globalcontents=~s/\&#275\;/e/g;  # e oberstrich
    $globalcontents=~s/\&#274\;/E/g;  # e oberstrich
    $globalcontents=~s/\&#257\;/a/g;  # a oberstrich
    $globalcontents=~s/\&#256\;/A/g;  # A oberstrich
    $globalcontents=~s/\&#299\;/i/g;  # i oberstrich
    $globalcontents=~s/\&#298\;/I/g;  # I oberstrich
    $globalcontents=~s/\&#333\;/o/g;  # o oberstrich
    $globalcontents=~s/\&#332\;/O/g;  # O oberstrich
    $globalcontents=~s/\&#363\;/u/g;  # u oberstrich
    $globalcontents=~s/\&#362\;/U/g;  # U oberstrich
  
    #$globalcontents=~s/ /\+/g;
    $globalcontents=~s/,/%2C/g;
    $globalcontents=~s/\[.+?\]//;
    $globalcontents=~s/ $//g;
    #$globalcontents=~s/ /\+/g;
    $globalcontents=~s/ /%20/g;

    return $globalcontents;
}

sub set_simple_category {
    my ($desc,$contents)=@_;

    # UTF8-Behandlung
    $desc     =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $contents =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;

    # Sonderbehandlung fuer bestimmte Kategorien
    if ($desc eq "ISSN") {
        my $ezbquerystring=$config{ezb_exturl}."&jq_term1=".$contents;

        $contents="$contents (<a href=\"$ezbquerystring\" title=\"Verfügbarkeit in der Elektronischen Zeitschriften Bibliothek (EZB) &uuml;berpr&uuml;fen\" target=ezb>als E-Journal der Uni-K&ouml;ln verf&uuml;gbar?</a>)";
    }

    my %kat=();
    $kat{'type'}     = "simple_category";
    $kat{'desc'}     = $desc;
    $kat{'contents'} = $contents;
  
    return \%kat;
}

sub set_url_category {
    my ($arg_ref) = @_;

    # Set defaults
    my $desc            = exists $arg_ref->{desc}
        ? $arg_ref->{desc}            : undef;
    my $url             = exists $arg_ref->{url}
        ? $arg_ref->{url}             : undef;
    my $contents        = exists $arg_ref->{contents}
        ? $arg_ref->{contents}        : undef;
    my $supplement      = exists $arg_ref->{supplement}
        ? $arg_ref->{supplement}      : undef;

    # UTF8-Behandlung
    $desc       =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $url        =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $contents   =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $supplement =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;

    my %kat=();
    $kat{'type'}       = "url_category";
    $kat{'desc'}       = $desc;
    $kat{'url'}        = $url;
    $kat{'contents'}   = $contents;
    $kat{'supplement'} = $supplement;

    return \%kat;
}

sub set_url_category_global {
    my ($arg_ref) = @_;

    # Set defaults
    my $desc            = exists $arg_ref->{desc}
        ? $arg_ref->{desc}            : undef;
    my $url             = exists $arg_ref->{url}
        ? $arg_ref->{url}             : undef;
    my $contents        = exists $arg_ref->{contents}
        ? $arg_ref->{contents}        : undef;
    my $supplement      = exists $arg_ref->{supplement}
        ? $arg_ref->{supplement}      : '';
    my $type            = exists $arg_ref->{type}
        ? $arg_ref->{type}            : undef;
    my $sorttype        = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}        : undef;
    my $sessionID       = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}       : undef;

    # UTF8-Behandlung

    $desc       =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $url        =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $contents   =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
    $supplement =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;

    my $globalcontents=$contents;

    $globalcontents=~s/<\/a>//;
    $globalcontents=~s/¬//g;
    $globalcontents=~s/\"//g;
    $globalcontents=~s/&lt;//g;
    $globalcontents=~s/&gt;//g;
    $globalcontents=~s/<//g;
    $globalcontents=~s/>//g;

    # Sonderzeichen

    # Caron
    $globalcontents=~s/\&#353\;/s/g;  # s hacek
    $globalcontents=~s/\&#352\;/S/g;  # S hacek
    $globalcontents=~s/\&#269\;/c/g;  # c hacek
    $globalcontents=~s/\&#268\;/C/g;  # C hacek
    $globalcontents=~s/\&#271\;/d/g;  # d hacek
    $globalcontents=~s/\&#270\;/D/g;  # D hacek
    $globalcontents=~s/\&#283\;/e/g;  # e hacek
    $globalcontents=~s/\&#282\;/E/g;  # E hacek
    $globalcontents=~s/\&#318\;/l/g;  # l hacek
    $globalcontents=~s/\&#317\;/L/g;  # L hacek
    $globalcontents=~s/\&#328\;/n/g;  # n hacek
    $globalcontents=~s/\&#327\;/N/g;  # N hacek
    $globalcontents=~s/\&#345\;/r/g;  # r hacek
    $globalcontents=~s/\&#344\;/R/g;  # R hacek
    $globalcontents=~s/\&#357\;/t/g;  # t hacek
    $globalcontents=~s/\&#356\;/T/g;  # T hacek
    $globalcontents=~s/\&#382\;/n/g;  # n hacek
    $globalcontents=~s/\&#381\;/N/g;  # N hacek
  
    # Macron
    $globalcontents=~s/\&#275\;/e/g;  # e oberstrich
    $globalcontents=~s/\&#274\;/E/g;  # e oberstrich
    $globalcontents=~s/\&#257\;/a/g;  # a oberstrich
    $globalcontents=~s/\&#256\;/A/g;  # A oberstrich
    $globalcontents=~s/\&#299\;/i/g;  # i oberstrich
    $globalcontents=~s/\&#298\;/I/g;  # I oberstrich
    $globalcontents=~s/\&#333\;/o/g;  # o oberstrich
    $globalcontents=~s/\&#332\;/O/g;  # O oberstrich
    $globalcontents=~s/\&#363\;/u/g;  # u oberstrich
    $globalcontents=~s/\&#362\;/U/g;  # U oberstrich
  
    #$globalcontents=~s/ /\+/g;
    $globalcontents=~s/,/%2C/g;
    $globalcontents=~s/\[.+?\]//;
    $globalcontents=~s/ $//g;
    #$globalcontents=~s/ /\+/g;
    $globalcontents=~s/ /%20/g;

    my $globalurl="";

    if ($type eq "swt") {
        $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=;hst=;swt=%22$globalcontents%22;kor=;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In+allen+Katalogen+suchen";
    }

    if ($type eq "kor") {
        $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=;hst=;swt=;kor=%22$globalcontents%22;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In%20allen%20Katalogen%20suchen";
    }

    if ($type eq "verf") {
        $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=%22$globalcontents%22;hst=;swt=;kor=;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In+allen+Katalogen+suchen";
    }

    my %kat=();
    $kat{'type'}       = "url_category_global";
    $kat{'desc'}       = $desc;
    $kat{'url'}        = $url;
    $kat{'globalurl'}  = $globalurl;
    $kat{'contents'}   = $contents;
    $kat{'supplement'} = $supplement;

    return \%kat;
}

sub get_result_navigation {
    my ($arg_ref) = @_;

    # Set defaults
    my $sessiondbh            = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}            : undef;
    my $database              = exists $arg_ref->{database}
        ? $arg_ref->{database}              : undef;
    my $titidn                = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}                : undef;
    my $sessionID             = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;
    my $searchmode            = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}            : undef;
    my $rating                = exists $arg_ref->{rating}
        ? $arg_ref->{rating}                : undef;
    my $bookinfo              = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}              : undef;
    my $hitrange              = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}              : undef;
    my $sortorder             = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}             : undef;
    my $sorttype              = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    # Bestimmen des vorigen und naechsten Treffer einer
    # vorausgegangenen Kurztitelliste
    my $sessionresult=$sessiondbh->prepare("select lastresultset from session where sessionid = ?") or $logger->error($DBI::errstr);
    $sessionresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    my $result=$sessionresult->fetchrow_hashref();
    my $lastresultstring="";
  
    if ($result->{'lastresultset'}) {
        $lastresultstring=$result->{'lastresultset'};
    }
  
    $sessionresult->finish();
  
    my $lasttiturl="";
    my $nexttiturl="";
  
    if ($lastresultstring=~m/(\w+:\d+)\|$database:$titidn/) {
        $lasttiturl=$1;
        my ($lastdatabase,$lastkatkey)=split(":",$lasttiturl);
        $lasttiturl="$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$lastdatabase;searchsingletit=$lastkatkey";
    }
    
    if ($lastresultstring=~m/$database:$titidn\|(\w+:\d+)/) {
        $nexttiturl=$1;
        my ($nextdatabase,$nextkatkey)=split(":",$nexttiturl);
        $nexttiturl="$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$nextdatabase;searchsingletit=$nextkatkey";
    }

    return ($lasttiturl,$nexttiturl);
}

sub get_index_by_swt {
    my ($swt,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    my @requests=("select schlagw from swt where schlagw like '$swt%' order by schlagw");
    my @temp=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  
    my @schlagwte=sort @temp;
    
    my @swtindex=();

    for (my $i=0; $i <= $#schlagwte; $i++) {
        my $schlagw=$schlagwte[$i];
        @requests=("select idn from swt where schlagw = '$schlagw'");
        my @swtidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
        @requests=("select titidn from titswtlok where swtverw=".$swtidns[0]);
        my $titanzahl=OpenBib::Search::Util::get_number(\@requests,$dbh);
    
        my $swtitem={
            swt       => $schlagw,
            swtidn    => $swtidns[0],
            titanzahl => $titanzahl,
        };
        push @swtindex, $swtitem;
    }

    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $#swtindex Schlagworte : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    return \@swtindex;
}

sub print_index_by_swt {
    my ($arg_ref) = @_;

    # Set defaults
    my $swt               = exists $arg_ref->{swt}
        ? $arg_ref->{swt}               : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $sessiondbh        = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}        : undef;
    my $searchmode        = exists $arg_ref->{searchmode}
        ? $arg_ref->{searchmode}        : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : undef;
    my $rating            = exists $arg_ref->{rating}
        ? $arg_ref->{rating}            : undef;
    my $bookinfo          = exists $arg_ref->{bookinfo}
        ? $arg_ref->{bookinfo}          : undef;
    my $sorttype          = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}          : undef;
    my $sortorder         = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}         : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $targetdbinfo_ref   = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}  : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;
    my $r                 = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}         : undef;
    my $stylesheet        = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}        : undef;
    my $view              = exists $arg_ref->{view}
        ? $arg_ref->{view}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my $swtindex=OpenBib::Search::Util::get_index_by_swt($swt,$dbh);

    my $poolname=$targetdbinfo_ref->{sigel}{$targetdbinfo_ref->{dbases}{$database}};

    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $sessionID,
	      
        database   => $database,
	  
        poolname   => $poolname,

        searchmode => $searchmode,
        hitrange   => $hitrange,
        rating     => $rating,
        bookinfo   => $bookinfo,
        sessionID  => $sessionID,
	
        swt        => $swt,
        swtindex   => $swtindex,

        utf2iso    => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            return $string;
        },
	      
        show_corporate_banner => 0,
        show_foot_banner      => 1,
        config     => \%config,
    };
  
    OpenBib::Common::Util::print_page($config{tt_search_showswtindex_tname},$ttdata,$r);

    return;
}

sub get_index_by_verf {
    my ($verf,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    my @requests=("select ans from aut where ans like '$verf%' order by ans");
    my @temp=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  
    my @verfasser=sort @temp;
    
    my @verfindex=();

    for (my $i=0; $i <= $#verfasser; $i++) {
        my $verfasser=$verfasser[$i];
        @requests=("select idn from aut where ans = '$verfasser'");
        my @verfidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
        @requests=("select titidn from titverf where verfverw=".$verfidns[0],"select titidn from titpers where persverw=".$verfidns[0],"select titidn from titgpers where persverw=".$verfidns[0]);
        my $titanzahl=OpenBib::Search::Util::get_number(\@requests,$dbh);
    
        my $verfitem={
            verf       => $verfasser,
            verfidn    => $verfidns[0],
            titanzahl  => $titanzahl,
        };
        push @verfindex, $verfitem;
    }

    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $#verfindex Verfasser : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    return \@verfindex;
}

sub get_index_by_kor {
    my ($kor,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    my @requests=("select korans from kor where korans like '$kor%'");
    my @temp=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  
    my @koerperschaft=sort @temp;
    
    my @korindex=();

    for (my $i=0; $i <= $#koerperschaft; $i++) {
        my $koerperschaft=$koerperschaft[$i];
        @requests=("select idn from kor where korans = '$koerperschaft'");
        my @koridns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
        @requests=("select titidn from titkor where korverw=".$koridns[0],"select titidn from titurh where urhverw=".$koridns[0]);
        my $titanzahl=OpenBib::Search::Util::get_number(\@requests,$dbh);
    
        my $koritem={
            kor       => $koerperschaft,
            koridn    => $koridns[0],
            titanzahl => $titanzahl,
        };
        push @korindex, $koritem;
    }

    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : $#korindex Koerperschaften : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    return \@korindex;
}

sub initial_search_for_titidns {
    my ($arg_ref) = @_;

    # Set defaults
    my $fs                = exists $arg_ref->{fs}
        ? $arg_ref->{fs}            : undef;
    my $verf              = exists $arg_ref->{verf}
        ? $arg_ref->{verf}          : undef;
    my $hst               = exists $arg_ref->{hst}
        ? $arg_ref->{hst}           : undef;
    my $hststring         = exists $arg_ref->{hststring}
        ? $arg_ref->{hststring}     : undef;
    my $swt               = exists $arg_ref->{swt}
        ? $arg_ref->{swt}           : undef;
    my $kor               = exists $arg_ref->{kor}
        ? $arg_ref->{kor}           : undef;
    my $notation          = exists $arg_ref->{notation}
        ? $arg_ref->{notation}      : undef;
    my $isbn              = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}          : undef;
    my $issn              = exists $arg_ref->{issn}
        ? $arg_ref->{issn}          : undef;
    my $sign              = exists $arg_ref->{sign}
        ? $arg_ref->{sign}          : undef;
    my $ejahr             = exists $arg_ref->{ejahr}
        ? $arg_ref->{ejahr}         : undef;
    my $ejahrop           = exists $arg_ref->{ejahrop}
        ? $arg_ref->{ejahrop}       : undef;
    my $mart              = exists $arg_ref->{mart}
        ? $arg_ref->{mart}          : undef;
    my $boolfs            = exists $arg_ref->{boolfs}
        ? $arg_ref->{boolfs}        : 'AND';
    my $boolverf          = exists $arg_ref->{boolverf}
        ? $arg_ref->{boolverf}      : 'AND';
    my $boolhst           = exists $arg_ref->{boolhst}
        ? $arg_ref->{boolhst}       : 'AND';
    my $boolhststring     = exists $arg_ref->{boolhststring}
        ? $arg_ref->{boolhststring} : 'AND';
    my $boolswt           = exists $arg_ref->{boolswt}
        ? $arg_ref->{boolswt}       : 'AND';
    my $boolkor           = exists $arg_ref->{boolkor}
        ? $arg_ref->{boolkor}       : 'AND';
    my $boolnotation      = exists $arg_ref->{boolnotation}
        ? $arg_ref->{boolnotation}  : 'AND';
    my $boolisbn          = exists $arg_ref->{boolisbn}
        ? $arg_ref->{boolisbn}      : 'AND';
    my $boolissn          = exists $arg_ref->{boolissn}
        ? $arg_ref->{boolissn}      : 'AND';
    my $boolsign          = exists $arg_ref->{boolsign}
        ? $arg_ref->{boolsign}      : 'AND';
    my $boolejahr         = exists $arg_ref->{boolejahr}
        ? $arg_ref->{boolejahr}     : 'AND';
    my $boolmart          = exists $arg_ref->{boolmart}
        ? $arg_ref->{boolmart}      : 'AND';
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}           : undef;
    my $maxhits           = exists $arg_ref->{maxhits}
        ? $arg_ref->{maxhits}       : 50;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Sicherheits-Checks
    if ($boolverf ne "AND" && $boolverf ne "OR" && $boolverf ne "NOT") {
        $boolverf="AND";
    }

    if ($boolhst ne "AND" && $boolhst ne "OR" && $boolhst ne "NOT") {
        $boolhst="AND";
    }

    if ($boolswt ne "AND" && $boolswt ne "OR" && $boolswt ne "NOT") {
        $boolswt="AND";
    }

    if ($boolkor ne "AND" && $boolkor ne "OR" && $boolkor ne "NOT") {
        $boolkor="AND";
    }

    if ($boolnotation ne "AND" && $boolnotation ne "OR" && $boolnotation ne "NOT") {
        $boolnotation="AND";
    }

    if ($boolisbn ne "AND" && $boolisbn ne "OR" && $boolisbn ne "NOT") {
        $boolisbn="AND";
    }

    if ($boolissn ne "AND" && $boolissn ne "OR" && $boolissn ne "NOT") {
        $boolissn="AND";
    }

    if ($boolsign ne "AND" && $boolsign ne "OR" && $boolsign ne "NOT") {
        $boolsign="AND";
    }

    if ($boolejahr ne "AND") {
        $boolejahr="AND";
    }

    if ($boolfs ne "AND" && $boolfs ne "OR" && $boolfs ne "NOT") {
        $boolfs="AND";
    }

    if ($boolmart ne "AND" && $boolmart ne "OR" && $boolmart ne "NOT") {
        $boolmart="AND";
    }

    if ($boolhststring ne "AND" && $boolhststring ne "OR" && $boolhststring ne "NOT") {
        $boolhststring="AND";
    }

    $boolverf      = "AND NOT" if ($boolverf      eq "NOT");
    $boolhst       = "AND NOT" if ($boolhst       eq "NOT");
    $boolswt       = "AND NOT" if ($boolswt       eq "NOT");
    $boolkor       = "AND NOT" if ($boolkor       eq "NOT");
    $boolnotation  = "AND NOT" if ($boolnotation  eq "NOT");
    $boolisbn      = "AND NOT" if ($boolisbn      eq "NOT");
    $boolissn      = "AND NOT" if ($boolissn      eq "NOT");
    $boolsign      = "AND NOT" if ($boolsign      eq "NOT");
    $boolfs        = "AND NOT" if ($boolfs        eq "NOT");
    $boolmart      = "AND NOT" if ($boolmart      eq "NOT");
    $boolhststring = "AND NOT" if ($boolhststring eq "NOT");
  
    my ($atime,$btime,$timeall);
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    # Aufbau des sqlquerystrings
    my $sqlselect = "";
    my $sqlfrom   = "";
    my $sqlwhere  = "";
  
  
    if ($fs) {	
        $fs=OpenBib::Search::Util::input2sgml($fs,1);
        $fs="match (verf,hst,kor,swt,notation,sign,isbn,issn) against ('$fs' IN BOOLEAN MODE)";
    }
  
    if ($verf) {	
        $verf=OpenBib::Search::Util::input2sgml($verf,1);
        $verf="match (verf) against ('$verf' IN BOOLEAN MODE)";
    }
  
    if ($hst) {
        $hst=OpenBib::Search::Util::input2sgml($hst,1);
        $hst="match (hst) against ('$hst' IN BOOLEAN MODE)";
    }
  
    if ($swt) {
        $swt=OpenBib::Search::Util::input2sgml($swt,1);
        $swt="match (swt) against ('$swt' IN BOOLEAN MODE)";
    }
  
    if ($kor) {
        $kor=OpenBib::Search::Util::input2sgml($kor,1);
        $kor="match (kor) against ('$kor' IN BOOLEAN MODE)";
    }
  
    my $notfrom="";
  
    # TODO: SQL-Statement fuer Notationssuche optimieren
    if ($notation) {
        $notation=OpenBib::Search::Util::input2sgml($notation,1);
        $notation="((notation.notation like '$notation%' or notation.benennung like '$notation%') and search.verwidn=titnot.titidn and notation.idn=titnot.notidn)";
        $notfrom=", notation, titnot";
    }
  
    my $signfrom="";
  
    if ($sign) {
        $sign=OpenBib::Search::Util::input2sgml($sign,1);
        $sign="(search.verwidn=mex.titidn and mex.idn=mexsign.mexidn and mexsign.signlok like '$sign%')";
        $signfrom=", mex, mexsign";
    }
  
    if ($isbn) {
        $isbn=OpenBib::Search::Util::input2sgml($isbn,1);
        $isbn=~s/-//g;
        $isbn="match (isbn) against ('$isbn' IN BOOLEAN MODE)";
    }
  
    if ($issn) {
        $issn=OpenBib::Search::Util::input2sgml($issn,1);
        $issn=~s/-//g;
        $issn="match (issn) against ('$issn' IN BOOLEAN MODE)";
    }
  
    if ($mart) {
        $mart=OpenBib::Search::Util::input2sgml($mart,1);
        $mart="match (artinh) against ('$mart' IN BOOLEAN MODE)";
    }
  
    if ($hststring) {
        $hststring=OpenBib::Search::Util::input2sgml($hststring,1);
        $hststring="(search.hststring = '$hststring')";
    }
  
    my $ejtest;
  
    ($ejtest)=$ejahr=~/.*(\d\d\d\d).*/;
    if (!$ejtest) {
        $ejahr="";              # Nur korrekte Jahresangaben werden verarbeitet
    }                           # alles andere wird ignoriert...
  
    if ($ejahr) {	   
        $ejahr="$boolejahr ejahr".$ejahrop."$ejahr";
    }
  
    # Einfuegen der Boolschen Verknuepfungsoperatoren in die SQL-Queries
  
    if (($ejahr) && ($boolejahr eq "OR")) {
        OpenBib::Search::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verkn&uuml;pfung und mindestens einem weiteren angegebenen Suchbegriff m&ouml;glich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Ihr Verst&auml;ndnis f&uuml;r diese Ma&szlig;nahme");
        goto LEAVEPROG;
    }
  
    # SQL-Search
  
    my $notfirstsql=0;
    my $sqlquerystring="";
  
    if ($fs) {
        $notfirstsql=1;
        $sqlquerystring=$fs;
    }
    if ($hst) {
        if ($notfirstsql) {
            $sqlquerystring.=" $boolhst ";
        }
        $notfirstsql=1;
        $sqlquerystring.=$hst;
    }
    if ($verf) {
        if ($notfirstsql) {
            $sqlquerystring.=" $boolverf ";
        }
        $notfirstsql=1;
        $sqlquerystring.=$verf;
    }
    if ($kor) {
        if ($notfirstsql) {
            $sqlquerystring.=" $boolkor ";
        }
        $notfirstsql=1;
        $sqlquerystring.=$kor;
    }
    if ($swt) {
        if ($notfirstsql) {
            $sqlquerystring.=" $boolswt ";
        }
        $notfirstsql=1;
        $sqlquerystring.=$swt;
    }
    if ($notation) {
        if ($notfirstsql) {
            $sqlquerystring.=" $boolnotation ";
        }
        $notfirstsql=1;
        $sqlquerystring.=$notation;
    }
    if ($isbn) {
        if ($notfirstsql) {
            $sqlquerystring.=" $boolisbn ";
        }
        $notfirstsql=1;
        $sqlquerystring.=$isbn;
    }
    if ($issn) {
        if ($notfirstsql) {
            $sqlquerystring.=" $boolissn ";
        }
        $notfirstsql=1;
        $sqlquerystring.=$issn;
    }
    if ($sign) {
        if ($notfirstsql) {
            $sqlquerystring.=" $boolsign ";
        }
        $notfirstsql=1;
        $sqlquerystring.=$sign;
    }
    if ($mart) {
        if ($notfirstsql) {
            $sqlquerystring.=" $boolmart ";
        }
        $notfirstsql=1;
        $sqlquerystring.=$mart;
    }
    if ($hststring) {
        if ($notfirstsql) {
            $sqlquerystring.=" $boolhststring ";
        }
        $notfirstsql=1;
        $sqlquerystring.=$hststring;
    }
  
    if ($ejahr) {
        if ($sqlquerystring eq "") {
            OpenBib::Search::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verkn&uuml;pfung und mindestens einem weiteren angegebenen Suchbegriff m&ouml;glich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Ihr Verst&auml;ndnis f&uuml;r diese Ma&szlig;nahme");
            goto LEAVEPROG;
        }
        else {
            $sqlquerystring="$sqlquerystring $ejahr";
        }
    }
  
    $sqlquerystring="select verwidn from search$signfrom$notfrom where $sqlquerystring limit $maxhits";
  
    $logger->debug("Fulltext-Query: $sqlquerystring");
  
    my @requests=($sqlquerystring);
  
    my @tidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

    $logger->info("Treffer: ".$#tidns);

    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : initital_search_for_titidns / $sqlquerystring -> $#tidns : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
  
    return @tidns;
}

1;

