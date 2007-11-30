####################################################################
#
#  OpenBib::Connector::OLWS::Search.pm
#
#  Dieses File ist (C) 2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Connector::OLWS::Search;

use strict;
use warnings;
no warnings 'redefine';

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use Benchmark ':hireswallclock';
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::VirtualSearch::Util;

sub search {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();

    # Suchbegriffe
    my $fs        = $args{ 'fs'        } || '';
    my $verf      = $args{ 'verf'      } || '';
    my $hst       = $args{ 'hst'       } || '';
    my $swt       = $args{ 'swt'       } || '';
    my $kor       = $args{ 'kor'       } || '';
    my $sign      = $args{ 'sign'      } || '';
    my $isbn      = $args{ 'isbn'      } || '';
    my $issn      = $args{ 'issn'      } || '';
    my $notation  = $args{ 'notation'  } || '';
    my $hststring = $args{ 'hststring' } || '';
    my $mart      = $args{ 'mart'      } || '';
    my $ejahr     = $args{ 'ejahr'     } || '';
    my $ejahrop   = $args{ 'ejahrop'   } || '';

    # Boolsche Verknuepfungen
    my $boolverf      = ($args{ 'boolverf'      })?$args{ 'boolverf'     }:"AND";
    my $boolhst       = ($args{ 'boolhst'       })?$args{ 'boolhst'      }:"AND";
    my $boolswt       = ($args{ 'boolswt'       })?$args{ 'boolswt'      }:"AND";
    my $boolkor       = ($args{ 'boolkor'       })?$args{ 'boolkor'      }:"AND";
    my $boolnotation  = ($args{ 'boolnotation'  })?$args{ 'boolnotation' }:"AND";
    my $boolisbn      = ($args{ 'boolisbn'      })?$args{ 'boolisbn'     }:"AND";
    my $boolissn      = ($args{ 'boolissn'      })?$args{ 'boolissn'     }:"AND";
    my $boolsign      = ($args{ 'boolsign'      })?$args{ 'boolsign'     }:"AND";
    my $boolejahr     = ($args{ 'boolejahr'     })?$args{ 'boolejahr'    }:"AND";
    my $boolfs        = ($args{ 'boolfs'        })?$args{ 'boolfs'       }:"AND";
    my $boolmart      = ($args{ 'mart'          })?$args{ 'boolmart'     }:"AND";
    my $boolhststring = ($args{ 'boolhststring' })?$args{ 'boolhststring'}:"AND";

    # Suchoptionen
    my $hitrange   = $args{ 'hitrange'   } || '';
    my $autoplus   = $args{ 'autoplus'   } || 1;
    my $sessionID  = $args{ 'sessionID'  } || -1;
    my $searchmode = $args{ 'searchmode' } || 'short';
    my $view       = $args{ 'view'       } || '';
    my $singleidn  = $args{ 'singleidn'  } || '';
    my $database   = $args{ 'database'   } || '';
    my $maxhits    = $args{ 'maxhits'    } || 200;
    my $offset     = $args{ 'offset'     } || 1;
    my $listlength = $args{ 'listlength' } || 999999999;
    my $sorttype   = $args{ 'sorttype'   } || "author";
    my $sortorder  = $args{ 'sortorder'  } || 'up';

    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen
  
    my $session = new OpenBib::Session();

    # BEGIN DB-Bestimmung
    ####################################################################
    # Bestimmung der Datenbanken, in denen gesucht werden soll
    ####################################################################

    my @databases=();

    # Ueber view koennen bei Direkteinsprung in VirtualSearch die
    # entsprechenden Kataloge vorausgewaehlt werden
  
    if ($view) {
        my $idnresult=$config->{dbh}->prepare("select dbname from viewdbs where viewname = ? order by dbname") or $logger->error($DBI::errstr);
        $idnresult->execute($view) or $logger->error($DBI::errstr);
    
        @databases=();
        while (my @idnres=$idnresult->fetchrow) {
            push @databases, $idnres[0];
        }
        $idnresult->finish();

    }
  
    # Ansonsten verwende einzelne uebergebene Datenbank
    elsif ($database) {
        push @databases, $database;
    }

    # Wenn kein View und keine Datenbank uebergeben wurde, dann suche
    # in allen Datenbanken
    else {
    
        my $idnresult=$config->{dbh}->prepare("select dbname,description from dbinfo where active=1 order by dbname") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);
    
        @databases=();
        while (my @idnres=$idnresult->fetchrow) {
            push @databases, $idnres[0];
        }
        $idnresult->finish();
    
    }

    # ENDE DB-Bestimmung
    ####################################################################


    ####################################################################
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

    ####################################################################
    # Filter: ISBN und ISSN
  
    # Entfernung der Minus-Zeichen bei der ISBN
    $fs        =~ s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
    $isbn      =~ s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
  
    # Entfernung der Minus-Zeichen bei der ISSN
    $fs        =~ s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)/$1$2$3$4$5$6$7$8/g;
    $issn      =~ s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)/$1$2$3$4$5$6$7$8/g;
  
    $fs        = OpenBib::VirtualSearch::Util::cleansearchterm($fs);
  
    # Filter Rest
    $verf      = OpenBib::VirtualSearch::Util::cleansearchterm($verf);
    $hst       = OpenBib::VirtualSearch::Util::cleansearchterm($hst);
    $hststring = OpenBib::VirtualSearch::Util::cleansearchterm($hststring);

    # Bei hststring zusaetzlich normieren durch Weglassung des ersten
    # Stopwortes
    $hststring = OpenBib::Common::Stopwords::strip_first_stopword($hststring);
    $swt       = OpenBib::VirtualSearch::Util::cleansearchterm($swt);
    $kor       = OpenBib::VirtualSearch::Util::cleansearchterm($kor);
    $sign      = OpenBib::VirtualSearch::Util::cleansearchterm($sign);
    $isbn      = OpenBib::VirtualSearch::Util::cleansearchterm($isbn);
    $issn      = OpenBib::VirtualSearch::Util::cleansearchterm($issn);
    $mart      = OpenBib::VirtualSearch::Util::cleansearchterm($mart);
    $notation  = OpenBib::VirtualSearch::Util::cleansearchterm($notation);
    $ejahr     = OpenBib::VirtualSearch::Util::cleansearchterm($ejahr);
    $ejahrop   = OpenBib::VirtualSearch::Util::cleansearchterm($ejahrop);
  
    ####################################################################
    # Umwandlung impliziter ODER-Verknuepfung in UND-Verknuepfung
  
    if ($autoplus eq "1") {
    
        $fs   = OpenBib::VirtualSearch::Util::conv2autoplus( $fs   ) if ($fs);
        $verf = OpenBib::VirtualSearch::Util::conv2autoplus( $verf ) if ($verf);
        $hst  = OpenBib::VirtualSearch::Util::conv2autoplus( $hst  ) if ($hst);
        $kor  = OpenBib::VirtualSearch::Util::conv2autoplus( $kor  ) if ($kor);
        $swt  = OpenBib::VirtualSearch::Util::conv2autoplus( $swt  ) if ($swt);
        $isbn = OpenBib::VirtualSearch::Util::conv2autoplus( $isbn ) if ($isbn);
        $issn = OpenBib::VirtualSearch::Util::conv2autoplus( $issn ) if ($issn);
    
    }
  
    if ($hitrange eq "alles") {
        $hitrange=-1;
    }

    my $targetdbinfo_ref   = $config->get_targetdbinfo();
    my $targetcircinfo_ref = $config->get_targetcircinfo();

    # Folgende nicht erlaubte Anfragen werden sofort ausgesondert
  
    my $firstsql;
    if ($fs) {
        $firstsql=1;
    }
    if ($verf) {
        $firstsql=1;
    }
    if ($kor) {
        $firstsql=1;
    }
    if ($hst) {
        $firstsql=1;
    }
    if ($swt) {
        $firstsql=1;
    }
    if ($notation) {
        $firstsql=1;
    }
  
    if ($sign) {
        $firstsql=1;
    }
  
    if ($isbn) {
        $firstsql=1;
    }
  
    if ($issn) {
        $firstsql=1;
    }
  
    if ($mart) {
        $firstsql=1;
    }

    if ($hststring) {
        $firstsql=1;
    }
  
    #   if ($ejahr){
    #     my ($ejtest)=$ejahr=~/.*(\d\d\d\d).*/;
    #     if (!$ejtest){
    #       OpenBib::Common::Util::print_warning("Bitte geben Sie als Erscheinungsjahr eine vierstellige Zahl ein.",$r);

    #       $sessiondbh->disconnect();
      
    #       return OK;
    #     }        
    #   }
  
    #   if ($boolejahr eq "OR"){
    #     if ($ejahr){
    #       OpenBib::Common::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der
    # UND-Verkn&uuml;pfung und mindestens einem weiteren angegebenen Suchbegriff m&ouml;glich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verst&auml;ndnis f&uuml;r diese Einschr&auml;nkung.",$r);

    #       $sessiondbh->disconnect();
      
    #       return OK;
    #     }
    #   }
  
    #   if ($boolejahr eq "AND"){
    #     if ($ejahr){
    #       if (!$firstsql){
    # 	OpenBib::Common::Util::print_warning("Das Suchkriterium Jahr ist nur in Verbindung mit der
    # UND-Verkn&uuml;pfung und mindestens einem weiteren angegebenen Suchbegriff m&ouml;glich, da sonst die Teffermengen zu gro&szlig; werden. Wir bitten um Verst&auml;ndnis f&uuml;r diese Einschr&auml;nkung.",$r);

    # 	$sessiondbh->disconnect();
	
    # 	return OK;
    #       }
    #     }
    #   }
  
    #   if (!$firstsql){
    #     OpenBib::Common::Util::print_warning("Es wurde kein Suchkriterium eingegeben.",$r);

    #     $sessiondbh->disconnect();
    
    #     return OK;
    #   }
  

    my %searchresult=();

    if ($database && $singleidn) {
        my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

        my $atime;
        my $btime;
        my $timeall;
    
        $atime=new Benchmark;
    
        my $searchmultipleaut=0;
        my $searchmultiplekor=0;
        my $searchmultipleswt=0;
        my $searchmultipletit=0;
        my $rating=0;
        my $bookinfo=0;
    
        my ($normset,$mexnormset,$circexemplarliste)=OpenBib::Search::Util::get_tit_set_by_idn({
            titidn             => $singleidn,
            hint               => "none",
            dbh                => $dbh,
            sessiondbh         => $session->{dbh},
            searchmultipleaut  => 0,
            searchmultiplekor  => 0,
            searchmultipleswt  => 0,
            searchmultiplekor  => 0,
            searchmultipletit  => 0,
            searchmode         => $searchmode,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => $targetcircinfo_ref,
            hitrange           => $hitrange,
            rating             => $rating,
            bookinfo           => $bookinfo,
            sorttype           => $sorttype,
            sortorder          => $sortorder,
            database           => $database,
            sessionID          => $sessionID
        });

        my $treffer="";

        if ($normset) {
            $treffer=1;
        }	
	
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
    
        if ($config->{benchmark}) {
            $logger->info("Zeit fuer : $treffer Titel : ist ".timestr($timeall));
        }
    
    
        my $resulttime=timestr($timeall,"nop");
        $resulttime=~s/(\d+\.\d+) .*/$1/;
	
        $searchresult{$database}{result}{normset}=$normset;
        $searchresult{$database}{result}{mexnormset}=$mexnormset;
        $searchresult{$database}{result}{circexemplarliste}=$circexemplarliste;
        $searchresult{$database}{dbhits}=$treffer;
    
        undef $atime;
        undef $btime;
        undef $timeall;
    
        $dbh->disconnect;
    
        return { 
	    searchresult => \%searchresult,
	    totalhits    => $treffer
        };
    
    
    }
    else {
        $verf  =~s/%2B(\w+)/$1/g;
        $hst   =~s/%2B(\w+)/$1/g;
        $kor   =~s/%2B(\w+)/$1/g;
        $ejahr =~s/%2B(\w+)/$1/g;
        $isbn  =~s/%2B(\w+)/$1/g;
        $issn  =~s/%2B(\w+)/$1/g;
    
  
        my $gesamttreffer=0;
    
        # BEGIN Anfrage an Datenbanken schicken und Ergebnisse einsammeln
        #
        ######################################################################
        # Schleife ueber alle Datenbanken 
        ######################################################################
    
    
        my @resultset=();
    
        foreach my $database (@databases) {
      
            #####################################################################
            ## Ausleihkonfiguration fuer den Katalog einlesen
      
            my $dbinforesult=$config->{dbh}->prepare("select circ,circurl,circcheckurl,circdb from dboptions where dbname = ?") or $logger->error($DBI::errstr);
            $dbinforesult->execute($database) or $logger->error($DBI::errstr);;
    
            my $circ=0;
            my $circurl="";
            my $circcheckurl="";
            my $circdb="";
      
            while (my $result=$dbinforesult->fetchrow_hashref()) {
                $circ=$result->{'circ'};
                $circurl=$result->{'circurl'};
                $circcheckurl=$result->{'circcheckurl'};
                $circdb=$result->{'circdb'};
            }
      
            $dbinforesult->finish();
      
      
            my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

            my @tidns=();
            if ($database && $singleidn) {
                push @tidns, $singleidn;
            }
            else {
                @tidns=OpenBib::Search::Util::initital_search_for_titidns({
                    fs            => $fs,
                    verf          => $verf,
                    hst           => $hst,
                    hststring     => $hststring,
                    swt           => $swt,
                    kor           => $kor,
                    notation      => $notation,
                    isbn          => $isbn,
                    issn          => $issn,
                    sign          => $sign,
                    ejahr         => $ejahr,
                    ejahrop       => $ejahrop,
                    mart          => $mart,
            
                    boolfs        => $boolfs,
                    boolverf      => $boolverf,
                    boolhst       => $boolhst,
                    boolhststring => $boolhststring,
                    boolswt       => $boolswt,
                    boolkor       => $boolkor,
                    boolnotation  => $boolnotation,
                    boolisbn      => $boolisbn,
                    boolissn      => $boolissn,
                    boolsign      => $boolsign,
                    boolejahr     => $boolejahr,
                    boolmart      => $boolmart,

                    dbh           => $dbh,
                    maxhits       => $maxhits,
                });
            }
      
            # Wenn mindestens ein Treffer gefunden wurde
      
            if ($#tidns >= 0) {
                my @outputbuffer=();

                my $atime=new Benchmark;
	
                foreach my $idn (@tidns) {

                    push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                        titidn            => "$idn",
                        hint              => "none",
                        mode              => 5,
                        dbh               => $dbh,
                        sessiondbh        => $session->{dbh},
                        searchmultipleaut => 0,
                        searchmultiplekor => 0,
                        searchmultipleswt => 0,
                        searchmultiplenot => 0,
                        searchmultipletit => 0,
                        searchmode        => $searchmode,
                        hitrange          => $hitrange,
                        rating            => '',
                        bookinfo          => '',
                        sorttype          => $sorttype,
                        sortorder         => $sortorder,
                        database          => $database,
                        sessionID         => $sessionID,
                    });
                }
                
                my $btime=new Benchmark;
                my $timeall=timediff($btime,$atime);
	
                if ($config->{benchmark}) {
                    $logger->debug("Zeit fuer : ".($#outputbuffer+1)." : ist ".timestr($timeall));
                }

                my @sortedoutputbuffer=();
	
                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
	
                my $treffer=$#sortedoutputbuffer+1;
	
                my $resulttime=timestr($timeall,"nop");
                $resulttime=~s/(\d+\.\d+) .*/$1/;
	
                $searchresult{$database}{result}=\@sortedoutputbuffer;
                $searchresult{$database}{dbhits}=$treffer;
                $gesamttreffer=$gesamttreffer+$treffer;
	
                undef $atime;
                undef $btime;
                undef $timeall;
	
            }
            $dbh->disconnect;
        }

        return {
	    fs           => $fs, 
	    databases    => \@databases,
	    searchresult => \%searchresult,
	    totalhits    => $gesamttreffer,
        };
    }
}

