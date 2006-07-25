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
use Benchmark ':hireswallclock';
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
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::User;

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

    my $session   = new OpenBib::Session({
        sessionID => $query->param('sessionID'),
    });

    my $user      = new OpenBib::User();
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Input auslesen
  
    my $sorttype     = ($query->param('sorttype'))?$query->param('sorttype'):"author";
    my $sortall      = ($query->param('sortall'))?$query->param('sortall'):'0';
    my $sortorder    = ($query->param('sortorder'))?$query->param('sortorder'):'up';
    my $trefferliste = $query->param('trefferliste') || '';
    my $autoplus     = $query->param('autoplus')     || '';
    my $queryid      = $query->param('queryid')      || '';
    my $offset       = (defined $query->param('offset'))?$query->param('offset'):undef;
    my $hitrange     = $query->param('hitrange')     || '';
    my $database     = $query->param('database')     || '';
    my $sb           = $query->param('sb')           || 'sql';
    my $action       = $query->param('action')       || '';

    my $queryoptions_ref
        = $session->get_queryoptions($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
  
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return OK;
    }

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    my $targetdbinfo_ref
        = $config->get_targetdbinfo();

    # BEGIN Weitere Treffer holen und cachen
    #
    ####################################################################

    if ($action eq "getnext"){
        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $atime=new Benchmark;

        my $searchquery_ref = $session->get_searchquery($queryid);
        
        my $result_ref=OpenBib::Search::Util::initial_search_for_titidns({
            searchquery_ref => $searchquery_ref,
            
            serien          => 0,
            dbh             => $dbh,
            maxhits         => $hitrange,
            offset          => $offset,
            
            enrich          => 0,
            enrichkeys_ref  => {},
        });
        
        my @tidns           = @{$result_ref->{titidns_ref}};
        my $fullresultcount = $result_ref->{fullresultcount};
        
        # Wenn mindestens ein Treffer gefunden wurde
        if ($#tidns >= 0) {
            
            my $a2time;
            
            if ($config->{benchmark}) {
                $a2time=new Benchmark;
            }
            
            my @outputbuffer=();
            my @resultset=();
            my @resultlists=();
            
            foreach my $idn (@tidns) {
                push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                    titidn            => $idn,
                    dbh               => $dbh,
                    sessiondbh        => $session->{dbh},
                    database          => $database,
                    sessionID         => $session->{ID},
                    targetdbinfo_ref  => $targetdbinfo_ref,
                });
            }
            
            my $btime      = new Benchmark;
            my $timeall    = timediff($btime,$atime);
            my $resulttime = timestr($timeall,"nop");
            $resulttime    =~s/(\d+\.\d+) .*/$1/;
            
            if ($config->{benchmark}) {
                my $b2time     = new Benchmark;
                my $timeall2   = timediff($b2time,$a2time);
                
                $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel (holen)       : ist ".timestr($timeall2));
                $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel (suchen+holen): ist ".timestr($timeall));
            }

            # Weitere Treffer Cachen.

            my $idnresult=$session->{dbh}->prepare("delete from searchresults where sessionid = ? and queryid = ? and dbname = ? and offset = ? and hitrange = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($session->{ID},$queryid,$database,$offset,$hitrange) or $logger->error($DBI::errstr);

            $idnresult=$session->{dbh}->prepare("insert into searchresults values (?,?,?,?,?,?,?)") or $logger->error($DBI::errstr);
            my $storableres=unpack "H*",Storable::freeze(\@outputbuffer);

            $logger->debug("YAML-Dumped: ".YAML::Dump(\@outputbuffer));
            my $num=$#outputbuffer+1;
            $idnresult->execute($session->{ID},$database,$offset,$hitrange,$storableres,$num,$queryid) or $logger->error($DBI::errstr);
            $idnresult->finish();

            my $loginname="";
            my $password="";
      
            my $userid=$user->get_userid_of_session($session->{ID});
      
            ($loginname,$password)=$user->get_cred_for_userid($userid) if ($userid && $user->get_targettype_of_session($session->{ID}) ne "self");
      
            # Hash im Loginname ersetzen
            $loginname=~s/#/\%23/;
      
            my $hostself="http://".$r->hostname.$r->uri;
            
            # Eintraege merken fuer Lastresultset
            foreach my $item_ref (@outputbuffer) {
                push @resultset, { id       => $item_ref->{id},
                                   database => $item_ref->{database},
                               };
            }
            
            push @resultlists, {
                database   => $database,
                resultlist => \@outputbuffer,
            };

            my @offsets = $session->get_resultlists_offsets({
                    database  => $database,
                    queryid   => $queryid,
                    hitrange  => $hitrange,
                });
            
            # TT-Data erzeugen
            my $ttdata={
                view           => $view,
                stylesheet     => $stylesheet,
                sessionID      => $session->{ID},
		  
                resultlists    => \@resultlists,
                dbinfo         => $targetdbinfo_ref->{dbinfo},
		  
                loginname      => $loginname,
                password       => $password,

                database       => $database,
                queryid        => $queryid,
                offset         => $offset,
                hitrange       => $hitrange,
                offsets        => \@offsets,
                config         => $config,
                msg            => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_resultlists_showsinglepool_tname},$ttdata,$r);
            $session->updatelastresultset(\@resultset);
            return OK;

        }

        
    }
    elsif ($action eq "showrange"){
        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $atime=new Benchmark;

        my @resultlists = ();
        my @resultset   = ();
        
        foreach my $searchresult ($session->get_items_in_resultlist_per_db({
            queryid  => $queryid,
            database => $database,
            offset   => $offset,
            hitrange => $hitrange,
        })){
            my $storableres=Storable::thaw(pack "H*", $searchresult);
            
            my @outputbuffer=@$storableres;
            
            my $treffer=$#outputbuffer+1;
            
            push @resultlists, {
                database   => $database,
                resultlist => \@outputbuffer,
            };
            
            # Eintraege merken fuer Lastresultset
            foreach my $item_ref (@outputbuffer) {
                push @resultset, { id       => $item_ref->{id},
                                   database => $database,
                               };
            }
        }
      

        my $loginname="";
        my $password="";
        
        my $userid=$user->get_userid_of_session($session->{ID});
        
        ($loginname,$password)=$user->get_cred_for_userid($userid) if ($userid && $user->get_targettype_of_session($session->{ID}) ne "self");
        
        # Hash im Loginname ersetzen
        $loginname=~s/#/\%23/;
        
        my $hostself="http://".$r->hostname.$r->uri;
        
        my @offsets = $session->get_resultlists_offsets({
            database  => $database,
            queryid   => $queryid,
            hitrange  => $hitrange,
        });
            
        # TT-Data erzeugen
        my $ttdata={
            view           => $view,
            stylesheet     => $stylesheet,
            sessionID      => $session->{ID},

            qopts          => $queryoptions_ref,
            resultlists    => \@resultlists,
            dbinfo         => $targetdbinfo_ref->{dbinfo},
            
            loginname      => $loginname,
            password       => $password,
            
            database       => $database,
            queryid        => $queryid,
            offset         => $offset,
            hitrange       => $hitrange,
            offsets        => \@offsets,
            config         => $config,
            msg            => $msg,
        };
        
        OpenBib::Common::Util::print_page($config->{tt_resultlists_showsinglepool_tname},$ttdata,$r);
        $session->updatelastresultset(\@resultset);
        return OK;
    }
    
    # BEGIN Trefferliste
    #
    ####################################################################
    # Wenn die Trefferlistenfunktion ausgewaehlt wurde, dann ...
    ####################################################################
  
    if ($trefferliste) {
        my $rows=$session->get_number_of_items_in_resultlist();
        
        if ($rows <= 0) {
            OpenBib::Common::Util::print_warning($msg->maketext("Derzeit existiert (noch) keine Trefferliste"),$r,$msg);
            return OK;
        }
    
        ####################################################################
        # ... falls die Auswahlseite angezeigt werden soll
        ####################################################################
    
        if ($trefferliste eq "choice") {
      
            my @queryids     = ();
            my @querystrings = ();
            my @queryhits    = ();
      
            my $idnresult=$session->{dbh}->prepare("select distinct searchresults.queryid as queryid,queries.query as query,queries.hits as hits from searchresults,queries where searchresults.sessionid = ? and searchresults.queryid=queries.queryid order by queryid desc") or $logger->error($DBI::errstr);
            $idnresult->execute($session->{ID}) or $logger->error($DBI::errstr);
      
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

            $idnresult=$session->{dbh}->prepare("select dbname,hits from searchresults where sessionid = ? and queryid = ? order by hits desc") or $logger->error($DBI::errstr);
            $idnresult->execute($session->{ID},@{$thisquery_ref}{id}) or $logger->error($DBI::errstr);

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
                sessionID  => $session->{ID},

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
                $queryid = $session->get_max_queryid();
            }

            my @resultset=();
      
            if ($sortall == 1) {

                my @outputbuffer=();

                foreach my $item_ref ($session->get_all_items_in_resultlist({
                    queryid => $queryid,
                })) {
                    my $storableres=Storable::thaw(pack "H*", $item_ref->{searchresult});

                    push @outputbuffer, @$storableres;
                }

                my $treffer=$#outputbuffer+1;

                # Sortierung
                my @sortedoutputbuffer=();
                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

                my $loginname="";
                my $password="";

                my $userid=$user->get_userid_of_session($session->{ID});
	
                ($loginname,$password)=$user->get_cred_for_userid($userid) if ($userid && $user->get_targettype_of_session($session->{ID}) ne "self");
	
                # Hash im Loginname ersetzen
                $loginname=~s/#/\%23/;

                my $hostself="http://".$r->hostname.$r->uri;
	
                my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortboth',1,$msg);
	
                # TT-Data erzeugen
                my $ttdata={
		    view           => $view,
		    stylesheet     => $stylesheet,
		    sessionID      => $session->{ID},

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


                $session->updatelastresultset(\@resultset);
            }
            elsif ($sortall == 0) {
                # Katalogoriertierte Sortierung

                my @resultlists=();

                foreach my $item_ref ($session->get_all_items_in_resultlist({
                    queryid => $queryid,
                })) {
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
	
                my $userid=$user->get_userid_of_session($session->{ID});
	
                ($loginname,$password)=$user->get_cred_for_userid($userid) if ($userid && $user->get_targettype_of_session($session->{ID}) ne "self");
	
                # Hash im Loginname ersetzen
                $loginname=~s/#/\%23/;

                my $hostself="http://".$r->hostname.$r->uri;
	
                my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortboth',1,$msg);
	
                # TT-Data erzeugen
                my $ttdata={
		    view           => $view,
		    stylesheet     => $stylesheet,
		    sessionID      => $session->{ID},

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
                $session->updatelastresultset(\@resultset);
            }
            return OK;
        }
        ####################################################################
        # ... falls die Treffer zu einer queryid aus einer Datenbank 
        # angezeigt werden sollen
        ####################################################################
        elsif ($targetdbinfo_ref->{dbases}{$trefferliste} ne "") {
            my @resultset=();
      
            my @resultlists=();

            foreach my $searchresult ($session->get_items_in_resultlist_per_db({
                queryid  => $queryid,
                database => $trefferliste,
            })){
                my $storableres=Storable::thaw(pack "H*", $searchresult);
	
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
      
            my $userid=$user->get_userid_of_session($session->{ID});
      
            ($loginname,$password)=$user->get_cred_for_userid($userid) if ($userid && $user->get_targettype_of_session($session->{ID}) ne "self");
      
            # Hash im Loginname ersetzen
            $loginname=~s/#/\%23/;
      
            my $hostself="http://".$r->hostname.$r->uri;
      
            my ($queryargs,$sortselect,$thissortstring)=OpenBib::Common::Util::get_sort_nav($r,'sortsingle',1,$msg);
      
            # TT-Data erzeugen
            my $ttdata={
                view           => $view,
                stylesheet     => $stylesheet,
                sessionID      => $session->{ID},
		  
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
            $session->updatelastresultset(\@resultset);
            return OK;
        }
    }
  
    ####################################################################
    # ENDE Trefferliste
    #

    return OK;
}

1;
