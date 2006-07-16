####################################################################
#
#  OpenBib::ResultLists.pm
#
#  Dieses File ist (C) 2003-2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::ResultLists;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable ();
use Template;
use YAML();

use OpenBib::Common::Stopwords;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::ResultLists::Util;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }
  
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # Verbindung zur SQL-Datenbank herstellen
    my $sessiondbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $userdbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);
  
    # CGI-Input auslesen
  
    my $sorttype     = ($query->param('sorttype'))?$query->param('sorttype'):"author";
    my $sortall      = ($query->param('sortall'))?$query->param('sortall'):'0';
    my $sortorder    = ($query->param('sortorder'))?$query->param('sortorder'):'up';
    my $trefferliste = $query->param('trefferliste') || '';
    my $autoplus     = $query->param('autoplus') || '';
    my $queryid      = $query->param('queryid') || '';

    my $sessionID    = ($query->param('sessionID'))?$query->param('sessionID'):'';

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
  
    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);

        $sessiondbh->disconnect();
        $userdbh->disconnect();
  
        return OK;
    }

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }

    my $targetdbinfo_ref
        = $config->get_targetdbinfo();

    # BEGIN Trefferliste
    #
    ####################################################################
    # Wenn die Trefferlistenfunktion ausgewaehlt wurde, dann ...
    ####################################################################
  
    if ($trefferliste) {
        my $idnresult=$sessiondbh->prepare("select count(sessionid) as rowcount from searchresults where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
        my $res=$idnresult->fetchrow_hashref;
        my $rows=$res->{rowcount};
        
        if ($rows <= 0) {
            OpenBib::Common::Util::print_warning($msg->maketext("Derzeit existiert (noch) keine Trefferliste"),$r,$msg);
            $idnresult->finish();

            $sessiondbh->disconnect();
            $userdbh->disconnect();
      
            return OK;
        }
    
        ####################################################################
        # ... falls die Auswahlseite angezeigt werden soll
        ####################################################################
    
        if ($trefferliste eq "choice") {
      
            my @queryids     = ();
            my @querystrings = ();
            my @queryhits    = ();
      
            $idnresult=$sessiondbh->prepare("select distinct searchresults.queryid as queryid,queries.query as query,queries.hits as hits from searchresults,queries where searchresults.sessionid = ? and searchresults.queryid=queries.queryid order by queryid desc") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
      
            my @queries=();

            while (my $res=$idnresult->fetchrow_hashref) {

                push @queries, {
                    id          => decode_utf8($res->{queryid}),
                    searchquery => Storable::thaw(pack "H*",$res->{query}),
                    hits        => decode_utf8($res->{hits}),
                };
	
            }
      
            # Finde den aktuellen Query
            my $thisquery_ref={};

            # Wenn keine Queryid angegeben wurde, dann nehme den ersten Eintrag,
            # da dieser der aktuellste ist
            if ($queryid eq "") {
                $thisquery_ref=$queries[0];
            }
            # ansonsten nehmen den ausgewaehlten
            else {
                foreach my $query_ref (@queries) {
                    if (@{$query_ref}{id} eq "$queryid") {
                        $thisquery_ref=$query_ref;
                    }
                }
            }

            $idnresult=$sessiondbh->prepare("select dbname,hits from searchresults where sessionid = ? and queryid = ? order by hits desc") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,@{$thisquery_ref}{id}) or $logger->error($DBI::errstr);

            my $hitcount=0;
            my @resultdbs=();

            while (my @res=$idnresult->fetchrow) {
                push @resultdbs, {
                    trefferdb     => decode_utf8($res[0]),
                    trefferdbdesc => $targetdbinfo_ref->{dbnames}{decode_utf8($res[0])},
                    trefferzahl   => decode_utf8($res[1]),
                };
	
                $hitcount+=decode_utf8($res[1]);
            }

            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
                sessionID  => $sessionID,

                thisquery  => $thisquery_ref,
                queryid    => $queryid,
                hitcount   => $hitcount,
                resultdbs  => \@resultdbs,
                queries    => \@queries,
                config     => $config,
                msg        => $msg,
            };
            OpenBib::Common::Util::print_page($config->{tt_resultlists_choice_tname},$ttdata,$r);

            return OK;
        }
        ####################################################################
        # ... falls alle Treffer zu einer queryid angezeigt werden sollen
        ####################################################################
        elsif ($trefferliste eq "all") {
            # Erst am Ende der Anfangsrecherche wird die queryid erzeugt. Damit ist
            # sie noch nicht vorhanden, wenn am Anfang der Seite die Sortierungs-
            # funktionalitaet bereitgestellt wird. Wenn dann ohne queryid
            # die Trefferliste sortiert werden soll, dann muss zuerst die 
            # queryid bestimmt werden. Die betreffende ist die letzte zur aktuellen
            # sessionid
            if ($queryid eq "") {
                $idnresult=$sessiondbh->prepare("select max(queryid) from queries where sessionid = ?") or $logger->error($DBI::errstr);
                $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
	
                my @res=$idnresult->fetchrow;
                $queryid = decode_utf8($res[0]);
            }

            $idnresult=$sessiondbh->prepare("select searchresult,dbname from searchresults where sessionid = ? and queryid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$queryid) or $logger->error($DBI::errstr);

            my $searchresult_ref={};
            while (my $res=$idnresult->fetchrow_hashref){
                $searchresult_ref->{$res->{dbname}}=$res->{searchresult};
            }

            my @sortedsearchresults=();
            # Sortieren von Searchresults gemaess Ordnung der DBnames in ihren OrgUnits
            foreach my $dbname ($config->get_sorted_list_of_dbnames_by_orgunit()){
                push @sortedsearchresults, {
                    dbname       => $dbname,
                    searchresult => $searchresult_ref->{$dbname},
                };
            }

            my @resultset=();
      
            if ($sortall == 1) {

                my @outputbuffer=();

                foreach my $item_ref (@sortedsearchresults) {
                    my $storableres=Storable::thaw(pack "H*", $item_ref->{searchresult});

                    push @outputbuffer, @$storableres;
                }

                my $treffer=$#outputbuffer+1;

                # Sortierung
                my @sortedoutputbuffer=();
                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

                my $loginname="";
                my $password="";

                my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
	
                ($loginname,$password)=OpenBib::Common::Util::get_cred_for_userid($userdbh,$userid) if ($userid && OpenBib::Common::Util::get_targettype_of_session($userdbh,$sessionID) ne "self");
	
                # Hash im Loginname ersetzen
                $loginname=~s/#/\%23/;

                my $hostself="http://".$r->hostname.$r->uri;
	
                my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortboth',1,$msg);
	
                # TT-Data erzeugen
                my $ttdata={
		    view           => $view,
		    stylesheet     => $stylesheet,
		    sessionID      => $sessionID,

		    searchmode     => 2,
		    bookinfo       => 0,
		    rating         => 0,
		    
		    resultlist     => \@sortedoutputbuffer,
		    targetdbinfo   => $targetdbinfo_ref,
		    
		    loginname      => $loginname,
		    password       => $password,
		    
		    queryargs      => $queryargs,
		    sortselect     => $sortselect,
		    thissortstring => $thissortstring,
		    
		    config         => $config,
                    msg            => $msg,
                };

                OpenBib::Common::Util::print_page($config->{tt_resultlists_showall_sortall_tname},$ttdata,$r);

                # Eintraege merken fuer Lastresultset
                foreach my $item_ref (@sortedoutputbuffer) {
                    push @resultset, { id       => $item_ref->{id},
				       database => $item_ref->{database},
                                   };
                }


                OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
                $idnresult->finish();
            }
            elsif ($sortall == 0) {
                # Katalogoriertierte Sortierung

                my @resultlists=();

                foreach my $item_ref (@sortedsearchresults) {
                    my $storableres=Storable::thaw(pack "H*", $item_ref->{searchresult});

                    my $database=$item_ref->{dbname};

                    my @outputbuffer=@$storableres;

                    my $treffer=$#outputbuffer+1;

                    # Sortierung
                    my @sortedoutputbuffer=();
                    OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

                    push @resultlists, {
                        database   => $database,
                        resultlist => \@sortedoutputbuffer,
                    };

                    # Eintraege merken fuer Lastresultset
                    foreach my $item_ref (@sortedoutputbuffer) {
                        push @resultset, { id       => $item_ref->{id},
					   database => $item_ref->{database},
                                       };
                    }
                }
	
                my $loginname="";
                my $password="";
	
                my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
	
                ($loginname,$password)=OpenBib::Common::Util::get_cred_for_userid($userdbh,$userid) if ($userid && OpenBib::Common::Util::get_targettype_of_session($userdbh,$sessionID) ne "self");
	
                # Hash im Loginname ersetzen
                $loginname=~s/#/\%23/;

                my $hostself="http://".$r->hostname.$r->uri;
	
                my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortboth',1,$msg);
	
                # TT-Data erzeugen
                my $ttdata={
		    view           => $view,
		    stylesheet     => $stylesheet,
		    sessionID      => $sessionID,

		    searchmode     => 2,
		    bookinfo       => 0,
		    rating         => 0,
		    
		    resultlists    => \@resultlists,
		    targetdbinfo   => $targetdbinfo_ref,
		    
		    loginname      => $loginname,
		    password       => $password,
		    
		    queryargs      => $queryargs,
		    sortselect     => $sortselect,
		    thissortstring => $thissortstring,
		    
		    config         => $config,
                    msg            => $msg,
                };
      
                OpenBib::Common::Util::print_page($config->{tt_resultlists_showall_tname},$ttdata,$r);
                OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
                $idnresult->finish();
            }
      
            $idnresult->finish();
      
            $sessiondbh->disconnect();
            $userdbh->disconnect();
      
            return OK;
        }
        ####################################################################
        # ... falls die Treffer zu einer queryid aus einer Datenbank 
        # angezeigt werden sollen
        ####################################################################
        elsif ($targetdbinfo_ref->{dbases}{$trefferliste} ne "") {
            my @resultset=();
      
            $idnresult=$sessiondbh->prepare("select searchresult from searchresults where sessionid = ? and dbname = ? and queryid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$trefferliste,$queryid) or $logger->error($DBI::errstr);
      
            my @resultlists=();

            while (my @res=$idnresult->fetchrow) {
                my $storableres=Storable::thaw(pack "H*", $res[0]);
	
                my @outputbuffer=@$storableres;
	
                my $treffer=$#outputbuffer+1;
	
                # Sortierung
                my @sortedoutputbuffer=();
                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);
	
                push @resultlists, {
                    database   => $trefferliste,
                    resultlist => \@sortedoutputbuffer,
                };
	
                # Eintraege merken fuer Lastresultset
                foreach my $item_ref (@sortedoutputbuffer) {
                    push @resultset, { id       => $item_ref->{id},
				       database => $trefferliste,
                    };
                }
            }
      
            my $loginname="";
            my $password="";
      
            my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
      
            ($loginname,$password)=OpenBib::Common::Util::get_cred_for_userid($userdbh,$userid) if ($userid && OpenBib::Common::Util::get_targettype_of_session($userdbh,$sessionID) ne "self");
      
            # Hash im Loginname ersetzen
            $loginname=~s/#/\%23/;
      
            my $hostself="http://".$r->hostname.$r->uri;
      
            my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortsingle',1,$msg);
      
            # TT-Data erzeugen
            my $ttdata={
                view           => $view,
                stylesheet     => $stylesheet,
                sessionID      => $sessionID,
		  
                searchmode     => 2,
                bookinfo       => 0,
                rating         => 0,
		  
                resultlists    => \@resultlists,
                dbinfo         => $targetdbinfo_ref->{dbinfo},
		  
                loginname      => $loginname,
                password       => $password,
		  
                queryargs      => $queryargs,
                sortselect     => $sortselect,
                thissortstring => $thissortstring,
		  
                config         => $config,
                msg            => $msg,
            };
      
      
      
            OpenBib::Common::Util::print_page($config->{tt_resultlists_showsinglepool_tname},$ttdata,$r);
            OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
            $idnresult->finish();

            $sessiondbh->disconnect();
            $userdbh->disconnect();
      
            return OK;
        }
    }
  
    ####################################################################
    # ENDE Trefferliste
    #

    $sessiondbh->disconnect();
    $userdbh->disconnect();
  
    return OK;
}

1;
