#####################################################################
#
#  OpenBib::Search::Util
#
#  Dieses File ist (C) 2004 Oliver Flimm <flimm@openbib.org>
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

use Log::Log4perl qw(get_logger :levels);

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
## get_aut_by_idn(autidn,mode,...): Gebe zu autidn geh"oerenden
##                                  Autorenstammsatz aus
##
## autidn: IDN des Autorenstammsatzes
## mode:   1 - Nur Ansetzungsform wird ausgegeben
##         2 - Gesamter Autorenstammsatz ausgeben
##         3 - Gesamter Autorenstammsatz + Anzahl verkn"upfter Titeldaten 
##             ausgeben
##         5 - Autor in Listenform ausgeben
##
## Und nun jede Menge Variablen, damit mod_perl keine Probleme macht
##
## $dbh
## $benchmark
## $searchmultipleaut
## $searchmode
## $showmexintit
## $casesensitive
## $hitrange
## $sorttype
## $database

sub get_aut_by_idn {

    my ($autidn,$mode,$dbh,$benchmark,$searchmultipleaut,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $autstatement1="select * from aut where idn=$autidn";
    my $autstatement2="select * from autverw where autidn=$autidn";

    my $atime;
    my $btime;
    my $timeall;

    if ($benchmark){
	$atime=new Benchmark;
    }

    my $autresult1=$dbh->prepare("$autstatement1") or $logger->error($DBI::errstr);
    $autresult1->execute() or $logger->error($DBI::errstr);

    my $autres1=$autresult1->fetchrow_hashref;

    $autresult1->finish();

    if ($benchmark){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $autstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($mode == 1){
	if ($autres1->{ans}){
	    return $autres1->{ans};
	}
	return;
    }

    if (($mode == 2)||($mode == 3)){
      print_inst_head($database,"base");

      print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
      
	if ($searchmultipleaut){
	    print "\n<hr>\n";
	}
	else {
#	    print "<h1>Gefundener Autor</h1>\n";
	}

	print "<table cellpadding=2>\n";
	print "<tr><td>Kategorie</td><td>Inhalt</td></tr>\n";
#	print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td></tr>\n";
	
	# Ausgabe diverser Informationen

	print_simple_category("Ident-Nr","$autres1->{idn}");
	print_simple_category("Ident-Alt","$autres1->{ida}") if ($autres1->{ida});
	print_simple_category("Versnr","$autres1->{versnr}") if ($autres1->{versnr});
	print_simple_category("Ansetzung","$autres1->{ans}") if ($autres1->{ans});
	print_simple_category("Pndnr","$autres1->{pndnr}") if ($autres1->{pndnr});
	print_simple_category("Verbnr","$autres1->{verbnr}") if ($autres1->{verbnr});

	if ($benchmark){
	    $atime=new Benchmark;
	}

	# Ausgabe der Verweisformen

	my $autresult2=$dbh->prepare("$autstatement2") or $logger->error($DBI::errstr);
	$autresult2->execute() or $logger->error($DBI::errstr);

	my $autres2;
	while ($autres2=$autresult2->fetchrow_hashref){
	  print_simple_category("Verweis","$autres2->{verw}");
	}    

	$autresult2->finish();

	if ($benchmark){
	    $btime=new Benchmark;
	    $timeall=timediff($btime,$atime);
	    $logger->info("Zeit fuer : $autstatement2 : ist ".timestr($timeall));
	    undef $atime;
	    undef $btime;
	    undef $timeall;
	}

    }

    if ($mode == 3){

      # Ausgabe der Anzahl verk"upfter Titel

	my @requests=("select titidn from titverf where verfverw=$autres1->{idn}","select titidn from titpers where persverw=$autres1->{idn}","select titidn from titgpers where persverw=$autres1->{idn}");
	my $titelnr=get_number(\@requests,$dbh);

	print_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&searchtitofaut=$autres1->{idn}","$titelnr</a>");

    }

    if ($mode == 5){

	print "<tr><td><input type=checkbox name=searchmultipleaut value=$autres1->{idn} ";
	print "></td><td>";
	print "<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;sorttype=$sorttype&amp;sortorder=$sortorder&amp;database=$database&amp;searchsingleaut=$autres1->{idn}&amp;generalsearch=searchsingleaut\">";
	print "<strong>$autres1->{ans}</strong></a></td></tr>\n";
	return;
    }
    print "</table>";
    return;
}

sub get_aut_ans_by_idn {

    my ($autidn,$dbh)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $autstatement1="select * from aut where idn=$autidn";

    my $atime;
    my $btime;
    my $timeall;

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $autresult1=$dbh->prepare("$autstatement1") or $logger->error($DBI::errstr);
    $autresult1->execute() or $logger->error($DBI::errstr);

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

    if ($autres1->{ans}){
      return $autres1->{ans};
    }
    return;
}

sub get_aut_set_by_idn {

    my ($autidn,$dbh,$searchmultipleaut,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $autstatement1="select * from aut where idn=$autidn";
    my $autstatement2="select * from autverw where autidn=$autidn";

    my $atime;
    my $btime;
    my $timeall;

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $autresult1=$dbh->prepare("$autstatement1") or $logger->error($DBI::errstr);
    $autresult1->execute();

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

    print_inst_head($database,"base");
    
    print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
    
    if ($searchmultipleaut){
      print "\n<hr>\n";
    }
    else {
      #	    print "<h1>Gefundener Autor</h1>\n";
    }
    
    print "<table cellpadding=2>\n";
    print "<tr><td>Kategorie</td><td>Inhalt</td></tr>\n";
    #	print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td></tr>\n";
    
    # Ausgabe diverser Informationen
    
    print_simple_category("Ident-Nr","$autres1->{idn}");
    print_simple_category("Ident-Alt","$autres1->{ida}") if ($autres1->{ida});
    print_simple_category("Versnr","$autres1->{versnr}") if ($autres1->{versnr});
    print_simple_category("Ansetzung","$autres1->{ans}") if ($autres1->{ans});
    print_simple_category("Pndnr","$autres1->{pndnr}") if ($autres1->{pndnr});
    print_simple_category("Verbnr","$autres1->{verbnr}") if ($autres1->{verbnr});
    
    if ($config{benchmark}){
      $atime=new Benchmark;
    }
    
    # Ausgabe der Verweisformen
    
    my $autresult2=$dbh->prepare("$autstatement2") or $logger->error($DBI::errstr);
    $autresult2->execute() or $logger->error($DBI::errstr);
    
    my $autres2;
    while ($autres2=$autresult2->fetchrow_hashref){
      print_simple_category("Verweis","$autres2->{verw}");
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
    
    print_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&searchtitofaut=$autres1->{idn}","$titelnr</a>");

    print "</table>";
    return;
}

#####################################################################
## get_kor_by_idn(koridn,mode,...): Gebe zu koridn geh"oerenden 
##                              K"orperschaftsstammsatz aus
##
## koridn: IDN des K"orperschaftsstammsatzes
## mode:   1 - Nur Ansetzungsform wird ausgegeben
##         2 - Gesamten K"orperschaftsstammsatz ausgeben
##         3 - Gesamter K"orperschaftsstammsatz + Anzahl verkn"upfter 
##             Titeldaten ausgeben
##         5 - Ansetzungsform in Suchzeile ausgeben
##
## Und nun jede Menge Variablen, damit mod_perl keine Probleme macht
##
## $dbh
## $benchmark
## $searchmultiplekor
## $searchmode
## $showmexintit
## $casesensitive
## $hitrange
## $sorttype
## $database

sub get_kor_by_idn {

    my ($koridn,$mode,$dbh,$benchmark,$searchmultiplekor,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $korstatement1="select * from kor where idn=$koridn";
    my $korstatement2="select * from korverw where koridn=$koridn";
    my $korstatement3="select * from korfrueh where koridn=$koridn";
    my $korstatement4="select * from korspaet where koridn=$koridn";
    my $atime;
    my $btime;
    my $timeall;

    if ($benchmark){
	$atime=new Benchmark;
    }

    my $korresult1=$dbh->prepare("$korstatement1") or $logger->error($DBI::errstr);
    $korresult1->execute() or $logger->error($DBI::errstr);

    my $korres1=$korresult1->fetchrow_hashref;
    $korresult1->finish();

    if ($benchmark){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $korstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }


    if ($mode == 1){
	if ($korres1->{korans}){
	    return $korres1->{korans};
	}
	return;
    }

    if (($mode == 2)||($mode == 3)){
      print_inst_head($database,"base");

      print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);

	if ($searchmultiplekor){
	    print "\n<hr>\n";
	}
	else{
#	    print "<h1>Gefundene K&ouml;rperschaft</h1>\n";
	}
	print "<table cellpadding=2>\n";
	print "<tr><td>Kategorie</td><td>Inhalt</td></tr>\n";
#	print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td></tr>\n";

	print_simple_category("Ident-Nr","$korres1->{idn}");

	print_simple_category("Ident-Alt","$korres1->{ida}") if ($korres1->{ida});
	print_simple_category("Ansetzung","$korres1->{korans}") if ($korres1->{korans});
	print_simple_category("GK-Ident","$korres1->{kgdident}") if ($korres1->{gkdident});
	
        # Verweisungsformen ausgeben

	if ($benchmark){
	    $atime=new Benchmark;
	}

	my $korresult2=$dbh->prepare("$korstatement2") or $logger->error($DBI::errstr);
	$korresult2->execute() or $logger->error($DBI::errstr);

	my $korres2;
	while ($korres2=$korresult2->fetchrow_hashref){
	  print_simple_category("Verweis","$korres2->{verw}");
	}    

	$korresult2->finish();

	if ($benchmark){
	    $btime=new Benchmark;
	    $timeall=timediff($btime,$atime);
	    $logger->info("Zeit fuer : $korstatement2 : ist ".timestr($timeall));
	    undef $atime;
	    undef $btime;
	    undef $timeall;
	}

        # Fruehere Form ausgeben

	if ($benchmark){
	    $atime=new Benchmark;
	}

	my $korresult3=$dbh->prepare("$korstatement3") or $logger->error($DBI::errstr);
	$korresult3->execute() or $logger->error($DBI::errstr);

	my $korres3;
	while ($korres3=$korresult3->fetchrow_hashref){
	  print_simple_category("Fr&uuml;her","$korres3->{frueher}");
	}    

	$korresult3->finish();

	if ($benchmark){
	    $btime=new Benchmark;
	    $timeall=timediff($btime,$atime);
	    $logger->info("Zeit fuer : $korstatement3 : ist ".timestr($timeall));
	    undef $atime;
	    undef $btime;
	    undef $timeall;
	}
        # Form fuer Spaeter ausgeben

	if ($benchmark){
	    $atime=new Benchmark;
	}

	my $korresult4=$dbh->prepare("$korstatement4") or $logger->error($DBI::errstr);
	$korresult4->execute() or $logger->error($DBI::errstr);

	my $korres4;
	while ($korres4=$korresult4->fetchrow_hashref){
	  print_simple_category("Sp&auml;ter","$korres4->{spaeter}");
	}    

	$korresult4->finish();

	if ($benchmark){
	    $btime=new Benchmark;
	    $timeall=timediff($btime,$atime);
	    $logger->info("Zeit fuer : $korstatement4 : ist ".timestr($timeall));
	    undef $atime;
	    undef $btime;
	    undef $timeall;
	}


    }

    if ($mode == 3){

	my @requests=("select titidn from titurh where urhverw=$korres1->{idn}","select titidn from titkor where korverw=$korres1->{idn}");
	my $titelnr=get_number(\@requests,$dbh);

	print_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&searchtitofurhkor=$korres1->{idn}","$titelnr</a>");
    }

    if ($mode == 5){
	print "<tr><td><input type=checkbox name=searchmultiplekor value=$korres1->{idn} ";
	print "></td><td>";
	print "<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;sorttype=$sorttype&amp;sortorder=$sortorder&amp;database=$database&amp;searchsinglekor=$korres1->{idn}\">";
	print "<strong>$korres1->{korans}</strong></a></td></tr>\n";
	return;
    }
    print "</table>";
    return;
}

sub get_kor_ans_by_idn {

  my ($koridn,$dbh)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $korstatement1="select * from kor where idn=$koridn";
  
  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $korresult1=$dbh->prepare("$korstatement1") or $logger->error($DBI::errstr);
  $korresult1->execute() or $logger->error($DBI::errstr);
  my $korres1=$korresult1->fetchrow_hashref;
  $korresult1->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $korstatement1 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  
  if ($korres1->{korans}){
    return $korres1->{korans};
  }
  return;
}

sub get_kor_set_by_idn {
  my ($koridn,$dbh,$searchmultiplekor,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $korstatement1="select * from kor where idn=$koridn";
  my $korstatement2="select * from korverw where koridn=$koridn";
  my $korstatement3="select * from korfrueh where koridn=$koridn";
  my $korstatement4="select * from korspaet where koridn=$koridn";
  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $korresult1=$dbh->prepare("$korstatement1") or $logger->error($DBI::errstr);
  $korresult1->execute() or $logger->error($DBI::errstr);

  my $korres1=$korresult1->fetchrow_hashref;
  $korresult1->finish();
  
  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $korstatement1 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  
  print_inst_head($database,"base");
  
  print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
  
  if ($searchmultiplekor){
    print "\n<hr>\n";
  }
  else{
    #	    print "<h1>Gefundene K&ouml;rperschaft</h1>\n";
  }
  print "<table cellpadding=2>\n";
  print "<tr><td>Kategorie</td><td>Inhalt</td></tr>\n";
  #	print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td></tr>\n";
  
  print_simple_category("Ident-Nr","$korres1->{idn}");
  
  print_simple_category("Ident-Alt","$korres1->{ida}") if ($korres1->{ida});
  print_simple_category("Ansetzung","$korres1->{korans}") if ($korres1->{korans});
  print_simple_category("GK-Ident","$korres1->{kgdident}") if ($korres1->{gkdident});
  
  # Verweisungsformen ausgeben
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $korresult2=$dbh->prepare("$korstatement2") or $logger->error($DBI::errstr);
  $korresult2->execute() or $logger->error($DBI::errstr);
  
  my $korres2;
  while ($korres2=$korresult2->fetchrow_hashref){
    print_simple_category("Verweis","$korres2->{verw}");
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
  $korresult3->execute() or $logger->error($DBI::errstr);
  
  my $korres3;
  while ($korres3=$korresult3->fetchrow_hashref){
    print_simple_category("Fr&uuml;her","$korres3->{frueher}");
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
  $korresult4->execute() or $logger->error($DBI::errstr);
  
  my $korres4;
  while ($korres4=$korresult4->fetchrow_hashref){
    print_simple_category("Sp&auml;ter","$korres4->{spaeter}");
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

  print_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&searchtitofurhkor=$korres1->{idn}","$titelnr</a>");

  print "</table>";
  return;
}

#####################################################################
## get_swt_by_idn(swtidn,mode,...): Gebe zu swtidn geh"oerenden 
##                                  Schlagwortstammsatz aus
##
## swtidn: IDN des Schlagwortstammsatzes
## mode:   1 - Nur Ansetzungsform wird ausgegeben
##         2 - Gesamter Autorenstammsatz ausgeben
##         3 - Gesamter Autorenstammsatz + Anzahl verkn"upfter Titeldaten
##             ausgeben
##         5 - Ansetzungsform in Suchzeile ausgeben
##
## Und nun jede Menge Variablen, damit mod_perl keine Probleme macht
##
## $dbh
## $benchmark
## $searchmultipleswt
## $searchmode
## $showmexintit
## $casesensitive
## $hitrange
## $sorttype
## $database

sub get_swt_by_idn {

    my ($swtidn,$mode,$dbh,$benchmark,$searchmultipleswt,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$rdbinfo,$sessionID)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my %dbinfo=%$rdbinfo;

    my $swtstatement1="select * from swt where idn=$swtidn";
    my $swtstatement2="select * from swtverw where swtidn=$swtidn";
    my $swtstatement3="select * from swtueber where swtidn=$swtidn";
    my $swtstatement4="select * from swtassoz where swtidn=$swtidn";
    my $swtstatement5="select * from swtfrueh where swtidn=$swtidn";
    my $swtstatement6="select * from swtspaet where swtidn=$swtidn";

    my $atime;
    my $btime;
    my $timeall;

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $swtresult1=$dbh->prepare("$swtstatement1") or $logger->error($DBI::errstr);
    $swtresult1->execute() or $logger->error($DBI::errstr);

    my $swtres1=$swtresult1->fetchrow_hashref;
    $swtresult1->finish();

    if ($mode == 1){
      if ($swtres1->{schlagw}){
	return $swtres1->{schlagw};
      }
      return;
    }


    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $swtstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if (($mode == 2)||($mode == 3)){
      print_inst_head($database,"base");

      print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);

      if ($searchmultipleswt){
	print "\n<hr>\n";
      }
      else {
#	print "<h1>Gefundenes Schlagwort</h1>\n";
      }
      
      print "<table cellpadding=2>";
      print "<tr><td>Kategorie</td><td>Inhalt</td></tr>\n";
#      print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td></tr>\n";
      
      # Ausgabe diverser Informationen
      
      print_simple_category("Ident-Nr","$swtres1->{idn}");
      print_simple_category("Ident-Alt","$swtres1->{ida}") if ($swtres1->{ida});
      print_simple_category("Schlagwort","$swtres1->{schlagw}") if ($swtres1->{schlagw});
      print_simple_category("Erlaeut","$swtres1->{erlaeut}") if ($swtres1->{erlaeut});
      print_simple_category("Verbidn","$swtres1->{verbidn}") if ($swtres1->{verbidn});
      
      if ($config{benchmark}){
	$atime=new Benchmark;
      }
      
      my $swtresult2=$dbh->prepare("$swtstatement2") or $logger->error($DBI::errstr);
      $swtresult2->execute() or $logger->error($DBI::errstr);
      
      my $swtres2;
      while ($swtres2=$swtresult2->fetchrow_hashref){
	print_simple_category("Verweis","$swtres2->{verw}") if ($swtres2->{verw});
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

      # 

      if ($config{benchmark}){
	$atime=new Benchmark;
      }
      
      my $swtresult3=$dbh->prepare("$swtstatement3") or $logger->error($DBI::errstr);
      $swtresult3->execute() or $logger->error($DBI::errstr);
      
      my $swtres3;
      while ($swtres3=$swtresult3->fetchrow_hashref){
	print_simple_category("&Uuml;berordnung","$swtres3->{ueber}") if ($swtres3->{ueber});
      }    
      $swtresult3->finish();
      
      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $swtstatement3 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }

      #

      if ($config{benchmark}){
	$atime=new Benchmark;
      }
      
      my $swtresult4=$dbh->prepare("$swtstatement4") or $logger->error($DBI::errstr);
      $swtresult4->execute() or $logger->error($DBI::errstr);
      
      my $swtres4;
      while ($swtres4=$swtresult4->fetchrow_hashref){
	print_simple_category("Assoz.","$swtres4->{assoz}") if ($swtres4->{assoz});
      }    
      $swtresult4->finish();
      
      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $swtstatement4 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }

      #

      if ($config{benchmark}){
	$atime=new Benchmark;
      }
      
      my $swtresult5=$dbh->prepare("$swtstatement5") or $logger->error($DBI::errstr);
      $swtresult5->execute() or $logger->error($DBI::errstr);
      
      my $swtres5;
      while ($swtres5=$swtresult5->fetchrow_hashref){
	print_simple_category("Fr&uuml;her","$swtres5->{frueher}") if ($swtres5->{frueher});
      }    
      $swtresult5->finish();
      
      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $swtstatement5 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }

      #

      if ($config{benchmark}){
	$atime=new Benchmark;
      }
      
      my $swtresult6=$dbh->prepare("$swtstatement6") or $logger->error($DBI::errstr);
      $swtresult6->execute() or $logger->error($DBI::errstr);
      
      my $swtres6;
      while ($swtres6=$swtresult6->fetchrow_hashref){
	print_simple_category("Sp&auml;ter","$swtres6->{spaeter}") if ($swtres6->{spaeter});
      }    
      $swtresult6->finish();
      
      if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $swtstatement6 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
      }
      
		
      if ($mode == 3){	
	my @requests=("select titidn from titswtlok where swtverw=$swtres1->{idn}");
	my $swtanzahl=get_number(\@requests,$dbh);
	
	print_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&searchtitofswt=$swtres1->{idn}","$swtanzahl</a>");
	
      }
      print "</table>";
    }
    if ($mode == 5){
      print "<tr><td><input type=checkbox name=searchmultipleswt value=$swtres1->{idn} ";
      print "></td><td><strong>";
      print "<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;sorttype=$sorttype&amp;sortorder=$sortorder&amp;database=$database&amp;searchsingleswt=$swtres1->{idn}\">";
      print "$swtres1->{schlagw}</strong></a></td>";
    }
    return;
  }

sub get_swt_ans_by_idn {

    my ($swtidn,$dbh)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $swtstatement1="select * from swt where idn=$swtidn";

    my $atime;
    my $btime;
    my $timeall;

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $swtresult1=$dbh->prepare("$swtstatement1") or $logger->error($DBI::errstr);
    $swtresult1->execute() or $logger->error($DBI::errstr);

    my $swtres1=$swtresult1->fetchrow_hashref;
    $swtresult1->finish();

    if ($swtres1->{schlagw}){
      return $swtres1->{schlagw};
    }
    return;
  }

sub get_swt_set_by_idn {
  
  my ($swtidn,$dbh,$searchmultipleswt,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$rdbinfo,$sessionID)=@_;
  
  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my %dbinfo=%$rdbinfo;
  
  my $swtstatement1="select * from swt where idn=$swtidn";
  my $swtstatement2="select * from swtverw where swtidn=$swtidn";
  
  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $swtresult1=$dbh->prepare("$swtstatement1") or $logger->error($DBI::errstr);
  $swtresult1->execute() or $logger->error($DBI::errstr);

  my $swtres1=$swtresult1->fetchrow_hashref;
  $swtresult1->finish();

  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : $swtstatement1 : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }
  
  print_inst_head($database,"base");
  
  print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);
  
  if ($searchmultipleswt){
    print "\n<hr>\n";
  }
  else {
    #	print "<h1>Gefundenes Schlagwort</h1>\n";
  }
  
  print "<table cellpadding=2>";
  print "<tr><td>Kategorie</td><td>Inhalt</td></tr>\n";
  #      print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td></tr>\n";
  
  # Ausgabe diverser Informationen
  
  print_simple_category("Ident-Nr","$swtres1->{idn}");
  print_simple_category("Ident-Alt","$swtres1->{ida}") if ($swtres1->{ida});
  print_simple_category("Schlagwort","$swtres1->{schlagw}") if ($swtres1->{schlagw});
  print_simple_category("Erlaeut","$swtres1->{erlaeut}") if ($swtres1->{erlaeut});
  print_simple_category("Verbidn","$swtres1->{verbidn}") if ($swtres1->{verbidn});
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }
  
  my $swtresult2=$dbh->prepare("$swtstatement2") or $logger->error($DBI::errstr);
  $swtresult2->execute() or $logger->error($DBI::errstr);
  
  my $swtres2;
  while ($swtres2=$swtresult2->fetchrow_hashref){
    print_simple_category("Verweis","$swtres2->{verw}") if ($swtres2->{verw});
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
  my $swtanzahl=get_number(\@requests,$dbh);
  
  print_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&searchtitofswt=$swtres1->{idn}","$swtanzahl</a>");
  
  print "</table>";
  return;
}

#####################################################################
## get_not_by_idn(notidn,mode,...): Gebe zu notidn geh"oerenden 
##                                  Notationsstammsatz aus
##
## notidn: IDN des Notationsstammsatzes
## mode:   1 - Nur Ansetzungsform wird ausgegeben
##         2 - Gesamter Notationsstammsatz ausgeben
##         3 - Gesamter Notationsstammsatz + Anzahl verkn"upfter Titeldaten
##             ausgeben
##         5 - Ansetzungsform in Suchzeile ausgeben
##
## Und nun jede Menge Variablen, damit mod_perl keine Probleme macht
##
## $dbh
## $benchmark
## $searchmultiplenot
## $searchmode
## $showmexintit
## $casesensitive
## $hitrange
## $sorttype
## $database

sub get_not_by_idn {

    my ($notidn,$mode,$dbh,$benchmark,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$sessionID)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $notstatement1="select * from notation where idn=$notidn";
    my $notstatement2="select * from notverw where notidn=$notidn";
    my $notstatement3="select * from notbenverw where notidn=$notidn";
    my $atime;
    my $btime;
    my $timeall;
    
    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $notresult1=$dbh->prepare("$notstatement1") or $logger->error($DBI::errstr);
    $notresult1->execute() or $logger->error($DBI::errstr);

    my $notres1=$notresult1->fetchrow_hashref;
    $notresult1->finish();
    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $notstatement1 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }
    
    if (($mode == 2)||($mode == 3)){
      print_inst_head($database,"base");
      print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);

#	print "<h1>Gefundene Notation</h1>\n";
	print "<table cellpadding=2>";
	print "<tr><td>Kategorie</td><td>Inhalt</td></tr>\n";
#	print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td></tr>\n";

	# Ausgabe verschiedener Informationen

	print_simple_category("Ident-Nr","$notres1->{idn}");
	print_simple_category("Ident-Alt","$notres1->{ida}") if ($notres1->{ida});
	print_simple_category("Vers-Nr","$notres1->{versnr}") if ($notres1->{versnr});
	print_simple_category("Notation","$notres1->{notation}") if ($notres1->{notation});
	print_simple_category("Benennung","$notres1->{benennung}") if ($notres1->{benennung});

	if ($config{benchmark}){
	    $atime=new Benchmark;
	}

	# Ausgabe der Verweise

	my $notresult2=$dbh->prepare("$notstatement2") or $logger->error($DBI::errstr);
	$notresult2->execute() or $logger->error($DBI::errstr);

	my $notres2;
	while ($notres2=$notresult2->fetchrow_hashref){
	  print_simple_category("Verweis","$notres2->{verw}");
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
	$notresult3->execute() or $logger->error($DBI::errstr);

	my $notres3;
	while ($notres3=$notresult3->fetchrow_hashref){
	  print_simple_category("Ben.Verweis","$notres3->{benverw}");
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

	print_simple_category("Abrufzeichen","$notres1->{abrufzeichen}") if ($notres1->{abrufzeichen});
	print_simple_category("Beschr-Not.","$notres1->{beschrnot}") if ($notres1->{beschrnot});
	print_simple_category("Abrufr","$notres1->{abrufr}") if ($notres1->{abrufr});

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

	if ($mode == 3){	

	  # Ausgabe der Anzahl verkn"upfter Titel
	  
	  my @requests=("select titidn from titnot where notidn=$notres1->{idn}");
	  my $anzahl=get_number(\@requests,$dbh);
	  
	  print_url_category("Anzahl Titel","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&searchtitofnot=$notres1->{idn}","$anzahl</a>");

	}
	print "</table>";
    }
    if ($mode == 1){

      # Zur"ucklieferung der Notation

      if ($notres1->{notation}){
	return $notres1->{notation};
      }
      return;

    }

    if ($mode == 5){
	print "<tr><td><input type=checkbox name=searchsinglenot value=$notres1->{idn} ";
	print "></td><td>";
	print "<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;sorttype=$sorttype&amp;sortorder=$sortorder&amp;database=$database&amp;searchsinglenot=$notres1->{idn}\">";
	print "<strong>$notres1->{notation}</strong></a></td>";
	return;
    }
    return;
}

#####################################################################
## get_tit_by_idn(titidn,hint,mode,...): Gebe zu titidn geh"oerenden 
##                                       Titelstammsatz aus
##
## titidn: IDN des Titelstammsatzes
## hint:   Zus"atzliche Informationen (z.B. "Ubergeordnete titidn)
## mode:   1 - Gesamter Titelstammsatz wird ausgegeben (default)
##         2 - HST ausgeben
##         5 - Auswahllisteneintrag ausgeben
##         6 - Auswahllisteneintrag ausgeben (GTF)
##         7 - Auswahllisteneintrag ausgeben (GTM)
##         8 - HST ausgeben (Gesamtkatalog)
##
## Und nun jede Menge Variablen, damit mod_perl keine Probleme macht
##
## $benchmark
## $searchmultipleaut
## $searchmultipleswt
## $searchmultiplekor
## $searchmultipletit
## $searchmultiplemex
## $searchmode
## $showmexintit
## $casesensitive
## $hitrange
## $rating
## $database
## $rdbinfo - Referenz auf %dbinfo
## $rtiteltyp - Referenz auf %titeltyp
## $rsigel - Referenz auf %sigel
## $rdbases - Referenz auf %dbases
## $rdbibinfo - Referenz auf %bibinfo

sub get_tit_by_idn { 

    my ($titidn,$hint,$mode,$dbh,$sessiondbh,$benchmark,$searchmultipleaut,$searchmultiplekor,$searchmultipleswt,$searchmultipletit,$searchmultiplemex,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$dbmode,$rdbinfo,$rtiteltyp,$rsigel,$rdbases,$rbibinfo,$sessionID)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my %dbinfo=%$rdbinfo;
    my %titeltyp=%$rtiteltyp;
    my %sigel=%$rsigel;
    my %dbases=%$rdbases;
    my %bibinfo=%$rbibinfo;

    my $titstatement1="select * from tit where idn=$titidn";

    my $atime;
    my $btime;
    my $timeall;

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult1=$dbh->prepare("$titstatement1") or $logger->error($DBI::errstr);
    $titresult1->execute() or $logger->error($DBI::errstr);

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

    if ($mode >= 5){

      my $retval="";

      my @verfasserarray=();

      my @signaturarray=();


      my $mexstatement1="select idn from mex where titidn=$titidn";

      my @requests=($mexstatement1);
      my @verknmex=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);

      my $mexidn;

      foreach $mexidn (@verknmex){
	my $mexstatement2="select signlok from mexsign where mexidn=$mexidn";	
	@requests=($mexstatement2);
	my @sign=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
	
	push @signaturarray, @sign;

      }


      my $signaturstring=join(" ; ", @signaturarray);
      $signaturstring="<span id=\"rlsignature\">$signaturstring</span>";

      # Verfasser etc. zusammenstellen
      
      # Ausgabe der Verfasser
      
      @requests=("select verfverw from titverf where titidn=$titidn");
      my @titres8=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      my $titidn8;
      foreach $titidn8 (@titres8){
       
	push @verfasserarray, get_aut_ans_by_idn("$titidn8",$dbh);
	
      }
      
      # Ausgabe der Personen
      
      @requests=("select persverw from titpers where titidn=$titidn");
      my @titres9=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      my $titidn9;
      foreach $titidn9 (@titres9){
	
	push @verfasserarray, get_aut_ans_by_idn("$titidn9",$dbh);
	
      }

      # Ausgabe der gefeierten Personen
      
      @requests=("select persverw from titgpers where titidn=$titidn");
      my @titres19=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      my $titidn19;
      foreach $titidn19 (@titres19){
	
	push @verfasserarray, get_aut_ans_by_idn("$titidn19",$dbh);
	
      }

      # Ausgabe der Urheber
      
      @requests=("select urhverw from titurh where titidn=$titidn");
      my @titres10=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      my $titidn10;
      foreach $titidn10 (@titres10){
	
	push @verfasserarray, get_kor_by_idn("$titidn10",1,$dbh,$benchmark,$searchmultiplekor,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);
      }
      
      # Ausgabe der K"orperschaften
      
      @requests=("select korverw from titkor where titidn=$titidn");
      my @titres11=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
      my $titidn11;
      foreach $titidn11 (@titres11){
	
	push @verfasserarray, get_kor_by_idn("$titidn11",1,$dbh,$benchmark,$searchmultiplekor,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID);
	
      }

      my $verfasserstring=join(" ; ",@verfasserarray);

      # Ab jetzt hochhangeln zum uebergeordneten Titel, wenn im lokalen keine
      # Sachl. Ben. bzw. HST vorhanden
      # GILT NUR FUER BISLOK TTYP4 - Bei Sisis macht das keinen Sinn

#	if (($titres1->{titeltyp} == 4)&&($titres1->{sachlben} eq "")&&($titres1->{hst} eq "")){
      if (($titres1->{sachlben} eq "")&&($titres1->{hst} eq "")){
	    
	    # Wenn bei Titeln des Typs 4 (Bandauff"uhrungen) die Kategorien 
	    # Sachliche Benennung und HST nicht besetzt sind, dann verwende als
	    # Ausgabetext stattdessen den HST des *ersten* "ubergeordneten Werkes und
	    # den Zusatz/Laufende Z"ahlung

	    if ($hint eq "none"){
#		open(DEBUG,">/tmp/none.fehleridns");
#		print DEBUG "Titelidn: $titidn\n";
#		close(DEBUG);

		my @requests=("select verwidn from titgtm where titidn=$titidn limit 1");
		my @tempgtmidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
		
		# in @tempgtmidns sind die IDNs der "ubergeordneten Werke

		my $tempgtmidn;

		foreach $tempgtmidn (@tempgtmidns){
		    
		  my @requests=("select hst from tit where idn=$tempgtmidn"); 
		  my @tithst=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);

		  @requests=("select ast from tit where idn=$tempgtmidn"); 
		  my @titast=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);

		  # Der AST hat Vorrang ueber den HST

		  if ($titast[0]){
		    $tithst[0]=$titast[0];
		  }
		  
		  @requests=("select zus from titgtm where verwidn=$tempgtmidn");
		  my @gtmzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
		  
		    $retval.="<tr><td><input type=checkbox name=searchmultipletit value=$titres1->{idn}></td><td>"; 
		    
		  my $showerschjahr=$titres1->{erschjahr};

		  if ($showerschjahr eq ""){
		    $showerschjahr=$titres1->{anserschjahr};
		  }

		    $retval.="<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchsingletit=$titres1->{idn}\"><strong>$tithst[0] ; $gtmzus[0]</strong></a>, $titres1->{verlag} $showerschjahr</td><td><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\" title=\"In die Merkliste\"><span id=\"rlmerken\"><img src=\"/images/openbib/3d-file-blue-clipboard.png\" height=\"29\" alt=\"In die Merkliste\" border=0></span></a></td><td align=left><b>$signaturstring</b>";


		}

		
		# obsolete ?????

		@requests=("select verwidn from titgtf where titidn=$titidn");
		my @tempgtfidns=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
		
		my $tempgtfidn;

		if ($#tempgtfidns >= 0){
		  $tempgtfidn=$tempgtfidns[0];
		# Problem: Mehrfachausgabe in Kurztrefferausgabe eines Titels...
		# Loesung: Nur der erste wird ausgegeben
#		foreach $tempgtfidn (@tempgtfidns){
		
		  my @requests=("select hst from tit where idn=$tempgtfidn");
    
		    my @tithst=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);

		  @requests=("select ast from tit where idn=$tempgtfidn");
    
		    my @titast=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);

		  # Der AST hat Vorrang ueber den HST

		  if ($titast[0]){
		    $tithst[0]=$titast[0];
		  }


		    
		  @requests=("select zus from titgtf where verwidn=$tempgtfidn");


		    my @gtfzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
		 
                   
		    $retval.="<tr><td><input type=checkbox name=searchmultipletit value=$titres1->{idn}></td><td>"; 

		  my $showerschjahr=$titres1->{erschjahr};

		  if ($showerschjahr eq ""){
		    $showerschjahr=$titres1->{anserschjahr};
		  }
		    
		    $retval.="<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchsingletit=$titres1->{idn}\"><strong>$tithst[0] ; $gtfzus[0]</strong></a>, $titres1->{verlag} $showerschjahr</td><td><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\"><span id=\"rlmerken\"><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\" title=\"In die Merkliste\"><img src=\"/images/openbib/3d-file-blue-clipboard.png\" height=\"29\" alt=\"In die Merkliste\" border=0></a></span></a></td><td align=left><b>$signaturstring</b>";


		}		    
	      
	      }
	    else {
		my @requests=("select hst from tit where idn=$hint");
		my @tithst=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);

		@requests=("select ast from tit where idn=$hint");
		my @titast=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);

		# Der AST hat Vorrang ueber den HST

		if ($titast[0]){
		  $tithst[0]=$titast[0];
		}
		
		$retval.="<tr><td><input type=checkbox name=searchmultipletit value=$titres1->{idn}></td><td>"; 

		if ($mode == 6){

		  my $showerschjahr=$titres1->{erschjahr};

		  if ($showerschjahr eq ""){
		    $showerschjahr=$titres1->{anserschjahr};
		  }

		    my @requests=("select zus from titgtf where verwidn=$hint and titidn=$titidn");
		    my @gtfzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
		    $retval.="<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchsingletit=$titres1->{idn}\"><strong>$tithst[0] ; $gtfzus[0]</strong></a>, $titres1->{verlag} $showerschjahr</td><td><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\"><span id=\"rlmerken\"><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\" title=\"In die Merkliste\"><img src=\"/images/openbib/3d-file-blue-clipboard.png\" height=\"29\" alt=\"In die Merkliste\" border=0></a></span></a></td><td align=left><b>$signaturstring</b>";		
		}
		if ($mode == 7){
		  my $showerschjahr=$titres1->{erschjahr};

		  if ($showerschjahr eq ""){
		    $showerschjahr=$titres1->{anserschjahr};
		  }

		    my @requests=("select zus from titgtm where verwidn=$hint and titidn=$titidn");
		  my @gtmzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
		  $retval.="<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchsingletit=$titres1->{idn}\"><strong>$tithst[0] ; $gtmzus[0]</strong></a>, $titres1->{verlag} $showerschjahr</td><td><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\"><span id=\"rlmerken\"><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\" title=\"In die Merkliste\"><img src=\"/images/openbib/3d-file-blue-clipboard.png\" height=\"29\" alt=\"In die Merkliste\" border=0></a></span></a></td><td align=left><b>$signaturstring</b>";		

		}			     
		if ($mode == 8){
		  my $showerschjahr=$titres1->{erschjahr};

		  if ($showerschjahr eq ""){
		    $showerschjahr=$titres1->{anserschjahr};
		  }

		  my @requests=("select zus from titinverkn where titverw=$hint and titidn=$titidn");
		  my @invkzus=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
		  $retval.="<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;database=$database&amp;searchsingletit=$titres1->{idn}\"><strong>$tithst[0] ; $invkzus[0]</strong></a>, $titres1->{verlag} $showerschjahr</td><td><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\"><span id=\"rlmerken\"><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\" title=\"In die Merkliste\"><img src=\"/images/openbib/3d-file-blue-clipboard.png\" height=\"29\" alt=\"In die Merkliste\" border=0></a></span></a></td><td align=left><b>$signaturstring</b>";		
		}			     
	    }
	  }

	# Falls HST oder Sachlben existieren, dann gebe ganz normal aus:

	else {
		$retval.="<tr><td><input type=checkbox name=searchmultipletit value=$titres1->{idn}></td><td>";

		# Der AST hat Vorrang ueber den HST
		
		if ($titres1->{ast}){
		  $titres1->{hst}=$titres1->{ast};
		}

		if ($titres1->{hst} eq ""){
		  $titres1->{hst}="Kein HST/AST vorhanden";
		}

		$retval.="<strong><span id=\"rlauthor\">$verfasserstring</span></strong><br>";
#		$retval.="<strong><span id=\"rlauthor\">$verfasserstring</span></strong><br>" if ($verfasserstring ne "");
		$retval.=" <a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;sorttype=$sorttype&amp;sortorder=$sortorder&amp;database=$database&amp;searchsingletit=$titres1->{idn}\">";

		  my $showerschjahr=$titres1->{erschjahr};

		  if ($showerschjahr eq ""){
		    $showerschjahr=$titres1->{anserschjahr};
		  }

		  my $titstring="";

		if ($titres1->{hst}){
		  $titstring=$titres1->{hst};
		}
		elsif ($titres1->{sachlben}){
		  $titstring=$titres1->{sachlben};
		}

		$retval.="<strong><span id=\"rltitle\">$titstring</span></strong></a>, <span id=\"rlpublisher\">$titres1->{verlag}</span> <span id=\"rlyearofpub\">$showerschjahr</span></td><td><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\"><span id=\"rlmerken\"><a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\" title=\"In die Merkliste\"><img src=\"/images/openbib/3d-file-blue-clipboard.png\" height=\"29\" alt=\"In die Merkliste\" border=0></a></span></a></td><td align=left><b>$signaturstring</b>";
		
	      }
	$retval.="</td></tr>\n";
	return $retval;
      }

    if ($mode == 2){
	print "$titres1->{hst}";
	return;
    }

    my $titstatement2="select * from titgtunv where titidn=$titidn";
    my $titstatement3="select * from titisbn where titidn=$titidn";
    my $titstatement4="select * from titgtm where titidn=$titidn";
    my $titstatement5="select * from titgtf where titidn=$titidn";
    my $titstatement6="select * from titinverkn where titidn=$titidn";
    my $titstatement7="select * from titswtlok where titidn=$titidn";
    my $titstatement8="select * from titverf where titidn=$titidn";
    my $titstatement9="select * from titpers where titidn=$titidn";
    my $titstatement10="select * from titurh where titidn=$titidn";
    my $titstatement11="select * from titkor where titidn=$titidn";
    my $titstatement12="select * from titnot where titidn=$titidn";
    my $titstatement13="select * from titissn where titidn=$titidn";
    my $titstatement14="select * from titwst where titidn=$titidn";
    my $titstatement15="select * from titurl where titidn=$titidn";
    my $titstatement16="select * from titpsthts where titidn=$titidn";
    my $titstatement17="select * from titbeigwerk where titidn=$titidn";
    my $titstatement18="select * from titartinh where titidn=$titidn";

    my $titstatement19="select * from titsammelverm where titidn=$titidn";
    my $titstatement20="select * from titanghst where titidn=$titidn";
    my $titstatement21="select * from titpausg where titidn=$titidn";
    my $titstatement22="select * from tittitbeil where titidn=$titidn";
    my $titstatement23="select * from titbezwerk where titidn=$titidn";
    my $titstatement24="select * from titfruehausg where titidn=$titidn";
    my $titstatement25="select * from titfruehtit where titidn=$titidn";
    my $titstatement26="select * from titspaetausg  where titidn=$titidn";
    my $titstatement27="select * from titabstract  where titidn=$titidn";
    my $titstatement28="select * from titner where titidn=$titidn";
    my $titstatement29="select * from titillang where titidn=$titidn";

    # Bestimmen des vorigen und naechsten Treffer einer
    # vorausgegangenen Kurztitelliste

