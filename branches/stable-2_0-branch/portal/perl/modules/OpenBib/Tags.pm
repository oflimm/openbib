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

    my $offset         = $query->param('titid')       || 0;
    my $hitrange       = $query->param('titid')       || 50;
    my $database       = $query->param('database')    || '';
    my $sorttype       = $query->param('sorttype')    || "author";
    my $sortorder      = $query->param('sortorder')   || "up";
    my $titid          = $query->param('titid')       || '';
    my $titdb          = $query->param('titdb')       || '';
    my $titisbn        = $query->param('titisbn')     || '';
    my $tags           = decode_utf8($query->param('tags'))        || '';
    my $type           = $query->param('type')        || 1;

    my $private_tags   = $query->param('private_tags')   || 0;
    my $searchtitoftag = $query->param('searchtitoftag') || '';
    my $show_usertags  = $query->param('show_usertags')  || '';

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
    
    my $loginname = $user->get_username_for_userid($userid);
    
    if ($do_add){

        if (!$userid){
            OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
            return OK;
        }

        $logger->debug("Aufnehmen/Aendern der Tags: $tags");
        
        $user->add_tags({
            tags      => $tags,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
            type      => $type,
        });

        $r->internal_redirect("http://$config->{servername}$config->{search_loc}?sessionID=$session->{ID};database=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
        return OK;
    }
    elsif ($do_del){

        if (!$userid){
            OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
            return OK;
        }

        $user->del_tags({
            tags      => $tags,
            titid     => $titid,
            titdb     => $titdb,
            loginname => $loginname,
        });
        
        $r->internal_redirect("http://$config->{servername}$config->{search_loc}?sessionID=$session->{ID};database=$titdb;searchsingletit=$titid;queryid=$queryid;no_log=1");
        return OK;

    }

    if ($show_usertags){

        if (!$userid){
            OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
            return OK;
        }

        my $targettype=$user->get_targettype_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            targettype => $targettype,
            loginname  => $loginname,
            user       => $user,
            config     => $config,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_tags_showusertags_tname},$ttdata,$r);
    }
    
    if ($searchtitoftag) {
        my @titelidns = ();
        my $hits      = 0;

        if ($searchtitoftag =~ /^\d+$/){
            # Zuerst Gesamtzahl bestimmen
            
            if ($private_tags){
                if (!$userid){
                    OpenBib::Common::Util::print_warning("Sie müssen sich authentifizieren, um taggen zu können",$r,$msg);
                    return OK;
                }

                my $sqlrequest="select count(distinct titid,titdb) as conncount from tittag where tagid=? and loginname=?";
                my $request=$user->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
                $request->execute($searchtitoftag,$loginname);
            
                my $res=$request->fetchrow_hashref;
                $hits = $res->{conncount};
                
                my $limits="";
                if ($hitrange > 0){
                    $limits="limit $offset,$hitrange";
                }
                
                # Bestimmung der Titel
                $sqlrequest="select distinct titid,titdb from tittag where tagid=? and loginname=? $limits";
                $request=$user->{dbh}->prepare("") or $logger->error($DBI::errstr);
                $request->execute($searchtitoftag,$loginname);
                
                
                while (my $res=$request->fetchrow_hashref){
                    push @titelidns, {
                        id       => $res->{titid},
                        dbname   => $res->{titdb}
                    };
                }
                $request->finish();
            }
            else {
                my $sqlrequest="select count(distinct titid,titdb) as conncount from tittag where tagid=?";
                my @sqlargs = ();
                push @sqlargs, $searchtitoftag;

                if ($database) {
                    $sqlrequest.=" and titdb=?";
                    push @sqlargs, $database;
                }

                $logger->debug($sqlrequest." - ".join(",",@sqlargs));
                my $request=$user->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
                $request->execute(@sqlargs);
            
                my $res=$request->fetchrow_hashref;
                $hits = $res->{conncount};
                
                my $limits="";
                if ($hitrange > 0){
                    $limits="limit $offset,$hitrange";
                    
                }

                $sqlrequest="select distinct titid,titdb from tittag where tagid=?";
                @sqlargs = ();
                push @sqlargs, $searchtitoftag;
                
                if ($database) {
                    $sqlrequest.=" and titdb=?";
                    push @sqlargs, $database;
                }

                $sqlrequest.=" $limits";

                # Bestimmung der Titel
                $request=$user->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
                $request->execute(@sqlargs);
                
                
                while (my $res=$request->fetchrow_hashref){
                    push @titelidns, {
                        id       => $res->{titid},
                        dbname   => $res->{titdb}
                    };
                }
                $request->finish();
            }
        }

        $logger->debug("Titel-IDs: ".YAML::Dump(\@titelidns));

        if ($#titelidns == -1) {
            OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
            return OK;
        }
        else {
            my @outputbuffer=();
            my ($atime,$btime,$timeall);
      
            if ($config->{benchmark}) {
                $atime=new Benchmark;
            }
      
            foreach my $titel (@titelidns) {

                my $titelidn = $titel->{id};
                my $database = $titel->{dbname};

                my $dbh
                    = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                        or $logger->error_die($DBI::errstr);

                push @outputbuffer, OpenBib::Search::Util::get_tit_listitem_by_idn({
                    titidn            => $titelidn,
                    dbh               => $dbh,
                    sessiondbh        => $session->{dbh},
                    targetdbinfo_ref  => $targetdbinfo_ref,
                    database          => $database,
                    sessionID         => $session->{ID},
                });

                $dbh->disconnect();
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

                query            => $query,
                template         => 'tt_tags_showtitlist_tname',
                location         => 'tags_loc',

                msg              => $msg,
            });
        }	
    }

    return OK;
}

1;
