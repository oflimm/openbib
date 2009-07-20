#####################################################################
#
#  OpenBib::Handler::Apache::Search.pm
#
#  Copyright 1997-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Search;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request;
use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::Session;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

#     my $status=$query->parse;

#     if ($status) {
#         $logger->error("Cannot parse Arguments");
#     }

    my $session   = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $user      = OpenBib::User->instance({sessionID => $session->{ID}});

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
    my $swtindex          = decode_utf8($query->param('swtindex'))          || '';
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
    my $searchtitofcnt    = decode_utf8($query->param('searchtitofcnt'))    || '';

    my $browsecat         = $query->param('browsecat')         || '';
    my $browsecontent     = $query->param('browsecontent')     || '';
    my $category          = $query->param('category')          || '';

    my $olws              = $query->param('olws')              || 0;
    my $olws_action       = $query->param('olws_action')       || '';
    my $collection        = $query->param('collection')        || '';

    my $queryid           = $query->param('queryid')           || '';
    my $format            = $query->param('format')            || 'full';

    my $no_log            = $query->param('no_log')            || '';

    # Sub-Template ID
    my $stid              = $query->param('stid')              || '';

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

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        $dbh->disconnect();

        return Apache2::Const::OK;
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

    # Suche ueber OLWS (urn:/Viewer)
    
    if ($olws){
        if (exists $circinfotable->{$database} && exists $circinfotable->{$database}{circcheckurl}){
	    my $poolname=$dbinfotable->{sigel}{
	      $dbinfotable->{dbases}{$database}};
            
            if ($olws_action eq "browse"){

                $logger->debug("Endpoint: ".$circinfotable->{$database}{circcheckurl});
                my $soapresult;
                eval {
                    my $soap = SOAP::Lite
                        -> uri("urn:/Viewer")
                            -> proxy($circinfotable->{$database}{circcheckurl});

                    my $result = $soap->browse(
                        SOAP::Data->name(parameter  =>\SOAP::Data->value(
                            SOAP::Data->name(collection => $collection)->type('string'),
                            SOAP::Data->name(category   => $browsecat)->type('string'),
                            SOAP::Data->name(content    => $browsecontent)->type('string'))));
                    
                    unless ($result->fault) {
                        $soapresult=$result->result;
                    }
                    else {
                        $logger->error("SOAP Viewer Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                    }
                };
                
                if ($@){
                    $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
                }

                $logger->debug("OLWS".YAML::Dump($soapresult));

                # TT-Data erzeugen
                my $ttdata={
                    view        => $view,
                    stylesheet  => $stylesheet,
                    database    => $database,
                    poolname    => $poolname,
                    qopts       => $queryoptions->get_options,
                    sessionID   => $session->{ID},
                    result      => $soapresult,

                    collection    => $collection,
                    browsecontent => $browsecontent,
                    browsecat     => $browsecat,

                    config      => $config,
                    user        => $user,
                    msg         => $msg,
                };

                $stid=~s/[^0-9]//g;
                my $templatename = ($stid)?"tt_search_olws_browse_".$stid."_tname":"tt_search_olws_browse_tname";

                OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
                return Apache2::Const::OK;
            }
            
            my $soap = SOAP::Lite
                -> uri("urn:/Viewer")
                    -> proxy($circinfotable->{$database}{circcheckurl});

        }
    }

    
    #####################################################################
    ## Schlagwortindex
  
    if ($swtindex ne "") {
    
        OpenBib::Search::Util::print_index_by_swt({
            swt              => $swtindex,
            dbh              => $dbh,
            database         => $database,
            apachereq        => $r,
            stylesheet       => $stylesheet,
            view             => $view,
            msg              => $msg,
        });
        return Apache2::Const::OK;
    }

    #######################################################################
    # Nachdem initial per SQL nach den Usereingaben eine Treffermenge 
    # gefunden wurde, geht es nun exklusiv in der SQL-DB weiter

    if ($generalsearch) { 
        if (($generalsearch=~/^verf/)||($generalsearch=~/^pers/)) {
            my $verfidn=$query->param("$generalsearch");

            my $normset=OpenBib::Record::Person->new({database => $database, id => $verfidn})->load_full_record({dbh => $dbh})->to_rawdata;
            
	    my $poolname=$dbinfotable->{sigel}{
	      $dbinfotable->{dbases}{$database}};
            
            # TT-Data erzeugen
            my $ttdata={
                view             => $view,
                stylesheet       => $stylesheet,
                database         => $database,
		poolname         => $poolname,
                queryoptions_ref => $queryoptions->get_options,
                sessionID        => $session->{ID},
                normset          => $normset,
                
                config     => $config,
                user       => $user,
                msg        => $msg,
            };

            $stid=~s/[^0-9]//g;
            my $templatename = ($stid)?"tt_search_showautset_".$stid."_tname":"tt_search_showautset_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            return Apache2::Const::OK;
        }
    
        if ($generalsearch=~/^supertit/) {
            my $recordlist = new OpenBib::RecordList::Title();

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

            while (my $res=$request->fetchrow_hashref) {
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{targetid}}));
            }

            $request->finish();
            
            $recordlist->print_to_handler({
                database         => $database,
                sortorder        => $sortorder,
                sorttype         => $sorttype,
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                hits             => $hits,
                offset           => $offset,
                hitrange         => $hitrange,
                msg              => $msg,
            });

            return Apache2::Const::OK;
        }

        if ($generalsearch=~/^subtit/) {
            my $recordlist = new OpenBib::RecordList::Title();

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
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{sourceid}}));
            }

            $request->finish();

            $recordlist->print_to_handler({
                database         => $database,
                sortorder        => $sortorder,
                sorttype         => $sorttype,
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                hits             => $hits,
                offset           => $offset,
                hitrange         => $hitrange,
                msg              => $msg,
            });

            return Apache2::Const::OK;
        }

        if ($generalsearch=~/^hst/) {
            my $titidn=$query->param("$generalsearch");

            OpenBib::Record::Title->new({database=>$database, id=>$titidn})
                  ->load_full_record({dbh => $dbh})
                      ->print_to_handler({
                          apachereq          => $r,
                          stylesheet         => $stylesheet,
                          view               => $view,
                          msg                => $msg,
                      });

            return Apache2::Const::OK;
        }
    
        if ($generalsearch=~/^swt/) {
            my $swtidn=$query->param("$generalsearch");

            my $normset=OpenBib::Record::Subject->new({database => $database, id => $swtidn})->load_full_record({dbh => $dbh})->to_rawdata;

	    my $poolname=$dbinfotable->{sigel}{
	      $dbinfotable->{dbases}{$database}};

            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
                database   => $database,
	        poolname   => $poolname,
                qopts      => $queryoptions->get_options,
                sessionID  => $session->{ID},
                normset    => $normset,

                config     => $config,
                user       => $user,
                msg        => $msg,
            };

            $stid=~s/[^0-9]//g;
            my $templatename = ($stid)?"tt_search_showswtset_".$stid."_tname":"tt_search_showswtset_tname";

            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            return Apache2::Const::OK;
        }
    
        if ($generalsearch=~/^not/) {
            my $notidn=$query->param("notation");
            
            my $normset=OpenBib::Record::Classification->new({database => $database, id => $notidn})->load_full_record({dbh => $dbh})->to_rawdata;

	    my $poolname=$dbinfotable->{sigel}{
	      $dbinfotable->{dbases}{$database}};

            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
                database   => $database,
		poolname   => $poolname,
                qopts      => $queryoptions->get_options,
                sessionID  => $session->{ID},
                normset    => $normset,
                
                config     => $config,
                user       => $user,
                msg        => $msg,
            };

            $stid=~s/[^0-9]//g;
            my $templatename = ($stid)?"tt_search_shownotset_".$stid."_tname":"tt_search_shownotset_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            return Apache2::Const::OK;
        }
    
    }
  
    #####################################################################
    if ($searchmultipletit) {
        my @mtitidns=$query->param('searchmultipletit');

        OpenBib::Search::Util::print_mult_tit_set_by_idn({
            titidns_ref        => \@mtitidns,
            dbh                => $dbh,
            database           => $database,
            apachereq          => $r,
            stylesheet         => $stylesheet,
            view               => $view,
            msg                => $msg,
        });
        return Apache2::Const::OK;
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
#             hitrange           => $hitrange,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $session->{ID},
#             apachereq          => $r,
#             stylesheet         => $stylesheet,
#             view               => $view,
#         });
#         return Apache2::Const::OK;
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
#             hitrange           => $hitrange,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $session->{ID},
#             apachereq          => $r,
#             stylesheet         => $stylesheet,
#             view               => $view,
#         });
#         return Apache2::Const::OK;
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
#             hitrange           => $hitrange,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $session->{ID},
#             apachereq          => $r,
#             stylesheet         => $stylesheet,
#             view               => $view,
#         });
#         return Apache2::Const::OK;
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
#             hitrange           => $hitrange,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $session->{ID},
#             apachereq          => $r,
#             stylesheet         => $stylesheet,
#             view               => $view,
#         });
#         return Apache2::Const::OK;
#    }
  
    #####################################################################
    
    if ($searchsingletit) {
        # Zuerst die zugehoerige Suchanfrage bestimmen

        my $searchquery = OpenBib::SearchQuery->instance;

        if ($queryid){
            $searchquery->load({sessionID => $session->{ID}, queryid => $queryid});
        }

        if ($config->get_system_of_db($database) eq "Z39.50"){
            my $z3950dbh = new OpenBib::Search::Z3950($database);

            my ($normset,$mexnormset) = $z3950dbh->get_singletitle($searchsingletit);
            
            my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation({
                session    => $session,
                database   => $database,
                titidn     => $searchsingletit,
            });
            
            my $poolname=$dbinfotable->{sigel}{
                $dbinfotable->{dbases}{$database}};
            
            # TT-Data erzeugen
            my $ttdata={
                view        => $view,
                stylesheet  => $stylesheet,
                database    => $database,
                poolname    => $poolname,
                format      => $format,
                prevurl     => $prevurl,
                nexturl     => $nexturl,
                qopts       => $queryoptions->get_options,
                sessionID   => $session->{ID},
                titidn      => $searchsingletit,
                normset     => $normset,
                mexnormset  => $mexnormset,
                circset     => {},

                searchquery => $searchquery,
                
                config      => $config,
                user        => $user,
                msg         => $msg,
            };

            $stid=~s/[^0-9]//g;
            my $templatename = ($stid)?"tt_search_showtitset_".$stid."_tname":"tt_search_showtitset_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

        }
        else {
            OpenBib::Record::Title->new({database => $database, id => $searchsingletit})
                  ->load_full_record({dbh => $dbh})->print_to_handler({
                          apachereq          => $r,
                          format             => $format,
                          stylesheet         => $stylesheet,
                          view               => $view,
                          msg                => $msg,
                          no_log             => $no_log,
                      });
        }
        return Apache2::Const::OK;
    }
  
    #####################################################################
    if ($searchsingleswt) {
        my $normset=OpenBib::Record::Subject->new({database => $database, id => $searchsingleswt})->load_full_record({dbh => $dbh})->to_rawdata;
        
	my $poolname=$dbinfotable->{sigel}{
	  $dbinfotable->{dbases}{$database}};

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            poolname   => $poolname,
            qopts      => $queryoptions->get_options,
            sessionID  => $session->{ID},
            normset    => $normset,
            
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_search_showswtset_tname},$ttdata,$r);

        $session->log_event({
            type      => 14,
            content   => {
                id       => $searchsingleswt,
                database => $database,
            },
            serialize => 1,
        });

        return Apache2::Const::OK;
    }
  
    ######################################################################
    if ($searchsinglekor) {
        my $normset=OpenBib::Record::CorporateBody->new({database => $database, id => $searchsinglekor})->load_full_record({dbh => $dbh})->to_rawdata;  
        
	my $poolname=$dbinfotable->{sigel}{
	  $dbinfotable->{dbases}{$database}};

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
	    poolname   => $poolname,
            qopts      => $queryoptions->get_options,
            sessionID  => $session->{ID},
            normset    => $normset,
            
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_search_showkorset_tname},$ttdata,$r);

        $session->log_event({
            type      => 12,
            content   => {
                id       => $searchsinglekor,
                database => $database,
            },
            serialize => 1,
        });

        return Apache2::Const::OK;
    }
    
    ######################################################################
    if ($searchsinglenot) {
        my $normset=OpenBib::Record::Classification->new({database => $database, id => $searchsinglenot})->load_full_record({dbh => $dbh})->to_rawdata;
	
	my $poolname=$dbinfotable->{sigel}{
	  $dbinfotable->{dbases}{$database}};

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            poolname   => $poolname,
            qopts      => $queryoptions->get_options,
            sessionID  => $session->{ID},
            normset    => $normset,
            
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_search_shownotset_tname},$ttdata,$r);

        $session->log_event({
            type      => 13,
            content   => {
                id       => $searchsinglenot,
                database => $database,
            },
            serialize => 1,
        });

        return Apache2::Const::OK;
    }
  
    #####################################################################
    if ($searchsingleaut) {
        my $normset=OpenBib::Record::Person->new({database => $database, id => $searchsingleaut})->load_full_record()->to_rawdata;

        my $poolname=$dbinfotable->{sigel}{
            $dbinfotable->{dbases}{$database}};
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            poolname   => $poolname,
            qopts      => $queryoptions->get_options,
            sessionID  => $session->{ID},
            normset    => $normset,
            
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_search_showautset_tname},$ttdata,$r);

        $session->log_event({
            type      => 11,
            content   => {
                id       => $searchsingleaut,
                database => $database,
            },
            serialize => 1,
        });

        return Apache2::Const::OK;
    }
    
    if ($searchtitofaut) {
        my $recordlist = new OpenBib::RecordList::Title();

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
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{sourceid}}));
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
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}}));
            }        
            $request->finish();
        }
        
        $recordlist->print_to_handler({
            database         => $database,
            sortorder        => $sortorder,
            sorttype         => $sorttype,
            apachereq        => $r,
            stylesheet       => $stylesheet,
            view             => $view,
            hits             => $hits,
            offset           => $offset,
            hitrange         => $hitrange,
            msg              => $msg,
        });

        return Apache2::Const::OK;
    }
  
    #####################################################################
    if ($searchtitofurhkor) {
        my $recordlist = new OpenBib::RecordList::Title();

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
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{sourceid}}));
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
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}}));
            }        
            $request->finish();
        }

        $recordlist->print_to_handler({
            database         => $database,
            sortorder        => $sortorder,
            sorttype         => $sorttype,
            apachereq        => $r,
            stylesheet       => $stylesheet,
            view             => $view,
            hits             => $hits,
            offset           => $offset,
            hitrange         => $hitrange,
            msg              => $msg,
        });

        return Apache2::Const::OK;
    }
  
    #######################################################################
    if ($searchtitofswt) {
        my $recordlist = new OpenBib::RecordList::Title();

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
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{sourceid}}));
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
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}}));
            }        
            $request->finish();
        }

        $recordlist->print_to_handler({
            database         => $database,
            sortorder        => $sortorder,
            sorttype         => $sorttype,
            apachereq        => $r,
            stylesheet       => $stylesheet,
            view             => $view,
            hits             => $hits,
            offset           => $offset,
            hitrange         => $hitrange,
            msg              => $msg,
        });

        
        return Apache2::Const::OK;
    }
  
    #######################################################################
    if ($searchtitofnot) {
        my $recordlist = new OpenBib::RecordList::Title();

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
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{sourceid}}));
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
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}}));
            }
            $request->finish();
        }

        $recordlist->print_to_handler({
            database         => $database,
            sortorder        => $sortorder,
            sorttype         => $sorttype,
            apachereq        => $r,
            stylesheet       => $stylesheet,
            view             => $view,
            hits             => $hits,
            offset           => $offset,
            hitrange         => $hitrange,
            msg              => $msg,
        });

        return Apache2::Const::OK;
    }

    #######################################################################
    # Titel zu einem gegebenen Kategorie-Inhalt
    # Voraussetzung: Diese Kategorie muss String-Invertiert sein (convert.yml)
    #                Ausnahme: Anreicherung enrich
    if ($searchtitofcnt) {
        my $recordlist = new OpenBib::RecordList::Title();

        my $hits      = 0;

        my $searchtitofcntnorm = OpenBib::Common::Util::grundform({
            content  => $searchtitofcnt,
        });

        my ($type,$thiscategory)=$category=~/^([A-Z])(\d+)/;

        $type =
            ($type eq "U")?'user':
                ($type eq "E")?'enrich':
                    ($type eq "P")?'aut':
                        ($type eq "C")?'kor':
                            ($type eq "S")?'swt':
                                ($type eq "N")?'notation':'tit';
        
        my $limits="";
        if ($hitrange > 0){
            $limits="limit $offset,$hitrange";
        }

        my $conn_cat_ref = {
            'T0100' => 'aut',
            'T0101' => 'aut',
            'T0102' => 'aut',
            'T0103' => 'aut',
            'T0200' => 'kor',
            'T0201' => 'kor',
            'T0700' => 'notation',
            'T0710' => 'swt',
            'T0902' => 'swt',
            'T0902' => 'swt',
            'T0907' => 'swt',
            'T0912' => 'swt',
            'T0917' => 'swt',
            'T0922' => 'swt',
            'T0927' => 'swt',
            'T0932' => 'swt',
            'T0937' => 'swt',
            'T0942' => 'swt',
            'T0947' => 'swt',
        };

        if ($type eq "tit" && exists $conn_cat_ref->{$category}){
            # Bestimmung der Titel
            my $normtable  = $conn_cat_ref->{$category};
            my $targettype =
                ($normtable eq "aut")?2:
                ($normtable eq "kor")?3:
                ($normtable eq "swt")?4:
                ($normtable eq "notation")?5:1;

            my $sqlstring="select distinct conn.sourceid as sourceid from ".$normtable."_string as norm, conn where conn.category=? and conn.sourcetype=1 and conn.targettype=? and conn.targetid=norm.id and norm.category=1 and norm.content=?";
            my $request=$dbh->prepare($sqlstring) or $logger->error($DBI::errstr);
            $request->execute($thiscategory,$targettype,$searchtitofcntnorm);

            $logger->debug("$thiscategory/$targettype/$searchtitofcntnorm");
            while (my $res=$request->fetchrow_hashref){
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{sourceid}}));
            }
            
            # Bestimmung der Titelzahl
            $request=$dbh->prepare("select count(distinct conn.sourceid) as rowcount from ".$normtable."_string as norm, conn where conn.category=? and conn.sourcetype=1 and conn.targettype=? and conn.targetid=norm.id and norm.category=1 and norm.content=?") or $logger->error($DBI::errstr);
            $request->execute($thiscategory,$targettype,$searchtitofcntnorm);
            
            my $res=$request->fetchrow_hashref;
            $hits=$res->{rowcount};
            
            $request->finish();
        }
        elsif ($type eq "enrich"){
            my $enrichdbh
                = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                    or $logger->error_die($DBI::errstr);

            my $sqlstring="select distinct ai.id as id from all_isbn as ai, normdata as n where n.category=? and n.content=? and n.isbn=ai.isbn and ai.dbname=? $limits ";
            my $request=$enrichdbh->prepare($sqlstring) or $logger->error($DBI::errstr);
            $request->execute($thiscategory,$searchtitofcnt,$database);

            $logger->debug("Enrich: $sqlstring");
            $logger->debug("Enrich: $thiscategory/$type/$searchtitofcnt");
            while (my $res=$request->fetchrow_hashref){
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}}));
            }
            
            # Bestimmung der Titelzahl
            $request=$enrichdbh->prepare("select count(distinct ai.id) as rowcount from all_isbn as ai, normdata as n where n.category=? and n.content=? and n.isbn=ai.isbn and ai.dbname=?") or $logger->error($DBI::errstr);
            $request->execute($thiscategory,$searchtitofcnt,$database);
            
            my $res=$request->fetchrow_hashref;
            $hits=$res->{rowcount};
            
            $request->finish();
            
        }
        else {
            # Bestimmung der Titel
            my $request=$dbh->prepare("select distinct id from tit_string where category=? and content=? $limits ") or $logger->error($DBI::errstr);
            $request->execute($thiscategory,$searchtitofcntnorm);
            
            while (my $res=$request->fetchrow_hashref){
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}}));
            }        
            
            # Bestimmung der Titelzahl
            $request=$dbh->prepare("select count(distinct id) as rowcount from tit_string where category=? and content=?") or $logger->error($DBI::errstr);
            $request->execute($thiscategory,$searchtitofcntnorm);
            
            my $res=$request->fetchrow_hashref;
            $hits=$res->{rowcount};
            
            $request->finish();
        }

        $recordlist->print_to_handler({
            database         => $database,
            sortorder        => $sortorder,
            sorttype         => $sorttype,
            apachereq        => $r,
            stylesheet       => $stylesheet,
            template         => 'tt_search_showtitlist_of_cnt_tname',
            view             => $view,
            hits             => $hits,
            offset           => $offset,
            hitrange         => $hitrange,
            msg              => $msg,
        });

        return Apache2::Const::OK;
    }

    #######################################################################
    # Browsen ueber alle Inhalte von Kategorien
    # Voraussetzung: Diese Kategorie muss String-Invertiert sein (Config.pm)
    if ($browsecat) {
        my $browselist_ref = [];
        my $hits           = 0;

        my ($type,$thiscategory)=$browsecat=~/^([A-Z])(\d+)/;

        $type =
            ($type eq "P")?'aut':
                ($type eq "C")?'kor':
                    ($type eq "S")?'swt':
                        ($type eq "N")?'notation':'tit';
        
        my $limits="";
        if ($hitrange > 0){
            $limits="limit $offset,$hitrange";
        }

        my $conn_cat_ref = {
            'T0100' => 'aut',
            'T0101' => 'aut',
            'T0102' => 'aut',
            'T0103' => 'aut',
            'T0200' => 'kor',
            'T0201' => 'kor',
            'T0700' => 'notation',
            'T0710' => 'swt',
            'T0902' => 'swt',
            'T0902' => 'swt',
            'T0907' => 'swt',
            'T0912' => 'swt',
            'T0917' => 'swt',
            'T0922' => 'swt',
            'T0927' => 'swt',
            'T0932' => 'swt',
            'T0937' => 'swt',
            'T0942' => 'swt',
            'T0947' => 'swt',
        };

        if ($type eq "tit" && exists $conn_cat_ref->{$browsecat}){
            # Bestimmung der Titel
            my $normtable  = $conn_cat_ref->{$browsecat};
            my $targettype =
                ($normtable eq "aut")?2:
                ($normtable eq "kor")?3:
                ($normtable eq "swt")?4:
                ($normtable eq "notation")?5:1;

            my $sqlstring="select distinct norm.content as content from $normtable as norm, conn where conn.category=? and conn.sourcetype=1 and conn.targettype=? and conn.targetid=norm.id and norm.category=1 order by content $limits ";
            my $request=$dbh->prepare($sqlstring) or $logger->error($DBI::errstr);
            $request->execute($thiscategory,$targettype);
            
            $logger->debug("SQL: $sqlstring");
            while (my $res=$request->fetchrow_hashref){
                push @$browselist_ref, decode_utf8($res->{content});
            }
            
            # Bestimmung der Titelzahl
            $request=$dbh->prepare("select count(distinct content) as rowcount from tit where category=?") or $logger->error($DBI::errstr);
            $request->execute($thiscategory);
            
            my $res=$request->fetchrow_hashref;
            $hits=$res->{rowcount};
            
            $request->finish();
        }
        else {
            # Bestimmung der Titel
            my $request=$dbh->prepare("select distinct content from $type where category=? order by content $limits ") or $logger->error($DBI::errstr);
            $request->execute($thiscategory);
            
            while (my $res=$request->fetchrow_hashref){
                push @$browselist_ref, decode_utf8($res->{content});
            }
            
            # Bestimmung der Titelzahl
            $request=$dbh->prepare("select count(distinct content) as rowcount from tit where category=?") or $logger->error($DBI::errstr);
            $request->execute($thiscategory);
            
            my $res=$request->fetchrow_hashref;
            $hits=$res->{rowcount};
            
            $request->finish();
        }
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            browsecat  => $browsecat,
            qopts      => $queryoptions->get_options,
            sessionID  => $session->{ID},
            browselist => $browselist_ref,
            hits       => $hits,
            
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{"tt_search_browse_".$type."_tname"},$ttdata,$r);
        return Apache2::Const::OK;
    }

    # Falls bis hierhin noch nicht abgearbeitet, dann wirds wohl nichts mehr geben
    OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
    $logger->error("Unerlaubt das Ende erreicht");
  
    $dbh->disconnect;
    return Apache2::Const::OK;
}

1;
