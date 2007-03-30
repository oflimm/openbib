#####################################################################
#
#  OpenBib::Tags.pm
#
#  Copyright 2007 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Tags;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use Encode 'decode_utf8';
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;
use OpenBib::User;

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

    my $offset = 0;
    my $hitrange= 0;
    my $database =0;
    my $sorttype = "author";
    my $sortorder ="up";
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
    my $titisbn        = $query->param('titisbn')     || '';
    my $tags           = $query->param('tags')        || '';

    my $searchtitoftag = $query->param('searchtitoftag') || '';

    my $queryid        = $query->param('queryid')     || '';

    my $do_add         = $query->param('do_add')      || '';
    my $do_edit        = $query->param('do_edit')     || '';
    my $do_del         = $query->param('do_del')      || '';
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########
  
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

        return OK;
    }
    
    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    my $user = new OpenBib::User();

    my $userid = $user->get_userid_of_session($session->{ID});

    if (!$userid){
        OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
        return OK;
    }
    
    my $loginname = $user->get_username_for_userid($userid);
    
    if ($do_add){
        $user->add_tags({
            tags      => $tags,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
        });

        $r->internal_redirect("http://$config->{servername}$config->{search_loc}?sessionID=$session->{ID};database=$titdb;searchsingletit=$titid;queryid=$queryid");
        return OK;
    }
    elsif ($do_del){
        $user->del_tags({
            tags      => $tags,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
        });
        
        $r->internal_redirect("http://$config->{servername}$config->{search_loc}?sessionID=$session->{ID};database=$titdb;searchsingletit=$titid;queryid=$queryid");
        return OK;

    }

    if ($searchtitoftag) {
        my @titelidns = ();
        my $hits      = 0;

        if ($searchtitoftag =~ /^\d+$/){
            # Zuerst Gesamtzahl bestimmen
            my $sqlrequest="select count(distinct titid,titdb) as conncount from tittag  where tagid=?";
            my $request=$user->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
            $request->execute($searchtitoftag);
            
            my $res=$request->fetchrow_hashref;
            $hits = $res->{conncount};

            my $limits="";
            if ($hitrange > 0){
                $limits="limit $offset,$hitrange";

            }

            # Bestimmung der Titel
            $request=$user->{dbh}->prepare("select distinct stagid from conn where targetid=? and sourcetype=1 and targettype=2 $limits") or $logger->error($DBI::errstr);
            $request->execute($searchtitoftag);
            
            
            while (my $res=$request->fetchrow_hashref){
                push @titelidns, $res->{sourceid};
            }
            $request->finish();            
        }
        
        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
            return OK;
        }
    
        if ($#titelidns == 0) {
            OpenBib::Search::Util::print_tit_set_by_idn({
                titidn             => $titelidns[0],
#                dbh                => $dbh,
                session            => $session,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                queryoptions_ref   => $queryoptions_ref,
                database           => $database,
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
      
            if ($config->{benchmark}) {
                $atime=new Benchmark;
            }
      
            foreach my $titelidn (@titelidns) {
                push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                    titidn            => $titelidn,
#                    dbh               => $dbh,
                    sessiondbh        => $session->{dbh},
                    targetdbinfo_ref  => $targetdbinfo_ref,
                    database          => $database,
                    sessionID         => $session->{ID},
                });
            }
            
            if ($config->{benchmark}) {
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

            $session->updatelastresultset(\@resultset);
            OpenBib::Search::Util::print_tit_list_by_idn({
                itemlist_ref     => \@sortedoutputbuffer,
                targetdbinfo_ref => $targetdbinfo_ref,
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
            return OK;
        }	
    }

    return OK;
}

1;
