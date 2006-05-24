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

use Log::Log4perl qw(get_logger :levels);

use Apache::Request();      # CGI-Handling (or require)

use SOAP::Lite;

use DBI;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

my $benchmark;

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

    my $atime;
    my $btime;
    my $timeall;

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $autresult1=$dbh->prepare("$autstatement1") or $logger->error($DBI::errstr);
    $autresult1->execute($autidn) or $logger->error($DBI::errstr);

    my $autres1=$autresult1->fetchrow_hashref;

    $autresult1->finish();

    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $autstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    my $autans;

    if ($autres1->{ans}){
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
  
    my ($autidn,$dbh,$searchmultipleaut,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my @normset=();

    my $autstatement1="select * from aut where idn = ?";
    my $autstatement2="select * from autverw where autidn = ?";

    my $atime;
    my $btime;
    my $timeall;

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $autresult1=$dbh->prepare("$autstatement1") or $logger->error($DBI::errstr);
    $autresult1->execute($autidn);

    my $autres1=$autresult1->fetchrow_hashref;

    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $autstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    # Ausgabe diverser Informationen
    
    push @normset, set_simple_category("Ident-Nr","$autres1->{idn}");
    push @normset, set_simple_category("Ident-Alt","$autres1->{ida}") if ($autres1->{ida});
    push @normset, set_simple_category("Versnr","$autres1->{versnr}") if ($autres1->{versnr});
    push @normset, set_simple_category("Ansetzung","$autres1->{ans}") if ($autres1->{ans});
    push @normset, set_simple_category("Pndnr","$autres1->{pndnr}") if ($autres1->{pndnr});
    push @normset, set_simple_category("Verbnr","$autres1->{verbnr}") if ($autres1->{verbnr});
    
    if ($config{benchmark}){
      $atime=new Benchmark;
    }
    
    # Ausgabe der Verweisformen
    
    my $autresult2=$dbh->prepare("$autstatement2") or $logger->error($DBI::errstr);
    $autresult2->execute($autidn) or $logger->error($DBI::errstr);
    
    my $autres2;
    while ($autres2=$autresult2->fetchrow_hashref){
      push @normset, set_simple_category("Verweis","$autres2->{verw}");
    }    
    
    $autresult2->finish();
    
    if ($config{benchmark}){
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
    
    push @normset, set_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;searchtitofaut=$autres1->{idn}",$titelnr);

    $autresult1->finish();

    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
    # dieses angewendet werden
    
    if (exists $config{categorymapping}{$database}){
      for (my $i=0; $i<=$#normset; $i++){
        my $normdesc=$normset[$i]{desc};
      
        # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
        if (exists $config{categorymapping}{$database}{$normdesc}){
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
  
  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $korresult1=$dbh->prepare("$korstatement1") or $logger->error($DBI::errstr);
  $korresult1->execute($koridn) or $logger->error($DBI::errstr);
  my $korres1=$korresult1->fetchrow_hashref;
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $korstatement1 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  

  my $korans;

  if ($korres1->{korans}){
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
  my ($koridn,$dbh,$searchmultiplekor,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my @normset=();

  my $korstatement1="select * from kor where idn = ?";
  my $korstatement2="select * from korverw where koridn = ?";
  my $korstatement3="select * from korfrueh where koridn = ?";
  my $korstatement4="select * from korspaet where koridn = ?";
  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $korresult1=$dbh->prepare("$korstatement1") or $logger->error($DBI::errstr);
  $korresult1->execute($koridn) or $logger->error($DBI::errstr);

  my $korres1=$korresult1->fetchrow_hashref;
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $korstatement1 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  push @normset, set_simple_category("Ident-Nr","$korres1->{idn}");
  
  push @normset, set_simple_category("Ident-Alt","$korres1->{ida}") if ($korres1->{ida});
  push @normset, set_simple_category("Ansetzung","$korres1->{korans}") if ($korres1->{korans});
  push @normset, set_simple_category("GK-Ident","$korres1->{gkdident}") if ($korres1->{gkdident});
  
  # Verweisungsformen ausgeben
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $korresult2=$dbh->prepare("$korstatement2") or $logger->error($DBI::errstr);
  $korresult2->execute($koridn) or $logger->error($DBI::errstr);
  
  my $korres2;
  while ($korres2=$korresult2->fetchrow_hashref){
    push @normset, set_simple_category("Verweis","$korres2->{verw}");
  }    
  
  $korresult2->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $korstatement2 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Fruehere Form ausgeben
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $korresult3=$dbh->prepare("$korstatement3") or $logger->error($DBI::errstr);
  $korresult3->execute($koridn) or $logger->error($DBI::errstr);
  
  my $korres3;
  while ($korres3=$korresult3->fetchrow_hashref){
    push @normset, set_simple_category("Fr&uuml;her","$korres3->{frueher}");
  }    
  
  $korresult3->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $korstatement3 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  # Form fuer Spaeter ausgeben
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $korresult4=$dbh->prepare("$korstatement4") or $logger->error($DBI::errstr);
  $korresult4->execute($koridn) or $logger->error($DBI::errstr);
  
  my $korres4;
  while ($korres4=$korresult4->fetchrow_hashref){
    push @normset, set_simple_category("Sp&auml;ter","$korres4->{spaeter}");
  }    
  
  $korresult4->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $korstatement4 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  my @requests=("select titidn from titurh where urhverw=$korres1->{idn}","select titidn from titkor where korverw=$korres1->{idn}");
  my $titelnr=get_number(\@requests,$dbh);

  push @normset, set_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;searchtitofurhkor=$korres1->{idn}",$titelnr);

  $korresult1->finish();

  
  # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
  # dieses angewendet werden
  
  if (exists $config{categorymapping}{$database}){
    for (my $i=0; $i<=$#normset; $i++){
      my $normdesc=$normset[$i]{desc};
      
      # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
      if (exists $config{categorymapping}{$database}{$normdesc}){
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
  
  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $swtresult1=$dbh->prepare("$swtstatement1") or $logger->error($DBI::errstr);
  $swtresult1->execute($swtidn) or $logger->error($DBI::errstr);
  
  my $swtres1=$swtresult1->fetchrow_hashref;
  
  my $schlagwort;
  
  if ($swtres1->{schlagw}){
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
  
  my ($swtidn,$dbh,$searchmultipleswt,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rdbinfo,$sessionID)=@_;
  
  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my @normset=();

  my %dbinfo=%$rdbinfo;
  
  my $swtstatement1="select * from swt where idn = ?";
  my $swtstatement2="select * from swtverw where swtidn = ?";
  
  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $swtresult1=$dbh->prepare("$swtstatement1") or $logger->error($DBI::errstr);
  $swtresult1->execute($swtidn) or $logger->error($DBI::errstr);
  
  my $swtres1=$swtresult1->fetchrow_hashref;

  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $swtstatement1 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe diverser Informationen
  
  push @normset, set_simple_category("Ident-Nr","$swtres1->{idn}");
  push @normset, set_simple_category("Ident-Alt","$swtres1->{ida}") if ($swtres1->{ida});
  push @normset, set_simple_category("Schlagwort","$swtres1->{schlagw}") if ($swtres1->{schlagw});
  push @normset, set_simple_category("Erlaeut","$swtres1->{erlaeut}") if ($swtres1->{erlaeut});
  push @normset, set_simple_category("Verbidn","$swtres1->{verbidn}") if ($swtres1->{verbidn});
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $swtresult2=$dbh->prepare("$swtstatement2") or $logger->error($DBI::errstr);
  $swtresult2->execute($swtidn) or $logger->error($DBI::errstr);
  
  my $swtres2;
  while ($swtres2=$swtresult2->fetchrow_hashref){
    push @normset, set_simple_category("Verweis","$swtres2->{verw}") if ($swtres2->{verw});
  }    
  $swtresult2->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $swtstatement2 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  
  my @requests=("select titidn from titswtlok where swtverw=$swtres1->{idn}");
  my $titelnr=get_number(\@requests,$dbh);

  push @normset, set_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;searchtitofswt=$swtres1->{idn}",$titelnr);
  
  $swtresult1->finish();

  # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
  # dieses angewendet werden
  
  if (exists $config{categorymapping}{$database}){
    for (my $i=0; $i<=$#normset; $i++){
      my $normdesc=$normset[$i]{desc};
      
      # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
      if (exists $config{categorymapping}{$database}{$normdesc}){
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

    my $atime;
    my $btime;
    my $timeall;
    
    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $notresult1=$dbh->prepare("$notstatement1") or $logger->error($DBI::errstr);
    $notresult1->execute($notidn) or $logger->error($DBI::errstr);

    my $notres1=$notresult1->fetchrow_hashref;

    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $notstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }
    
    # Zur"ucklieferung der Notation

    my $notation;
    
    if ($notres1->{notation}){
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

    my ($notidn,$dbh,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my @normset=();

    my $notstatement1="select * from notation where idn = ?";
    my $notstatement2="select * from notverw where notidn = ?";
    my $notstatement3="select * from notbenverw where notidn = ?";
    my $atime;
    my $btime;
    my $timeall;
    
    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $notresult1=$dbh->prepare("$notstatement1") or $logger->error($DBI::errstr);
    $notresult1->execute($notidn) or $logger->error($DBI::errstr);

    my $notres1=$notresult1->fetchrow_hashref;

    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $notstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }
    
    # Ausgabe diverser Informationen
  
    push @normset, set_simple_category("Ident-Nr","$notres1->{idn}");
    push @normset, set_simple_category("Ident-Alt","$notres1->{ida}") if ($notres1->{ida});
    push @normset, set_simple_category("Vers-Nr","$notres1->{versnr}") if ($notres1->{versnr});
    push @normset, set_simple_category("Notation","$notres1->{notation}") if ($notres1->{notation});
    push @normset, set_simple_category("Benennung","$notres1->{benennung}") if ($notres1->{benennung});
    
    if ($config{benchmark}){
      $atime=new Benchmark;
    }
    
    # Ausgabe der Verweise
    
    my $notresult2=$dbh->prepare("$notstatement2") or $logger->error($DBI::errstr);
    $notresult2->execute($notidn) or $logger->error($DBI::errstr);
    
    my $notres2;
    while ($notres2=$notresult2->fetchrow_hashref){
      push @normset, set_simple_category("Verweis","$notres2->{verw}");
    }
    $notresult2->finish();

    if ($config{benchmark}){
      $btime=new Benchmark;
      $timeall=timediff($btime,$atime);
      $logger->info("Zeit fuer : $notstatement2 : ist ".timestr($timeall));
      undef $atime;
      undef $btime;
      undef $timeall;
    }
    
    if ($config{benchmark}){
      $atime=new Benchmark;
    }
    
    # Ausgabe von Benverw
    
    my $notresult3=$dbh->prepare("$notstatement3") or $logger->error($DBI::errstr);
    $notresult3->execute($notidn) or $logger->error($DBI::errstr);
    
    my $notres3;
    while ($notres3=$notresult3->fetchrow_hashref){
      push @normset, set_simple_category("Ben.Verweis","$notres3->{benverw}");
    }    
    $notresult3->finish();
    
    if ($config{benchmark}){
      $btime=new Benchmark;
      $timeall=timediff($btime,$atime);
      $logger->info("Zeit fuer : $notstatement3 : ist ".timestr($timeall));
      undef $atime;
      undef $btime;
      undef $timeall;
    }
    
    # Ausgabe diverser Informationen
    
    push @normset, set_simple_category("Abrufzeichen","$notres1->{abrufzeichen}") if ($notres1->{abrufzeichen});
    push @normset, set_simple_category("Beschr-Not.","$notres1->{beschrnot}") if ($notres1->{beschrnot});
    push @normset, set_simple_category("Abrufr","$notres1->{abrufr}") if ($notres1->{abrufr});
    
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

    # Ausgabe der Anzahl verkn"upfter Titel
    
    my @requests=("select titidn from titnot where notidn=$notres1->{idn}");
    my $titelnr=get_number(\@requests,$dbh);
    
    push @normset, set_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;searchtitofnot=$notres1->{idn}",$titelnr);
    
    $notresult1->finish();

    # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
    # dieses angewendet werden
    
    if (exists $config{categorymapping}{$database}){
      for (my $i=0; $i<=$#normset; $i++){
        my $normdesc=$normset[$i]{desc};
      
        # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
        if (exists $config{categorymapping}{$database}{$normdesc}){
	  $normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
        }
      }
    }

    return \@normset;
}

sub get_tit_listitem_by_idn { 

  my ($titidn,$hint,$mode,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rdbinfo,$rtiteltyp,$rsigel,$rdbases,$rbibinfo,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my %dbinfo=%$rdbinfo;
  my %titeltyp=%$rtiteltyp;
  my %sigel=%$rsigel;
  my %dbases=%$rdbases;
  my %bibinfo=%$rbibinfo;
  
  my $titstatement1="select * from tit where idn = ?";
  
  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult1=$dbh->prepare("$titstatement1") or $logger->error($DBI::errstr);
  $titresult1->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres1=$titresult1->fetchrow_hashref;
  $titresult1->finish();
  
  if ($config{benchmark}){
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
  
  my $mexidn;
  
  foreach $mexidn (@verknmex){
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
  my $titidn8;
  foreach $titidn8 (@titres8){
    
    push @verfasserarray, get_aut_ans_by_idn("$titidn8",$dbh);
    
  }
  
  # Ausgabe der Personen

  {
    my $reqstring="select persverw,bez from titpers where titidn=?";
    my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
    while (my $res=$request->fetchrow_hashref){	    
      my $persverw=$res->{persverw};
      my $bez=$res->{bez};
      
      if ($bez){
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
  my $titidn19;
  foreach $titidn19 (@titres19){
    
    push @verfasserarray, get_aut_ans_by_idn("$titidn19",$dbh);
    
  }
  
  # Ausgabe der Urheber
  
  @requests=("select urhverw from titurh where titidn=$titidn");
  my @titres10=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  my $titidn10;
  foreach $titidn10 (@titres10){
    
    push @verfasserarray, get_kor_ans_by_idn("$titidn10",$dbh);
  }
  
  # Ausgabe der K"orperschaften
  
  @requests=("select korverw from titkor where titidn=$titidn");
  my @titres11=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  my $titidn11;
  foreach $titidn11 (@titres11){
    
    push @verfasserarray, get_kor_ans_by_idn("$titidn11",$dbh);
    
  }
  
  $listitem{verfasser}=join(" ; ",@verfasserarray);
  
  my $erschjahr=$titres1->{erschjahr};
  
  if ($erschjahr eq ""){
    $erschjahr=$titres1->{anserschjahr};
  }
  
  $listitem{erschjahr}=$erschjahr;

  $listitem{idn}=$titres1->{idn};

  $listitem{auflage}=$titres1->{aug};

  $listitem{publisher}=$titres1->{verlag};

  $listitem{database}=$database;

  # Ab jetzt hochhangeln zum uebergeordneten Titel, wenn im lokalen keine
  # Sachl. Ben. bzw. HST vorhanden
  
  if (($titres1->{sachlben} eq "")&&($titres1->{hst} eq "")){
    
    # Wenn bei Titeln des Typs 4 (Bandauff"uhrungen) die Kategorien 
    # Sachliche Benennung und HST nicht besetzt sind, dann verwende als
    # Ausgabetext stattdessen den HST des *ersten* "ubergeordneten Werkes und
    # den Zusatz/Laufende Z"ahlung

    my ($gt,$aus,$titstring)=("","","");

    my $gtresult=$dbh->prepare("select gt from titgt where titidn=? limit 1") or $logger->error($DBI::errstr);
    $gtresult->execute($titidn);

    my $gtall_ref=$gtresult->fetchall_arrayref;

    $logger->info($gtresult);
    $titstring=($gtall_ref->[0][0])?$gtall_ref->[0][0]:'';
    
    if (!$titstring){
      my $ausresult=$dbh->prepare("select aus from titaus where titidn=? limit 1") or $logger->error($DBI::errstr);
      $ausresult->execute($titidn);

      my $ausall_ref=$ausresult->fetchall_arrayref;
      $titstring=($ausall_ref->[0][0])?$ausall_ref->[0][0]:'';
    }

    if (!$titstring){
      $titstring="Kein HST/AST vorhanden";
    }

    $listitem{hst}=$titstring;
    $listitem{zus}="";
    $listitem{title}=$titstring;

    
#     if ($hint eq "none"){

#       # Finde anhand GTM
      
#       my @requests=("select verwidn from titgtm where titidn=$titidn limit 1");
#       my @tempgtmidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
      
#       # in @tempgtmidns sind die IDNs der "ubergeordneten Werke
      
#       my $tempgtmidn;
      
#       foreach $tempgtmidn (@tempgtmidns){
	
# 	my @requests=("select hst from tit where idn=$tempgtmidn"); 
# 	my @tithst=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
# 	@requests=("select ast from tit where idn=$tempgtmidn"); 
# 	my @titast=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
# 	# Der AST hat Vorrang ueber den HST
	
# 	if ($titast[0]){
# 	  $tithst[0]=$titast[0];
# 	}
	
# 	@requests=("select zus from titgtm where verwidn=$tempgtmidn");
# 	my @gtmzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
# 	$listitem{hst}=$tithst[0];
# 	$listitem{zus}=$gtmzus[0];
# 	$listitem{title}="$listitem{hst} ; $listitem{zus}";
#       }
      
      
#       # obsolete ?????
      
#       @requests=("select verwidn from titgtf where titidn=$titidn");
#       my @tempgtfidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
      
#       my $tempgtfidn;
      
#       if ($#tempgtfidns >= 0){
# 	$tempgtfidn=$tempgtfidns[0];

# 	# Problem: Mehrfachausgabe in Kurztrefferausgabe eines Titels...
# 	# Loesung: Nur der erste wird ausgegeben
# 	#		foreach $tempgtfidn (@tempgtfidns){
	
# 	my @requests=("select hst from tit where idn=$tempgtfidn");
	
# 	my @tithst=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
# 	@requests=("select ast from tit where idn=$tempgtfidn");
	
# 	my @titast=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
# 	# Der AST hat Vorrang ueber den HST
	
# 	if ($titast[0]){
# 	  $tithst[0]=$titast[0];
# 	}
	
# 	@requests=("select zus from titgtf where verwidn=$tempgtfidn");
	
# 	my @gtfzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
# 	$listitem{hst}=$tithst[0];
# 	$listitem{zus}=$gtfzus[0];
# 	$listitem{title}="$listitem{hst} ; $listitem{zus}";	
#       }		    
      
#     }
#     else {
#       my @requests=("select hst from tit where idn=$hint");
#       my @tithst=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
      
#       @requests=("select ast from tit where idn=$hint");
#       my @titast=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
      
#       # Der AST hat Vorrang ueber den HST
      
#       if ($titast[0]){
# 	$tithst[0]=$titast[0];
#       }
      
#       if ($mode == 6){
	
# 	my @requests=("select zus from titgtf where verwidn=$hint and titidn=$titidn");
# 	my @gtfzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
# 	$listitem{hst}=$tithst[0];
# 	$listitem{zus}=$gtfzus[0];
# 	$listitem{title}="$listitem{hst} ; $listitem{zus}";	
#      }
#       if ($mode == 7){
# 	my $showerschjahr=$titres1->{erschjahr};
	
# 	if ($showerschjahr eq ""){
# 	  $showerschjahr=$titres1->{anserschjahr};
# 	}
	
# 	my @requests=("select zus from titgtm where verwidn=$hint and titidn=$titidn");
# 	my @gtmzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
	
# 	$listitem{hst}=$tithst[0];
# 	$listitem{zus}=$gtmzus[0];
# 	$listitem{title}="$listitem{hst} ; $listitem{zus}";
#       }			     
#       if ($mode == 8){
# 	my $showerschjahr=$titres1->{erschjahr};
	
# 	if ($showerschjahr eq ""){
# 	  $showerschjahr=$titres1->{anserschjahr};
# 	}
	
# 	my @requests=("select zus from titinverkn where titverw=$hint and titidn=$titidn");
# 	my @invkzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

# 	$listitem{hst}=$tithst[0];
# 	$listitem{zus}=$invkzus[0];
# 	$listitem{title}="$listitem{hst} ; $listitem{zus}";
#      }			     
#     }
  }
  
  # Falls HST oder Sachlben existieren, dann gebe ganz normal aus:
  
  else {
    
    # Der AST hat Vorrang ueber den HST
    
    if ($titres1->{ast}){
      $titres1->{hst}=$titres1->{ast};
    }
    
    if ($titres1->{hst} eq ""){
      $titres1->{hst}="Kein HST/AST vorhanden";
    }
    
    my $titstring="";
    
    if ($titres1->{hst}){
      $titstring=$titres1->{hst};
    }
    elsif ($titres1->{sachlben}){
      $titstring=$titres1->{sachlben};
    }
    
    $listitem{hst}=$titstring;
    $listitem{zus}="";
    $listitem{title}=$titstring;
  }

  return \%listitem;
}

sub print_tit_list_by_idn { 

  my ($ritemlist,$rdbinfo,$searchmode,$rating,$bookinfo,$database,$sessionID,$r,$stylesheet,$hitrange,$offset,$view)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my @itemlist=@$ritemlist;
  my %dbinfo=%$rdbinfo;

  my $hits=$#itemlist;

  
  # Navigationselemente erzeugen

  my %args=$r->args;
  delete $args{offset};
  delete $args{hitrange};
  my @args=();
  while (my ($key,$value)=each %args){
    push @args,"$key=$value";
  }

  my $baseurl="http://$config{servername}$config{search_loc}?".join(";",@args);

  my @nav=();

  if ($hitrange > 0){
    for (my $i=1; $i <= $hits; $i+=$hitrange){
      my $active=0;

      if ($i == $offset){
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
	      view       => $view,
	      stylesheet => $stylesheet,
	      sessionID  => $sessionID,
	      
	      database => $database,

	      hits => $hits,
	      
	      searchmode => $searchmode,
	      rating => $rating,
	      bookinfo => $bookinfo,
	      sessionID => $sessionID,
	      
	      dbinfo => \%dbinfo,
	      itemlist => \@itemlist,
	      hostself => $hostself,
	      queryargs => $queryargs,
	      baseurl => $baseurl,
	      thissortstring => $thissortstring,
	      sortselect => $sortselect,
	      
	      hitrange => $hitrange,
	      offset => $offset,
	      nav => \@nav,

	      utf2iso => sub {
		my $string=shift;
		$string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		return $string;
	      },
	      
	      show_corporate_banner => 0,
	      show_foot_banner => 1,
	      config     => \%config,
	     };
  
  OpenBib::Common::Util::print_page($config{tt_search_showtitlist_tname},$ttdata,$r);

  return;
}

sub print_tit_set_by_idn { 

  my ($titidn,$hint,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rdbinfo,$rtiteltyp,$rsigel,$rdbases,$rbibinfo,$sessionID,$r,$stylesheet,$view)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn($titidn,$hint,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rdbinfo,$rtiteltyp,$rsigel,$rdbases,$rbibinfo,$sessionID);

  my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation($sessiondbh,$database,$titidn,$sessionID,$searchmode,$rating,$bookinfo,$hitrange,$sortorder,$sorttype);


  # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
  # dieses angewendet werden

#   if (exists $config{categorymapping}{$database}){
#     my @normset=@$normset;
#     for (my $i=0; $i<=$#normset; $i++){
#       my $normdesc=$normset[$i]{desc};

#       # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
#       if (exists $config{categorymapping}{$database}{$normdesc}){
# 	$normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
#       }
#     }
#     $normset=\@normset;
#   }

  my %sigel=%$rsigel;
  my %dbases=%$rdbases;

  my $poolname=$sigel{$dbases{$database}};

  # TT-Data erzeugen
  
  my $ttdata={
	      view       => $view,
	      stylesheet => $stylesheet,
	      sessionID  => $sessionID,
	      
	      database => $database,
	  
	      poolname => $poolname,

	      prevurl => $prevurl,
	      nexturl => $nexturl,

	      searchmode => $searchmode,
	      hitrange => $hitrange,
	      rating => $rating,
	      bookinfo => $bookinfo,
	      sessionID => $sessionID,
	
	      titidn => $titidn,
	      normset => $normset,
	      mexnormset => $mexnormset,
	      circset => $circset,

              activefeed => OpenBib::Common::Util::get_activefeeds_of_db($sessiondbh,$database),

	      utf2iso => sub {
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

  my ($rtitidns,$hint,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rdbinfo,$rtiteltyp,$rsigel,$rdbases,$rbibinfo,$sessionID,$r,$stylesheet,$view)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my @titidns=@$rtitidns;

  my @titsets=();

  foreach my $titidn (@titidns){
    my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn($titidn,$hint,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rdbinfo,$rtiteltyp,$rsigel,$rdbases,$rbibinfo,$sessionID);
    my $thisset={
		 titidn     => $titidn,
		 normset    => $normset,
		 mexnormset => $mexnormset,
		 circset    => $circset,
		};
    push @titsets, $thisset;
  }

  my %sigel=%$rsigel;
  my %dbases=%$rdbases;

  my $poolname=$sigel{$dbases{$database}};

  # TT-Data erzeugen
  
  my $ttdata={
	      view       => $view,
	      stylesheet => $stylesheet,
	      sessionID  => $sessionID,
	      
	      database => $database,
	  
	      poolname => $poolname,

	      searchmode => $searchmode,
	      hitrange => $hitrange,
	      rating => $rating,
	      bookinfo => $bookinfo,
	      sessionID => $sessionID,
	
	      titsets => \@titsets,

	      utf2iso => sub {
		my $string=shift;
		$string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		return $string;
	      },
	      
	      show_corporate_banner => 0,
	      show_foot_banner => 1,
	      config     => \%config,
	     };
  
  OpenBib::Common::Util::print_page($config{tt_search_showmulttitset_tname},$ttdata,$r);

  return;
}

sub get_tit_hst_by_idn { 

  my ($titidn,$hint,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rdbinfo,$rtiteltyp,$rsigel,$rdbases,$rbibinfo,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my %dbinfo=%$rdbinfo;
  my %titeltyp=%$rtiteltyp;
  my %sigel=%$rsigel;
  my %dbases=%$rdbases;
  my %bibinfo=%$rbibinfo;
  
  my $titstatement1="select * from tit where idn = ?";
  
  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult1=$dbh->prepare("$titstatement1") or $logger->error($DBI::errstr);
  $titresult1->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres1=$titresult1->fetchrow_hashref;
  $titresult1->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement1 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  
  return $titres1->{hst};
}

sub get_tit_set_by_idn { 

  my ($titidn,$hint,$dbh,$sessiondbh,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmode,$circ,$circurl,$circcheckurl,$circdb,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rdbinfo,$rtiteltyp,$rsigel,$rdbases,$rbibinfo,$sessionID)=@_;
  
  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my @normset=();
  
  my %dbinfo=%$rdbinfo;
  my %titeltyp=%$rtiteltyp;
  my %sigel=%$rsigel;
  my %dbases=%$rdbases;
  my %bibinfo=%$rbibinfo;
  
  my $titstatement1="select * from tit where idn = ?";
  my $titstatement2="select * from titgtunv where titidn = ?";
  my $titstatement3="select * from titisbn where titidn = ?";
  my $titstatement4="select * from titgtm where titidn = ?";
  my $titstatement5="select * from titgtf where titidn = ?";
  my $titstatement6="select * from titinverkn where titidn = ?";
  my $titstatement7="select * from titswtlok where titidn = ?";
  my $titstatement8="select * from titverf where titidn = ?";
  my $titstatement9="select * from titpers where titidn = ?";
  my $titstatement10="select * from titurh where titidn = ?";
  my $titstatement11="select * from titkor where titidn = ?";
  my $titstatement12="select * from titnot where titidn = ?";
  my $titstatement13="select * from titissn where titidn = ?";
  my $titstatement14="select * from titwst where titidn = ?";
  my $titstatement15="select * from titurl where titidn = ?";
  my $titstatement16="select * from titpsthts where titidn = ?";
  my $titstatement17="select * from titbeigwerk where titidn = ?";
  my $titstatement18="select * from titartinh where titidn = ?";
  my $titstatement19="select * from titsammelverm where titidn = ?";
  my $titstatement20="select * from titanghst where titidn = ?";
  my $titstatement21="select * from titpausg where titidn = ?";
  my $titstatement22="select * from tittitbeil where titidn = ?";
  my $titstatement23="select * from titbezwerk where titidn = ?";
  my $titstatement24="select * from titfruehausg where titidn = ?";
  my $titstatement25="select * from titfruehtit where titidn = ?";
  my $titstatement26="select * from titspaetausg  where titidn = ?";
  my $titstatement27="select * from titabstract  where titidn = ?";
  my $titstatement28="select * from titner where titidn = ?";
  my $titstatement29="select * from titillang where titidn = ?";
  my $titstatement30="select * from titdrucker where titidn = ?";
  my $titstatement31="select * from titerschland where titidn = ?";
  my $titstatement32="select * from titformat where titidn = ?";
  my $titstatement33="select * from titquelle where titidn = ?";
  my $titstatement34="select * from tittit where titidn = ?";
  my $titstatement35="select * from titgt  where titidn = ?";
  my $titstatement36="select * from titaus where titidn = ?";
  
  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult1=$dbh->prepare("$titstatement1") or $logger->error($DBI::errstr);
  $titresult1->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres1=$titresult1->fetchrow_hashref;
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement1 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  # Ausgabe der Toolzeile fuer Merkliste


#    print "<table cellpadding=2>\n";
#    print "<tr><td>Kategorie</td><td>Inhalt</td></tr>\n";
##    print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td></tr>\n";

  # Ausgabe diverser Informationen
  
  push @normset, set_simple_category("Ident-Nr","$titres1->{idn}");
  push @normset, set_simple_category("Ident-Alt","$titres1->{ida}") if ($titres1->{ida});
  #    push @normset, set_simple_category("Titeltyp","<i>$titeltyp{$titres1->{titeltyp}}</i>") if ($titres1->{titeltyp});
  push @normset, set_simple_category("Versnr","$titres1->{versnr}") if ($titres1->{versnr});
  
  
  # Ausgabe der Verfasser
  
  my @requests=("select verfverw from titverf where titidn=$titidn");
  my @titres8=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  my $titidn8;
  foreach $titidn8 (@titres8){
    push @normset, set_url_category_global("Verfasser","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;verf=$titidn8;generalsearch=verf",get_aut_ans_by_idn("$titidn8",$dbh),"","verf",$sorttype,$sessionID);
  }

  # Ausgabe der Personen
  
  {
    my $reqstring="select persverw,bez from titpers where titidn=?";
    my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
    $request->execute($titidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
    
    while (my $res=$request->fetchrow_hashref){	    
      my $persverw=$res->{persverw};
      my $bez=$res->{bez};
      
      if ($bez){
	push @normset, set_url_category_global("Person","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;pers=$persverw;generalsearch=pers",get_aut_ans_by_idn("$persverw",$dbh),$bez,"verf",$sorttype,$sessionID);
      }
      else {
	push @normset, set_url_category_global("Person","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;pers=$persverw;generalsearch=pers",get_aut_ans_by_idn("$persverw",$dbh),$bez,"verf",$sorttype,$sessionID);
      }
      
    }
    $request->finish();
  }

#   @requests=("select persverw from titpers where titidn=$titidn");
#   my @titres9=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
#   my $titidn9;
#   foreach $titidn9 (@titres9){
#     push @normset, set_url_category_global("Person","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;pers=$titidn9;generalsearch=pers",get_aut_ans_by_idn("$titidn9",$dbh),"","verf",$sorttype,$sessionID);
#   }

  # Ausgabe der gefeierten Personen
  
  @requests=("select persverw from titgpers where titidn=$titidn");
  my @titres13=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  my $titidn13;
  foreach $titidn13 (@titres13){
    push @normset, set_url_category_global("Gefeierte Person","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;pers=$titidn13;generalsearch=pers",get_aut_ans_by_idn("$titidn13",$dbh),"","verf",$sorttype,$sessionID);
  }

  # Ausgabe der Urheber
  
  @requests=("select urhverw from titurh where titidn=$titidn");
  my @titres10=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  my $titidn10;
  foreach $titidn10 (@titres10){
    push @normset, set_url_category_global("Urheber","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;urh=$titidn10;generalsearch=urh",get_kor_ans_by_idn("$titidn10",$dbh),"","kor",$sorttype,$sessionID);
  }
  
  # Ausgabe der K"orperschaften
  
  @requests=("select korverw from titkor where titidn=$titidn");
  my @titres11=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  my $titidn11;
  foreach $titidn11 (@titres11){
    push @normset, set_url_category_global("K&ouml;rperschaft","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;kor=$titidn11;generalsearch=kor",get_kor_ans_by_idn("$titidn11",$dbh),"","kor",$sorttype,$sessionID);
  }
  
  # Ausgabe diverser Informationen
  
  push @normset, set_simple_category("AST","$titres1->{ast}") if ($titres1->{ast});    
  
  push @normset, set_simple_category("Est-He","$titres1->{esthe}") if ($titres1->{esthe});    
  push @normset, set_simple_category("Est-Fn","$titres1->{estfn}") if ($titres1->{estfn});
  push @normset, set_simple_category("HST","<strong>$titres1->{hst}</strong>") if ($titres1->{hst});
  
  # Ausgabe der Sammlungsvermerke
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult19=$dbh->prepare("$titstatement19") or $logger->error($DBI::errstr);
  $titresult19->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres19;
  while ($titres19=$titresult19->fetchrow_hashref){
    push @normset, set_simple_category("SammelVermerk","$titres19->{'sammelverm'}");
  }
  $titresult19->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement19 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  
  # Ausgabe der WST's
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult14=$dbh->prepare("$titstatement14") or $logger->error($DBI::errstr);
  $titresult14->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres14;
  while ($titres14=$titresult14->fetchrow_hashref){
    push @normset, set_simple_category("WST","$titres14->{'wst'}");
  }
  $titresult14->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement14 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe der PSTHTS
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult16=$dbh->prepare("$titstatement16") or $logger->error($DBI::errstr);
  $titresult16->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres16;
  while ($titres16=$titresult16->fetchrow_hashref){
    push @normset, set_simple_category("PST Vorl.","$titres16->{'psthts'}");
  }
  $titresult16->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement16 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe der Beigefuegten Werke
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult17=$dbh->prepare("$titstatement17") or $logger->error($DBI::errstr);
  $titresult17->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres17;
  while ($titres17=$titresult17->fetchrow_hashref){
    push @normset, set_simple_category("Beig.Werke","$titres17->{'beigwerk'}");
  }
  $titresult17->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement17 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe der URL's
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult15=$dbh->prepare("$titstatement15") or $logger->error($DBI::errstr);
  $titresult15->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres15;
  while ($titres15=$titresult15->fetchrow_hashref){
    push @normset, set_simple_category("URL","<a href=\"$titres15->{'url'}\" target=_blank>$titres15->{'url'}</a>");
  }
  $titresult15->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement15 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  push @normset, set_simple_category("Zu erg. Urh","$titres1->{zuergurh}") if ($titres1->{zuergurh});
  push @normset, set_simple_category("Zusatz","$titres1->{zusatz}") if ($titres1->{zusatz});
  push @normset, set_simple_category("Vorl.beig.Werk","$titres1->{vorlbeigwerk}") if ($titres1->{vorlbeigwerk});
  push @normset, set_simple_category("Gemeins.Angaben","$titres1->{gemeinsang}") if ($titres1->{gemeinsang});
  push @normset, set_simple_category("Sachl.Ben.","<strong>$titres1->{sachlben}</strong>") if ($titres1->{sachlben});
  push @normset, set_simple_category("Vorl.Verfasser","$titres1->{vorlverf}") if ($titres1->{vorlverf});
  push @normset, set_simple_category("Vorl.Unterreihe","$titres1->{vorlunter}") if ($titres1->{vorlunter});    
  push @normset, set_simple_category("Ausgabe","$titres1->{ausg}") if ($titres1->{ausg});    
  push @normset, set_simple_category("Verlagsort","$titres1->{verlagsort}") if ($titres1->{verlagsort});    
  push @normset, set_simple_category("Verlag","$titres1->{verlag}") if ($titres1->{verlag});    
  push @normset, set_simple_category("Weitere Orte","$titres1->{weitereort}") if ($titres1->{weitereort});    
  push @normset, set_simple_category("Aufnahmeort","$titres1->{aufnahmeort}") if ($titres1->{aufnahmeort});    
  push @normset, set_simple_category("Aufnahmejahr","$titres1->{aufnahmejahr}") if ($titres1->{aufnahmejahr});    
  push @normset, set_simple_category("Ersch. Jahr","$titres1->{erschjahr}") if ($titres1->{erschjahr});    
  push @normset, set_simple_category("Ans. Ersch. Jahr","$titres1->{anserschjahr}") if ($titres1->{anserschjahr});    
  push @normset, set_simple_category("Ersch. Verlauf","$titres1->{erschverlauf}") if ($titres1->{erschverlauf});    
  
  push @normset, set_simple_category("Verfasser Quelle","$titres1->{verfquelle}") if ($titres1->{verfquelle});    
  push @normset, set_simple_category("Ersch.Ort Quelle","$titres1->{eortquelle}") if ($titres1->{eortquelle});    
  push @normset, set_simple_category("Ersch.Jahr Quelle","$titres1->{ejahrquelle}") if ($titres1->{ejahrquelle});    
  
  # Ausgabe der Illustrationsangaben
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult29=$dbh->prepare("$titstatement29") or $logger->error($DBI::errstr);
  $titresult29->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres29;
  while ($titres29=$titresult29->fetchrow_hashref){
    push @normset, set_simple_category("Ill.Angaben",$titres29->{'illang'});
  }
  $titresult29->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement29 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  # Ausgabe des Druckers
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult30=$dbh->prepare("$titstatement30") or $logger->error($DBI::errstr);
  $titresult30->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres30;
  while ($titres30=$titresult30->fetchrow_hashref){
    push @normset, set_simple_category("Drucker",$titres30->{'drucker'});
  }
  $titresult30->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement30 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  # Ausgabe des Erscheinungslandes
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult31=$dbh->prepare("$titstatement31") or $logger->error($DBI::errstr);
  $titresult31->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres31;
  while ($titres31=$titresult31->fetchrow_hashref){
    push @normset, set_simple_category("Ersch.Land",$titres31->{'erschland'});
  }
  $titresult31->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement31 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  # Ausgabe des Formats
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult32=$dbh->prepare("$titstatement32") or $logger->error($DBI::errstr);
  $titresult32->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres32;
  while ($titres32=$titresult32->fetchrow_hashref){
    push @normset, set_simple_category("Format",$titres32->{'format'});
  }
  $titresult32->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement32 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  # Ausgabe der Quelle
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult33=$dbh->prepare("$titstatement33") or $logger->error($DBI::errstr);
  $titresult33->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres33;
  while ($titres33=$titresult33->fetchrow_hashref){
    push @normset, set_simple_category("Quelle",$titres33->{'quelle'});
  }
  $titresult33->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement33 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  push @normset, set_simple_category("Kollation","$titres1->{kollation}") if ($titres1->{kollation});    


  # Ausgabe GT
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult35=$dbh->prepare("$titstatement35") or $logger->error($DBI::errstr);
  $titresult35->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres35;
  while ($titres35=$titresult35->fetchrow_hashref){
    push @normset, set_simple_category("Gesamttitel",$titres35->{gt});
    
  }
  $titresult35->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement35 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  # Ausgabe aus:
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult36=$dbh->prepare("$titstatement36") or $logger->error($DBI::errstr);
  $titresult36->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres36;
  while ($titres36=$titresult36->fetchrow_hashref){
    push @normset, set_simple_category("In:",$titres36->{aus});
    
  }
  $titresult36->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement36 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  
#   # Ausgabe GTM
  
#   if ($config{benchmark}){
#     $atime=new Benchmark;
#   }
  
#   my $titresult4=$dbh->prepare("$titstatement4") or $logger->error($DBI::errstr);
#   $titresult4->execute($titidn) or $logger->error($DBI::errstr);
  
#   my $titres4;
#   while ($titres4=$titresult4->fetchrow_hashref){
#     my $titstatement="select hst from tit where idn = ?";
#     my $titresult=$dbh->prepare("$titstatement") or $logger->error($DBI::errstr);
#     $titresult->execute($titres4->{verwidn}) or $logger->error($DBI::errstr);
#     my $titres=$titresult->fetchrow_hashref;
    
#     push @normset, set_url_category("Gesamttitel","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;singlegtm=$titres4->{verwidn};generalsearch=singlegtm",$titres->{hst}," ; $titres4->{zus}");
    
#   }
#   $titresult4->finish();
  
#   if ($config{benchmark}){
#     $btime=new Benchmark;
#     $timeall=timediff($btime,$atime);
#     $logger->info("Zeit fuer : $titstatement4 : ist ".timestr($timeall));
#     undef $atime;
#     undef $btime;
#     undef $timeall;
#   }
  
#   if ($config{benchmark}){
#     $atime=new Benchmark;
#   }
  
  # Augabe GTF
  
#   if ($config{benchmark}){
#     $atime=new Benchmark;
#   }
  
#   my $titresult5=$dbh->prepare("$titstatement5") or $logger->error($DBI::errstr);
#   $titresult5->execute($titidn) or $logger->error($DBI::errstr);
  
#   my $titres5;
#   while ($titres5=$titresult5->fetchrow_hashref){
#     my $titstatement="select hst,ast,vorlverf,zuergurh,vorlunter from tit where idn = ?";
#     my $titresult=$dbh->prepare("$titstatement") or $logger->error($DBI::errstr);
#     $titresult->execute($titres5->{verwidn}) or $logger->error($DBI::errstr);
#     my $titres=$titresult->fetchrow_hashref;
    
#     my $asthst=$titres->{hst};
    
#     my $verfurh=$titres->{zuergurh};
    
#     if ($titres->{vorlverf}){
#       $verfurh=$titres->{vorlverf};
#     }
    
#     if (!$asthst && $titres->{ast}){
#       $asthst=$titres->{ast};
#     }
    
#     my $vorlunter=$titres->{vorlunter};
    
#     if ($vorlunter){
#       $asthst="$asthst : $vorlunter";
#     }
    
    
#     if ($verfurh){
#       $asthst=$asthst." / ".$verfurh;
#     }
    
#     push @normset, set_url_category("Gesamttitel","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;singlegtf=$titres5->{verwidn};generalsearch=singlegtf",$asthst," ; $titres5->{zus}");
    
#   }
#   $titresult5->finish();
  
#   if ($config{benchmark}){
#     $btime=new Benchmark;
#     $timeall=timediff($btime,$atime);
#     $logger->info("Zeit fuer : $titstatement5 ++ : ist ".timestr($timeall));
#     undef $atime;
#     undef $btime;
#     undef $timeall;
#   }
  
#   if ($config{benchmark}){
#     $atime=new Benchmark;
#   }
  
#   # Ausgabe IN Verkn.
  
#   if ($config{benchmark}){
#     $atime=new Benchmark;
#   }
  
#   my $titresult6=$dbh->prepare("$titstatement6") or $logger->error($DBI::errstr);
#   $titresult6->execute($titidn) or $logger->error($DBI::errstr);
  
#   my $titres6;
#   while ($titres6=$titresult6->fetchrow_hashref){
#     my $titverw=$titres6->{titverw};
    
#     my $titstatement="select hst,sachlben from tit where idn = ?";
#     my $titresult=$dbh->prepare("$titstatement") or $logger->error($DBI::errstr);
#     $titresult->execute($titverw) or $logger->error($DBI::errstr);
#     my $titres=$titresult->fetchrow_hashref;
    
#     # Wenn HST vorhanden, dann nimm ihn, sonst Sachlben.
    
#     my $verkn=($titres->{hst})?$titres->{hst}:$titres->{sachlben};
    
#     # Wenn weder HST, noch Sachlben vorhanden, dann haben wir
#     # einen Titeltyp4 ohne irgendeine weitere Information und wir m"ussen
#     # uns f"ur HST/Sachlben-Informationen eine Suchebene tiefer 
#     # hangeln :-(
    
#     if (!$verkn){
#       my $gtmidnresult1=$dbh->prepare("select verwidn from titgtm where titidn = ?") or $logger->error($DBI::errstr);
#       $gtmidnresult1->execute($titverw) or $logger->error($DBI::errstr);
#       my $gtmidnres1=$gtmidnresult1->fetchrow_hashref;
#       my $gtmidn=$gtmidnres1->{verwidn};
#       $gtmidnresult1->finish();
      
#       if ($gtmidn){
# 	my $gtmidnresult2=$dbh->prepare("select hst,sachlben from tit where idn = ?") or $logger->error($DBI::errstr);
# 	$gtmidnresult2->execute($gtmidn) or $logger->error($DBI::errstr);
# 	my $gtmidnres2=$gtmidnresult2->fetchrow_hashref;
# 	$verkn=($gtmidnres2->{hst})?$gtmidnres2->{hst}:$gtmidnres2->{sachlben};
# 	$gtmidnresult2->finish();
#       }
#     }
    
#     if (!$verkn){
#       my $gtfidnresult1=$dbh->prepare("select verwidn, zus from titgtf where titidn = ?") or $logger->error($DBI::errstr);
#       $gtfidnresult1->execute($titverw) or $logger->error($DBI::errstr);
#       my $gtfidnres1=$gtfidnresult1->fetchrow_hashref;
#       my $gtfidn=$gtfidnres1->{verwidn};
#       my $gtfzus=$gtfidnres1->{zus};
#       $gtfidnresult1->finish();
      
#       if ($gtfidn){
# 	my $gtfidnresult2=$dbh->prepare("select hst,sachlben from tit where idn = ?") or $logger->error($DBI::errstr);
# 	$gtfidnresult2->execute($gtfidn) or $logger->error($DBI::errstr);
# 	my $gtfidnres2=$gtfidnresult2->fetchrow_hashref;
# 	$verkn=($gtfidnres2->{hst})?$gtfidnres2->{hst}:$gtfidnres2->{sachlben};
# 	$gtfidnresult2->finish();
#       }
#       if ($gtfzus){
# 	$verkn="$verkn ; $gtfzus";
#       }
#     }
    
#     # Der Zusatz wird doppelt ausgegeben. In der Verknuepfung und
#     # auch im Zusatz. Es wird nun ueberprueft, ob doppelte Information
#     # bis/vom Semikolon vorhanden ist und gegebenenfalls geloescht.
    
#     my ($check1)=$titres6->{zus}=~/^(.+?) \;/;
#     my ($check2)=$verkn=~/^.+\;(.+)$/;
    
#     my $zusatz=$titres6->{zus};
    
#     # Doppelte Information ist vorhanden, dann ...
#     if ($check1 eq $check2){
#       $zusatz=~s/^.+? \; (.+?)$/$1/;
#     }
    
#     push @normset, set_url_category("In:","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;singlegtf=$titverw;generalsearch=singlegtf",$verkn," ; $zusatz ");
    
#   }
  
#   $titresult6->finish();	
  
  
#   if ($config{benchmark}){
#     $btime=new Benchmark;
#     $timeall=timediff($btime,$atime);
#     $logger->info("Zeit fuer : $titstatement6 : ist ".timestr($timeall));
#     undef $atime;
#     undef $btime;
#     undef $timeall;
#   }
  
#   if ($config{benchmark}){
#     $atime=new Benchmark;
#   }
  
#   # Ausgabe GT unverkn.
  
#   if ($config{benchmark}){
#     $atime=new Benchmark;
#   }
  
#   my $titresult2=$dbh->prepare("$titstatement2") or $logger->error($DBI::errstr);
#   $titresult2->execute($titidn) or $logger->error($DBI::errstr);
  
#   my $titres2;
#   while ($titres2=$titresult2->fetchrow_hashref){
#     push @normset, set_simple_category("GT unverkn","$titres2->{gtunv}");
#   }
#   $titresult2->finish();
  
#   if ($config{benchmark}){
#     $btime=new Benchmark;
#     $timeall=timediff($btime,$atime);
#     $logger->info("Zeit fuer : $titstatement2 : ist ".timestr($timeall));
#     undef $atime;
#     undef $btime;
#     undef $timeall;
#   }
  
  # Ausgabe diverser Informationen
  
#  push @normset, set_simple_category("IN unverkn","$titres1->{inunverkn}") if ($titres1->{inunverkn});    
  push @normset, set_simple_category("Mat.Benennung","$titres1->{matbenennung}") if ($titres1->{matbenennung});    
  push @normset, set_simple_category("Sonst.Mat.ben","$titres1->{sonstmatben}") if ($titres1->{sonstmatben});    
  push @normset, set_simple_category("Sonst.Angaben","$titres1->{sonstang}") if ($titres1->{sonstang});    
  push @normset, set_simple_category("Begleitmaterial","$titres1->{begleitmat}") if ($titres1->{begleitmat});    
  push @normset, set_simple_category("Fu&szlig;note","$titres1->{fussnote}") if ($titres1->{fussnote});    
  
  # Ausgabe der AngabenHST
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult20=$dbh->prepare("$titstatement20") or $logger->error($DBI::errstr);
  $titresult20->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres20;
  while ($titres20=$titresult20->fetchrow_hashref){
    push @normset, set_simple_category("AngabenHST","$titres20->{'anghst'}");
  }
  $titresult20->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement20 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  
  # Ausgabe der ParallelAusgabe
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult21=$dbh->prepare("$titstatement21") or $logger->error($DBI::errstr);
  $titresult21->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres21;
  while ($titres21=$titresult21->fetchrow_hashref){
    push @normset, set_simple_category("Parallele Ausg.","$titres21->{'pausg'}");
  }
  $titresult21->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement21 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe der TitBeilage
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult22=$dbh->prepare("$titstatement22") or $logger->error($DBI::errstr);
  $titresult22->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres22;
  while ($titres22=$titresult22->fetchrow_hashref){
    push @normset, set_simple_category("Titel Beilage","$titres22->{'titbeil'}");
  }
  $titresult22->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement22 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe der Bezugswerk
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult23=$dbh->prepare("$titstatement23") or $logger->error($DBI::errstr);
  $titresult23->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres23;
  while ($titres23=$titresult23->fetchrow_hashref){
    push @normset, set_simple_category("Bezugswerk","$titres23->{'bezwerk'}");
  }
  $titresult23->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement23 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe der FruehAusg
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult24=$dbh->prepare("$titstatement24") or $logger->error($DBI::errstr);
  $titresult24->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres24;
  while ($titres24=$titresult24->fetchrow_hashref){
    push @normset, set_simple_category("Fr&uuml;here Ausg.","$titres24->{'fruehausg'}");
  }
  $titresult24->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement24 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe des FruehTit
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult25=$dbh->prepare("$titstatement25") or $logger->error($DBI::errstr);
  $titresult25->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres25;
  while ($titres25=$titresult25->fetchrow_hashref){
    push @normset, set_simple_category("Fr&uuml;herer Titel","$titres25->{'fruehtit'}");
  }
  $titresult25->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement25 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe der SpaetAusg
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult26=$dbh->prepare("$titstatement26") or $logger->error($DBI::errstr);
  $titresult26->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres26;
  while ($titres26=$titresult26->fetchrow_hashref){
    push @normset, set_simple_category("Sp&auml;tere Ausg.","$titres26->{'spaetausg'}");
  }
  $titresult26->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement26 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  push @normset, set_simple_category("Bind-Preis","$titres1->{bindpreis}") if ($titres1->{bindpreis});    
  push @normset, set_simple_category("Hsfn","$titres1->{hsfn}") if ($titres1->{hsfn});    
  push @normset, set_simple_category("Sprache","$titres1->{sprache}") if ($titres1->{sprache});    
  
  
  # Ausgabe der Abstracts
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult27=$dbh->prepare("$titstatement27") or $logger->error($DBI::errstr);
  $titresult27->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres27;
  while ($titres27=$titresult27->fetchrow_hashref){
    push @normset, set_simple_category("Abstract","$titres27->{'abstract'}");
  }
  $titresult27->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement27 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  push @normset, set_simple_category("Mass.","$titres1->{mass}") if ($titres1->{mass});    
  push @normset, set_simple_category("&Uuml;bers. HST","$titres1->{uebershst}") if ($titres1->{uebershst});    
  #    push @normset, set_simple_category("Bemerkung","$titres1->{rem}") if ($titres1->{rem});    
  #    push @normset, set_simple_category("Bemerkung","$titres1->{bemerk}") if ($titres1->{bemerk});    
  
  # Ausgabe der NER
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult28=$dbh->prepare("$titstatement28") or $logger->error($DBI::errstr);
  $titresult28->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres28;
  while ($titres28=$titresult28->fetchrow_hashref){
    push @normset, set_simple_category("Nebeneintr.","$titres28->{'ner'}");
  }
  $titresult28->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement28 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe der Medienart/Art-Inhalt
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult18=$dbh->prepare("$titstatement18") or $logger->error($DBI::errstr);
  $titresult18->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres18;
  while ($titres18=$titresult18->fetchrow_hashref){
    push @normset, set_simple_category("Medienart","$titres18->{'artinhalt'}");
  }
  $titresult18->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement18 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  # Ausgabe der Schlagworte
  
  @requests=("select swtverw from titswtlok where titidn=$titidn");
  my @titres7=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  my $titidn7;
  foreach $titidn7 (@titres7){
    
    push @normset, set_url_category_global("Schlagwort","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;swt=$titidn7;generalsearch=swt",get_swt_ans_by_idn("$titidn7",$dbh),"","swt",$sorttype,$sessionID);
    
  }
  
  # Augabe der Notationen
  
  @requests=("select notidn from titnot where titidn=$titidn");
  my @titres12=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  my $titidn12;
  foreach $titidn12 (@titres12){
    
    push @normset, set_url_category("Notation","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;notation=$titidn12;generalsearch=not",get_not_ans_by_idn("$titidn12",$dbh));
    
  }
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  # Ausgabe der ISBN's
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult3=$dbh->prepare("$titstatement3") or $logger->error($DBI::errstr);
  $titresult3->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres3;
  my $isbn;

  my @isbns=();
  while ($titres3=$titresult3->fetchrow_hashref){
    $isbn=$titres3->{isbn};
    push @normset, set_simple_category("ISBN",$isbn);

    push @isbns, $isbn;
  }
  $titresult3->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement3 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  # Ausgabe der ISSN's
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $titresult13=$dbh->prepare("$titstatement13") or $logger->error($DBI::errstr);
  $titresult13->execute($titidn) or $logger->error($DBI::errstr);
  
  my $titres13;
  while ($titres13=$titresult13->fetchrow_hashref){
    push @normset, set_simple_category("ISSN","$titres13->{issn}");
  }
  $titresult13->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $titstatement13 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  # Anreicherung mit zentralen Enrichmentdaten
  {
      my ($atime,$btime,$timeall);
      
      if ($config{benchmark}) {
          $atime=new Benchmark;
      }
      
      # Verbindung zur SQL-Datenbank herstellen
      my $enrichdbh
          = DBI->connect("DBI:$config{dbimodule}:dbname=$config{enrichmntdbname};host=$config{enrichmntdbhost};port=$config{enrichmntdbport}", $config{enrichmntdbuser}, $config{enrichmntdbpasswd})
              or $logger->error_die($DBI::errstr);
      
      foreach my $isbn (@isbns){
          
          $isbn =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
          
          my $reqstring="select category,content from normdata where isbn=? order by category ASC";
          my $request=$enrichdbh->prepare($reqstring) or $logger->error($DBI::errstr);
          $request->execute($isbn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

          my $categorynames_ref = {
              T3001 => { type    => "url",
                         desc    => "TOC / &Uuml;bersicht",
                         content => "<img src=\"/images/openbib/html.png\">&nbsp;Digitalisiertes Inhaltsverzeichnis (&Uuml;bersicht)",
                     },
#              T3002 => { type => "url",
#                         desc => "TOC / TIFF",
#                         content => "<img src=\"/images/openbib/image.png\">&nbsp;Digitalisiertes Inhaltsverzeichnis (Tiff-Format)",
#                     },
              T3003 => { type => "url",
                         desc => "TOC / PDF",
                         content => "<img src=\"/images/openbib/pdf-document.png\">&nbsp;Digitalisiertes Inhaltsverzeichnis (PDF-Format)",
                     },
          };

          while (my $res=$request->fetchrow_hashref) {
              my $category   = "T".sprintf "%04d",$res->{category };
              my $content    =                    $res->{content  };

              if (exists $categorynames_ref->{$category}){
                  if ($categorynames_ref->{$category}->{type} eq "url"){
                      push @normset, set_url_category($categorynames_ref->{$category}->{desc},$content,$categorynames_ref->{$category}->{content});
                  }
              }
              else {
                  $logger->debug("Enrich: $isbn nicht gefunden");
              }
          }
          $request->finish();
          $logger->debug("Enrich: $isbn -> $reqstring");
      }

      $enrichdbh->disconnect();

      if ($config{benchmark}) {
          $btime=new Benchmark;
          $timeall=timediff($btime,$atime);
          $logger->info("Zeit fuer : Bestimmung von Enrich-Normdateninformationen ist ".timestr($timeall));
          undef $atime;
          undef $btime;
          undef $timeall;
      }
      
      
  }

  
  # Ausgabe der Anzahl verkn"upfter Ueberordnungen
  
  @requests=("select verwidn from tittit where titidn=$titres1->{idn}");
  my $verkntit=get_number(\@requests,$dbh);
  if ($verkntit > 0){
    
    push @normset, set_url_category("&Uuml;berordnungen","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;supertit=$titres1->{idn};generalsearch=supertit",$verkntit);
    
  }

  # Ausgabe der Anzahl verkn"upfter Unterordnungen
  
  @requests=("select titidn from tittit where verwidn=$titres1->{idn}");
  $verkntit=get_number(\@requests,$dbh);
  if ($verkntit > 0){
    
    push @normset, set_url_category("Unterordnungen","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;subtit=$titres1->{idn};generalsearch=subtit",$verkntit);
    
  }

  
  # Ausgabe der Anzahl verkn"upfter GTM
  
#   @requests=("select titidn from titgtm where verwidn=$titres1->{idn}");
#   my $verkntit=get_number(\@requests,$dbh);
#   if ($verkntit > 0){
    
#     push @normset, set_url_category("B&auml;nde","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;gtmtit=$titres1->{idn};generalsearch=gtmtit",$verkntit);
    
#   }
  
#   # Ausgabe der Anzahl verkn"upfter GTF
  
#   @requests=("select titidn from titgtf where verwidn=$titres1->{idn}");
#   $verkntit=get_number(\@requests,$dbh);
#   if ($verkntit > 0){
#     push @normset, set_url_category("St&uuml;cktitel","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;gtftit=$titres1->{idn};generalsearch=gtftit",$verkntit);
#   }
  
#   # Ausgabe der Anzahl verkn"upfter IN verkn.
  
#   @requests=("select titidn from titinverkn where titverw=$titres1->{idn}");
#   $verkntit=get_number(\@requests,$dbh);
#   if ($verkntit > 0){
    
#     push @normset, set_url_category("Teile","$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$database;invktit=$titres1->{idn};generalsearch=invktit",$verkntit);
    
#   }
  
  
  @requests=("select idn from mex where titidn=$titres1->{idn}");
  my @verknmex=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

  my @mexnormset=();

  
  #	print "</table>\n";
  if ($#verknmex >= 0){
    #	  print "<p>\n";
    #	  print "<table>\n";
    #	  print "<tr align=center><td bgcolor=\"lightblue\" width=\"225\">Besitzende Bibliothek</td><td bgcolor=\"lightblue\" width=\"250\">Standort</td><td bgcolor=\"lightblue\" width=\"120\">Inventarnummer</td><td bgcolor=\"lightblue\" width=\"250\">Lokale Signatur</td>";
    
    #	  print "<td bgcolor=\"lightblue\" width=\"230\">Bestandsverlauf</td>";
    
    #	  print "</tr>\n";
    
    my $mexsatz;

    foreach $mexsatz (@verknmex){
      get_mex_set_by_idn($mexsatz,$dbh,$searchmode,$circ,$circurl,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%sigel,\%dbases,\%bibinfo,$sessionID,\@mexnormset);
    }
    #	  print "</table>\n";
  }
  
  #    print "</td></tr></table>\n";
  
  # Gegebenenfalls bestimmung der Ausleihinfo fuer Exemplare
  
  my $circexlist=undef;

    if ($circ){

      my $circidn=(exists $titres1->{idn} && exists $titres1->{ida} && $titres1->{idn} != $titres1->{ida})?$titres1->{ida}:$titres1->{idn};

      my $soap = SOAP::Lite
	-> uri("urn:/MediaStatus")
	    -> proxy($circcheckurl);
      my $result = $soap->get_mediastatus($circidn,$circdb);
      
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

    if (defined($circexlist)){
      @circexemplarliste = @{$circexlist};
    }

    if ($circ && $#circexemplarliste >= 0){
#      print << "CIRCHEAD";
#<p>
#<table width="100%">
#<tr><th>Ausleihe/Exemplare</th></tr>
#<tr><td class="boxedclear" style="font-size:12pt">
#<table>
#CIRCHEAD

#      print "<tr align=center><td bgcolor=\"lightblue\" width=\"225\">Besitzende Bibliothek</td><td bgcolor=\"lightblue\" width=\"250\">Standort</td><td bgcolor=\"lightblue\" width=\"120\">Lokale Signatur</td><td bgcolor=\"lightblue\" width=\"120\">Ausleihstatus</td><td bgcolor=\"lightblue\" width=\"110\">Aktion</td></tr>\n";
      
#      foreach my $singleex (@circexemplarliste) {
      for (my $i=0; $i <= $#circexemplarliste; $i++) {
	$circexemplarliste[$i]{'Standort'}=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
	$circexemplarliste[$i]{'Signatur'}=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
	$circexemplarliste[$i]{'Status'}=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
	$circexemplarliste[$i]{'Rueckgabe'}=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
	$circexemplarliste[$i]{'Exemplar'}=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
	
	# Zusammensetzung von Signatur und Exemplar

	$circexemplarliste[$i]{'Signatur'}=$circexemplarliste[$i]{'Signatur'}.$circexemplarliste[$i]{'Exemplar'};
#	$signatur=$signatur.$exemplar;

	# Ein im Exemplar-Datensatz gefundenes Sigel geht vor

	my $bibliothek="";

	my $sigel=$dbases{$database};

	if (length($sigel)>0){
	  
	  if (exists $sigel{$sigel}){
	    $bibliothek=$sigel{$sigel};
	  }
	  else{
	    $bibliothek="Unbekannt (38/$sigel)";
	  }
	}
	else {
	  if (exists $sigel{$dbases{$database}}){
	    $bibliothek=$sigel{$dbases{$database}};
	  }
	  else{
	    $bibliothek="Unbekannt (38/$sigel)";
	  }
	}
	$circexemplarliste[$i]{'Bibliothek'}=$bibliothek;

	my $bibinfourl=$bibinfo{$dbases{$database}};

	$circexemplarliste[$i]{'Bibinfourl'}=$bibinfourl;

	my $ausleihstatus=$circexemplarliste[$i]{'Ausleihstatus'};

#	print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td>";
#	print "<td>$standort</td><td><strong>$signatur</strong></td>";
	
	my $ausleihstring;
        if (exists $circexemplarliste[$i]{'Ausleihstatus'}){
            if ($circexemplarliste[$i]{'Ausleihstatus'} eq "bestellbar"){
                $ausleihstring="ausleihen?";
            }
            elsif ($circexemplarliste[$i]{'Ausleihstatus'} eq "bestellt"){
                $ausleihstring="vormerken?";
            }
            elsif ($circexemplarliste[$i]{'Ausleihstatus'} eq "entliehen"){
                $ausleihstring="vormerken/verl&auml;ngern?";
            }
            elsif ($circexemplarliste[$i]{'Ausleihstatus'} eq "bestellbar"){
                $ausleihstring="ausleihen?";
            }
            else {
                $ausleihstring="Weiter";
            }
        }
        else {
            $ausleihstring="Weiter";
        }
        
	$circexemplarliste[$i]{'Ausleihstring'}=$ausleihstring;

	if ($circexemplarliste[$i]{'Standort'}=~/Erziehungswiss/ || $circexemplarliste[$i]{'Standort'}=~/Heilp.*?dagogik-Magazin/){
	  $circexemplarliste[$i]{'Ausleihurl'}="$circurl?Login=ewa&Query=0000=$titidn";

#	  print "<td><strong>$ausleihstatus</strong></td><td bgcolor=\"yellow\"><a TARGET=_blank href=\"$circurl&branch=4&KatKeySearch=$titidn\">$ausleihstring</a></td>";
	}
	else {
	  if ($database eq "inst001" || $database eq "poetica"){
	    $circexemplarliste[$i]{'Ausleihurl'}="$circurl?Login=sisis&Query=0000=$titidn
";
#	    print "<td><strong>$ausleihstatus</strong></td><td bgcolor=\"yellow\"><a TARGET=_blank href=\"$circurl&branch=0&KatKeySearch=$titidn\">$ausleihstring</a></td>";
	  }
	  else {
	    $circexemplarliste[$i]{'Ausleihurl'}="$circurl&KatKeySearch=$titidn";
#	    print "<td><strong>$ausleihstatus</strong></td><td bgcolor=\"yellow\"><a TARGET=_blank href=\"$circurl&KatKeySearch=$titidn\">$ausleihstring</a></td>";
	  }
	}
      }

#      print "</table></td></tr></table>\n";
    }
    else {
      @circexemplarliste=();
    }

#    print "<p>\n<!-- Title ends here -->\n";

      # Ausgabe der Buchinformationen anhand der ISBN
      
      if ($bookinfo){
      my @bookinfobuffer=();
      my $bookinfoidx=0;
      $bookinfobuffer[$bookinfoidx++]="<p>\n<table>\n";
      $bookinfobuffer[$bookinfoidx++]="<tr><td bgcolor=\"lightblue\" colspan=3><b>Beschreibung dieses Buches</b></td></tr>\n";
      
      my $biquelle;
      my $biisbn=$isbn;

      $biisbn=~s/-//g;
      $biisbn=~s/_//g;
      $biisbn=~s/x/X/g;

      my $biinfo;

      # Hier kommen die extra Passworte fuer die BuchinfoDB

      #   $ratecount=1;
      my $bidbh=DBI->connect("DBI:$config{dbimodule}:dbname=bookinfo;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or die "could not connect";          
      
      my $birequest;
      
      $birequest="select * from bookinfo where isbn = ?";
      
      my $biresult=$bidbh->prepare($birequest) or $logger->error($DBI::errstr);
      
      $biresult->execute($biisbn) or $logger->error($DBI::errstr);
      
      my $bookcounter;
      while(($biisbn,$biquelle,$biinfo)=$biresult->fetchrow()){
	
	$bookinfobuffer[$bookinfoidx++]="<tr><td colspan=3>$biinfo</td></tr>\n";
	$bookinfobuffer[$bookinfoidx++]="<tr><td bgcolor=\"lightblue\" colspan=3><b>Quelle: $biquelle</b></td></tr>\n";
	
	$biresult->finish();
	
	#      $avgrating=$avgrating/$ratcount;
	
	#	  print "<tr><td bgcolor=\"lightblue\" colspan=2>Durchschnittliche Bewertung</td><td bgcolor=\"lightblue\">$avgrating</td></tr>\n";
	$bookcounter++;

	$bidbh->disconnect;
      }

      $bookinfobuffer[$bookinfoidx++]="</table>\n";

      if ($bookcounter){
	my $k=0;
	while ($k<$bookinfoidx){
#	  print $bookinfobuffer[$k];
	  $k++;
	}
      }
    }

    # Ausgabe der Nutzer-Bewertungen f"ur ein Buch

    if ($rating){
 #     print "<p>\n<table>\n";
 #     print "<tr><td bgcolor=\"lightblue\" colspan=3><b>Bewertungen dieses Buches</b> - von Nutzern f&uuml;r Nutzer</td></tr>\n";
      
      #  my $avgrating;
      my $ratcount;
      my $rdate;
      my $rtidn;
      my $ridn;
      my $rname;
      my $rurl;
      my $rsubject;
      my $rrating;
      my $rmeinung;
      
      #   $ratecount=1;
      my $rdbh=DBI->connect("DBI:$config{dbimodule}:rating:$config{dbhost}:$config{dbport}", undef, undef) or die "could not connect";          
      
      
      my $rrequest;
      
      $rrequest="select * from rating where titidn = ?";
      
      my $rresult=$rdbh->prepare($rrequest) or $logger->error($DBI::errstr);
      
      
      $rresult->execute($titres1->{idn}) or $logger->error($DBI::errstr);
      
      while (($ridn,$rtidn,$rdate,$rname,$rurl,$rsubject,$rrating,$rmeinung)=$rresult->fetchrow){	    
	
#	print "<tr><td><b>$rname<b></td><td><b>$rsubject</b></td><td><b>$rrating</b></td></tr>\n";
	
#	print "<tr><td colspan=3>$rmeinung</td></tr>\n";
#	print "<tr><td bgcolor=\"lightblue\" colspan=3>&nbsp;</td></tr>\n";
	$ratcount++;
      }
      $rresult->finish();
      
#      #      $avgrating=$avgrating/$ratcount;
      if (!$ratcount){
#	print "<tr><td bgcolor=\"lightblue\" colspan=3>Es wurden noch keine Bewertungen abgegeben</td></tr>\n";
      }
#      #	  print "<tr><td bgcolor=\"lightblue\" colspan=2>Durchschnittliche Bewertung</td><td bgcolor=\"lightblue\">$avgrating</td></tr>\n";
      
#      print "</table>\n";
#      print "Wenn Sie ihre Meinung zu diesem Buch abgeben wollen, so klicken sie bitte <a href=\"/cgi-bin/biblio-rating.pl?titidn=$titres1->{idn};database=$database;action=mask\"><b>hier</b></a>\n";

    }

    $titresult1->finish();


  # Wenn ein Kategoriemapping fuer diesen Katalog existiert, dann muss 
  # dieses angewendet werden
  
  if (exists $config{categorymapping}{$database}){
    for (my $i=0; $i<=$#normset; $i++){
      my $normdesc=$normset[$i]{desc};
      
      # Wenn fuer diese Kategorie ein Mapping existiert, dann anwenden
      if (exists $config{categorymapping}{$database}{$normdesc}){
	$normset[$i]{desc}=$config{categorymapping}{$database}{$normdesc};
      }
    }
  }
  
  return (\@normset,\@mexnormset,\@circexemplarliste);
}	    



#####################################################################
## get_mex_by_idn(mexidn,mode): Gebe zu mexidn geh"oerenden 
##                              Exemplardatenstammsatz aus
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

sub get_mex_by_idn {

    my ($mexidn,$dbh,$searchmode,$circ,$circurl,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rsigel,$rdbases,$rbibinfo,$sessionID)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    # 
	
    my $mexstatement1="select * from mex where idn = ?";
    my $mexstatement2="select * from mexsign where mexidn = ?";
    my $atime;
    my $btime;
    my $timeall;
    
    my %sigel=%$rsigel;
    my %dbases=%$rdbases;
    my %bibinfo=%$rbibinfo;

    my @requests=("select titidn from mex where idn = $mexidn");
    my @verkntit=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $mexresult1=$dbh->prepare("$mexstatement1") or $logger->error($DBI::errstr);
    $mexresult1->execute($mexidn) or $logger->error($DBI::errstr);
    my $mexres1=$mexresult1->fetchrow_hashref;    

    my $sigel=$mexres1->{'sigel'};
    my $standort=$mexres1->{'standort'} || " - ";
    my $inventarnummer=$mexres1->{'invnr'} || " - ";
    my $erschverl=$mexres1->{'erschverl'} || " - ";
    my $buchung=$mexres1->{'buchung'} || " - ";
    my $fallig=$mexres1->{'fallig'} || " - ";
    my $ida=$mexres1->{'ida'};
    my $verbnr=$mexres1->{'verbnr'};
    my $lokfn=$mexres1->{'lokfn'};
    my $titidn1=$mexres1->{'titidn'};

    $mexresult1->finish();

    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $mexstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    my $bibliothek="";

    # Ein im Exemplar-Datensatz gefundenes Sigel geht vor
    
    if (length($sigel)>0){
      
      if (exists $sigel{$sigel}){
	$bibliothek=$sigel{$sigel};
      }
      else{
	$bibliothek="Unbekannt (38/$sigel)";
      }
    }
    else {
      if (exists $sigel{$dbases{$database}}){
	$bibliothek=$sigel{$dbases{$database}};
      }
      else{
	$bibliothek="Unbekannt (38/$sigel)";
      }
    }
    
    my $bibinfourl="";
    
    if (exists $bibinfo{$sigel}){
      $bibinfourl=$bibinfo{$sigel};
    }
    else {
      $bibinfourl="http://www.ub.uni-koeln.de/dezkat/bibfuehrer.html";
    }
    
    my $mexresult2=$dbh->prepare("$mexstatement2") or $logger->error($DBI::errstr);
    $mexresult2->execute($mexidn) or $logger->error($DBI::errstr);
    
    if ($mexresult2->rows == 0){
      
      print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td>$inventarnummer</td><td> - </td>";
      #print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td> - </td>";
      
      print "<td>$erschverl</td>";

      print "</tr>\n";
    }
    else {
      my @mexres2;
      while (@mexres2=$mexresult2->fetchrow){
	my $signatur=$mexres2[1];
	my $titidn=$verkntit[0];
	print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td>$inventarnummer</td><td><strong><span id=\"rlsignature\">$signatur</span></strong></td>";
	#print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td><strong><span id=\"rlsignature\">$signatur</span></strong></td>";
	
	print "<td>$erschverl</td>";
	
	print "</tr>\n";
      }    
    }
    
    $mexresult2->finish();
  }

sub get_mex_set_by_idn {

  my ($mexidn,$dbh,$searchmode,$circ,$circurl,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rsigel,$rdbases,$rbibinfo,$sessionID,$rmexnormset)=@_;
  
  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my $mexstatement1="select * from mex where idn = ?";
  my $mexstatement2="select * from mexsign where mexidn = ?";
  my $atime;
  my $btime;
  my $timeall;
  
  my %sigel=%$rsigel;
  my %dbases=%$rdbases;
  my %bibinfo=%$rbibinfo;
  
  my @requests=("select titidn from mex where idn = $mexidn");
  my @verkntit=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $mexresult1=$dbh->prepare("$mexstatement1") or $logger->error($DBI::errstr);
  $mexresult1->execute($mexidn) or $logger->error($DBI::errstr);
  my $mexres1=$mexresult1->fetchrow_hashref;    
  
  my $sigel=$mexres1->{'sigel'};
  my $standort=$mexres1->{'standort'} || " - ";
  my $inventarnummer=$mexres1->{'invnr'} || " - ";
  my $erschverl=$mexres1->{'erschverl'} || " - ";
  my $buchung=$mexres1->{'buchung'} || " - ";
  my $fallig=$mexres1->{'fallig'} || " - ";
  my $ida=$mexres1->{'ida'};
  my $verbnr=$mexres1->{'verbnr'};
  my $lokfn=$mexres1->{'lokfn'};
  my $titidn1=$mexres1->{'titidn'};
  
  $mexresult1->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $mexstatement1 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  my $bibliothek="";
  
  # Ein im Exemplar-Datensatz gefundenes Sigel geht vor
  
  if (length($sigel)>0){
    
    if (exists $sigel{$sigel}){
      $bibliothek=$sigel{$sigel};
    }
    else{
      $bibliothek="Unbekannt (38/$sigel)";
    }
  }
  else {
    if (exists $sigel{$dbases{$database}}){
      $bibliothek=$sigel{$dbases{$database}};
    }
    else{
      $bibliothek="Unbekannt (38/$sigel)";
    }
  }
  
  my $bibinfourl="";
  
  if (exists $bibinfo{$sigel}){
    $bibinfourl=$bibinfo{$sigel};
  }
  else {
    $bibinfourl="http://www.ub.uni-koeln.de/dezkat/bibfuehrer.html";
  }
  
  my $mexresult2=$dbh->prepare("$mexstatement2") or $logger->error($DBI::errstr);
  $mexresult2->execute($mexidn) or $logger->error($DBI::errstr);
  
  # Keine Signatur am Exemplarsatz
  
  if ($mexresult2->rows == 0){
    my %mex=();
    $mex{bibinfourl}=$bibinfourl;
    $mex{bibliothek}=$bibliothek;
    $mex{standort}=$standort;
    $mex{inventarnummer}=$inventarnummer;
    $mex{signatur}="-";
    $mex{erschverl}=$erschverl;
#      print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td>$inventarnummer</td><td> - </td>";
#      #print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td> - </td>";
      
#      print "<td>$erschverl</td>";

#      print "</tr>\n";
      push @$rmexnormset,\%mex;
  }
    # Mindestens eine Signatur:
    # Es werden einzelne Zeilen fuer jede Signatur erzeugt
  else {
    my @mexres2;
    while (@mexres2=$mexresult2->fetchrow){
      my $signatur=$mexres2[1];
      
      my %mex=();
      $mex{bibinfourl}=$bibinfourl;
      $mex{bibliothek}=$bibliothek;
      $mex{standort}=$standort;
      $mex{inventarnummer}=$inventarnummer;
      $mex{signatur}=$signatur;
      $mex{erschverl}=$erschverl;
      push @$rmexnormset,\%mex;
      
#	print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td>$inventarnummer</td><td><strong><span id=\"rlsignature\">$signatur</span></strong></td>";
#	#print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td><strong><span id=\"rlsignature\">$signatur</span></strong></td>";
	
#	print "<td>$erschverl</td>";
	
#	print "</tr>\n";
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
    my $atime;
    my $btime;
    my $timeall;
    
    my @reqarray=@$rreqarray;

    my $numberrequest;
    foreach $numberrequest (@reqarray){

	if ($config{benchmark}){
	    $atime=new Benchmark;
	}
    
	my $numberresult=$dbh->prepare("$numberrequest") or $logger->error($DBI::errstr);
	$numberresult->execute() or $logger->error("Request: $numberrequest - ".$DBI::errstr);

	my @numberres;
	while (@numberres=$numberresult->fetchrow){
	    $metaidns{$numberres[0]}=1;
	}
	$numberresult->execute();
	$numberresult->finish();
	if ($config{benchmark}){
	    $btime=new Benchmark;
	    $timeall=timediff($btime,$atime);
	    $logger->info("Zeit fuer Nummer zu : $numberrequest : ist ".timestr($timeall));
	}
	
    }
    my $i=0;
    my $key;
    my $value;
    while (($key,$value)=each %metaidns){
	$idns[$i++]=$key;
    }
    
    return $#idns+1;
}

#####################################################################
## no_result(): Gebe Fehlermeldung aus, falls nichts in der Datenbank
##              gefunden wurde

sub no_result {

    print "<h1>Kein Treffer</h1>\n";
    print "Zu Ihrer Anfrage wurde nichts in der Datenbank gefunden\n";
}

#####################################################################
## print_warning(): Gebe Fehlermeldung aus

sub print_warning {
    my $warning=shift @_;

    print "<h1>Achtung!</h1>\n";
    print "$warning";
}


#####################################################################
## input2sgml(line,initialsearch,withumlaut): Wandle die Eingabe line 
##                   nach SGML um wenn die 
##                   Anfangs-Suche via SQL-Datenbank stattfindet
##                   Keine Umwandlung bei Anfangs-Suche

sub input2sgml {
  my ($line,$initialsearch,$withumlaut)=@_;

  # Bei der initialen Suche via Volltext wird eine Normierung auf
  # ausgeschriebene Umlaute und den Grundbuchstaben bei Diakritika
  # vorgenommen
 
  if ($initialsearch) { 
    $line=~s/�/ue/g; 
    $line=~s/�/ae/g;
    $line=~s/�/oe/g;
    $line=~s/�/Ue/g;
    $line=~s/�/Ae/g;
    $line=~s/�/Oe/g;
    $line=~s/�/ss/g; 
    
    # Weitere Diakritika
    
    $line=~s/�/e/g;
    $line=~s/�/a/g;
    $line=~s/�/o/g;
    $line=~s/�/u/g;
    $line=~s/�/e/g;
    $line=~s/�/a/g;
    $line=~s/�/o/g;
    $line=~s/�/u/g;
    $line=~s/�/e/g;
    $line=~s/�/E/g;
    $line=~s/�/a/g;
    $line=~s/�/a/g;
    $line=~s/�/i/g;
    $line=~s/�/I/g;
    $line=~s/�/o/g;
    $line=~s/�/O/g;
    $line=~s/�/u/g;
    $line=~s/�/U/g;
    $line=~s/�/y/g;
    $line=~s/�/Y/g;
    
    if ($line=~/\"/){
      $line=~s/`/ /g;
    }
    else {
      $line=~s/`/ +/g;
    }
    return $line;
  }
  
  $line=~s/�/\&uuml\;/g;	
  $line=~s/�/\&auml\;/g;
  $line=~s/�/\&ouml\;/g;
  $line=~s/�/\&Uuml\;/g;
  $line=~s/�/\&Auml\;/g;
  $line=~s/�/\&Ouml\;/g;
  $line=~s/�/\&szlig\;/g;
  
  $line=~s/�/\&Eacute\;/g;	
  $line=~s/�/\&Egrave\;/g;	
  $line=~s/�/\&Ecirc\;/g;	
  $line=~s/�/\&Aacute\;/g;	
  $line=~s/�/\&Agrave\;/g;	
  $line=~s/�/\&Acirc\;/g;	
  $line=~s/�/\&Oacute\;/g;	
  $line=~s/�/\&Ograve\;/g;	
  $line=~s/�/\&Ocirc\;/g;	
  $line=~s/�/\&Uacute\;/g;	
  $line=~s/�/\&Ugrave\;/g;	
  $line=~s/�/\&Ucirc\;/g;	
  $line=~s/�/\&Iacute\;/g;     
  $line=~s/�/\&Igrave\;/g;	
  $line=~s/�/\&Icirc\;/g;	
  $line=~s/�/\&Ntilde\;/g;	
  $line=~s/�/\&Otilde\;/g;	
  $line=~s/�/\&Atilde\;/g;	
  
  $line=~s/�/\&eacute\;/g;	
  $line=~s/�/\&egrave\;/g;	
  $line=~s/�/\&ecirc\;/g;	
  $line=~s/�/\&aacute\;/g;	
  $line=~s/�/\&agrave\;/g;	
  $line=~s/�/\&acirc\;/g;	
  $line=~s/�/\&oacute\;/g;	
  $line=~s/�/\&ograve\;/g;	
  $line=~s/�/\&ocirc\;/g;	
  $line=~s/�/\&uacute\;/g;	
  $line=~s/�/\&ugrave\;/g;	
  $line=~s/�/\&ucirc\;/g;	
  $line=~s/�/\&iacute\;/g;     
  $line=~s/�/\&igrave\;/g;	
  $line=~s/�/\&icirc\;/g;	
  $line=~s/�/\&ntilde\;/g;	
  $line=~s/�/\&otilde\;/g;	
  $line=~s/�/\&atilde\;/g;	
  
  $line=~s/\"u/\&uuml\;/g;
  $line=~s/\"a/\&auml\;/g;
  $line=~s/\"o/\&ouml\;/g;
  $line=~s/\"U/\&Uuml\;/g;
  $line=~s/\"A/\&Auml\;/g;
  $line=~s/\"O/\&Ouml\;/g;
  $line=~s/\"s/\&szlig\;/g;
  $line=~s/\'/\\'/g;
  $line=~s/\*/\%/g;
  return $line;		# 
}

sub print_url_category {

  my ($name,$url,$contents)=@_;

  print << "CATEGORY";
<tr><td bgcolor="lightblue"><strong>$name</strong></td><td><a href="$url">$contents</td></tr>
CATEGORY

  return;
}

sub print_url_category_global {

  my ($name,$url,$contents,$type,$sorttype,$sessionID)=@_;

  my $globalcontents=$contents;

  $globalcontents=~s/<\/a>//;
  $globalcontents=~s/�//g;
  $globalcontents=~s/\"//g;

#  if ($type eq "swt"){
#    $globalcontents=~s/&lt;/</g;
#    $globalcontents=~s/&gt;/>/g;
    
#  }
#  else {
    $globalcontents=~s/&lt;//g;
    $globalcontents=~s/&gt;//g;
    $globalcontents=~s/<//g;
    $globalcontents=~s/>//g;
#  }

  # Sonderzeichen

  # Caron

  $globalcontents=~s/\&#353\;/s/g; # s hacek
  $globalcontents=~s/\&#352\;/S/g; # S hacek
  $globalcontents=~s/\&#269\;/c/g; # c hacek
  $globalcontents=~s/\&#268\;/C/g; # C hacek
  $globalcontents=~s/\&#271\;/d/g; # d hacek
  $globalcontents=~s/\&#270\;/D/g; # D hacek
  $globalcontents=~s/\&#283\;/e/g; # e hacek
  $globalcontents=~s/\&#282\;/E/g; # E hacek
  $globalcontents=~s/\&#318\;/l/g; # l hacek
  $globalcontents=~s/\&#317\;/L/g; # L hacek
  $globalcontents=~s/\&#328\;/n/g; # n hacek
  $globalcontents=~s/\&#327\;/N/g; # N hacek
  $globalcontents=~s/\&#345\;/r/g; # r hacek
  $globalcontents=~s/\&#344\;/R/g; # R hacek
  $globalcontents=~s/\&#357\;/t/g; # t hacek
  $globalcontents=~s/\&#356\;/T/g; # T hacek
  $globalcontents=~s/\&#382\;/n/g; # n hacek
  $globalcontents=~s/\&#381\;/N/g; # N hacek
  
  # Macron
  
  $globalcontents=~s/\&#275\;/e/g; # e oberstrich
  $globalcontents=~s/\&#274\;/E/g; # e oberstrich
  $globalcontents=~s/\&#257\;/a/g; # a oberstrich
  $globalcontents=~s/\&#256\;/A/g; # A oberstrich
  $globalcontents=~s/\&#299\;/i/g; # i oberstrich
  $globalcontents=~s/\&#298\;/I/g; # I oberstrich
  $globalcontents=~s/\&#333\;/o/g; # o oberstrich
  $globalcontents=~s/\&#332\;/O/g; # O oberstrich
  $globalcontents=~s/\&#363\;/u/g; # u oberstrich
  $globalcontents=~s/\&#362\;/U/g; # U oberstrich
  
  #$globalcontents=~s/ /\+/g;
  $globalcontents=~s/,/%2C/g;
  $globalcontents=~s/\[.+?\]//;
  $globalcontents=~s/ $//g;
  #$globalcontents=~s/ /\+/g;
  $globalcontents=~s/ /%20/g;

  my $globalurl="";

  if ($type eq "swt"){
    $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=;hst=;swt=%22$globalcontents%22;kor=;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In+allen+Katalogen+suchen";
  }

  if ($type eq "kor"){
    $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=;hst=;swt=;kor=%22$globalcontents%22;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In%20allen%20Katalogen%20suchen";
  }

  if ($type eq "verf"){
    $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=%22$globalcontents%22;hst=;swt=;kor=;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In+allen+Katalogen+suchen";
  }

  print << "CATEGORY";
<tr><td bgcolor="lightblue"><strong>$name</strong></td><td><a href="$globalurl" title="Begriff in allen Katalogen suchen"><span style="font-family:Arial,helv,Helvetica,Verdana; font-size:135%; color=blue;">G</span></a>&nbsp;<a href="$url" title="Begriff in diesem Katalog suchen">$contents</td></tr>
CATEGORY

  return;
}

sub get_global_contents {
  my ($globalcontents)=@_;

  $globalcontents=~s/<\/a>//;
  $globalcontents=~s/�//g;
  $globalcontents=~s/\"//g;

  $globalcontents=~s/&lt;//g;
  $globalcontents=~s/&gt;//g;
  $globalcontents=~s/<//g;
  $globalcontents=~s/>//g;

  # Caron

  $globalcontents=~s/\&#353\;/s/g; # s hacek
  $globalcontents=~s/\&#352\;/S/g; # S hacek
  $globalcontents=~s/\&#269\;/c/g; # c hacek
  $globalcontents=~s/\&#268\;/C/g; # C hacek
  $globalcontents=~s/\&#271\;/d/g; # d hacek
  $globalcontents=~s/\&#270\;/D/g; # D hacek
  $globalcontents=~s/\&#283\;/e/g; # e hacek
  $globalcontents=~s/\&#282\;/E/g; # E hacek
  $globalcontents=~s/\&#318\;/l/g; # l hacek
  $globalcontents=~s/\&#317\;/L/g; # L hacek
  $globalcontents=~s/\&#328\;/n/g; # n hacek
  $globalcontents=~s/\&#327\;/N/g; # N hacek
  $globalcontents=~s/\&#345\;/r/g; # r hacek
  $globalcontents=~s/\&#344\;/R/g; # R hacek
  $globalcontents=~s/\&#357\;/t/g; # t hacek
  $globalcontents=~s/\&#356\;/T/g; # T hacek
  $globalcontents=~s/\&#382\;/n/g; # n hacek
  $globalcontents=~s/\&#381\;/N/g; # N hacek
  
  # Macron
  
  $globalcontents=~s/\&#275\;/e/g; # e oberstrich
  $globalcontents=~s/\&#274\;/E/g; # e oberstrich
  $globalcontents=~s/\&#257\;/a/g; # a oberstrich
  $globalcontents=~s/\&#256\;/A/g; # A oberstrich
  $globalcontents=~s/\&#299\;/i/g; # i oberstrich
  $globalcontents=~s/\&#298\;/I/g; # I oberstrich
  $globalcontents=~s/\&#333\;/o/g; # o oberstrich
  $globalcontents=~s/\&#332\;/O/g; # O oberstrich
  $globalcontents=~s/\&#363\;/u/g; # u oberstrich
  $globalcontents=~s/\&#362\;/U/g; # U oberstrich
  
  #$globalcontents=~s/ /\+/g;
  $globalcontents=~s/,/%2C/g;
  $globalcontents=~s/\[.+?\]//;
  $globalcontents=~s/ $//g;
  #$globalcontents=~s/ /\+/g;
  $globalcontents=~s/ /%20/g;


  return $globalcontents;
}

sub print_simple_category {

  my ($name,$contents)=@_;

  # Sonderbehandlung fuer bestimmte Kategorien
  
  if ($name eq "ISSN"){
    my $ezbquerystring=$config{ezb_exturl}."&jq_term1=".$contents;

    $contents="$contents (<a href=\"$ezbquerystring\" title=\"Verf�gbarkeit in der Elektronischen Zeitschriften Bibliothek (EZB) &uuml;berpr&uuml;fen\" target=ezb>als E-Journal der Uni-K&ouml;ln verf&uuml;gbar?</a>)";
  }

  # Ausgabe

  print << "CATEGORY";
<tr><td bgcolor="lightblue"><strong>$name</strong></td><td>$contents</td></tr>
CATEGORY

  return;
}

sub print_inst_head {
  my ($database,$type,$sessionID,$titidn)=@_;


  if ($type eq "base"){
    print << "INSTHEAD";
<table BORDER=0 CELLSPACING=0 CELLPADDING=0 width="100%">
  <tr bgcolor="lightblue">
    <td  width="20">&nbsp;</td><td valign="middle" ALIGN=left height="32"><img src="/images/openbib/$database.png"></td>
  </tr>
</table>
INSTHEAD
}
  elsif ($type eq "extended"){
    print << "INSTHEAD";
<table  BORDER=0 CELLSPACING=0 CELLPADDING=0 width="100%">
  <tr bgcolor="lightblue">
    <td width="20">&nbsp;</td>
    <td valign="middle" ALIGN=left height="32"><img src="/images/openbib/$database.png"></td>
      <td>&nbsp;</td>
      <td bgcolor=white align=right width=180>
	<a href=\"$config{managecollection_loc}?sessionID=$sessionID;action=insert;database=$database;singleidn=$titidn\" target=\"header\" title=\"In die Merkliste\"><img src="/images/openbib/3d-file-blue-clipboard.png" height="29" alt="In die Merkliste" border=0></a>&nbsp;
        <a href=\"$config{managecollection_loc}?sessionID=$sessionID;action=mail;database=$database;singleidn=$titidn\" target=\"body\" title=\"Als Mail verschicken\"><img src="/images/openbib/3d-file-blue-mailbox.png" height="29" alt="Als Mail verschicken" border=0></a>&nbsp;
        <a href=\"$config{managecollection_loc}?sessionID=$sessionID;action=save;database=$database;singleidn=$titidn\" target=\"save\" title=\"Abspeichern\"><img src="/images/openbib/3d-file-blue-disk35.png" height="29" alt="Abspeichern" border=0></a>&nbsp;
        <a href=\"$config{managecollection_loc}?sessionID=$sessionID;action=print;database=$database;singleidn=$titidn\" target=\"print\" title=\"Ausdrucken\"><img src="/images/openbib/3d-file-blue-printer.png" height="29" alt="Ausdrucken" border=0></a>&nbsp;
       </td>
  </tr>
</table>
INSTHEAD

  }
  return;
}

sub print_mult_sel_form {
  my ($searchmode,$hitrange,$rating,$bookinfo,$database,$sessionID)=@_;

print << "SEL_FORM_HEAD";
<form method="get" action="$config{search_loc}">
<input type=hidden name=searchmode value=$searchmode>
<input type=hidden name=hitrange value=$hitrange>
<input type=hidden name=rating value=$rating>
<input type=hidden name=bookinfo value=$bookinfo>
<input type=hidden name=database value=$database>
<input type=hidden name=sessionID value=$sessionID>
SEL_FORM_HEAD

  return;
}

sub set_simple_category {

  my ($desc,$contents)=@_;

  # UTF8-Behandlung

  $desc=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
  $contents=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 


  # Sonderbehandlung fuer bestimmte Kategorien
  
  if ($desc eq "ISSN"){
    my $ezbquerystring=$config{ezb_exturl}."&jq_term1=".$contents;

    $contents="$contents (<a href=\"$ezbquerystring\" title=\"Verf�gbarkeit in der Elektronischen Zeitschriften Bibliothek (EZB) &uuml;berpr&uuml;fen\" target=ezb>als E-Journal der Uni-K&ouml;ln verf&uuml;gbar?</a>)";
  }

  my %kat=();
  $kat{'type'}="simple_category";
  $kat{'desc'}=$desc;
  $kat{'contents'}=$contents;
  
  return \%kat;
}

sub set_url_category {

  my ($desc,$url,$contents,$supplement)=@_;

  $supplement="" unless defined ($supplement);
  
  # UTF8-Behandlung

  $desc      =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
  $url       =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
  $contents  =~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
  $supplement=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 

  my %kat=();
  $kat{'type'}="url_category";
  $kat{'desc'}=$desc;
  $kat{'url'}=$url;
  $kat{'contents'}=$contents;
  $kat{'supplement'}=$supplement;

  return \%kat;
}

sub set_url_category_global {

  my ($desc,$url,$contents,$supplement,$type,$sorttype,$sessionID)=@_;

  $supplement="" unless defined ($supplement);
  
  # UTF8-Behandlung

  $desc=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
  $url=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
  $contents=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
  $supplement=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 

  my $globalcontents=$contents;

  $globalcontents=~s/<\/a>//;
  $globalcontents=~s/�//g;
  $globalcontents=~s/\"//g;

#  if ($type eq "swt"){
#    $globalcontents=~s/&lt;/</g;
#    $globalcontents=~s/&gt;/>/g;
    
#  }
#  else {
    $globalcontents=~s/&lt;//g;
    $globalcontents=~s/&gt;//g;
    $globalcontents=~s/<//g;
    $globalcontents=~s/>//g;
#  }

  # Sonderzeichen

  # Caron

  $globalcontents=~s/\&#353\;/s/g; # s hacek
  $globalcontents=~s/\&#352\;/S/g; # S hacek
  $globalcontents=~s/\&#269\;/c/g; # c hacek
  $globalcontents=~s/\&#268\;/C/g; # C hacek
  $globalcontents=~s/\&#271\;/d/g; # d hacek
  $globalcontents=~s/\&#270\;/D/g; # D hacek
  $globalcontents=~s/\&#283\;/e/g; # e hacek
  $globalcontents=~s/\&#282\;/E/g; # E hacek
  $globalcontents=~s/\&#318\;/l/g; # l hacek
  $globalcontents=~s/\&#317\;/L/g; # L hacek
  $globalcontents=~s/\&#328\;/n/g; # n hacek
  $globalcontents=~s/\&#327\;/N/g; # N hacek
  $globalcontents=~s/\&#345\;/r/g; # r hacek
  $globalcontents=~s/\&#344\;/R/g; # R hacek
  $globalcontents=~s/\&#357\;/t/g; # t hacek
  $globalcontents=~s/\&#356\;/T/g; # T hacek
  $globalcontents=~s/\&#382\;/n/g; # n hacek
  $globalcontents=~s/\&#381\;/N/g; # N hacek
  
  # Macron
  
  $globalcontents=~s/\&#275\;/e/g; # e oberstrich
  $globalcontents=~s/\&#274\;/E/g; # e oberstrich
  $globalcontents=~s/\&#257\;/a/g; # a oberstrich
  $globalcontents=~s/\&#256\;/A/g; # A oberstrich
  $globalcontents=~s/\&#299\;/i/g; # i oberstrich
  $globalcontents=~s/\&#298\;/I/g; # I oberstrich
  $globalcontents=~s/\&#333\;/o/g; # o oberstrich
  $globalcontents=~s/\&#332\;/O/g; # O oberstrich
  $globalcontents=~s/\&#363\;/u/g; # u oberstrich
  $globalcontents=~s/\&#362\;/U/g; # U oberstrich
  
  #$globalcontents=~s/ /\+/g;
  $globalcontents=~s/,/%2C/g;
  $globalcontents=~s/\[.+?\]//;
  $globalcontents=~s/ $//g;
  #$globalcontents=~s/ /\+/g;
  $globalcontents=~s/ /%20/g;

  my $globalurl="";

  if ($type eq "swt"){
    $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=;hst=;swt=%22$globalcontents%22;kor=;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In+allen+Katalogen+suchen";
  }

  if ($type eq "kor"){
    $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=;hst=;swt=;kor=%22$globalcontents%22;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In%20allen%20Katalogen%20suchen";
  }

  if ($type eq "verf"){
    $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID;hitrange=-1;swtindexall=;verf=%22$globalcontents%22;hst=;swt=;kor=;sign=;isbn=;notation=;verknuepfung=und;ejahr=;ejahrop=genau;maxhits=200;sorttype=$sorttype;searchall=In+allen+Katalogen+suchen";
  }

  my %kat=();
  $kat{'type'}="url_category_global";
  $kat{'desc'}=$desc;
  $kat{'url'}=$url;
  
  $kat{'globalurl'}=$globalurl;
  $kat{'contents'}=$contents;
  $kat{'supplement'}=$supplement;

  return \%kat;
}

sub get_result_navigation {
  my ($sessiondbh,$database,$titidn,$sessionID,$searchmode,$rating,$bookinfo,$hitrange,$sortorder,$sorttype)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  # Bestimmen des vorigen und naechsten Treffer einer
  # vorausgegangenen Kurztitelliste
  
  my $sessionresult=$sessiondbh->prepare("select lastresultset from session where sessionid = ?") or $logger->error($DBI::errstr);
  $sessionresult->execute($sessionID) or $logger->error($DBI::errstr);
  
  my $result=$sessionresult->fetchrow_hashref();
  my $lastresultstring="";
  
  if ($result->{'lastresultset'}){
    $lastresultstring=$result->{'lastresultset'};
  }
  
  $sessionresult->finish();
  
  my $lasttiturl="";
  my $nexttiturl="";
  
  if ($lastresultstring=~m/(\w+:\d+)\|$database:$titidn/){
    $lasttiturl=$1;
    my ($lastdatabase,$lastkatkey)=split(":",$lasttiturl);
    $lasttiturl="$config{search_loc}?sessionID=$sessionID;search=Mehrfachauswahl;searchmode=$searchmode;rating=$rating;bookinfo=$bookinfo;hitrange=$hitrange;sorttype=$sorttype;sortorder=$sortorder;database=$lastdatabase;searchsingletit=$lastkatkey";
  }
    
  if ($lastresultstring=~m/$database:$titidn\|(\w+:\d+)/){
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

  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }

  $swt=OpenBib::Search::Util::input2sgml($swt,1,0);

  $swt=~s/\*$//;

  my @requests=("select schlagw from swt where schlagwnorm like '$swt%' order by schlagw");
  my @temp=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  
  my @schlagwte=sort @temp;
    
  my @swtindex=();

  for (my $i=0; $i <= $#schlagwte; $i++){
    my $schlagw=$schlagwte[$i];
    @requests=("select idn from swt where schlagw = '$schlagw'");
    my @swtidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
    foreach my $swtidn (@swtidns){
      @requests=("select titidn from titswtlok where swtverw=$swtidn");
      my $titanzahl=OpenBib::Search::Util::get_number(\@requests,$dbh);
      
      my $swtitem={
		   swt       => $schlagw,
		   swtidn    => $swtidn,
		   titanzahl => $titanzahl, 
		  };
      
      push @swtindex, $swtitem;
    }
  }

  if ($config{benchmark}){
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

  my ($swt,$dbh,$sessiondbh,$searchmode,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rdbinfo,$rtiteltyp,$rsigel,$rdbases,$rbibinfo,$sessionID,$r,$stylesheet,$view)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my $swtindex=OpenBib::Search::Util::get_index_by_swt($swt,$dbh);

  my %sigel=%$rsigel;
  my %dbases=%$rdbases;

  my $poolname=$sigel{$dbases{$database}};

  # TT-Data erzeugen
  
  my $ttdata={
	      view       => $view,
	      stylesheet => $stylesheet,
	      sessionID  => $sessionID,
	      
	      database => $database,
	  
	      poolname => $poolname,

	      searchmode => $searchmode,
	      hitrange => $hitrange,
	      rating => $rating,
	      bookinfo => $bookinfo,
	      sessionID => $sessionID,
	
	      swt      => $swt,
	      swtindex => $swtindex,

	      utf2iso => sub {
		my $string=shift;
		$string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
		return $string;
	      },
	      
	      show_corporate_banner => 0,
	      show_foot_banner => 1,
	      config     => \%config,
	     };
  
  OpenBib::Common::Util::print_page($config{tt_search_showswtindex_tname},$ttdata,$r);

  return;

}

sub get_index_by_verf {
  my ($verf,$dbh)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }

  $verf=OpenBib::Search::Util::input2sgml($verf,1,0);

  $verf=~s/\*$//;
  
  my @requests=("select ans from aut where ansnorm like '$verf%' order by ans");
  my @temp=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  
  my @verfasser=sort @temp;
    
  my @verfindex=();

  for (my $i=0; $i <= $#verfasser; $i++){
    my $verfasser=$verfasser[$i];
    @requests=("select idn from aut where ans = '$verfasser'");
    my @verfidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

    foreach my $verfidn (@verfidns){
      @requests=("select titidn from titverf where verfverw=$verfidn","select titidn from titpers where persverw=$verfidn","select titidn from titgpers where persverw=$verfidn");
      my $titanzahl=OpenBib::Search::Util::get_number(\@requests,$dbh);
      
      my $verfitem={
		    verf       => $verfasser,
		    verfidn    => $verfidn,
		    titanzahl  => $titanzahl, 
		   };
      
      push @verfindex, $verfitem;
    }
  }

  if ($config{benchmark}){
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

  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }

  $kor=OpenBib::Search::Util::input2sgml($kor,1,0);

  $kor=~s/\*$//;
  
  my @requests=("select korans from kor where koransnorm like '$kor%'");
  my @temp=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
  
  my @koerperschaft=sort @temp;
    
  my @korindex=();

  for (my $i=0; $i <= $#koerperschaft; $i++){
    my $koerperschaft=$koerperschaft[$i];
    @requests=("select idn from kor where korans = '$koerperschaft'");
    my @koridns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);
    foreach my $koridn (@koridns){
      @requests=("select titidn from titkor where korverw=$koridn","select titidn from titurh where urhverw=$koridn");
      my $titanzahl=OpenBib::Search::Util::get_number(\@requests,$dbh);
      
      my $koritem={
		   kor       => $koerperschaft,
		   koridn    => $koridn,
		   titanzahl  => $titanzahl, 
		  };
      
      push @korindex, $koritem;
    }
  }

  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $#korindex Koerperschaften : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  return \@korindex;
}

sub initital_search_for_titidns {
  my ($fs,$verf,$hst,$hststring,$swt,$kor,$notation,$isbn,$issn,$sign,$ejahr,$ejahrop,$mart,$boolfs,$boolverf,$boolhst,$boolhststring,$boolswt,$boolkor,$boolnotation,$boolisbn,$boolissn,$boolsign,$boolejahr,$boolmart,$dbh,$maxhits)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $withumlaut=0;

  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }

  # Aufbau des sqlquerystrings

  my $sqlselect="";
  my $sqlfrom="";
  my $sqlwhere="";
  
  
  if ($fs){	
    my @fsidns;
    
    $fs=OpenBib::Search::Util::input2sgml($fs,1,$withumlaut);
    $fs="match (verf,hst,kor,swt,notation,sign,isbn,issn) against ('$fs' IN BOOLEAN MODE)";
  }
  
  if ($verf){	
    my @autidns;
    
    $verf=OpenBib::Search::Util::input2sgml($verf,1,$withumlaut);
    $verf="match (verf) against ('$verf' IN BOOLEAN MODE)";
  }
  
  my @tittit;
  
  if ($hst){
    $hst=OpenBib::Search::Util::input2sgml($hst,1,$withumlaut);
    $hst="match (hst) against ('$hst' IN BOOLEAN MODE)";
  }
  
  my @swtidns;
  
  if ($swt){
    $swt=OpenBib::Search::Util::input2sgml($swt,1,$withumlaut);
    $swt="match (swt) against ('$swt' IN BOOLEAN MODE)";
  }
  
  my @koridns;
  
  if ($kor){
    $kor=OpenBib::Search::Util::input2sgml($kor,1,$withumlaut);
    $kor="match (kor) against ('$kor' IN BOOLEAN MODE)";
  }
  
  my $notfrom="";
  my @notidns;
  
  # TODO: SQL-Statement fuer Notationssuche optimieren
  
  if ($notation){
    $notation=~s/\*$/%/;
    $notation=~s/\'/\\\'/g;
    $notation="((notation.notation like '$notation' or notation.benennung like '$notation') and search.verwidn=titnot.titidn and notation.idn=titnot.notidn)";
    $notfrom=", notation, titnot";
  }
  
  my $signfrom="";
  my @signidns;
  
  if ($sign){
    $sign=~s/\*$/%/;
    $sign="(search.verwidn=mex.titidn and mex.idn=mexsign.mexidn and mexsign.signlok like '$sign')";
    $signfrom=", mex, mexsign";
  }
  
  my @isbnidns;
  
  if ($isbn){
    $isbn=OpenBib::Search::Util::input2sgml($isbn,1,$withumlaut);
    $isbn=~s/-//g;
    $isbn="match (isbn) against ('$isbn' IN BOOLEAN MODE)";
  }
  
  my @issnidns;
  
  if ($issn){
    $issn=OpenBib::Search::Util::input2sgml($issn,1,$withumlaut);
    $issn=~s/-//g;
    $issn="match (issn) against ('$issn' IN BOOLEAN MODE)";
  }
  
  my @martidns;
  
  if ($mart){
    $mart=OpenBib::Search::Util::input2sgml($mart,1,$withumlaut);
    $mart="match (artinh) against ('$mart' IN BOOLEAN MODE)";
  }
  
  my @hststringidns;
  
  if ($hststring){
    $hststring=~s/\*$/%/;
    $hststring=OpenBib::Search::Util::input2sgml($hststring,1,$withumlaut);
    $hststring="(search.hststring like '$hststring')";
  }
  
  my $ejtest;
  
  ($ejtest)=$ejahr=~/.*(\d\d\d\d).*/;
  if (!$ejtest){
    $ejahr=""; # Nur korrekte Jahresangaben werden verarbeitet
  }              # alles andere wird ignoriert...
  
  if ($ejahr){	   
    $ejahr="$boolejahr ejahr".$ejahrop."$ejahr";
  }
  
  my @tidns;
  
  # Einfuegen der Boolschen Verknuepfungsoperatoren in die SQL-Queries
  
  if (($ejahr) && ($boolejahr eq "OR")){
    OpenBib::Search::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der UND-Verkn&uuml;pfung und mindestens einem weiteren angegebenen Suchbegriff m&ouml;glich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Ihr Verst&auml;ndnis f&uuml;r diese Ma&szlig;nahme");
    goto LEAVEPROG;
  }
  
  # SQL-Search
  
  my $notfirstsql=0;
  my $sqlquerystring="";
  
  if ($fs){
    $notfirstsql=1;
    $sqlquerystring=$fs;
  }
  if ($hst){
    if ($notfirstsql){
      $sqlquerystring.=" $boolhst ";
    }
    $notfirstsql=1;
    $sqlquerystring.=$hst;
  }
  if ($verf){
    if ($notfirstsql){
      $sqlquerystring.=" $boolverf ";
    }
    $notfirstsql=1;
    $sqlquerystring.=$verf;
  }
  if ($kor){
    if ($notfirstsql){
      $sqlquerystring.=" $boolkor ";
    }
    $notfirstsql=1;
    $sqlquerystring.=$kor;
  }
  if ($swt){
    if ($notfirstsql){
      $sqlquerystring.=" $boolswt ";
    }
    $notfirstsql=1;
    $sqlquerystring.=$swt;
  }
  if ($notation){
    if ($notfirstsql){
      $sqlquerystring.=" $boolnotation ";
    }
    $notfirstsql=1;
    $sqlquerystring.=$notation;
  }
  if ($isbn){
    if ($notfirstsql){
      $sqlquerystring.=" $boolisbn ";
    }
    $notfirstsql=1;
    $sqlquerystring.=$isbn;
  }
  if ($issn){
    if ($notfirstsql){
      $sqlquerystring.=" $boolissn ";
    }
    $notfirstsql=1;
    $sqlquerystring.=$issn;
  }
  if ($sign){
    if ($notfirstsql){
      $sqlquerystring.=" $boolsign ";
    }
    $notfirstsql=1;
    $sqlquerystring.=$sign;
  }
  if ($mart){
    if ($notfirstsql){
      $sqlquerystring.=" $boolmart ";
    }
    $notfirstsql=1;
    $sqlquerystring.=$mart;
  }
  if ($hststring){
    if ($notfirstsql){
      $sqlquerystring.=" $boolhststring ";
    }
      $notfirstsql=1;
    $sqlquerystring.=$hststring;
  }
  
  if ($ejahr){
    if ($sqlquerystring eq ""){
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
  
  @tidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

  $logger->info("Treffer: ".$#tidns);

  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : initital_search_for_titidns / $sqlquerystring -> $#tidns : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  return @tidns;
}

sub get_recent_titids {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$dbh->prepare("select idn as id,sdn as content from tit order by content desc limit $limit");
    $request->execute();

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

sub get_recent_titids_by_aut {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();


    $dbh->do("create temporary table autids (id int, index (id))");

    my $request=$dbh->prepare("insert into autids select titidn from titverf where verfverw = ? union select titidn from titpers where persverw = ? union select titidn from titgpers where persverw = ?");
    $request->execute($id,$id,$id);

    $request=$dbh->prepare("select tit.idn as id,tit.sdn as content from tit,autids where tit.idn=autids.id order by tit.sdn desc limit $limit");
    $request->execute();
    
#    my $request=$dbh->prepare("select tit.idn as id,tit.sdn as content from tit where tit.idn IN ( select titidn from titverf where verfverw = ? union select titidn from titpers where persverw = ? union select titidn from titgpers where persverw = ?) order by tit.sdn desc limit $limit");
#    $request->execute($id,$id,$id);

#    my $request=$dbh->prepare("select tit.idn as id,tit.sdn as content from tit,titverf,titpers,titgpers where (titverf.verfverw = ? and titverf.titidn = tit.idn) or (titpers.persverw = ? and titpers.titidn = tit.idn) or (titgpers.persverw = ? and titgpers.titidn=tit.idn) order by tit.sdn desc limit $limit");
#    my $request=$dbh->prepare("select tit.idn as id,tit.sdn as content from tit right join titverf ON (titverf.verfverw = ? and titverf.titidn = tit.idn) right join titpers on (titpers.persverw = ? and titpers.titidn = tit.idn) right join titgpers on (titgpers.persverw = ? and titgpers.titidn = tit.idn )  order by tit.sdn desc limit $limit");
#    $request->execute($id,$id,$id);



    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }

    $dbh->do("drop table autids");

    return \@titlist;
}

sub get_recent_titids_by_kor {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $dbh->do("create temporary table korids (id int, index (id))");

    my $request=$dbh->prepare("insert into korids select titidn from titkor where korverw = ? union select titidn from titurh where urhverw = ?");
    $request->execute($id,$id);

    $request=$dbh->prepare("select tit.idn as id,tit.sdn as content from tit,korids where tit.idn=korids.id order by tit.sdn desc limit $limit");
    $request->execute();
    
#    my $request=$dbh->prepare("select tit.idn as id,tit.sdn as content from tit where tit.idn IN ( select titidn from titkor where korverw = ? union select titidn from titurh where urhverw = ?) order by tit.sdn desc limit $limit");
#    $request->execute($id,$id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }

    $dbh->do("drop table korids");
    
    return \@titlist;
}

sub get_recent_titids_by_swt {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$dbh->prepare("select tit.idn as id,tit.sdn as content from tit,titswtlok where titswtlok.swtverw = ? and tit.idn = titswtlok.titidn  order by tit.sdn desc limit $limit");
    $request->execute($id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    return \@titlist;
}

sub get_recent_titids_by_not {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$dbh->prepare("select tit.idn as id,tit.sdn as content from tit,titnot where titnot.notidn = ? and tit.idn = titnot.titidn  order by tit.sdn desc limit $limit");
    $request->execute($id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    return \@titlist;
}

1;
