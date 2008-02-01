####################################################################
#
#  OpenBib::Handler::Apache::ResultLists.pm
#
#  Dieses File ist (C) 2003-2007 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::ResultLists;

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
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::ResultLists::Util;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $query=Apache::Request->instance($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = new OpenBib::Session({
        sessionID => $query->param('sessionID'),
    });

    my $user      = new OpenBib::User({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Input auslesen
  
    my $sorttype     = ($query->param('sorttype'))?$query->param('sorttype'):"author";
    my $sortall      = ($query->param('sortall'))?$query->param('sortall'):'0';
    my $sortorder    = ($query->param('sortorder'))?$query->param('sortorder'):'up';
    my $autoplus     = $query->param('autoplus')     || '';
    my $queryid      = $query->param('queryid')      || '';
    my $offset       = (defined $query->param('offset'))?$query->param('offset'):0;
    ($offset)=$offset=~/^(-?\d+)$/; # offset muss numerisch sein (SQL-Injection)
    my $hitrange     = $query->param('hitrange')     || 50;
    ($hitrange)=$hitrange=~/^(-?\d+)$/; # hitrange muss numerisch sein (SQL-Injection)

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

    if ($session->get_number_of_items_in_resultlist() <= 0) {
        OpenBib::Common::Util::print_warning($msg->maketext("Derzeit existiert (noch) keine Trefferliste"),$r,$msg);
        return OK;
    }
    
    # BEGIN Weitere Treffer holen und cachen
    #
    ####################################################################

    if ($action eq "getnext"){
        my $recordlist = new OpenBib::RecordList::Title();

        my @resultset    = ();
        my @resultlists  = ();

        my ($searchquery_ref,$searchquery_hits) = $session->get_searchquery($queryid);

        if ($config->get_system_of_db($database) eq "Z39.50"){
            my $atime=new Benchmark;
            
            # Beschraenkung der Treffer pro Datenbank, da Z39.50-Abragen
            # sehr langsam sind
            # Beschraenkung ist in der Config.pm der entsprechenden DB definiert
            
            my $z3950dbh = new OpenBib::Search::Z3950($database);

            $z3950dbh->search($searchquery_ref);
            $z3950dbh->{rs}->option(elementSetName => "B");
            
            my $fullresultcount = $z3950dbh->{rs}->size();

            # Wenn mindestens ein Treffer gefunden wurde
            if ($fullresultcount >= 0) {
                
                my $a2time;
                
                if ($config->{benchmark}) {
                    $a2time=new Benchmark;
                }
                
                $recordlist = $z3950dbh->get_resultlist($offset,$hitrange);
                
                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                
                if ($config->{benchmark}) {
                    my $b2time     = new Benchmark;
                    my $timeall2   = timediff($b2time,$a2time);
                    
                    $logger->info("Zeit fuer : ".($recordlist->size())." Titel (holen)       : ist ".timestr($timeall2));
                    $logger->info("Zeit fuer : ".($recordlist->size())." Titel (suchen+holen): ist ".timestr($timeall));
                }
                
                
            }
        }
        elsif ($queryoptions_ref->{sb} eq 'xapian'){
            # Xapian
            
            my $atime=new Benchmark;

            $logger->debug("Creating Xapian DB-Object for database $database");
            my $dbh = new Search::Xapian::Database ( $config->{xapian_index_base_path}."/".$database) || $logger->fatal("Couldn't open/create Xapian DB $!\n");

            my $request = new OpenBib::Search::Local::Xapian();
            
            $request->initial_search({
                searchquery_ref => $searchquery_ref,
                
                serien          => 0,
                dbh             => $dbh,
                database        => $database,
                
                enrich          => 0,
                enrichkeys_ref  => {},
            });
            
            my $fullresultcount = scalar($request->matches);
            
            my $btime      = new Benchmark;
            my $timeall    = timediff($btime,$atime);
            my $resulttime = timestr($timeall,"nop");
            $resulttime    =~s/(\d+\.\d+) .*/$1/;
            
            $logger->info($fullresultcount . " results found in $resulttime");
            
            if ($fullresultcount >= 1){
                
                my $range_start = $offset;
                my $range_end   = $offset+$hitrange;
                my $mcount=0;

                foreach my $match ($request->matches){
                    if ($mcount <  $range_start){
                        $mcount++;
                        next;
                    }
                    last if ($mcount >= $range_end);
                    
                    my $document=$match->get_document();
                    my $titlistitem_raw=pack "H*", decode_utf8($document->get_data());
                    my $titlistitem_ref=Storable::thaw($titlistitem_raw);

                    $logger->debug("Pushing titlistitem_ref:\n".YAML::Dump($titlistitem_ref));

                    $recordlist->add($titlistitem_ref);

                    $mcount++;
                }
            } 
        }
        elsif ($queryoptions_ref->{sb} eq 'sql'){

            my $dbh
                = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                    or $logger->error_die($DBI::errstr);
            
            my $atime=new Benchmark;
            
            my $result_ref=OpenBib::Search::Util::initial_search_for_titidns({
                searchquery_ref => $searchquery_ref,
                
                serien          => 0,
                dbh             => $dbh,
                hitrange        => $hitrange,
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

                my $record     = new OpenBib::Record::Title({database=>$database});

                foreach my $idn (@tidns) {
                    $recordlist->add($record->get_brief_record({id=>$idn})->to_rawdata);
                }

                my $btime      = new Benchmark;
                my $timeall    = timediff($btime,$atime);
                my $resulttime = timestr($timeall,"nop");
                $resulttime    =~s/(\d+\.\d+) .*/$1/;
                
                if ($config->{benchmark}) {
                    my $b2time     = new Benchmark;
                    my $timeall2   = timediff($b2time,$a2time);
                    
                    $logger->info("Zeit fuer : ".($recordlist->size())." Titel (holen)       : ist ".timestr($timeall2));
                    $logger->info("Zeit fuer : ".($recordlist->size())." Titel (suchen+holen): ist ".timestr($timeall));
                }
            }
        }

        $logger->debug("Recordlist\n".YAML::Dump($recordlist->to_list));
        # Sortierung

        $recordlist->sort({order=>$sortorder,type=>$sorttype});
        
        # Weitere Treffer Cachen.

        $session->set_searchresult({
            queryid    => $queryid,
            recordlist => $recordlist,
            database   => $database,
            offset     => $offset,
            hitrange   => $hitrange,
        });
        
        my $loginname="";
        my $password="";
        
        ($loginname,$password)=$user->get_credentials() if ($user->{ID} && $user->get_targettype_of_session($session->{ID}) ne "self");
        
        # Hash im Loginname ersetzen
        $loginname=~s/#/\%23/;

        
        # Eintraege merken fuer Lastresultset
        push @resultset, @{$recordlist->to_ids};
        
        push @resultlists, {
            database   => $database,
            resultlist => $recordlist->to_list,
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

            query          => $query,
            
            qopts          => $queryoptions_ref,
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
        })){
            my $storable_ref=Storable::thaw(pack "H*", $searchresult);

            my $recordlist = new OpenBib::RecordList::Title();

            $recordlist->add_from_storable($storable_ref);
                
            # Sortierung des Outputbuffers
            
            $recordlist->sort({order=>$sortorder,type=>$sorttype});

            my $treffer=$recordlist->size();
            
            push @resultlists, {
                database   => $database,
                resultlist => $recordlist->to_list,
            };

            
            push @resultset, @{$recordlist->to_ids};

        }
      
        my $loginname="";
        my $password="";
        
        ($loginname,$password)=$user->get_credentials() if ($user->{ID} && $user->get_targettype_of_session($session->{ID}) ne "self");
        
        # Hash im Loginname ersetzen
        $loginname=~s/#/\%23/;
        
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

            query          => $query,
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
    ####################################################################
    # ... falls die Auswahlseite angezeigt werden soll
    ####################################################################
    elsif ($action eq "choice"){
        my @queryids     = ();
        my @querystrings = ();
        my @queryhits    = ();
        
        my @queries      = $session->get_all_searchqueries({
            offset => '0',
        });
        
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

        my ($resultdbs_ref,$hitcount)=$session->get_db_histogram_of_query(@{$thisquery_ref}{id}) ;
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            
            
            thisquery  => $thisquery_ref,
            queryid    => $queryid,
            
            qopts      => $queryoptions_ref,
            hitcount   => $hitcount,
            resultdbs  => $resultdbs_ref,
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
    elsif ($action eq "showall"){
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

            my $recordlist = new OpenBib::RecordList::Title();
            
            foreach my $item_ref ($session->get_all_items_in_resultlist({
                queryid => $queryid,
            })) {
                my $storable_ref=Storable::thaw(pack "H*", $item_ref->{searchresult});

                $recordlist->add_from_storable($storable_ref);
            }
            
            my $treffer=$recordlist->size();
            
            # Sortierung

            $recordlist->sort({order=>$sortorder,type=>$sorttype});

            my $loginname="";
            my $password="";
            
            ($loginname,$password)=$user->get_credentials() if ($user->{ID} && $user->get_targettype_of_session($session->{ID}) ne "self");
            
            # Hash im Loginname ersetzen
            $loginname=~s/#/\%23/;
            
            # TT-Data erzeugen
            my $ttdata={
                view           => $view,
                stylesheet     => $stylesheet,
                sessionID      => $session->{ID},
                
                resultlist     => $recordlist->to_list,
                targetdbinfo   => $targetdbinfo_ref,
                
                loginname      => $loginname,
                password       => $password,

                query          => $query,

                offset         => $offset,
                hitrange       => $hitrange,
                qopts          => $queryoptions_ref,
                
                config         => $config,
                msg            => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_resultlists_showall_sortall_tname},$ttdata,$r);

            $session->updatelastresultset($recordlist->to_ids);
        }
        elsif ($sortall == 0) {
            # Katalogoriertierte Sortierung
            
            my @resultlists=();
            
            foreach my $item_ref ($session->get_all_items_in_resultlist({
                queryid => $queryid,
            })) {
                my $storable_ref=Storable::thaw(pack "H*", $item_ref->{searchresult});
                
                my $database=$item_ref->{dbname};

                my $recordlist = new OpenBib::RecordList::Title();

                $recordlist->add_from_storable($storable_ref);

                my $treffer=$recordlist->size();
                
                # Sortierung

                $recordlist->sort({order=>$sortorder,type=>$sorttype});
                
                my @offsets = $session->get_resultlists_offsets({
                    database  => $database,
                    queryid   => $queryid,
                    hitrange  => $hitrange,
                });

                push @resultlists, {
                    database   => $database,
                    resultlist => $recordlist->to_list,
                    offsets    => \@offsets,
                };

                # Eintraege merken fuer Lastresultset
                push @resultset, @{$recordlist->to_ids};
            }
            
            my $loginname="";
            my $password="";
            
            ($loginname,$password)=$user->get_credentials() if ($user->{ID} && $user->get_targettype_of_session($session->{ID}) ne "self");
            
            # Hash im Loginname ersetzen
            $loginname=~s/#/\%23/;
            
            # TT-Data erzeugen
            my $ttdata={
                view           => $view,
                stylesheet     => $stylesheet,
                sessionID      => $session->{ID},
                
                resultlists    => \@resultlists,
                targetdbinfo   => $targetdbinfo_ref,

                offset         => $offset,
                hitrange       => $hitrange,
                qopts          => $queryoptions_ref,
                
                loginname      => $loginname,
                password       => $password,

                queryid        => $queryid,
                
                query          => $query,
                
                config         => $config,
                msg            => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_resultlists_showall_tname},$ttdata,$r);
            $session->updatelastresultset(\@resultset);
        }
        return OK;
    }

    ####################################################################
    # ENDE Trefferliste
    #

    return OK;
}

1;
