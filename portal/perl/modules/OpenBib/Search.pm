#####################################################################
#
#  OpenBib::Search.pm
#
#  Copyright 1997-2007 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Title;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;

my $benchmark;

if ($OpenBib::Config::config{benchmark}) {
    use Benchmark ':hireswallclock';
}

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

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################
  
    #####################################################################
    ## Hitrange: Anzahl gleichzeitig ausgegebener Treffer (Blaettern)
    ##          >0  - gibt die maximale Zahl an
    ##          <=0 - gibt immer alle Treffer aus
  
    my $hitrange=($query->param('hitrange'))?$query->param('hitrange'):-1;
    ($hitrange)=$hitrange=~/^(-?\d+)$/; # hitrange muss numerisch sein (SQL-Injection)
  
    #####################################################################
    ## Offset: Maximale Anzahl ausgegebener Treffer bei Anfangs-Suche
    ##          >0  - hitrange Treffer werden ab dieser Nr. ausgegeben 
  
    my $offset=($query->param('offset'))?$query->param('offset'):0;
    ($offset)=$offset=~/^(-?\d+)$/; # offset muss numerisch sein (SQL-Injection)

    #####################################################################
    ## Database: Name der verwendeten SQL-Datenbank
  
    my $database=($query->param('database'))?$query->param('database'):'inst001';
  
    #####################################################################
    ## Sortierung der Titellisten
  
    my $sorttype  = ($query->param('sorttype'))?$query->param('sorttype'):"author";
    my $sortorder = ($query->param('sortorder'))?$query->param('sortorder'):"up";

    my $benchmark=0;

    #####################################################################
    # Variablen in <FORM>, die den Such-Flu"s steuern
    #####################################################################
  
    #####################################################################
    ## Initialsearch:
  
    my $generalsearch     = $query->param('generalsearch')     || '';
    my $swtindex          = $query->param('swtindex')          || '';
    my $swtindexall       = $query->param('swtindexall')       || '';

    my $searchsingletit   = $query->param('searchsingletit')   || '';
    my $searchsingleaut   = $query->param('searchsingleaut')   || '';
    my $searchsingleswt   = $query->param('searchsingleswt')   || '';
    my $searchsinglenot   = $query->param('searchsinglenot')   || '';
    my $searchsinglekor   = $query->param('searchsinglekor')   || '';

    my $searchmultipleaut = $query->param('searchmultipleaut') || '';
    my $searchmultipletit = $query->param('searchmultipletit') || '';
    my $searchmultiplekor = $query->param('searchmultiplekor') || '';
    my $searchmultiplenot = $query->param('searchmultiplenot') || '';
    my $searchmultipleswt = $query->param('searchmultipleswt') || '';

    my $searchtitofaut    = $query->param('searchtitofaut')    || '';
    my $searchtitofurhkor = $query->param('searchtitofurhkor') || '';
    my $searchtitofnot    = $query->param('searchtitofnot')    || '';
    my $searchtitofswt    = $query->param('searchtitofswt')    || '';

    my $queryid           = $query->param('queryid')           || '';

    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########
  
    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen
  
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $queryoptions_ref
        = $session->get_queryoptions($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    my $targetdbinfo_ref
        = $config->get_targetdbinfo();

    my $targetcircinfo_ref
        = $config->get_targetcircinfo();

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        $dbh->disconnect();

        return OK;
    }
    
    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

  
    #####################################################################
    ## Eigentliche Suche (default)

    #####################################################################
    ## Schlagwortindex
  
    if ($swtindex ne "") {
    
        OpenBib::Search::Util::print_index_by_swt({
            swt              => $swtindex,
            dbh              => $dbh,
            sessiondbh       => $session->{dbh},
            targetdbinfo_ref => $targetdbinfo_ref,
            queryoptions_ref => $queryoptions_ref,
            database         => $database,
            sessionID        => $session->{ID},
            apachereq        => $r,
            stylesheet       => $stylesheet,
            view             => $view,
        });
        return OK;
    }

    #######################################################################
    # Nachdem initial per SQL nach den Usereingaben eine Treffermenge 
    # gefunden wurde, geht es nun exklusiv in der SQL-DB weiter

    if ($generalsearch) { 
        if (($generalsearch=~/^verf/)||($generalsearch=~/^pers/)) {
            my $verfidn=$query->param("$generalsearch");
            
            my $normset=OpenBib::Record::Person->new({database => $database})->get_full_record({id => $verfidn})->{normset};

	    my $poolname=$targetdbinfo_ref->{sigel}{
	      $targetdbinfo_ref->{dbases}{$database}};
            
            # TT-Data erzeugen
            my $ttdata={
                view             => $view,
                stylesheet       => $stylesheet,
                database         => $database,
		poolname         => $poolname,
                queryoptions_ref => $queryoptions_ref,
                sessionID        => $session->{ID},
                normset          => $normset,
                
                config     => $config,
                msg        => $msg,
            };
            OpenBib::Common::Util::print_page($config->{tt_search_showautset_tname},$ttdata,$r);
            return OK;
        }
    
        if ($generalsearch=~/^supertit/) {
            my $supertitidn = $query->param("$generalsearch");
            my $hits        = 0;

            # Zuerst Gesamtzahl bestimmen
            my $reqstring="select count(distinct targetid) as conncount from conn where sourceid=? and sourcetype=1 and targettype=1";
            my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($supertitidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

            my $res=$request->fetchrow_hashref;
            $hits = $res->{conncount};

            my $limits="";
            if ($hitrange > 0){
                $limits="limit $offset,$hitrange";
            }

            # Bestimmung der Titel
            $reqstring="select distinct targetid from conn where sourceid=? and sourcetype=1 and targettype=1 $limits";
            $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($supertitidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

            my @titidns=();
            
            while (my $res=$request->fetchrow_hashref) {
                push @titidns, $res->{targetid};
            }

            $request->finish();
            
            if ($#titidns == -1) {
                OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
                return OK;
            }
      
            if ($#titidns == 0) {
                OpenBib::Record::Title->new({database=>$database})
                      ->get_full_record({id=>$titidns[0]})
                          ->print_to_handler({
                              session            => $session,
                              queryoptions_ref   => $queryoptions_ref,
#                              searchquery_ref    => $searchquery_ref,
#                              queryid            => $queryid,
                              apachereq          => $r,
                              stylesheet         => $stylesheet,
                              view               => $view,
                              msg                => $msg,
                          });
                return OK;
            }

            if ($#titidns > 0) {
                my ($atime,$btime,$timeall);
                
                if ($config->{benchmark}) {
                    $atime=new Benchmark;
                }

                my $recordlist = new OpenBib::RecordList::Title();
                my $record     = new OpenBib::Record::Title({database=>$database});
                
                foreach my $idn (@titidns) {
                    $recordlist->add($record->get_brief_record({id=>$idn})->to_rawdata);
                }

                if ($config->{benchmark}) {
                    $btime   = new Benchmark;
                    $timeall = timediff($btime,$atime);
                    $logger->info("Zeit fuer : ".($recordlist->get_number)." Titel : ist ".timestr($timeall));
                    undef $atime;
                    undef $btime;
                    undef $timeall;
                }

                $recordlist->sort({order=>$sortorder,type=>$sorttype});

                $recordlist->print_to_handler({
                    queryoptions_ref => $queryoptions_ref,
                    database         => $database,
                    sessionID        => $session->{ID},
                    apachereq        => $r,
                    stylesheet       => $stylesheet,
                    view             => $view,
                    hits             => $hits,
                    offset           => $offset,
                    hitrange         => $hitrange,
                    msg              => $msg,
                });

                $session->updatelastresultset($recordlist->to_ids);

                return OK;
            }
        }

        if ($generalsearch=~/^subtit/) {
            my $subtitidn=$query->param("$generalsearch");
            my $hits        = 0;

            my $reqstring="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=1";
            my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($subtitidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
            
            my $res=$request->fetchrow_hashref;
            $hits = $res->{conncount};

            my $limits="";
            if ($hitrange > 0){
                $limits="limit $offset,$hitrange";
            }
            
            # Bestimmung der Titel
            $reqstring="select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=1 $limits";
            $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($subtitidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

            my @titidns=();
            
            while (my $res=$request->fetchrow_hashref) {
                push @titidns, $res->{sourceid};
            }

            $request->finish();
            
            if ($#titidns == -1) {
                OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
                return OK;
            }
      
            if ($#titidns == 0) {
                OpenBib::Record::Title->new({database=>$database})
                      ->get_full_record({id=>$titidns[0]})
                          ->print_to_handler({
                              session            => $session,
                              queryoptions_ref   => $queryoptions_ref,
#                              searchquery_ref    => $searchquery_ref,
#                              queryid            => $queryid,
                              apachereq          => $r,
                              stylesheet         => $stylesheet,
                              view               => $view,
                              msg                => $msg,
                          });

                return OK;
            }
      
            if ($#titidns > 0) {
                my ($atime,$btime,$timeall);
                
                if ($config->{benchmark}) {
                    $atime=new Benchmark;
                }

                my $recordlist = new OpenBib::RecordList::Title();
                my $record     = new OpenBib::Record::Title({database=>$database});
                
                foreach my $idn (@titidns) {
                    $recordlist->add($record->get_brief_record({id=>$idn})->to_rawdata);
                }

                if ($config->{benchmark}) {
                    $btime   = new Benchmark;
                    $timeall = timediff($btime,$atime);
                    $logger->info("Zeit fuer : ".($recordlist->get_number)." Titel : ist ".timestr($timeall));
                    undef $atime;
                    undef $btime;
                    undef $timeall;
                }

                $recordlist->sort({order=>$sortorder,type=>$sorttype});

                $recordlist->print_to_handler({
                    queryoptions_ref => $queryoptions_ref,
                    database         => $database,
                    sessionID        => $session->{ID},
                    apachereq        => $r,
                    stylesheet       => $stylesheet,
                    view             => $view,
                    hits             => $hits,
                    offset           => $offset,
                    hitrange         => $hitrange,
                    msg              => $msg,
                });

                $session->updatelastresultset($recordlist->to_ids);

                return OK;
            }
        }

        if ($generalsearch=~/^hst/) {
            my $titidn=$query->param("$generalsearch");

            OpenBib::Record::Title->new({database=>$database})
                  ->get_full_record({id=>$titidn})
                      ->print_to_handler({
                          session            => $session,
                          queryoptions_ref   => $queryoptions_ref,
                          #searchquery_ref    => $searchquery_ref,
                          #queryid            => $queryid,
                          apachereq          => $r,
                          stylesheet         => $stylesheet,
                          view               => $view,
                          msg                => $msg,
                      });

            return OK;
        }
    
        if ($generalsearch=~/^swt/) {
            my $swtidn=$query->param("$generalsearch");
            my $normset=OpenBib::Record::Subject->new({database => $database})->get_full_record({id => $swtidn})->to_rawdata;
            
	    my $poolname=$targetdbinfo_ref->{sigel}{
	      $targetdbinfo_ref->{dbases}{$database}};

            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
                database   => $database,
	        poolname   => $poolname,
                qopts      => $queryoptions_ref,
                sessionID  => $session->{ID},
                normset    => $normset,

                config     => $config,
                msg        => $msg,
            };
            OpenBib::Common::Util::print_page($config->{tt_search_showswtset_tname},$ttdata,$r);
            return OK;
        }
    
        if ($generalsearch=~/^not/) {
            my $notidn=$query->param("notation");

            my $normset=OpenBib::Record::Classification->new({database => $database})->get_full_record({id => $notidn})->to_rawdata;

	    my $poolname=$targetdbinfo_ref->{sigel}{
	      $targetdbinfo_ref->{dbases}{$database}};

            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
                database   => $database,
		poolname   => $poolname,
                qopts      => $queryoptions_ref,
                sessionID  => $session->{ID},
                normset    => $normset,
                
                config     => $config,
                msg        => $msg,
            };
            OpenBib::Common::Util::print_page($config->{tt_search_shownotset_tname},$ttdata,$r);
            return OK;
        }
    
    }
  
    #####################################################################
    if ($searchmultipletit) {
        my @mtitidns=$query->param('searchmultipletit');

        OpenBib::Search::Util::print_mult_tit_set_by_idn({
            titidns_ref        => \@mtitidns,
            dbh                => $dbh,
            sessiondbh         => $session->{dbh},
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => $targetcircinfo_ref,
            queryoptions_ref   => $queryoptions_ref,
            database           => $database,
            sessionID          => $session->{ID},
            apachereq          => $r,
            stylesheet         => $stylesheet,
            view               => $view,
            msg                => $msg,
        });
        return OK;
    }

    #####################################################################
    # Wird derzeit nicht unterstuetzt

#     if ($searchmultipleaut){
#         my @mautidns=$query->param('searchmultipleaut');
#         OpenBib::Search::Util::print_mult_aut_set_by_idn({
#             autidns_ref        => \@mautidns,
#             dbh                => $dbh,
#             sessiondbh         => $session->{dbh},
#             searchmultipleaut  => $searchmultipleaut,
#             targetdbinfo_ref   => $targetdbinfo_ref,
#             targetcircinfo_ref => $targetcircinfo_ref,
#             hitrange           => $hitrange,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $session->{ID},
#             apachereq          => $r,
#             stylesheet         => $stylesheet,
#             view               => $view,
#         });
#         return OK;
#     }
    
    #####################################################################
    # Wird derzeit nicht unterstuetzt

#     if ($searchmultiplekor){
#         my @mkoridns=$query->param('searchmultiplekor');
#         OpenBib::Search::Util::print_mult_kor_set_by_idn({
#             koridns_ref        => \@mkoridns,
#             dbh                => $dbh,
#             sessiondbh         => $session->{dbh},
#             searchmultiplekor  => $searchmultiplekor,
#             targetdbinfo_ref   => $targetdbinfo_ref,
#             targetcircinfo_ref => $targetcircinfo_ref,
#             hitrange           => $hitrange,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $session->{ID},
#             apachereq          => $r,
#             stylesheet         => $stylesheet,
#             view               => $view,
#         });
#         return OK;
#     }
  
    #####################################################################
    # Wird derzeit nicht unterstuetzt
  
#    if ($searchmultiplenot){
#         my @mnotidns=$query->param('searchmultiplenot');
#         OpenBib::Search::Util::print_mult_not_set_by_idn({
#             notidns_ref        => \@mnotidns,
#             dbh                => $dbh,
#             sessiondbh         => $session->{dbh},
#             searchmultiplekor  => $searchmultiplekor,
#             targetdbinfo_ref   => $targetdbinfo_ref,
#             targetcircinfo_ref => $targetcircinfo_ref,
#             hitrange           => $hitrange,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $session->{ID},
#             apachereq          => $r,
#             stylesheet         => $stylesheet,
#             view               => $view,
#         });
#         return OK;
#    }
    #####################################################################
    # Wird derzeit nicht unterstuetzt
  
#    if ($searchmultipleswt){
#         my @mswtidns=$query->param('searchmultipleswt');
#         OpenBib::Search::Util::print_mult_swt_set_by_idn({
#             swtidns_ref        => \@mswtidns,
#             dbh                => $dbh,
#             sessiondbh         => $session->{dbh},
#             searchmultiplekor  => $searchmultiplekor,
#             targetdbinfo_ref   => $targetdbinfo_ref,
#             targetcircinfo_ref => $targetcircinfo_ref,
#             hitrange           => $hitrange,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $session->{ID},
#             apachereq          => $r,
#             stylesheet         => $stylesheet,
#             view               => $view,
#         });
#         return OK;
#    }
  
    #####################################################################
  
    if ($searchsingletit) {
        # Zuerst die zugehoerige Suchanfrage bestimmen

        my $searchquery_ref = {};

        if ($queryid){
            $searchquery_ref = OpenBib::Common::Util::get_searchquery_of_queryid({
                queryid   => $queryid,
                sessionID => $session->{ID},
            });
        }

        if ($config->get_system_of_db($database) eq "Z39.50"){
            my $z3950dbh = new OpenBib::Search::Z3950($database);

            my ($normset,$mexnormset) = $z3950dbh->get_singletitle($searchsingletit);
            
            my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation({
                sessiondbh => $session->{dbh},
                database   => $database,
                titidn     => $searchsingletit,
                sessionID  => $session->{ID},
            });
            
            my $poolname=$targetdbinfo_ref->{sigel}{
                $targetdbinfo_ref->{dbases}{$database}};
            
            # TT-Data erzeugen
            my $ttdata={
                view        => $view,
                stylesheet  => $stylesheet,
                database    => $database,
                poolname    => $poolname,
                prevurl     => $prevurl,
                nexturl     => $nexturl,
                qopts       => $queryoptions_ref,
                sessionID   => $session->{ID},
                titidn      => $searchsingletit,
                normset     => $normset,
                mexnormset  => $mexnormset,
                circset     => {},

                searchquery => $searchquery_ref,
                
                config      => $config,
                msg         => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_search_showtitset_tname},$ttdata,$r);
        }
        else {
            OpenBib::Record::Title->new({database=>$database})
                  ->get_full_record({id=>$searchsingletit})
                      ->print_to_handler({
                          session            => $session,
                          queryoptions_ref   => $queryoptions_ref,
                          #searchquery_ref    => $searchquery_ref,
                          #queryid            => $queryid,
                          apachereq          => $r,
                          stylesheet         => $stylesheet,
                          view               => $view,
                          msg                => $msg,
                      });
        }

        return OK;
    }
  
    #####################################################################
    if ($searchsingleswt) {
        my $normset=OpenBib::Record::Subject->new({database => $database})->get_full_record({id => $searchsingleswt})->to_rawdata;

	my $poolname=$targetdbinfo_ref->{sigel}{
	  $targetdbinfo_ref->{dbases}{$database}};

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            poolname   => $poolname,
            qopts      => $queryoptions_ref,
            sessionID  => $session->{ID},
            normset    => $normset,
            
            config     => $config,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_search_showswtset_tname},$ttdata,$r);
        return OK;
    }
  
    ######################################################################
    if ($searchsinglekor) {
        my $normset=OpenBib::Record::CorporateBody->new({database => $database})->get_full_record({id => $searchsinglekor})->to_rawdata;
        
	my $poolname=$targetdbinfo_ref->{sigel}{
	  $targetdbinfo_ref->{dbases}{$database}};

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
	    poolname   => $poolname,
            qopts      => $queryoptions_ref,
            sessionID  => $session->{ID},
            normset    => $normset,
            
            config     => $config,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_search_showkorset_tname},$ttdata,$r);
        return OK;
    }
    
    ######################################################################
    if ($searchsinglenot) {
        my $normset=OpenBib::Record::Classification->new({database => $database})->get_full_record({id => $searchsinglenot})->to_rawdata;
	
	my $poolname=$targetdbinfo_ref->{sigel}{
	  $targetdbinfo_ref->{dbases}{$database}};

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            poolname   => $poolname,
            qopts      => $queryoptions_ref,
            sessionID  => $session->{ID},
            normset    => $normset,
            
            config     => $config,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_search_shownotset_tname},$ttdata,$r);
        return OK;
    }
  
    #####################################################################
    if ($searchsingleaut) {

        my $normset=OpenBib::Record::Person->new({database => $database})->get_full_record({id => $searchsingleaut})->to_rawdata;
        
        my $poolname=$targetdbinfo_ref->{sigel}{
            $targetdbinfo_ref->{dbases}{$database}};
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            poolname   => $poolname,
            qopts      => $queryoptions_ref,
            sessionID  => $session->{ID},
            normset    => $normset,
            
            config     => $config,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_search_showautset_tname},$ttdata,$r);
        return OK;
    }
    
    if ($searchtitofaut) {
        my @titelidns = ();
        my $hits      = 0;

        # Verfasser-Id numerisch, dann Titel zu von entsprechendem Normdaten
        # satz bestimmen.
        if ($searchtitofaut =~ /^\d+$/){
            # Zuerst Gesamtzahl bestimmen
            my $request=$dbh->prepare("select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=2") or $logger->error($DBI::errstr);
            $request->execute($searchtitofaut);
            
            my $res=$request->fetchrow_hashref;
            $hits = $res->{conncount};

            my $limits="";
            if ($hitrange > 0){
                $limits="limit $offset,$hitrange";
            }

            # Bestimmung der Titel
            $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=2 $limits") or $logger->error($DBI::errstr);
            $request->execute($searchtitofaut);
            
            
            while (my $res=$request->fetchrow_hashref){
                push @titelidns, $res->{sourceid};
            }
            $request->finish();            
        }
        # ... ansonsten wird fuer den Fall fehlender Normdaten der komplette
        # Verfasser uebergeben, der ausschliesslich in den Titeldaten zu finden ist.
        else {
            $searchtitofaut = OpenBib::Common::Util::grundform({
                content  => $searchtitofaut,
            });
            
            # Bestimmung der Titel
            # ToDo parametrisierung der Verfasserkategorien pro Katalog
            my $request=$dbh->prepare("select distinct id from tit_string where category in (100,101,103) and content=?") or $logger->error($DBI::errstr);
            $request->execute($searchtitofaut);
            
            while (my $res=$request->fetchrow_hashref){
                push @titelidns, $res->{id};
            }        
            $request->finish();
        }
        
        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
            return OK;
        }
    
        if ($#titelidns == 0) {
            OpenBib::Record::Title->new({database=>$database})
                  ->get_full_record({id=>$titelidns[0]})
                      ->print_to_handler({
                          session            => $session,
                          queryoptions_ref   => $queryoptions_ref,
                          #searchquery_ref    => $searchquery_ref,
                          #queryid            => $queryid,
                          apachereq          => $r,
                          stylesheet         => $stylesheet,
                          view               => $view,
                          msg                => $msg,
                      });

            return OK;
        }
    
        if ($#titelidns > 0) {
            my ($atime,$btime,$timeall);
            
            if ($config->{benchmark}) {
                $atime=new Benchmark;
            }
            
            my $recordlist = new OpenBib::RecordList::Title();
            my $record     = new OpenBib::Record::Title({database=>$database});
                
            foreach my $idn (@titelidns) {
                $recordlist->add($record->get_brief_record({id=>$idn})->to_rawdata);
            }
            
            if ($config->{benchmark}) {
                $btime   = new Benchmark;
                $timeall = timediff($btime,$atime);
                $logger->info("Zeit fuer : ".($recordlist->get_number)." Titel : ist ".timestr($timeall));
                undef $atime;
                undef $btime;
                undef $timeall;
            }
            
            $recordlist->sort({order=>$sortorder,type=>$sorttype});
            
            $recordlist->print_to_handler({
                queryoptions_ref => $queryoptions_ref,
                database         => $database,
                sessionID        => $session->{ID},
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                hits             => $hits,
                offset           => $offset,
                hitrange         => $hitrange,
                msg              => $msg,
            });
            
            $session->updatelastresultset($recordlist->to_ids);
            
            return OK;
        }	
    }
  
    #####################################################################
    if ($searchtitofurhkor) {
        my @titelidns = ();
        my $hits      = 0;

        # Koerperschafts-Id numerisch, dann Titel zu von entsprechendem Normdaten
        # satz bestimmen.
        if ($searchtitofurhkor =~ /^\d+$/){
            # Zuerst Gesamtzahl bestimmen
            my $request=$dbh->prepare("select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=3") or $logger->error($DBI::errstr);
            $request->execute($searchtitofurhkor);
            
            my $res=$request->fetchrow_hashref;
            $hits = $res->{conncount};

            my $limits="";
            if ($hitrange > 0){
                $limits="limit $offset,$hitrange";
            }

            # Bestimmung der Titel
            $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=3 $limits") or $logger->error($DBI::errstr);
            $request->execute($searchtitofurhkor);
            
            while (my $res=$request->fetchrow_hashref){
                push @titelidns, $res->{sourceid};
            }
            $request->finish();            
        }
        # ... ansonsten wird fuer den Fall fehlender Normdaten die komplette
        # Koerperschaft uebergeben, der ausschliesslich in den Titeldaten zu finden ist.
        else {
            $searchtitofurhkor = OpenBib::Common::Util::grundform({
                content  => $searchtitofurhkor,
            });
            
            # Bestimmung der Titel
            # ToDo parametrisierung der Koerperschaftskategorien pro Katalog
            my $request=$dbh->prepare("select distinct id from tit_string where category in (200,201) and content=?") or $logger->error($DBI::errstr);
            $request->execute($searchtitofurhkor);
            
            while (my $res=$request->fetchrow_hashref){
                push @titelidns, $res->{id};
            }        
            $request->finish();
        }

        
        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
            return OK;
        }

        if ($#titelidns == 0) {
            OpenBib::Record::Title->new({database=>$database})
                  ->get_full_record({id=>$titelidns[0]})
                      ->print_to_handler({
                          session            => $session,
                          queryoptions_ref   => $queryoptions_ref,
                          #searchquery_ref    => $searchquery_ref,
                          #queryid            => $queryid,
                          apachereq          => $r,
                          stylesheet         => $stylesheet,
                          view               => $view,
                          msg                => $msg,
                      });

            return OK;

        }
        if ($#titelidns > 0) {
            my ($atime,$btime,$timeall);
            
            if ($config->{benchmark}) {
                $atime=new Benchmark;
            }
            
            my $recordlist = new OpenBib::RecordList::Title();
            my $record     = new OpenBib::Record::Title({database=>$database});
                
            foreach my $idn (@titelidns) {
                $recordlist->add($record->get_brief_record({id=>$idn})->to_rawdata);
            }
            
            if ($config->{benchmark}) {
                $btime   = new Benchmark;
                $timeall = timediff($btime,$atime);
                $logger->info("Zeit fuer : ".($recordlist->get_number)." Titel : ist ".timestr($timeall));
                undef $atime;
                undef $btime;
                undef $timeall;
            }
            
            $recordlist->sort({order=>$sortorder,type=>$sorttype});
            
            $recordlist->print_to_handler({
                queryoptions_ref => $queryoptions_ref,
                database         => $database,
                sessionID        => $session->{ID},
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                hits             => $hits,
                offset           => $offset,
                hitrange         => $hitrange,
                msg              => $msg,
            });
            
            $session->updatelastresultset($recordlist->to_ids);
            
            return OK;
        }	
    }
  
    #######################################################################
    if ($searchtitofswt) {
        my @titelidns = ();
        my $hits      = 0;

        # Schlagwort-Id numerisch, dann Titel zu von entsprechendem Normdaten
        # satz bestimmen.
        if ($searchtitofswt =~ /^\d+$/){
            # Zuerst Gesamtzahl bestimmen
            my $request=$dbh->prepare("select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=4") or $logger->error($DBI::errstr);
            $request->execute($searchtitofswt);
            
            my $res=$request->fetchrow_hashref;
            $hits = $res->{conncount};

            my $limits="";
            if ($hitrange > 0){
                $limits="limit $offset,$hitrange";
            }

            # Bestimmung der Titel
            $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=4 $limits") or $logger->error($DBI::errstr);
            $request->execute($searchtitofswt);
            
            while (my $res=$request->fetchrow_hashref){
                push @titelidns, $res->{sourceid};
            }
            $request->finish();            
        }
        # ... ansonsten wird fuer den Fall fehlender Normdaten das komplette
        # Schlagwort uebergeben, der ausschliesslich in den Titeldaten zu finden ist.
        else {
            $searchtitofswt = OpenBib::Common::Util::grundform({
                content  => $searchtitofswt,
            });
            
            # Bestimmung der Titel
            # ToDo parametrisierung der Schlagwortkategorien pro Katalog
            my $request=$dbh->prepare("select distinct id from tit_string where category in (710,902,907,912,917,922,927,932,937,942,947) and content=?") or $logger->error($DBI::errstr);
            $request->execute($searchtitofswt);
            
            while (my $res=$request->fetchrow_hashref){
                push @titelidns, $res->{id};
            }        
            $request->finish();
        }
                
        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
            return OK;
        }
        if ($#titelidns == 0) {
            OpenBib::Record::Title->new({database=>$database})
                  ->get_full_record({id=>$titelidns[0]})
                      ->print_to_handler({
                          session            => $session,
                          queryoptions_ref   => $queryoptions_ref,
                          #searchquery_ref    => $searchquery_ref,
                          #queryid            => $queryid,
                          apachereq          => $r,
                          stylesheet         => $stylesheet,
                          view               => $view,
                          msg                => $msg,
                      });

            return OK;
        }
        if ($#titelidns > 0) {
            my ($atime,$btime,$timeall);
            
            if ($config->{benchmark}) {
                $atime=new Benchmark;
            }
            
            my $recordlist = new OpenBib::RecordList::Title();
            my $record     = new OpenBib::Record::Title({database=>$database});
                
            foreach my $idn (@titelidns) {
                $recordlist->add($record->get_brief_record({id=>$idn})->to_rawdata);
            }
            
            if ($config->{benchmark}) {
                $btime   = new Benchmark;
                $timeall = timediff($btime,$atime);
                $logger->info("Zeit fuer : ".($recordlist->get_number)." Titel : ist ".timestr($timeall));
                undef $atime;
                undef $btime;
                undef $timeall;
            }
            
            $recordlist->sort({order=>$sortorder,type=>$sorttype});
            
            $recordlist->print_to_handler({
                queryoptions_ref => $queryoptions_ref,
                database         => $database,
                sessionID        => $session->{ID},
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                hits             => $hits,
                offset           => $offset,
                hitrange         => $hitrange,
                msg              => $msg,
            });
            
            $session->updatelastresultset($recordlist->to_ids);

            return OK;
        }	
    }
  
    #######################################################################
    if ($searchtitofnot) {
        my @titelidns = ();
        my $hits      = 0;

        # Notations-Id numerisch, dann Titel zu von entsprechendem Normdaten
        # satz bestimmen.
        if ($searchtitofnot =~ /^\d+$/){
            # Zuerst Gesamtzahl bestimmen
            my $request=$dbh->prepare("select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=5") or $logger->error($DBI::errstr);
            $request->execute($searchtitofnot);
            
            my $res=$request->fetchrow_hashref;
            $hits = $res->{conncount};

            my $limits="";
            if ($hitrange > 0){
                $limits="limit $offset,$hitrange";
            }
            
            # Bestimmung der Titel
            $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=5 $limits") or $logger->error($DBI::errstr);
            $request->execute($searchtitofnot);

            while (my $res=$request->fetchrow_hashref){
                push @titelidns, $res->{sourceid};
            }
            $request->finish();
        }
        # ... ansonsten wird fuer den Fall fehlender Normdaten die komplette
        # Notation uebergeben, der ausschliesslich in den Titeldaten zu finden ist.
        else {
            $searchtitofnot = OpenBib::Common::Util::grundform({
                content  => $searchtitofnot,
            });
            
            # Bestimmung der Titel
            # ToDo parametrisierung der Notationskategorien pro Katalog
            my $request=$dbh->prepare("select distinct id from tit_string where category in (700) and content=?") or $logger->error($DBI::errstr);
            $request->execute($searchtitofnot);
            
            while (my $res=$request->fetchrow_hashref){
                push @titelidns, $res->{id};
            }        
            $request->finish();
        }
            
        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
            return OK;
        }
    
        if ($#titelidns == 0) {
            OpenBib::Record::Title->new({database=>$database})
                  ->get_full_record({id=>$titelidns[0]})
                      ->print_to_handler({
                          session            => $session,
                          queryoptions_ref   => $queryoptions_ref,
                          #searchquery_ref    => $searchquery_ref,
                          #queryid            => $queryid,
                          apachereq          => $r,
                          stylesheet         => $stylesheet,
                          view               => $view,
                          msg                => $msg,
                      });

            return OK;
        }
    
        if ($#titelidns > 0) {
            my ($atime,$btime,$timeall);
            
            if ($config->{benchmark}) {
                $atime=new Benchmark;
            }
            
            my $recordlist = new OpenBib::RecordList::Title();
            my $record     = new OpenBib::Record::Title({database=>$database});
                
            foreach my $idn (@titelidns) {
                $recordlist->add($record->get_brief_record({id=>$idn})->to_rawdata);
            }

            if ($config->{benchmark}) {
                $btime   = new Benchmark;
                $timeall = timediff($btime,$atime);
                $logger->info("Zeit fuer : ".($recordlist->get_number)." Titel : ist ".timestr($timeall));
                undef $atime;
                undef $btime;
                undef $timeall;
            }
            
            $recordlist->sort({order=>$sortorder,type=>$sorttype});
            
            $recordlist->print_to_handler({
                queryoptions_ref => $queryoptions_ref,
                database         => $database,
                sessionID        => $session->{ID},
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                hits             => $hits,
                offset           => $offset,
                hitrange         => $hitrange,
                msg              => $msg,
            });
            
            $session->updatelastresultset($recordlist->to_ids);

            return OK;
        }	
    }
  
    # Falls bis hierhin noch nicht abgearbeitet, dann wirds wohl nichts mehr geben
    OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
    $logger->error("Unerlaubt das Ende erreicht");
  
    $dbh->disconnect;
    return OK;
}

1;