sub get_aut_ans_by_idn {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Suchbegriffe
    my $id        = $args{ 'id'        } || '';
    my $database  = $args{ 'database'  } || '';

    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);

    my $ans=OpenBib::Search::Util::get_aut_ans_by_idn($id,$dbh);

    $logger->debug("Ans: $ans");

    $dbh->disconnect;

    return SOAP::Data->type(
        string=> $ans ) ->name('A0001');
}

sub get_kor_ans_by_idn {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Suchbegriffe
    my $id        = $args{ 'id'        } || '';
    my $database  = $args{ 'database'  } || '';

    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);

    my $ans=OpenBib::Search::Util::get_kor_ans_by_idn($id,$dbh);
    
    $dbh->disconnect;

    return SOAP::Data->type(
        string=> $ans ) ->name('C0001');

}

sub get_swt_ans_by_idn {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Suchbegriffe
    my $id        = $args{ 'id'        } || '';
    my $database  = $args{ 'database'  } || '';

    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);

    my $ans=OpenBib::Search::Util::get_swt_ans_by_idn($id,$dbh);
    
    $dbh->disconnect;

    return SOAP::Data->type(
        string=> $ans ) ->name('S0001');
}

sub get_not_ans_by_idn {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Suchbegriffe
    my $id        = $args{ 'id'        } || '';
    my $database  = $args{ 'database'  } || '';
    
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
    

    my $ans=OpenBib::Search::Util::get_not_ans_by_idn($id,$dbh);
    
    $dbh->disconnect;

    return SOAP::Data->type(
        string=> $ans ) ->name('N0001');

}