#    open (DEB,">/tmp/lastnext.out");

    my $sessionresult=$sessiondbh->prepare("select lastresultset from session where sessionid='$sessionID'") or $logger->error($DBI::errstr);
    $sessionresult->execute() or $logger->error($DBI::errstr);

#    print DEB "select lastresultset from session where sessionid='$sessionID'\n";

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
      $lasttiturl=<< "LAST";
<a href="$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$lastdatabase&searchsingletit=$lastkatkey">[Vorheriger Titel]</a>
LAST
    }
    else {
      $lasttiturl="<span color=\"slategrey\">[Vorheriger Titel]</span>";
    }
    
    if ($lastresultstring=~m/$database:$titidn\|(\w+:\d+)/){
      $nexttiturl=$1;
      my ($nextdatabase,$nextkatkey)=split(":",$nexttiturl);
      $nexttiturl=<< "NEXT";
<a href="$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$nextdatabase&searchsingletit=$nextkatkey">[N&auml;chster Titel]</a>
NEXT
    }
    else {
      $nexttiturl="<span color=\"slategrey\">[N&auml;chster Titel]</span>";
    }

#    print DEB "$lastresultstring\n -> $lasttiturl - $nexttiturl\n";
#    close(DEB);

    print_inst_head($database,"extended",$sessionID,$titidn);
    print_mult_sel_form($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID);

    if ($searchmultipletit){
	print "\n<hr>\n";
    }
    else {
#	print "<h1>Gefundener Titel</h1>\n";

      # Bei Einzelnen Titeln wird eine Zeile zum Vor und zuruckspringen
      # bzgl. der vorausgegangenen Titelliste angezeigt

      if ($nexttiturl || $lasttiturl){




	print << "LASTNEXT";
<table width="100%"  class="titlenav">
<tr><td align="left">$lasttiturl</td><td></td><td align="right">$nexttiturl</td></tr>
</table>
LASTNEXT
      }

    }


    # Ausgabe der Toolzeile fuer Merkliste


