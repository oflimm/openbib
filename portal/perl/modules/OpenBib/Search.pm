#####################################################################
#
#  OpenBib::Search.pm
#
#  Copyright 1997-2005 Oliver Flimm <flimm@openbib.org>
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

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config %msg);

*config = \%OpenBib::Config::config;
*msg    = OpenBib::Config::get_msgs($config{msg_path});

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
    my $searchall         = $query->param('searchall')         || '';
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

    my $fs                = $query->param('fs')                || '';
    my $verf              = $query->param('verf')              || '';
    my $hst               = $query->param('hst')               || '';
    my $hststring         = $query->param('hststring')         || '';
    my $swt               = $query->param('swt')               || '';
    my $kor               = $query->param('kor')               || '';
    my $sign              = $query->param('sign')              || '';
    my $isbn              = $query->param('isbn')              || '';
    my $issn              = $query->param('issn')              || '';
    my $notation          = $query->param('notation')          || '';
    my $ejahr             = $query->param('ejahr')             || '';
    my $ejahrop           = $query->param('ejahrop')           || 'eq';
    my $mart              = $query->param('mart')              || '';

    my $lang              = $query->param('l')                 || undef;

    #####################################################################
    ## boolX: Verkn"upfung der Eingabefelder (leere Felder werden ignoriert)
    ##        AND  - Und-Verkn"upfung
    ##        OR   - Oder-Verkn"upfung
    ##        NOT  - Und Nicht-Verknuepfung
  
    my $boolverf      = ($query->param('boolverf'))?$query->param('boolverf'):"AND";
    my $boolhst       = ($query->param('boolhst'))?$query->param('boolhst'):"AND";
    my $boolswt       = ($query->param('boolswt'))?$query->param('boolswt'):"AND";
    my $boolkor       = ($query->param('boolkor'))?$query->param('boolkor'):"AND";
    my $boolnotation  = ($query->param('boolnotation'))?$query->param('boolnotation'):"AND";
    my $boolisbn      = ($query->param('boolisbn'))?$query->param('boolisbn'):"AND";
    my $boolissn      = ($query->param('boolissn'))?$query->param('boolissn'):"AND";
    my $boolsign      = ($query->param('boolsign'))?$query->param('boolsign'):"AND";
    my $boolejahr     = ($query->param('boolejahr'))?$query->param('boolejahr'):"AND";
    my $boolfs        = ($query->param('boolfs'))?$query->param('boolfs'):"AND";
    my $boolmart      = ($query->param('boolmart'))?$query->param('boolmart'):"AND";
    my $boolhststring = ($query->param('boolhststring'))?$query->param('boolhststring'):"AND";

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

    # Wandlungstabelle Erscheinungsjahroperator
    my $ejahrop_ref={
        'eq' => '=',
        'gt' => '>',
        'lt' => '<',
    };

    # Setzen der arithmetischen Ejahrop-Operatoren
    if (exists $ejahrop_ref->{$ejahrop}){
        $ejahrop=$ejahrop_ref->{$ejahrop};
    }
    else {
        $ejahrop="=";
    }

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$r);

    $logger->debug(YAML::Dump($queryoptions_ref));
    
    my $targetdbinfo_ref
        = OpenBib::Common::Util::get_targetdbinfo($sessiondbh);

    my $targetcircinfo_ref
        = OpenBib::Common::Util::get_targetcircinfo($sessiondbh);
    
    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning("Ungültige Session",$r);
      
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

    #####################################################################
  
    if ($searchall) {           # Standardsuche
        my @tidns=OpenBib::Search::Util::initial_search_for_titidns({
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
    
        # Kein Treffer
        if ($#tidns == -1) {
            OpenBib::Common::Util::print_info("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden",$r);;
            return OK;
        }
    
        # Genau ein Treffer
        if ($#tidns == 0) {
            OpenBib::Search::Util::print_tit_set_by_idn({
                titidn             => $tidns[0],
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
            });

            return OK;
        }
    
        # Mehr als ein Treffer
        if ($#tidns > 0) {
            my @outputbuffer=();
            my ($atime,$btime,$timeall);
      
            if ($config{benchmark}) {
                $atime=new Benchmark;
            }

            foreach my $tidn (@tidns) {
                push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                    titidn            => $tidn,
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
            OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
            OpenBib::Search::Util::print_tit_list_by_idn({
                itemlist_ref     => \@sortedoutputbuffer,
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
                
                utf2iso          => sub {
                    my $string=shift;
                    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                    return $string;
                },
                
                config     => \%config,
                msg        => \%msg,
            };
            OpenBib::Common::Util::print_page($config{tt_search_showautset_tname},$ttdata,$r);
            return OK;
        }
    
        if ($generalsearch=~/^supertit/) {
            my $supertitidn=$query->param("$generalsearch");

            my $reqstring="select distinct targetid from connection where sourceid=? and sourcetype='tit' and targettype='tit'";
            my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($supertitidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

            my @titidns=();
            
            while (my $res=$request->fetchrow_hashref) {
                push @titidns, $res->{targetid};
            }

            $request->finish();
            
            if ($#titidns == -1) {
                OpenBib::Common::Util::print_info("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden",$r);;
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
                OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
                OpenBib::Search::Util::print_tit_list_by_idn({
                    itemlist_ref     => \@sortedoutputbuffer,
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
        }

        if ($generalsearch=~/^subtit/) {
            my $subtitidn=$query->param("$generalsearch");

            my $reqstring="select distinct sourceid from connection where targetid=? and sourcetype='tit' and targettype='tit'";
            my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($subtitidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

            my @titidns=();
            
            while (my $res=$request->fetchrow_hashref) {
                push @titidns, $res->{sourceid};
            }

            $request->finish();
            
            if ($#titidns == -1) {
                OpenBib::Common::Util::print_info("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden",$r);;
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
                OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
                OpenBib::Search::Util::print_tit_list_by_idn({
                    itemlist_ref     => \@sortedoutputbuffer,
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
                
                utf2iso    => sub {
                    my $string=shift;
                    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                    return $string;
                },
                
                show_corporate_banner => 0,
                show_foot_banner      => 1,
                config     => \%config,
                msg        => \%msg,
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
                
                utf2iso    => sub {
                    my $string=shift;
                    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                    return $string;
                },
                
                config     => \%config,
                msg        => \%msg,
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
            
            utf2iso    => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
                return $string;
            },
            
            config     => \%config,
            msg        => \%msg,
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
            
            utf2iso    => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                return $string;
            },

            config     => \%config,
            msg        => \%msg,
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
            
            utf2iso    => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                return $string;
            },
            
            config     => \%config,
            msg        => \%msg,
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
            
            utf2iso    => sub {
                my $string=shift;
                $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
                return $string;
            },
            
            config     => \%config,
            msg        => \%msg,
        };
        OpenBib::Common::Util::print_page($config{tt_search_showautset_tname},$ttdata,$r);
        return OK;
    }
  
    if ($searchtitofaut) {
        # Bestimmung der Titel
        my $request=$dbh->prepare("select distinct sourceid from connection where targetid=? and sourcetype='tit' and targettype='aut'") or $logger->error($DBI::errstr);
        $request->execute($searchtitofaut);

        my @titelidns=();
        while (my $res=$request->fetchrow_hashref){
            push @titelidns, $res->{sourceid};
        }

        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden",$r);;
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
            OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
            OpenBib::Search::Util::print_tit_list_by_idn({
                itemlist_ref     => \@sortedoutputbuffer,
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
    }
  
    #####################################################################
    if ($searchtitofurhkor) {
        # Bestimmung der Titel
        my $request=$dbh->prepare("select distinct sourceid from connection where targetid=? and sourcetype='tit' and targettype='kor'") or $logger->error($DBI::errstr);
        $request->execute($searchtitofurhkor);

        my @titelidns=();
        while (my $res=$request->fetchrow_hashref){
            push @titelidns, $res->{sourceid};
        }

        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden",$r);;
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
            OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
            OpenBib::Search::Util::print_tit_list_by_idn({
                itemlist_ref     => \@sortedoutputbuffer,
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
    }
  
    #######################################################################
    if ($searchtitofswt) {
        # Bestimmung der Titel
        my $request=$dbh->prepare("select distinct sourceid from connection where targetid=? and sourcetype='tit' and targettype='swt'") or $logger->error($DBI::errstr);
        $request->execute($searchtitofswt);

        my @titelidns=();
        while (my $res=$request->fetchrow_hashref){
            push @titelidns, $res->{sourceid};
        }
    
        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden",$r);;
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
            OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
            OpenBib::Search::Util::print_tit_list_by_idn({
                itemlist_ref     => \@sortedoutputbuffer,
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
    }
  
    #######################################################################
    if ($searchtitofnot) {
        # Bestimmung der Titel
        my $request=$dbh->prepare("select distinct sourceid from connection where targetid=? and sourcetype='tit' and targettype='notation'") or $logger->error($DBI::errstr);
        $request->execute($searchtitofnot);

        my @titelidns=();
        while (my $res=$request->fetchrow_hashref){
            push @titelidns, $res->{sourceid};
        }

        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden",$r);;
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
            OpenBib::Common::Util::updatelastresultset($sessiondbh,$sessionID,\@sortedoutputbuffer);
            OpenBib::Search::Util::print_tit_list_by_idn({
                itemlist_ref     => \@sortedoutputbuffer,
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
    }
  
    # Falls bis hierhin noch nicht abgearbeitet, dann wirds wohl nichts mehr geben
    OpenBib::Common::Util::print_info("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden",$r);;
    $logger->error("Unerlaubt das Ende erreicht");
  
    $dbh->disconnect;
    $sessiondbh->disconnect;
    return OK;
}

1;
