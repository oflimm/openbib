#####################################################################
#
#  OpenBib::Search.pm
#
#  Copyright 1997-2006 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config = \%OpenBib::Config::config;

my $benchmark;

if ($OpenBib::Config::config{benchmark}) {
    use Benchmark ':hireswallclock';
}

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    ## Wandlungstabelle Erscheinungsjahroperator
    my %ejop=(
        'genau' => '=',
        'jünger' => '>',
        'älter' => '<'
    );
  
    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }
  
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################
  
    #####################################################################
    ## Maxhits: Maximale Trefferzahl
    ##          > 0  - gibt die maximale Zahl an
  
    my $maxhits=($query->param('maxhits'))?$query->param('maxhits'):400;
  
    #####################################################################
    ## Rating
    ##          0 - nein
    ##          1 - ja
  
    my $rating=($query->param('rating'))?$query->param('rating'):0;
  
    #####################################################################
    ## Bookinfo
    ##          0 - nein
    ##          1 - ja
  
    my $bookinfo=($query->param('bookinfo'))?$query->param('bookinfo'):0;
  
    #####################################################################
    ## Hitrange: Anzahl gleichzeitig ausgegebener Treffer bei Anfangs-Suche
    ##          >0  - gibt die maximale Zahl an
    ##          <=0 - gibt immer alle Treffer aus 
  
    my $hitrange=($query->param('hitrange'))?$query->param('hitrange'):-1;
    if ($hitrange eq "alles") {
        $hitrange=-1
    }
  
    #####################################################################
    ## Offset: Maximale Anzahl ausgegebener Treffer bei Anfangs-Suche
    ##          >0  - hitrange Treffer werden ab dieser Nr. ausgegeben 
  
    my $offset=($query->param('offset'))?$query->param('offset'):1;
  
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

    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########
  
    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen
  
    my $dbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$r);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    my $targetdbinfo_ref
        = OpenBib::Common::Util::get_targetdbinfo($sessiondbh);

    my $targetcircinfo_ref
        = OpenBib::Common::Util::get_targetcircinfo($sessiondbh);
    
    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
      
        $sessiondbh->disconnect();
        $dbh->disconnect();
      
        return OK;
    }

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }

  
    #####################################################################
    ## Eigentliche Suche (default)

    #####################################################################
    ## Schlagwortindex
  
    if ($swtindex ne "") {
    
        OpenBib::Search::Util::print_index_by_swt({
            swt              => $swtindex,
            dbh              => $dbh,
            sessiondbh       => $sessiondbh,
            targetdbinfo_ref => $targetdbinfo_ref,
            queryoptions_ref => $queryoptions_ref,
            database         => $database,
            sessionID        => $sessionID,
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
            
            my $normset=OpenBib::Search::Util::get_aut_set_by_idn({
                autidn            => $verfidn,
                dbh               => $dbh,
                database          => $database,
                sessionID         => $sessionID,
            });
            
            # TT-Data erzeugen
            my $ttdata={
                view             => $view,
                stylesheet       => $stylesheet,
                database         => $database,
                queryoptions_ref => $queryoptions_ref,
                sessionID        => $sessionID,
                normset          => $normset,
                
                config     => \%config,
                msg        => $msg,
            };
            OpenBib::Common::Util::print_page($config{tt_search_showautset_tname},$ttdata,$r);
            return OK;
        }
    
        if ($generalsearch=~/^supertit/) {
            my $supertitidn=$query->param("$generalsearch");

            my $reqstring="select distinct targetid from conn where sourceid=? and sourcetype=1 and targettype=1";
            my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
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
                OpenBib::Search::Util::print_tit_set_by_idn({
                    titidn             => $titidns[0],
                    dbh                => $dbh,
                    sessiondbh         => $sessiondbh,
                    targetdbinfo_ref   => $targetdbinfo_ref,
                    targetcircinfo_ref => $targetcircinfo_ref,
                    queryoptions_ref   => $queryoptions_ref,
                    database           => $database,
                    sessionID          => $sessionID,
                    apachereq          => $r,
                    stylesheet         => $stylesheet,
                    view               => $view,
                    msg                => $msg,
                });
                return OK;

            }
      
            if ($#titidns > 0) {
                my @outputbuffer=();
                my ($atime,$btime,$timeall);
                
                if ($config{benchmark}) {
                    $atime=new Benchmark;
                }
	
                foreach my $idn (@titidns) {
                    push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                        titidn            => $idn,
                        dbh               => $dbh,
                        sessiondbh        => $sessiondbh,
                        targetdbinfo_ref  => $targetdbinfo_ref,
                        database          => $database,
                        sessionID         => $sessionID,
                    });
                }

                if ($config{benchmark}) {
                    $btime   = new Benchmark;
                    $timeall = timediff($btime,$atime);
                    $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel : ist ".timestr($timeall));
                    undef $atime;
                    undef $btime;
                    undef $timeall;
                }
	
                my @sortedoutputbuffer=();
                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

		my @resultset=();
		# Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
		foreach my $item_ref (@sortedoutputbuffer){
		  push @resultset, { id       => $item_ref->{id},
				     database => $item_ref->{database},
				   };
		}

                OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
                OpenBib::Search::Util::print_tit_list_by_idn({
                    itemlist_ref     => \@sortedoutputbuffer,
                    targetdbinfo_ref => $targetdbinfo_ref,
                    queryoptions_ref => $queryoptions_ref,
                    database         => $database,
                    sessionID        => $sessionID,
                    apachereq        => $r,
                    stylesheet       => $stylesheet,
                    view             => $view,
                    msg              => $msg,
                });
                return OK;
            }
        }

        if ($generalsearch=~/^subtit/) {
            my $subtitidn=$query->param("$generalsearch");

            my $reqstring="select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=1";
            my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
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
                OpenBib::Search::Util::print_tit_set_by_idn({
                    titidn             => $titidns[0],
                    dbh                => $dbh,
                    sessiondbh         => $sessiondbh,
                    targetdbinfo_ref   => $targetdbinfo_ref,
                    targetcircinfo_ref => $targetcircinfo_ref,
                    queryoptions_ref   => $queryoptions_ref,
                    database           => $database,
                    sessionID          => $sessionID,
                    apachereq          => $r,
                    stylesheet         => $stylesheet,
                    view               => $view,
                    msg                => $msg,
                });
                return OK;

            }
      
            if ($#titidns > 0) {
                my @outputbuffer=();
                my ($atime,$btime,$timeall);
                
                if ($config{benchmark}) {
                    $atime=new Benchmark;
                }
	
                foreach my $idn (@titidns) {
                    push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                        titidn            => $idn,
                        dbh               => $dbh,
                        sessiondbh        => $sessiondbh,
                        targetdbinfo_ref  => $targetdbinfo_ref,
                        database          => $database,
                        sessionID         => $sessionID,
                    });
                }

                if ($config{benchmark}) {
                    $btime   = new Benchmark;
                    $timeall = timediff($btime,$atime);
                    $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel : ist ".timestr($timeall));
                    undef $atime;
                    undef $btime;
                    undef $timeall;
                }
	
                my @sortedoutputbuffer=();
                OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

		my @resultset=();
		# Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
		foreach my $item_ref (@sortedoutputbuffer){
		  push @resultset, { id       => $item_ref->{id},
				     database => $item_ref->{database},
				   };
		}

                OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
                OpenBib::Search::Util::print_tit_list_by_idn({
                    itemlist_ref     => \@sortedoutputbuffer,
                    targetdbinfo_ref => $targetdbinfo_ref,
                    queryoptions_ref => $queryoptions_ref,
                    database         => $database,
                    sessionID        => $sessionID,
                    apachereq        => $r,
                    stylesheet       => $stylesheet,
                    view             => $view,
                    msg              => $msg,
                });
                return OK;
            }
        }

        if ($generalsearch=~/^hst/) {
            my $titidn=$query->param("$generalsearch");

            OpenBib::Search::Util::print_tit_set_by_idn({
                titidn             => $titidn,
                dbh                => $dbh,
                sessiondbh         => $sessiondbh,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                queryoptions_ref   => $queryoptions_ref,
                database           => $database,
                sessionID          => $sessionID,
                apachereq          => $r,
                stylesheet         => $stylesheet,
                view               => $view,
                msg                => $msg,
            });
            return OK;
        }
    
        if ($generalsearch=~/^swt/) {
            my $swtidn=$query->param("$generalsearch");
            my $normset=OpenBib::Search::Util::get_swt_set_by_idn({
                swtidn            => $swtidn,
                dbh               => $dbh,
                database          => $database,
                sessionID         => $sessionID,
            });
            
            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
                database   => $database,
                qopts      => $queryoptions_ref,
                sessionID  => $sessionID,
                normset    => $normset,

                config     => \%config,
                msg        => $msg,
            };
            OpenBib::Common::Util::print_page($config{tt_search_showswtset_tname},$ttdata,$r);
            return OK;
        }
    
        if ($generalsearch=~/^not/) {
            my $notidn=$query->param("notation");
            my $normset=OpenBib::Search::Util::get_not_set_by_idn({
                notidn            => $notidn,
                dbh               => $dbh,
                database          => $database,
                sessionID         => $sessionID,
            });
            
            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
                database   => $database,
                qopts      => $queryoptions_ref,
                sessionID  => $sessionID,
                normset    => $normset,
                
                config     => \%config,
                msg        => $msg,
            };
            OpenBib::Common::Util::print_page($config{tt_search_shownotset_tname},$ttdata,$r);
            return OK;
        }
    
    }
  
    #####################################################################
    if ($searchmultipletit) {
        my @mtitidns=$query->param('searchmultipletit');

        OpenBib::Search::Util::print_mult_tit_set_by_idn({
            titidns_ref        => \@mtitidns,
            dbh                => $dbh,
            sessiondbh         => $sessiondbh,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => $targetcircinfo_ref,
            queryoptions_ref   => $queryoptions_ref,
            database           => $database,
            sessionID          => $sessionID,
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
#             sessiondbh         => $sessiondbh,
#             searchmultipleaut  => $searchmultipleaut,
#             searchmode         => $searchmode,
#             targetdbinfo_ref   => $targetdbinfo_ref,
#             targetcircinfo_ref => $targetcircinfo_ref,
#             hitrange           => $hitrange,
#             rating             => $rating,
#             bookinfo           => $bookinfo,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $sessionID,
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
#             sessiondbh         => $sessiondbh,
#             searchmultiplekor  => $searchmultiplekor,
#             searchmode         => $searchmode,
#             targetdbinfo_ref   => $targetdbinfo_ref,
#             targetcircinfo_ref => $targetcircinfo_ref,
#             hitrange           => $hitrange,
#             rating             => $rating,
#             bookinfo           => $bookinfo,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $sessionID,
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
#             sessiondbh         => $sessiondbh,
#             searchmultiplekor  => $searchmultiplekor,
#             searchmode         => $searchmode,
#             targetdbinfo_ref   => $targetdbinfo_ref,
#             targetcircinfo_ref => $targetcircinfo_ref,
#             hitrange           => $hitrange,
#             rating             => $rating,
#             bookinfo           => $bookinfo,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $sessionID,
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
#             sessiondbh         => $sessiondbh,
#             searchmultiplekor  => $searchmultiplekor,
#             searchmode         => $searchmode,
#             targetdbinfo_ref   => $targetdbinfo_ref,
#             targetcircinfo_ref => $targetcircinfo_ref,
#             hitrange           => $hitrange,
#             rating             => $rating,
#             bookinfo           => $bookinfo,
#             sorttype           => $sorttype,
#             sortorder          => $sortorder,
#             database           => $database,
#             sessionID          => $sessionID,
#             apachereq          => $r,
#             stylesheet         => $stylesheet,
#             view               => $view,
#         });
#         return OK;
#    }
  
    #####################################################################
  
    if ($searchsingletit) {
        OpenBib::Search::Util::print_tit_set_by_idn({
            titidn             => $searchsingletit,
            dbh                => $dbh,
            sessiondbh         => $sessiondbh,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => $targetcircinfo_ref,
            queryoptions_ref   => $queryoptions_ref,
            database           => $database,
            sessionID          => $sessionID,
            apachereq          => $r,
            stylesheet         => $stylesheet,
            view               => $view,
            msg                => $msg,
        });
        return OK;
    }
  
    #####################################################################
    if ($searchsingleswt) {
        my $normset=OpenBib::Search::Util::get_swt_set_by_idn({
            swtidn            => $searchsingleswt,
            dbh               => $dbh,
            database          => $database,
            sessionID         => $sessionID,
        });
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            qopts      => $queryoptions_ref,
            sessionID  => $sessionID,
            normset    => $normset,
            
            config     => \%config,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config{tt_search_showswtset_tname},$ttdata,$r);
        return OK;
    }
  
    ######################################################################
    if ($searchsinglekor) {
        my $normset=OpenBib::Search::Util::get_kor_set_by_idn({
            koridn            => $searchsinglekor,
            dbh               => $dbh,
            database          => $database,
            sessionID         => $sessionID,
        });
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            qopts      => $queryoptions_ref,
            sessionID  => $sessionID,
            normset    => $normset,
            
            config     => \%config,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config{tt_search_showkorset_tname},$ttdata,$r);
        return OK;
    }
    
    ######################################################################
    if ($searchsinglenot) {
        my $normset=OpenBib::Search::Util::get_not_set_by_idn({
            notidn            => $searchsinglenot,
            dbh               => $dbh,
            database          => $database,
            sessionID         => $sessionID,
        });
	
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            qopts      => $queryoptions_ref,
            sessionID  => $sessionID,
            normset    => $normset,
            
            config     => \%config,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config{tt_search_shownotset_tname},$ttdata,$r);
        return OK;
    }
  
    #####################################################################
    if ($searchsingleaut) {
        my $normset=OpenBib::Search::Util::get_aut_set_by_idn({
            autidn            => "$searchsingleaut",
            dbh               => $dbh,
            database          => $database,
            sessionID         => $sessionID,
        });
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            database   => $database,
            qopts      => $queryoptions_ref,
            sessionID  => $sessionID,
            normset    => $normset,
            
            config     => \%config,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config{tt_search_showautset_tname},$ttdata,$r);
        return OK;
    }
  
    if ($searchtitofaut) {
        # Bestimmung der Titel
        my $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=2") or $logger->error($DBI::errstr);
        $request->execute($searchtitofaut);

        my @titelidns=();
        while (my $res=$request->fetchrow_hashref){
            push @titelidns, $res->{sourceid};
        }

        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
            return OK;
        }
    
        if ($#titelidns == 0) {
            OpenBib::Search::Util::print_tit_set_by_idn({
                titidn             => $titelidns[0],
                dbh                => $dbh,
                sessiondbh         => $sessiondbh,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                queryoptions_ref   => $queryoptions_ref,
                database           => $database,
                sessionID          => $sessionID,
                apachereq          => $r,
                stylesheet         => $stylesheet,
                view               => $view,
                msg                => $msg,
            });
            return OK;
        }
    
        if ($#titelidns > 0) {
            my @outputbuffer=();
            my ($atime,$btime,$timeall);
      
            if ($config{benchmark}) {
                $atime=new Benchmark;
            }
      
            foreach my $titelidn (@titelidns) {
                push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                    titidn            => $titelidn,
                    dbh               => $dbh,
                    sessiondbh        => $sessiondbh,
                    targetdbinfo_ref  => $targetdbinfo_ref,
                    database          => $database,
                    sessionID         => $sessionID,
                });
            }
            
            if ($config{benchmark}) {
                $btime   = new Benchmark;
                $timeall = timediff($btime,$atime);
                $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel : ist ".timestr($timeall));
                undef $atime;
                undef $btime;
                undef $timeall;
            }

            my @sortedoutputbuffer=();
            OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

	    my @resultset=();
	    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
	    foreach my $item_ref (@sortedoutputbuffer){
	      push @resultset, { id       => $item_ref->{id},
				 database => $item_ref->{database},
			       };
	    }

            OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
            OpenBib::Search::Util::print_tit_list_by_idn({
                itemlist_ref     => \@sortedoutputbuffer,
                targetdbinfo_ref => $targetdbinfo_ref,
                queryoptions_ref => $queryoptions_ref,
                database         => $database,
                sessionID        => $sessionID,
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                msg              => $msg,
            });
            return OK;
        }	
    }
  
    #####################################################################
    if ($searchtitofurhkor) {
        # Bestimmung der Titel
        my $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=3") or $logger->error($DBI::errstr);
        $request->execute($searchtitofurhkor);

        my @titelidns=();
        while (my $res=$request->fetchrow_hashref){
            push @titelidns, $res->{sourceid};
        }

        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
            return OK;
        }

        if ($#titelidns == 0) {
            OpenBib::Search::Util::print_tit_set_by_idn({
                titidn             => $titelidns[0],
                dbh                => $dbh,
                sessiondbh         => $sessiondbh,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                queryoptions_ref   => $queryoptions_ref,
                database           => $database,
                sessionID          => $sessionID,
                apachereq          => $r,
                stylesheet         => $stylesheet,
                view               => $view,
                msg                => $msg,
            });
            return OK;

        }
        if ($#titelidns > 0) {
            my @outputbuffer=();
            my ($atime,$btime,$timeall);
      
            if ($config{benchmark}) {
                $atime=new Benchmark;
            }

            foreach my $titelidn (@titelidns) {
                push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                    titidn            => $titelidn,
                    dbh               => $dbh,
                    sessiondbh        => $sessiondbh,
                    targetdbinfo_ref  => $targetdbinfo_ref,
                    database          => $database,
                    sessionID         => $sessionID,
                });
            }

            if ($config{benchmark}) {
                $btime   = new Benchmark;
                $timeall = timediff($btime,$atime);
                $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel : ist ".timestr($timeall));
                undef $atime;
                undef $btime;
                undef $timeall;
            }

            my @sortedoutputbuffer=();
            OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

	    my @resultset=();
	    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
	    foreach my $item_ref (@sortedoutputbuffer){
	      push @resultset, { id       => $item_ref->{id},
				 database => $item_ref->{database},
			       };
	    }
	    
            OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
            OpenBib::Search::Util::print_tit_list_by_idn({
                itemlist_ref     => \@sortedoutputbuffer,
                targetdbinfo_ref => $targetdbinfo_ref,
                queryoptions_ref => $queryoptions_ref,
                database         => $database,
                sessionID        => $sessionID,
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                msg              => $msg,
            });
            return OK;
        }	
    }
  
    #######################################################################
    if ($searchtitofswt) {
        # Bestimmung der Titel
        my $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=4") or $logger->error($DBI::errstr);
        $request->execute($searchtitofswt);

        my @titelidns=();
        while (my $res=$request->fetchrow_hashref){
            push @titelidns, $res->{sourceid};
        }
    
        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
            return OK;
        }
        if ($#titelidns == 0) {
            OpenBib::Search::Util::print_tit_set_by_idn({
                titidn             => $titelidns[0],
                dbh                => $dbh,
                sessiondbh         => $sessiondbh,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                queryoptions_ref   => $queryoptions_ref,
                database           => $database,
                sessionID          => $sessionID,
                apachereq          => $r,
                stylesheet         => $stylesheet,
                view               => $view,
                msg                => $msg,
            });
            return OK;
        }
        if ($#titelidns > 0) {
            my @outputbuffer=();
            my ($atime,$btime,$timeall);
      
            if ($config{benchmark}) {
                $atime=new Benchmark;
            }

            foreach my $titelidn (@titelidns) {
                push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                    titidn            => $titelidn,
                    dbh               => $dbh,
                    sessiondbh        => $sessiondbh,
                    targetdbinfo_ref  => $targetdbinfo_ref,
                    database          => $database,
                    sessionID         => $sessionID,
                });
            }

            if ($config{benchmark}) {
                $btime   = new Benchmark;
                $timeall = timediff($btime,$atime);
                $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel : ist ".timestr($timeall));
                undef $atime;
                undef $btime;
                undef $timeall;
            }

            my @sortedoutputbuffer=();
            OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

	    my @resultset=();
	    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
	    foreach my $item_ref (@sortedoutputbuffer){
	      push @resultset, { id       => $item_ref->{id},
				 database => $item_ref->{database},
			       };
	    }
	    
            OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
            OpenBib::Search::Util::print_tit_list_by_idn({
                itemlist_ref     => \@sortedoutputbuffer,
                targetdbinfo_ref => $targetdbinfo_ref,
                queryoptions_ref => $queryoptions_ref,
                database         => $database,
                sessionID        => $sessionID,
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                msg              => $msg,
            });
            return OK;
        }	
    }
  
    #######################################################################
    if ($searchtitofnot) {
        # Bestimmung der Titel
        my $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=5") or $logger->error($DBI::errstr);
        $request->execute($searchtitofnot);

        my @titelidns=();
        while (my $res=$request->fetchrow_hashref){
            push @titelidns, $res->{sourceid};
        }

        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
            return OK;
        }
    
        if ($#titelidns == 0) {
            OpenBib::Search::Util::print_tit_set_by_idn({
                titidn             => $titelidns[0],
                dbh                => $dbh,
                sessiondbh         => $sessiondbh,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                queryoptions_ref   => $queryoptions_ref,
                database           => $database,
                sessionID          => $sessionID,
                apachereq          => $r,
                stylesheet         => $stylesheet,
                view               => $view,
                msg                => $msg,
            });
            return OK;
        }
    
        if ($#titelidns > 0) {
            my @outputbuffer=();
            my ($atime,$btime,$timeall);
      
            if ($config{benchmark}) {
                $atime=new Benchmark;
            }

            foreach my $titelidn (@titelidns) {
                push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                    titidn            => $titelidn,
                    dbh               => $dbh,
                    sessiondbh        => $sessiondbh,
                    targetdbinfo_ref  => $targetdbinfo_ref,
                    database          => $database,
                    sessionID         => $sessionID,
                });
            }

            if ($config{benchmark}) {
                $btime   = new Benchmark;
                $timeall = timediff($btime,$atime);
                $logger->info("Zeit fuer : ".($#outputbuffer+1)." Titel : ist ".timestr($timeall));
                undef $atime;
                undef $btime;
                undef $timeall;
            }

            my @sortedoutputbuffer=();
            OpenBib::Common::Util::sort_buffer($sorttype,$sortorder,\@outputbuffer,\@sortedoutputbuffer);

	    my @resultset=();
	    # Nach der Sortierung in Resultset eintragen zur spaeteren Navigation
	    foreach my $item_ref (@sortedoutputbuffer){
	      push @resultset, { id       => $item_ref->{id},
				 database => $item_ref->{database},
			       };
	    }

            OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@resultset);
            OpenBib::Search::Util::print_tit_list_by_idn({
                itemlist_ref     => \@sortedoutputbuffer,
                targetdbinfo_ref => $targetdbinfo_ref,
                queryoptions_ref => $queryoptions_ref,
                database         => $database,
                sessionID        => $sessionID,
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                msg              => $msg,
            });
            return OK;
        }	
    }
  
    # Falls bis hierhin noch nicht abgearbeitet, dann wirds wohl nichts mehr geben
    OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
    $logger->error("Unerlaubt das Ende erreicht");
  
    $dbh->disconnect;
    $sessiondbh->disconnect;
    return OK;
}

1;