#    print "<a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\">In Merkliste</a><hr>\n";

    print "<p>\n";

    print "<!-- Title begins here -->\n";
    print "<table cellpadding=2>\n";
    print "<tr><td>Kategorie</td><td>Inhalt</td></tr>\n";
#    print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td></tr>\n";

    # Ausgabe diverser Informationen

    print_simple_category("Ident-Nr","$titres1->{idn}");
    print_simple_category("Ident-Alt","$titres1->{ida}") if ($titres1->{ida});
#    print_simple_category("Titeltyp","<i>$titeltyp{$titres1->{titeltyp}}</i>") if ($titres1->{titeltyp});
    print_simple_category("Versnr","$titres1->{versnr}") if ($titres1->{versnr});


    # Ausgabe der Verfasser
    
    my @requests=("select verfverw from titverf where titidn=$titidn");
    my @titres8=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    my $titidn8;
    foreach $titidn8 (@titres8){

      print_url_category_global("Verfasser","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&verf=$titidn8&generalsearch=verf",get_aut_ans_by_idn("$titidn8",$dbh)."</a>","verf",$sorttype,$sessionID);

    }

    # Ausgabe der Personen

    @requests=("select persverw from titpers where titidn=$titidn");
    my @titres9=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    my $titidn9;
    foreach $titidn9 (@titres9){

      print_url_category_global("Person","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&pers=$titidn9&generalsearch=pers",get_aut_ans_by_idn("$titidn9",$dbh)."</a>","verf",$sorttype,$sessionID);

    }

    # Ausgabe der gefeierten Personen

    @requests=("select persverw from titgpers where titidn=$titidn");
    my @titres13=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    my $titidn13;
    foreach $titidn13 (@titres13){

      print_url_category_global("Gefeierte Person","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&pers=$titidn13&generalsearch=pers",get_aut_ans_by_idn("$titidn13",$dbh)."</a>","verf",$sorttype,$sessionID);

    }

    # Ausgabe der Urheber

    @requests=("select urhverw from titurh where titidn=$titidn");
    my @titres10=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    my $titidn10;
    foreach $titidn10 (@titres10){

      print_url_category_global("Urheber","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&urh=$titidn10&generalsearch=urh",get_kor_by_idn("$titidn10",1,$dbh,$benchmark,$searchmultiplekor,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID)."</a>","kor",$sorttype,$sessionID);
    }

    # Ausgabe der K"orperschaften

    @requests=("select korverw from titkor where titidn=$titidn");
    my @titres11=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    my $titidn11;
    foreach $titidn11 (@titres11){

      print_url_category_global("K&ouml;rperschaft","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&kor=$titidn11&generalsearch=kor",get_kor_by_idn("$titidn11",1,$dbh,$benchmark,$searchmultiplekor,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID)."</a>","kor",$sorttype,$sessionID);

    }

    # Ausgabe diverser Informationen

    print_simple_category("AST","$titres1->{ast}") if ($titres1->{ast});    

    print_simple_category("Est-He","$titres1->{esthe}") if ($titres1->{esthe});    
    print_simple_category("Est-Fn","$titres1->{estfn}") if ($titres1->{estfn});
    print_simple_category("HST","<strong>$titres1->{hst}</strong>") if ($titres1->{hst});

    # Ausgabe der Sammlungsvermerke

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult19=$dbh->prepare("$titstatement19") or $logger->error($DBI::errstr);
    $titresult19->execute() or $logger->error($DBI::errstr);

    my $titres19;
    while ($titres19=$titresult19->fetchrow_hashref){
      print_simple_category("SammelVermerk","$titres19->{'sammelverm'}");
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
    $titresult14->execute() or $logger->error($DBI::errstr);

    my $titres14;
    while ($titres14=$titresult14->fetchrow_hashref){
      print_simple_category("WST","$titres14->{'wst'}");
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
    $titresult16->execute() or $logger->error($DBI::errstr);

    my $titres16;
    while ($titres16=$titresult16->fetchrow_hashref){
      print_simple_category("PST Vorl.","$titres16->{'psthts'}");
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
    $titresult17->execute() or $logger->error($DBI::errstr);

    my $titres17;
    while ($titres17=$titresult17->fetchrow_hashref){
      print_simple_category("Beig.Werke","$titres17->{'beigwerk'}");
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
    $titresult15->execute() or $logger->error($DBI::errstr);

    my $titres15;
    while ($titres15=$titresult15->fetchrow_hashref){
      print_simple_category("URL","<a href=\"$titres15->{'url'}\" target=_blank>$titres15->{'url'}</a>");
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

    print_simple_category("Zuerg. Urh","$titres1->{zuergurh}") if ($titres1->{zuergurh});
    print_simple_category("Zusatz","$titres1->{zusatz}") if ($titres1->{zusatz});
    print_simple_category("Vorl.beig.Werk","$titres1->{vorlbeigwerk}") if ($titres1->{vorlbeigwerk});
    print_simple_category("Gemeins.Angaben","$titres1->{gemeinsang}") if ($titres1->{gemeinsang});
    print_simple_category("Sachl.Ben.","<strong>$titres1->{sachlben}</strong>") if ($titres1->{sachlben});
    print_simple_category("Vorl.Verfasser","$titres1->{vorlverf}") if ($titres1->{vorlverf});
    print_simple_category("Vorl.Unterreihe","$titres1->{vorlunter}") if ($titres1->{vorlunter});    
    print_simple_category("Ausgabe","$titres1->{ausg}") if ($titres1->{ausg});    
    print_simple_category("Verlagsort","$titres1->{verlagsort}") if ($titres1->{verlagsort});    
    print_simple_category("Verlag","$titres1->{verlag}") if ($titres1->{verlag});    
    print_simple_category("Weitere Orte","$titres1->{weitereort}") if ($titres1->{weitereort});    
    print_simple_category("Aufnahmeort","$titres1->{aufnahmeort}") if ($titres1->{aufnahmeort});    
    print_simple_category("Aufnahmejahr","$titres1->{aufnahmejahr}") if ($titres1->{aufnahmejahr});    
    print_simple_category("Ersch. Jahr","$titres1->{erschjahr}") if ($titres1->{erschjahr});    
    print_simple_category("Ans. Ersch. Jahr","$titres1->{anserschjahr}") if ($titres1->{anserschjahr});    
    print_simple_category("Ersch. Verlauf","$titres1->{erschverlauf}") if ($titres1->{erschverlauf});    

    print_simple_category("Verfasser Quelle","$titres1->{verfquelle}") if ($titres1->{verfquelle});    
    print_simple_category("Ersch.Ort Quelle","$titres1->{eortquelle}") if ($titres1->{eortquelle});    
    print_simple_category("Ersch.Jahr Quelle","$titres1->{ejahrquelle}") if ($titres1->{ejahrquelle});    

    # Ausgabe der Illustrationsangaben

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult29=$dbh->prepare("$titstatement29") or $logger->error($DBI::errstr);
    $titresult29->execute() or $logger->error($DBI::errstr);

    my $titres29;
    while ($titres29=$titresult29->fetchrow_hashref){
      print_simple_category("Ill.Angaben",$titres29->{'illang'});
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

    print_simple_category("Kollation","$titres1->{kollation}") if ($titres1->{kollation});    
    
    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    # Ausgabe GTM

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult4=$dbh->prepare("$titstatement4") or $logger->error($DBI::errstr);
    $titresult4->execute() or $logger->error($DBI::errstr);

    my $titres4;
    while ($titres4=$titresult4->fetchrow_hashref){
	my $titstatement="select hst from tit where idn=$titres4->{verwidn}";
	my $titresult=$dbh->prepare("$titstatement") or $logger->error($DBI::errstr);
	$titresult->execute() or $logger->error($DBI::errstr);
	my $titres=$titresult->fetchrow_hashref;

	print_url_category("GTM","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&singlegtm=$titres4->{verwidn}&generalsearch=singlegtm","$titres->{hst}</a> ; $titres4->{zus}");

    }
    $titresult4->finish();

    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $titstatement4 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    # Augabe GTF

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult5=$dbh->prepare("$titstatement5") or $logger->error($DBI::errstr);
    $titresult5->execute() or $logger->error($DBI::errstr);

    my $titres5;
    while ($titres5=$titresult5->fetchrow_hashref){
	my $titstatement="select hst,ast,vorlverf,zuergurh,vorlunter from tit where idn=$titres5->{verwidn}";
	my $titresult=$dbh->prepare("$titstatement") or $logger->error($DBI::errstr);
	$titresult->execute() or $logger->error($DBI::errstr);
	my $titres=$titresult->fetchrow_hashref;

	my $asthst=$titres->{hst};

	my $verfurh=$titres->{zuergurh};

	if ($titres->{vorlverf}){
	  $verfurh=$titres->{vorlverf};
	}

	if (!$asthst && $titres->{ast}){
	  $asthst=$titres->{ast};
	}
	
	my $vorlunter=$titres->{vorlunter};
	
        if ($vorlunter){
          $asthst="$asthst : $vorlunter";
        }
	

	if ($verfurh){
	  $asthst=$asthst." / ".$verfurh;
	}

	print_url_category("GTF","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&singlegtf=$titres5->{verwidn}&generalsearch=singlegtf","$asthst</a> ; $titres5->{zus}");

    }
    $titresult5->finish();

    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $titstatement5 ++ : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    # Ausgabe IN Verkn.

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult6=$dbh->prepare("$titstatement6") or $logger->error($DBI::errstr);
    $titresult6->execute() or $logger->error($DBI::errstr);

    my $titres6;
    while ($titres6=$titresult6->fetchrow_hashref){
        my $titverw=$titres6->{titverw};

	my $titstatement="select hst,sachlben from tit where idn=$titverw";
	my $titresult=$dbh->prepare("$titstatement") or $logger->error($DBI::errstr);
	$titresult->execute() or $logger->error($DBI::errstr);
	my $titres=$titresult->fetchrow_hashref;

	# Wenn HST vorhanden, dann nimm ihn, sonst Sachlben.

	my $verkn=($titres->{hst})?$titres->{hst}:$titres->{sachlben};

	# Wenn weder HST, noch Sachlben vorhanden, dann haben wir
	# einen Titeltyp4 ohne irgendeine weitere Information und wir m"ussen
	# uns f"ur HST/Sachlben-Informationen eine Suchebene tiefer 
	# hangeln :-(

	if (!$verkn){
	  my $gtmidnresult1=$dbh->prepare("select verwidn from titgtm where titidn=$titverw") or $logger->error($DBI::errstr);
	  $gtmidnresult1->execute() or $logger->error($DBI::errstr);
	  my $gtmidnres1=$gtmidnresult1->fetchrow_hashref;
	  my $gtmidn=$gtmidnres1->{verwidn};
	  $gtmidnresult1->finish();

	  if ($gtmidn){
	    my $gtmidnresult2=$dbh->prepare("select hst,sachlben from tit where idn=$gtmidn") or $logger->error($DBI::errstr);
	    $gtmidnresult2->execute() or $logger->error($DBI::errstr);
	    my $gtmidnres2=$gtmidnresult2->fetchrow_hashref;
	    $verkn=($gtmidnres2->{hst})?$gtmidnres2->{hst}:$gtmidnres2->{sachlben};
	    $gtmidnresult2->finish();
	  }
	}

	if (!$verkn){
	  my $gtfidnresult1=$dbh->prepare("select verwidn, zus from titgtf where titidn=$titverw") or $logger->error($DBI::errstr);
	  $gtfidnresult1->execute() or $logger->error($DBI::errstr);
	  my $gtfidnres1=$gtfidnresult1->fetchrow_hashref;
	  my $gtfidn=$gtfidnres1->{verwidn};
	  my $gtfzus=$gtfidnres1->{zus};
	  $gtfidnresult1->finish();
	  
	  if ($gtfidn){
	    my $gtfidnresult2=$dbh->prepare("select hst,sachlben from tit where idn=$gtfidn") or $logger->error($DBI::errstr);
	    $gtfidnresult2->execute() or $logger->error($DBI::errstr);
	    my $gtfidnres2=$gtfidnresult2->fetchrow_hashref;
	    $verkn=($gtfidnres2->{hst})?$gtfidnres2->{hst}:$gtfidnres2->{sachlben};
	    $gtfidnresult2->finish();
	  }
	  if ($gtfzus){
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
	if ($check1 eq $check2){
	  $zusatz=~s/^.+? \; (.+?)$/$1/;
	}

	print_url_category("IN verkn","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&singlegtf=$titverw&generalsearch=singlegtf","$verkn</a> ; $zusatz ");

    }

    $titresult6->finish();	


    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $titstatement6 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    # Ausgabe GT unverkn.

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult2=$dbh->prepare("$titstatement2") or $logger->error($DBI::errstr);
    $titresult2->execute() or $logger->error($DBI::errstr);

    my $titres2;
    while ($titres2=$titresult2->fetchrow_hashref){
	print_simple_category("GT unverkn","$titres2->{gtunv}");
    }
    $titresult2->finish();

    if ($config{benchmark}){
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Zeit fuer : $titstatement2 : ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    # Ausgabe diverser Informationen

    print_simple_category("IN unverkn","$titres1->{inunverkn}") if ($titres1->{inunverkn});    
    print_simple_category("Mat.Benennung","$titres1->{matbenennung}") if ($titres1->{matbenennung});    
    print_simple_category("Sonst.Mat.ben","$titres1->{sonstmatben}") if ($titres1->{sonstmatben});    
    print_simple_category("Sonst.Angaben","$titres1->{sonstang}") if ($titres1->{sonstang});    
    print_simple_category("Begleitmaterial","$titres1->{begleitmat}") if ($titres1->{begleitmat});    
    print_simple_category("Fu&szlig;note","$titres1->{fussnote}") if ($titres1->{fussnote});    

    # Ausgabe der AngabenHST

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult20=$dbh->prepare("$titstatement20") or $logger->error($DBI::errstr);
    $titresult20->execute() or $logger->error($DBI::errstr);

    my $titres20;
    while ($titres20=$titresult20->fetchrow_hashref){
      print_simple_category("AngabenHST","$titres20->{'anghst'}");
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
    $titresult21->execute() or $logger->error($DBI::errstr);

    my $titres21;
    while ($titres21=$titresult21->fetchrow_hashref){
      print_simple_category("Parallele Ausg.","$titres21->{'pausg'}");
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
    $titresult22->execute() or $logger->error($DBI::errstr);

    my $titres22;
    while ($titres22=$titresult22->fetchrow_hashref){
      print_simple_category("Titel Beilage","$titres22->{'titbeil'}");
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
    $titresult23->execute() or $logger->error($DBI::errstr);

    my $titres23;
    while ($titres23=$titresult23->fetchrow_hashref){
      print_simple_category("Bezugswerk","$titres23->{'bezwerk'}");
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
    $titresult24->execute() or $logger->error($DBI::errstr);

    my $titres24;
    while ($titres24=$titresult24->fetchrow_hashref){
      print_simple_category("Fr&uuml;here Ausg.","$titres24->{'fruehausg'}");
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
    $titresult25->execute() or $logger->error($DBI::errstr);

    my $titres25;
    while ($titres25=$titresult25->fetchrow_hashref){
      print_simple_category("Fr&uuml;herer Titel","$titres25->{'fruehtit'}");
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
    $titresult26->execute() or $logger->error($DBI::errstr);

    my $titres26;
    while ($titres26=$titresult26->fetchrow_hashref){
      print_simple_category("Sp&auml;tere Ausg.","$titres26->{'spaetausg'}");
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

    print_simple_category("Bind-Preis","$titres1->{bindpreis}") if ($titres1->{bindpreis});    
    print_simple_category("Hsfn","$titres1->{hsfn}") if ($titres1->{hsfn});    
    print_simple_category("Sprache","$titres1->{sprache}") if ($titres1->{sprache});    


    # Ausgabe der Abstracts

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult27=$dbh->prepare("$titstatement27") or $logger->error($DBI::errstr);
    $titresult27->execute() or $logger->error($DBI::errstr);

    my $titres27;
    while ($titres27=$titresult27->fetchrow_hashref){
      print_simple_category("Abstract","$titres27->{'abstract'}");
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

    print_simple_category("Mass.","$titres1->{mass}") if ($titres1->{mass});    
    print_simple_category("&Uuml;bers. HST","$titres1->{uebershst}") if ($titres1->{uebershst});    
#    print_simple_category("Bemerkung","$titres1->{rem}") if ($titres1->{rem});    
#    print_simple_category("Bemerkung","$titres1->{bemerk}") if ($titres1->{bemerk});    

    # Ausgabe der NER

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult28=$dbh->prepare("$titstatement28") or $logger->error($DBI::errstr);
    $titresult28->execute() or $logger->error($DBI::errstr);

    my $titres28;
    while ($titres28=$titresult28->fetchrow_hashref){
      print_simple_category("Nebeneintr.","$titres28->{'ner'}");
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
    $titresult18->execute() or $logger->error($DBI::errstr);

    my $titres18;
    while ($titres18=$titresult18->fetchrow_hashref){
      print_simple_category("Medienart","$titres18->{'artinhalt'}");
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
    my @titres7=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    my $titidn7;
    foreach $titidn7 (@titres7){

      print_url_category_global("Schlagwort","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&swt=$titidn7&generalsearch=swt",get_swt_ans_by_idn("$titidn7",$dbh)."</a>","swt",$sorttype,$sessionID);

    }

    # Augabe der Notationen

    @requests=("select notidn from titnot where titidn=$titidn");
    my @titres12=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);
    my $titidn12;
    foreach $titidn12 (@titres12){

      print_url_category("Notation","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&notation=$titidn12&generalsearch=not",get_not_by_idn("$titidn12",1,$dbh,$benchmark,$searchmode,$showmexintit,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$sessionID)."</a>");

    }

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    # Ausgabe der ISBN's

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $titresult3=$dbh->prepare("$titstatement3") or $logger->error($DBI::errstr);
    $titresult3->execute() or $logger->error($DBI::errstr);

    my $titres3;
    my $isbn;
    while ($titres3=$titresult3->fetchrow_hashref){

      print_simple_category("ISBN","$titres3->{isbn}");
      $isbn=$titres3->{isbn};

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
    $titresult13->execute() or $logger->error($DBI::errstr);

    my $titres13;
    while ($titres13=$titresult13->fetchrow_hashref){
      print_simple_category("ISSN","$titres13->{issn}");
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

    # Ausgabe der Anzahl verkn"upfter GTM

    @requests=("select titidn from titgtm where verwidn=$titres1->{idn}");
    my $verkntit=get_number(\@requests,$dbh);
      if ($verkntit > 0){

	print_url_category("B&auml;nde","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&gtmtit=$titres1->{idn}&generalsearch=gtmtit","$verkntit</a>");

    }

    # Ausgabe der Anzahl verkn"upfter GTF

    @requests=("select titidn from titgtf where verwidn=$titres1->{idn}");
    $verkntit=get_number(\@requests,$dbh);
    if ($verkntit > 0){
      print_url_category("St&uuml;cktitel","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&gtftit=$titres1->{idn}&generalsearch=gtftit","$verkntit</a>");
    }

    # Ausgabe der Anzahl verkn"upfter IN verkn.

    @requests=("select titidn from titinverkn where titverw=$titres1->{idn}");
    $verkntit=get_number(\@requests,$dbh);
    if ($verkntit > 0){

      print_url_category("Teil. UW","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&invktit=$titres1->{idn}&generalsearch=invktit","$verkntit</a>");

    }
    
    # Ausgabe der Anzahl verkn"upfter Exemplardaten

    @requests=("select idn from mex where titidn=$titres1->{idn}");
    my @verknmex=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);

    if (!$showmexintit){
	if ($#verknmex >= 0){

	  print_url_category("Exemplare","$config{search_loc}?sessionID=$sessionID&search=Mehrfachauswahl&searchmode=$searchmode&rating=$rating&bookinfo=$bookinfo&showmexintit=$showmexintit&casesensitive=$casesensitive&hitrange=$hitrange&sorttype=$sorttype&sortorder=$sortorder&database=$database&mextit=$titres1->{idn}&generalsearch=mextit",$#verknmex+1);

	}
	print "</table>\n";
    }
    else {
	print "</table>\n";
	if ($#verknmex >= 0){
	    print "<p>\n";
	    print "<table>\n";
	    #print "<tr align=center><td bgcolor=\"lightblue\">Besitzende Bibliothek</td><td bgcolor=\"lightblue\">Standort</td><td bgcolor=\"lightblue\">Inventarnummer</td><td bgcolor=\"lightblue\">Lokale Signatur</td>";
	    print "<tr align=center><td bgcolor=\"lightblue\">Besitzende Bibliothek</td><td bgcolor=\"lightblue\">Standort</td><td bgcolor=\"lightblue\">Lokale Signatur</td>";

	    print "<td bgcolor=\"lightblue\">Bestandsverlauf</td>";
	    
	    if ($circ){
	      print "<td bgcolor=\"lightblue\">Ausleihstatus</td><td bgcolor=\"lightblue\">Aktion</td>";
	    }

	    print "</tr>\n";

	    my $mexsatz;
	    foreach $mexsatz (@verknmex){
		get_mex_by_idn($mexsatz,6,$dbh,$benchmark,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,\%sigel,\%dbases,\%bibinfo,$searchmultiplemex,$sessionID);
	    }
	    print "</table>\n";
	}	    
    }

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
      
      $birequest="select * from bookinfo where isbn = '$biisbn'";
      
      my $biresult=$bidbh->prepare($birequest) or $logger->error($DBI::errstr);
      
      $biresult->execute() or $logger->error($DBI::errstr);
      
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
	  print $bookinfobuffer[$k];
	  $k++;
	}
      }
    }

    # Ausgabe der Nutzer-Bewertungen f"ur ein Buch

    if ($rating){
      print "<p>\n<table>\n";
      print "<tr><td bgcolor=\"lightblue\" colspan=3><b>Bewertungen dieses Buches</b> - von Nutzern f&uuml;r Nutzer</td></tr>\n";
      
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
      
      $rrequest="select * from rating where titidn = $titres1->{idn}";
      
      my $rresult=$rdbh->prepare($rrequest) or $logger->error($DBI::errstr);
      
      
      $rresult->execute() or $logger->error($DBI::errstr);
      
      while (($ridn,$rtidn,$rdate,$rname,$rurl,$rsubject,$rrating,$rmeinung)=$rresult->fetchrow){	    
	
	print "<tr><td><b>$rname<b></td><td><b>$rsubject</b></td><td><b>$rrating</b></td></tr>\n";
	
	print "<tr><td colspan=3>$rmeinung</td></tr>\n";
	print "<tr><td bgcolor=\"lightblue\" colspan=3>&nbsp;</td></tr>\n";
	$ratcount++;
      }
      $rresult->finish();
      
      #      $avgrating=$avgrating/$ratcount;
      if (!$ratcount){
	print "<tr><td bgcolor=\"lightblue\" colspan=3>Es wurden noch keine Bewertungen abgegeben</td></tr>\n";
      }
      #	  print "<tr><td bgcolor=\"lightblue\" colspan=2>Durchschnittliche Bewertung</td><td bgcolor=\"lightblue\">$avgrating</td></tr>\n";
      
      print "</table>\n";
      print "Wenn Sie ihre Meinung zu diesem Buch abgeben wollen, so klicken sie bitte <a href=\"/cgi-bin/biblio-rating.pl?titidn=$titres1->{idn}&database=$database&action=mask\"><b>hier</b></a>\n";

    }

    print "<p>\n<!-- Title ends here -->\n";

    return;
}	    

#####################################################################
## get_mex_by_idn(mexidn,mode): Gebe zu mexidn geh"oerenden 
##                              Exemplardatenstammsatz aus
##
## mexidn: IDN des Exemplardatenstammsatzes
## mode:     2 : Gesamten Exemplardatenstammsatz ausgeben
##           3 : Gesamten Exemplardatenstammsatz + Verknuepfung wird
##               ausgeben
##           5 : Nur Bibliothekssigel wird ausgegeben
##           6 : Reihenauflistung
##
## Und nun jede Menge Variablen, damit mod_perl keine Probleme macht
##
## $dbh
## $benchmark
## $searchmode
## $showmexintit
## $casesensitive
## $hitrange
## $sorttype
## $database
## $rsigel - Referenz auf %sigel
## $rdbases
## $rbibinfo
## $searchmultiplemex

sub get_mex_by_idn {

    my ($mexidn,$mode,$dbh,$benchmark,$searchmode,$showmexintit,$circ,$circurl,$circcheckurl,$casesensitive,$hitrange,$rating,$bookinfo,$sorttype,$sortorder,$database,$rsigel,$rdbases,$rbibinfo,$searchmultiplemex,$sessionID)=@_;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $mexstatement1="select * from mex where idn=$mexidn";
    my $mexstatement2="select * from mexsign where mexidn=$mexidn";
    my $atime;
    my $btime;
    my $timeall;
    
    my %sigel=%$rsigel;
    my %dbases=%$rdbases;
    my %bibinfo=%$rbibinfo;

    my @requests=("select titidn from mex where idn=$mexidn");
    my @verkntit=OpenBib::Common::Util::get_sql_result(\@requests,$dbh,$benchmark);

    if ($config{benchmark}){
	$atime=new Benchmark;
    }

    my $mexresult1=$dbh->prepare("$mexstatement1") or $logger->error($DBI::errstr);
    $mexresult1->execute() or $logger->error($DBI::errstr);
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

    if ($mode == 5){
	print "<tr><td><input type=checkbox name=searchmultiplemex value=$mexidn ";
	print "></td><td>";
	print "<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;sorttype=$sorttype&amp;sortorder=$sortorder&amp;database=$database&amp;searchsinglemex=$mexidn\">";

	if (length($sigel)>0){
	    if (exists $sigel{$sigel}){
		print "<strong>$sigel{$sigel}</strong></a>";
	    }
	    else{
		print "<strong>Unbekannt (38/$sigel)</strong></a>";
	    }
	}
        else {
	    if (exists $dbases{$database}){
		print "<strong>$dbases{$database}</strong></a>";
	    }
	    else{
		print "<strong>Unbekannt (38/$sigel)</strong></a>";
	    }
	}

	if ($config{benchmark}){
	    $atime=new Benchmark;
	}

	my $mexresult2=$dbh->prepare("$mexstatement2") or $logger->error($DBI::errstr);
	$mexresult2->execute() or $logger->error($DBI::errstr);

	my @mexres2;
	while (@mexres2=$mexresult2->fetchrow){ 
	    if ($mexres2[1]){
		print ", ".$mexres2[1];
	    }
	}
	$mexresult2->finish();
	print "</td></tr>\n";

	if ($config{benchmark}){
	    $btime=new Benchmark;
	    $timeall=timediff($btime,$atime);
	    $logger->info("Zeit fuer : $mexstatement2 : ist ".timestr($timeall));
	    undef $atime;
	    undef $btime;
	    undef $timeall;
	}
	return;
    }

    if ($mode == 6){	

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

#	$bibliothek=$database;

#	my $bibliothek;
#	if (!$sigel{$sigel}){
#	    $bibliothek="-";
#	}
#	else {
#	    $bibliothek=$sigel{$sigel};
#	}
	
# 	if (!$standort){
# 	    $standort="-";
# 	}
	
# 	if (!$inventarnummer){
# 	    $inventarnummer="-";
# 	}

# 	my $ausleihstatus;
	#if (!$mexres1[8]){
	    #$ausleihstatus="vorr&auml;tig";
	#}
	#else {
	  #if ($mexres1[8] eq "A"){
	    #$ausleihstatus="ausgeliehen";
	  #}
	  #else {
	    #$ausleihstatus="vorr&auml;tig";
	  #}
	#}

# 	my $buchung;
# 	if (!$buchung){
# 	    $buchung="-";
# 	}

# 	my $faellig;
# 	if (!$mexres1[12]){
# 	    $faellig="-";
# 	}
# 	else {
# 	    $faellig=$mexres1[12];
# 	}

# 	my $erschverl;
# 	if (!$mexres1[13]){
# 	    $erschverl="-";
# 	}
# 	else {
# 	    $erschverl=$mexres1[13];
# 	}
	
	my $mexresult2=$dbh->prepare("$mexstatement2") or $logger->error($DBI::errstr);
	$mexresult2->execute() or $logger->error($DBI::errstr);

	if ($mexresult2->rows == 0){

	    #print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td>$inventarnummer</td><td> - </td>";
	    print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td> - </td>";

	    print "<td>$erschverl</td>";

	    if ($circ){
	      print "<td></td>";
	    }

	    print "</tr>\n";
	}
	else {
	    my @mexres2;
	    while (@mexres2=$mexresult2->fetchrow){
                my $signatur=$mexres2[1];
		my $titidn=$verkntit[0];
		#print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td>$inventarnummer</td><td><strong><span id=\"rlsignature\">$signatur</span></strong></td>";
		print "<tr align=center><td><a href=\"$bibinfourl\"><strong>$bibliothek</strong></a></td><td>$standort</td><td><strong><span id=\"rlsignature\">$signatur</span></strong></td>";

		print "<td>$erschverl</td>";

		if ($circ){
                  my $ua=new LWP::UserAgent;
                  my $request=new HTTP::Request POST => $circcheckurl;

                  $request->content_type("application/x-www-form-urlencoded");

                  my $suchstring="katkey=$titidn&signatur=$signatur&database=$database";
                  $request->content("$suchstring");
                  my $response=$ua->request($request);

		  if ($response->is_success) {
		    $logger->debug("Getting ", $response->content);
		  }
		  else {
		    $logger->error("Getting ", $response->status_line);
		  }

                  my $status=$response->content();
                  my($ausleihstatus,$faellig)=split(":#:",$status);

                  my $ausleihstring;
                  if ($ausleihstatus eq "bestellbar"){
                      $ausleihstring="ausleihen?";
                  }
                  elsif ($ausleihstatus eq "bestellt"){
                      $ausleihstring="vormerken?";
                  }
                  elsif ($ausleihstatus eq "entliehen"){
                      $ausleihstring="vormerken/verl&auml;ngern?";
                  }
                  elsif ($ausleihstatus eq "bestellbar"){
                      $ausleihstring="ausleihen?";
                  }
                  else {
                      $ausleihstring="WebOPAC?";
                  }
		  if ($standort=~/Erziehungswiss/ || $standort=~/Heilp.*?dagogik-Magazin/){
		     print "<td><strong>$ausleihstatus</strong></td><td bgcolor=\"yellow\"><a TARGET=_blank href=\"$circurl&branch=4&KatKeySearch=$titidn\">$ausleihstring</a></td>";
		  }
		  else {
		    if ($database eq "inst001" || $database eq "poetica"){
		      print "<td><strong>$ausleihstatus</strong></td><td bgcolor=\"yellow\"><a TARGET=_blank href=\"$circurl&branch=0&KatKeySearch=$titidn\">$ausleihstring</a></td>";
		    }
		    else {
		      print "<td><strong>$ausleihstatus</strong></td><td bgcolor=\"yellow\"><a TARGET=_blank href=\"$circurl&KatKeySearch=$titidn\">$ausleihstring</a></td>";
		    }
		  }
#		  print "<td><a TARGET=_blank href=\"/cgi-bin/benutzerkonto.pl?sessionID=$sessionID\">Benutzerkonto-Test</a></td>";
		}
		print "</tr>\n";
	    }    
	}
	
	$mexresult2->finish();
    }
    

    if (($mode == 2)||($mode == 3)){
	if ($searchmultiplemex){
	    print "<hr>\n";
	}
	else {
#	    print "<h1>Gefundene Exemplardaten</h1>\n";
	}

	print "<table cellpadding=2>\n";
	print "<tr><td>Kategorie</td><td>Inhalt</td></tr>\n";
#	print "<tr bgcolor=\"lightblue\"><td>&nbsp;</td><td>".$dbinfo{"$database"}."</td></tr>\n";

	print "<tr><td bgcolor=\"lightblue\"><strong>Ident-Nr</strong></td>";
	print "<td>$mexidn";
	print "</td>";
	print "</tr>\n";
	if ($ida){
	    print "<tr><td bgcolor=\"lightblue\"><strong>Ident-Alt</strong></td>";
	    print "<td>$ida";
	    print "</td>";
	    print "</tr>\n";
	}

	print "<tr><td bgcolor=\"lightblue\"><strong>Bibliothek</strong></td><td>";

	if (length($sigel)>0){
	    if ($sigel{$sigel} ne ""){
		print "<a href=\"".$bibinfo{$sigel}."\"><strong>$sigel{$sigel}</strong></a>";
	    }
	    else{
		print "<strong>Unbekannt</strong>";
	    }
	}
	else {
	    if ($dbases{$database} ne ""){
		print "<strong>$dbases{$database}</strong></a>";
	    }
	    else{
		print "<strong>Unbekannt</strong></a>";
	    }
	}
	
	print "</td>";
	print "</tr>\n";
	
		
	if ($verbnr){
	    print "<tr><td bgcolor=\"lightblue\"><strong>Verbnr</strong></td>";
	    print "<td>$verbnr";
	    print "</td>";
	    print "</tr>\n";
	}    
	if ($standort){
	    print "<tr><td bgcolor=\"lightblue\"><strong>Standort</strong></td>";
	    print "<td>$standort";
	    print "</td>";
	    print "</tr>\n";
	}    
	if ($inventarnummer){
	    print "<tr><td bgcolor=\"lightblue\"><strong>Inventar-Nr.</strong></td>";
	    print "<td>$inventarnummer";
	    print "</td>";
	    print "</tr>\n";
	}    

	if ($lokfn){
	    print "<tr><td bgcolor=\"lightblue\"><strong>LOK FN</strong></td>";
	    print "<td>$lokfn";
	    print "</td>";
	    print "</tr>\n";
	}    

	if ($config{benchmark}){
	    $atime=new Benchmark;
	}

	my $mexresult2=$dbh->prepare("$mexstatement2") or $logger->error($DBI::errstr);
	$mexresult2->execute() or $logger->error($DBI::errstr);

	my @mexres2;
	while (@mexres2=$mexresult2->fetchrow){
	    print "<tr><td bgcolor=\"lightblue\"><strong>Sign-lok</strong></td>";
	    print "<td>$mexres2[1]";
	    print "</td>";
	    print "</tr>\n";
	}    
	$mexresult2->finish();

	if ($config{benchmark}){
	    $btime=new Benchmark;
	    $timeall=timediff($btime,$atime);
	    $logger->info("Zeit fuer : $mexstatement2 : ist ".timestr($timeall));
	    undef $atime;
	    undef $btime;
	    undef $timeall;
	}

    }

    if ($mode == 3){
	print "<tr><td bgcolor=\"lightblue\"><strong>Zugeh. Titelnr.</strong></td>";
	print "<td>";
	print "<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;sorttype=$sorttype&amp;sortorder=$sortorder&amp;database=$database&amp;searchsingletit=$titidn1\">";
	print $titidn1;
	print "</a></td>";
	print "</tr>\n";
    }

    if ($mode == 5){
	print "<tr><td><input type=checkbox name=searchmultipleaut value=$mexidn ";
	print "></td><td>";
	print "<a href=\"$config{search_loc}?sessionID=$sessionID&amp;search=Mehrfachauswahl&amp;searchmode=$searchmode&amp;rating=$rating&amp;bookinfo=$bookinfo&amp;showmexintit=$showmexintit&amp;casesensitive=$casesensitive&amp;hitrange=$hitrange&amp;sorttype=$sorttype&amp;sortorder=$sortorder&amp;database=$database&amp;searchtitofaut=$mexidn\">";
	print "<strong>$mexidn</strong></a></td>";
	return;
    }
    print "</table>" unless ($mode==6);
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
	$numberresult->execute() or $logger->error($DBI::errstr);

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
    
    if ($line=~/\"/){
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
  $globalcontents=~s/¬//g;
  $globalcontents=~s/\"//g;

  if ($type eq "swt"){
    $globalcontents=~s/&lt;/</g;
    $globalcontents=~s/&gt;/>/g;
    
  }
  else {
    $globalcontents=~s/&lt;//g;
    $globalcontents=~s/&gt;//g;
    $globalcontents=~s/<//g;
    $globalcontents=~s/>//g;
  }


  #$globalcontents=~s/ /\+/g;
  $globalcontents=~s/,/%2C/g;
  $globalcontents=~s/\[.+?\]//;
  $globalcontents=~s/ $//g;
  #$globalcontents=~s/ /\+/g;
  $globalcontents=~s/ /%20/g;

  my $globalurl="";

  if ($type eq "swt"){
    $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID&hitrange=-1&swtindexall=&verf=&hst=&swt=%22$globalcontents%22&kor=&sign=&isbn=&notation=&verknuepfung=und&ejahr=&ejahrop=genau&maxhits=200&sorttype=$sorttype&tosearch=In+allen+Katalogen+suchen";
  }

  if ($type eq "kor"){
    $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID&hitrange=-1&swtindexall=&verf=&hst=&swt=&kor=%22$globalcontents%22&sign=&isbn=&notation=&verknuepfung=und&ejahr=&ejahrop=genau&maxhits=200&sorttype=$sorttype&tosearch=In%20allen%20Katalogen%20suchen";
  }

  if ($type eq "verf"){
    $globalurl="$config{virtualsearch_loc}?sessionID=$sessionID&hitrange=-1&swtindexall=&verf=%22$globalcontents%22&hst=&swt=&kor=&sign=&isbn=&notation=&verknuepfung=und&ejahr=&ejahrop=genau&maxhits=200&sorttype=$sorttype&tosearch=In+allen+Katalogen+suchen";
  }

  print << "CATEGORY";
<tr><td bgcolor="lightblue"><strong>$name</strong></td><td><a href="$globalurl" title="Begriff in allen Katalogen suchen"><span style="font-family:Arial,helv,Helvetica,Verdana; font-size:135%; color=blue;">G</span></a>&nbsp;<a href="$url" title="Begriff in diesem Katalog suchen">$contents</td></tr>
CATEGORY

  return;
}

sub print_simple_category {

  my ($name,$contents)=@_;

  # Sonderbehandlung fuer bestimmte Kategorien
  
  if ($name eq "ISSN"){
    my $ezbquerystring="http://www.bibliothek.uni-regensburg.de/ezeit/searchres.phtml?bibid=USBK&frames=&colors=7&offset=0&KT=&KT_bool=OR&KW=&Notations[]=all&selected_colors[]=1&selected_colors[]=2&selected_colors[]=4&input_date=&PU=&IS=".$contents."&howmany=25&=Suchen";

    $contents="$contents (<a href=\"$ezbquerystring\" title=\"Verfügbarkeit in der Elektronischen Zeitschriften Bibliothek (EZB)\" target=ezb>Verf&uuml;gbarkeit EZB</a>)";
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
	<a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=insert&database=$database&singleidn=$titidn\" target=\"header\" title=\"In die Merkliste\"><img src="/images/openbib/3d-file-blue-clipboard.png" height="29" alt="In die Merkliste" border=0></a>&nbsp;
        <a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=mail&database=$database&singleidn=$titidn\" target=\"mail\" title=\"Als Mail verschicken\"><img src="/images/openbib/3d-file-blue-mailbox.png" height="29" alt="Als Mail verschicken" border=0></a>&nbsp;
        <a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=save&database=$database&singleidn=$titidn\" target=\"save\" title=\"Abspeichern\"><img src="/images/openbib/3d-file-blue-disk35.png" height="29" alt="Abspeichern" border=0></a>&nbsp;
        <a href=\"$config{managecollection_loc}?sessionID=$sessionID&action=print&database=$database&singleidn=$titidn\" target=\"print\" title=\"Ausdrucken\"><img src="/images/openbib/3d-file-blue-printer.png" height="29" alt="Ausdrucken" border=0></a>&nbsp;
       </td>
  </tr>
</table>
INSTHEAD

  }
  return;
}

sub print_mult_sel_form {
  my ($searchmode,$casesensitive,$hitrange,$rating,$bookinfo,$showmexintit,$database,$dbmode,$sessionID)=@_;

print << "SEL_FORM_HEAD";
<form method="get" action="$config{search_loc}">
<input type=hidden name=searchmode value=$searchmode>
<input type=hidden name=casesensitive value=$casesensitive>
<input type=hidden name=hitrange value=$hitrange>
<input type=hidden name=rating value=$rating>
<input type=hidden name=bookinfo value=$bookinfo>
<input type=hidden name=showmexintit value=$showmexintit>
<input type=hidden name=database value=$database>
<input type=hidden name=dbmode value=$dbmode>
<input type=hidden name=sessionID value=$sessionID>
SEL_FORM_HEAD

  return;
}

1;
