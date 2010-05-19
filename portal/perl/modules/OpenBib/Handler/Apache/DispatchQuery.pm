#####################################################################
#
#  OpenBib::Handler::Apache::DispatchQuery
#
#  Dieses File ist (C) 2005-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::DispatchQuery;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::SubRequest ();
use DBI;
use Digest::MD5;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });     

    my $view=$r->subprocess_env('openbib_view') || $config->{defaultview};

    my $queryid   = $query->param('queryid') || '';

    # Main-Actions
    my $do_newquery      = $query->param('do_newquery')      || '';
    my $do_resultlist    = $query->param('do_resultlist')    || '';
    my $do_externalquery = $query->param('do_externalquery') || '';

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        
        return Apache2::Const::OK;
    }

    if    ($do_newquery) {
        $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{searchmask_loc}{name}?queryid=$queryid");
        return Apache2::Const::OK;
    }
    elsif ($do_resultlist) {
        $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{resultlists_loc}{name}?action=choice&queryid=$queryid");
        return Apache2::Const::OK;
    }
    elsif ($do_externalquery) {
        $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{externaljump_loc}{name}?queryid=$queryid");
        return Apache2::Const::OK;
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Aktion"),$r,$msg);
        return Apache2::Const::OK;
    }
  
    return Apache2::Const::OK;
}

1;
