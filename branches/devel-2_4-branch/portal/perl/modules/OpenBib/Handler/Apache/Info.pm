#####################################################################
#
#  OpenBib::Handler::Apache::Info
#
#  Dieses File ist (C) 2006-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Info;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;
use OpenBib::Template::Utilities;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->instance;
    my $statistics  = new OpenBib::Statistics();
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $utils       = new OpenBib::Template::Utilities;

    my $query       = Apache2::Request->new($r);

    my $session     = OpenBib::Session->instance({ apreq => $r });

    my $user        = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $useragent=$r->subprocess_env('HTTP_USER_AGENT');
  
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $view=$r->subprocess_env('openbib_view') || $config->{defaultview};

    my $uri  = $r->parsed_uri;
    my $path = $uri->path;
    
    # Basisipfad entfernen
    my $basepath = $config->{base_loc}."/$view/".$config->{handler}{info_loc}{name};
    $path=~s/$basepath//;

    $logger->debug("Path: $path without basepath $basepath");
    
    # Service-Parameter aus URI bestimmen
    my $stid = 0;
    
    if ($path=~m/^\/([^\/]+)/){
        $stid     = $1;
    }
    else {
        return Apache2::Const::OK;
    }

    # Sub-Template ID
    my $database = $query->param('db')       || '';
    my $id       = $query->param('id')       || '';
    my $format   = $query->param('format')   || '';

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    my $viewdesc      = $config->get_viewdesc_from_viewname($view);

    # TT-Data erzeugen
    my $ttdata={
        format        => $format,
        stid          => $stid,
        database      => $database,
        query         => $query,
        id            => $id,
        view          => $view,
        stylesheet    => $stylesheet,
        viewdesc      => $viewdesc,
        sessionID     => $session->{ID},
	session       => $session,
        useragent     => $useragent,
        config        => $config,
        dbinfo        => $dbinfotable,
        statistics    => $statistics,
        utils         => $utils,
        user          => $user,
        msg           => $msg,
    };

    $stid=~s/[^0-9]//g;

    my $templatename = ($stid)?"tt_info_".$stid."_tname":"tt_info_tname";

    OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

    return Apache2::Const::OK;
}

1;
