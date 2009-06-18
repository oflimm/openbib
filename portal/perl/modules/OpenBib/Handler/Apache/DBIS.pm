#####################################################################
#
#  OpenBib::Handler::Apache::DBIS.pm
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

package OpenBib::Handler::Apache::DBIS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common REDIRECT);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
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
use OpenBib::DBIS;
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
    
    my $query  = Apache2::Request->new($r);

    my $status = $query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments");
    }

    my $session   = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $action         = decode_utf8($query->param('action'))   || '';
    my $show_cloud     = decode_utf8($query->param('show_cloud'));
    my $notation       = decode_utf8($query->param('notation')) || '';
    my $fs             = decode_utf8($query->param('fs'))       || '';
    my $stid           = decode_utf8($query->param('stid'))     || '';

    my $access_green   = decode_utf8($query->param('access_green'))     || 0;
    my $access_yellow  = decode_utf8($query->param('access_yellow'))    || 0;
    my $access_red     = decode_utf8($query->param('access_red'))       || 0;
    my $access_de      = decode_utf8($query->param('access_de'))        || 0;
    my $id             = decode_utf8($query->param('id'))       || undef;
    my $lett           = decode_utf8($query->param('lett'))     || '';

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

        return Apache2::Const::OK;
    }
    
    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    my $colors  = $access_green + $access_yellow*44;
    my $ocolors = $access_red*8 + $access_de*32;

    # Wenn keine Parameter uebergeben wurden, dann Defaults nehmen
    if (!$colors && !$ocolors){
        $logger->debug("Using defaults for color and ocolor");

        $colors  = $config->{dbis_colors};
        $ocolors = $config->{dbis_ocolors};

        my $colors_mask  = dec2bin($colors);
        my $ocolors_mask = dec2bin($ocolors);
        
        $access_red    = ($ocolors_mask & 0b001000)?1:0;
        $access_de     = ($ocolors_mask & 0b100000)?1:0;
        $access_green  = ($colors_mask  & 0b000001)?1:0;
        $access_yellow = ($colors_mask  & 0b101100)?1:0;
    }
    else {
        $logger->debug("Using CGI values for color and ocolor");
    }
    
    my $dbis = new OpenBib::DBIS({colors => $colors, ocolors => $ocolors, lang => $queryoptions->get_option('l') });
    
    if ($action eq "show_subjects"){
        my $subjects_ref = $dbis->get_subjects();

        $logger->debug(YAML::Dump($subjects_ref));
            
        # TT-Data erzeugen
        my $ttdata={
            access_green  => $access_green,
            access_yellow => $access_yellow,
            access_red    => $access_red,
            access_de     => $access_de,
            show_cloud    => $show_cloud,
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
        
        my $templatename = ($stid)?"tt_dbis_showsubjects_".$stid."_tname":"tt_dbis_showsubjects_tname";
        
        OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
        return Apache2::Const::OK;
    }
    elsif ($action eq "search_dbs"){
        if ($fs){
            my $dbs_ref = $dbis->search_dbs({
                fs       => $fs,
                notation => $notation,
                lett     => $lett,
            });
            
            $logger->debug(YAML::Dump($dbs_ref));
            
            # TT-Data erzeugen
            my $ttdata={
                access_green  => $access_green,
                access_yellow => $access_yellow,
                access_red    => $access_red,
                access_de     => $access_de,
                dbs           => $dbs_ref,
                view          => $view,
                stylesheet    => $stylesheet,
                sessionID     => $session->{ID},
                session       => $session,
                useragent     => $useragent,
                config        => $config,
                msg           => $msg,
            };
            
            $stid=~s/[^0-9]//g;
            
            my $templatename = ($stid)?"tt_dbis_searchdbs_".$stid."_tname":"tt_dbis_searchdbs_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
            return Apache2::Const::OK;
        }
        else {
            OpenBib::Common::Util::print_warning($msg->maketext("Kein Suchbegriff vorhanden"),$r,$msg);                
            return Apache2::Const::OK;
        }       
    }
    elsif ($action eq "show_dbs"){
        if ($notation){
            my $dbs_ref = $dbis->get_dbs({
                notation => $notation,
                lett     => $lett,
            });
            
            $logger->debug(YAML::Dump($dbs_ref));
            
            # TT-Data erzeugen
            my $ttdata={
                access_green  => $access_green,
                access_yellow => $access_yellow,
                access_red    => $access_red,
                access_de     => $access_de,
                dbs           => $dbs_ref,
                view          => $view,
                stylesheet    => $stylesheet,
                sessionID     => $session->{ID},
                session       => $session,
                useragent     => $useragent,
                config        => $config,
                msg           => $msg,
            };
            
            $stid=~s/[^0-9]//g;
            
            my $templatename = ($stid)?"tt_dbis_showdbs_".$stid."_tname":"tt_dbis_showdbs_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
            return Apache2::Const::OK;
        }
        else {
            OpenBib::Common::Util::print_warning($msg->maketext("Keine Notation vorhanden"),$r,$msg);                
            return Apache2::Const::OK;
        }
    }
    elsif ($action eq "show_dbinfo"){
        if ($id){
            my $dbinfo_ref = $dbis->get_dbinfo({
                id => $id,
            });
            
            $logger->debug(YAML::Dump($dbinfo_ref));
            
            # TT-Data erzeugen
            my $ttdata={
                dbinfo   => $dbinfo_ref,
                view          => $view,
                stylesheet    => $stylesheet,
                sessionID     => $session->{ID},
                session       => $session,
                useragent     => $useragent,
                config        => $config,
                msg           => $msg,
            };
            
            $stid=~s/[^0-9]//g;
            
            my $templatename = ($stid)?"tt_dbis_showdbinfo_".$stid."_tname":"tt_dbis_showdbinfo_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
            return Apache2::Const::OK;
        }
        else {
            OpenBib::Common::Util::print_warning($msg->maketext("Keine Dbid vorhanden"),$r,$msg);
            return Apache2::Const::OK;
        }
    }
    elsif ($action eq "show_dbreadme"){
        if ($id){
            my $dbreadme_ref = $dbis->get_dbreadme({
                id => $id,
            });
            
            $logger->debug("ReadME-Daten: ".YAML::Dump($dbreadme_ref));

            if ($dbreadme_ref->{location}){
                $r->content_type('text/html');
                $r->headers_out("Location" => $dbreadme_ref->{location});
                
                return Apache2::Const::REDIRECT;
            }
            else {

                # TT-Data erzeugen
                my $ttdata={
                    dbreadme => $dbreadme_ref,
                    view          => $view,
                    stylesheet    => $stylesheet,
                    sessionID     => $session->{ID},
                    session       => $session,
                    useragent     => $useragent,
                    config        => $config,
                    msg           => $msg,
                };
                
                $stid=~s/[^0-9]//g;
                
                my $templatename = ($stid)?"tt_dbis_showdbreadme_".$stid."_tname":"tt_dbis_showdbreadme_tname";
            
                OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

                return Apache2::Const::OK;
            }
        }
        else {
            OpenBib::Common::Util::print_warning($msg->maketext("Keine Dbid vorhanden"),$r,$msg);
            return Apache2::Const::OK;
        }
    }

    OpenBib::Common::Util::print_warning($msg->maketext("Keine gültige Aktion"),$r,$msg);

    return Apache2::Const::OK;
}

sub dec2bin {
    my $str = unpack("B32", pack("N", shift));
    $str =~ s/^0+(?=\d)//;   # strip leading zeroes
    return $str;
}
sub bin2dec {
    return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}

1;