sub get_recent_titids_by_aut {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Suchbegriffe
    my $database  =  $args{ 'database'  } || '';
    my $id        = ($args{ 'id'        } =~/^\d+$/)?$args{'id'   }:0;
    my $limit     = ($args{ 'limit'     } =~/^\d+$/)?$args{'limit'}:0;

    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
    
    my $titlist_ref=OpenBib::Search::Util::get_recent_titids_by_aut({
        dbh   => $dbh,
        id    => $id,
        limit => $limit,
    });
    
    $dbh->disconnect;

    return $titlist_ref;
}

sub get_recent_titids_by_kor {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Suchbegriffe
    my $database  =  $args{ 'database'  } || '';
    my $id        = ($args{ 'id'        } =~/^\d+$/)?$args{'id'   }:0;
    my $limit     = ($args{ 'limit'     } =~/^\d+$/)?$args{'limit'}:0;

    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);

    my $titlist_ref=OpenBib::Search::Util::get_recent_titids_by_kor({
        dbh   => $dbh,
        id    => $id,
        limit => $limit,
    });
    
    $dbh->disconnect;

    return $titlist_ref;
}

sub get_recent_titids_by_swt {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Suchbegriffe
    my $database  =  $args{ 'database'  } || '';
    my $id        = ($args{ 'id'        } =~/^\d+$/)?$args{'id'   }:0;
    my $limit     = ($args{ 'limit'     } =~/^\d+$/)?$args{'limit'}:0;

    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);

    my $titlist_ref=OpenBib::Search::Util::get_recent_titids_by_swt({
        dbh   => $dbh,
        id    => $id,
        limit => $limit,
    });
    
    $dbh->disconnect;

    return $titlist_ref;
}

