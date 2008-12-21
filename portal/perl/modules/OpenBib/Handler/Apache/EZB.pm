#####################################################################
#
#  OpenBib::Handler::Apache::EZB.pm
#
#  Copyright 2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::EZB;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use Benchmark ':hireswallclock';
use Encode qw/decode_utf8 encode_utf8/;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::BibSonomy;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::EZB;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->instance;
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    
    my $query  = Apache::Request->instance($r);

    my $status = $query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $action         = decode_utf8($query->param('action'))   || '';
    my $notation       = decode_utf8($query->param('notation')) || '';
    my $stid           = decode_utf8($query->param('stid'))     || '';

    my $sc             = decode_utf8($query->param('sc'))       || '';
    my $lc             = decode_utf8($query->param('lc'))       || '';
    my $sindex         = decode_utf8($query->param('sindex'))   || 0;
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    my $useragent=$r->subprocess_env('HTTP_USER_AGENT');

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
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

    my $ezb = new OpenBib::EZB;
    
    if ($action eq "show_subjects"){
        my $subjects_ref = $ezb->get_subjects();

        $logger->debug(YAML::Dump($subjects_ref));
            
        # TT-Data erzeugen
        my $ttdata={
            subjects      => $subjects_ref,
            view          => $view,
            stylesheet    => $stylesheet,
            sessionID     => $session->{ID},
            session       => $session,
            useragent     => $useragent,
            config        => $config,
            msg           => $msg,
        };
            
        $stid=~s/[^0-9]//g;
        
        my $templatename = ($stid)?"tt_ezb_showsubjects_".$stid."_tname":"tt_ezb_showsubjects_tname";
        
        OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
        return OK;
    }
    elsif ($action eq "show_journals"){
        if ($notation){
            my $journals_ref = $ezb->get_journals({
                notation => $notation,
                sc       => $sc,
                lc       => $lc,
                sindex   => $sindex,
            });
            
            $logger->debug(YAML::Dump($journals_ref));
            
            # TT-Data erzeugen
            my $ttdata={
                journals      => $journals_ref,
                view          => $view,
                stylesheet    => $stylesheet,
                sessionID     => $session->{ID},
                session       => $session,
                useragent     => $useragent,
                config        => $config,
                msg           => $msg,
            };
            
            $stid=~s/[^0-9]//g;
            
            my $templatename = ($stid)?"tt_ezb_showjournals_".$stid."_tname":"tt_ezb_showjournals_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
            return OK;
        }
        else {
            OpenBib::Common::Util::print_warning($msg->maketext("Keine Notation vorhanden"),$r,$msg);                
        }       
    }

    OpenBib::Common::Util::print_warning($msg->maketext("Keine gültige Aktion"),$r,$msg);

    return OK;
}

1;