sub get_recent_titids_by_not {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Suchbegriffe
    my $database  =  $args{ 'database'  } || '';
    my $id        = ($args{ 'id'        } =~/^\d+$/)?$args{'id'   }:0;
    my $limit     = ($args{ 'limit'     } =~/^\d+$/)?$args{'limit'}:0;

    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);

    my $titlist_ref=OpenBib::Search::Util::get_recent_titids_by_not({
        dbh   => $dbh,
        id    => $id,
        limit => $limit,
    });
    
    $dbh->disconnect;

    return $titlist_ref;
}

sub get_tit_listitem_by_idn {
    my ($class, %args) = @_;

    # Log4perl logger erzeugen

    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Suchbegriffe
    my $database  =  $args{ 'database'  } || '';
    my $id        = ($args{ 'id'        } =~/^\d+$/)?$args{'id'   }:0;

    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);

    my $session = new OpenBib::Session();

    my $targetdbinfo_ref
        = $config->get_targetdbinfo();

    my $tititem_ref=OpenBib::Search::Util::get_tit_listitem_by_idn({
        titidn            => $id,
        dbh               => $dbh,
        sessiondbh        => $session->{dbh},
        database          => $database,
        sessionID         => '-1',
        targetdbinfo_ref  => $targetdbinfo_ref,
    });

    $dbh->disconnect;

    return $tititem_ref;
};

1;
