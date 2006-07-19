#####################################################################
#
#  OpenBib::DispatchQuery
#
#  Dieses File ist (C) 2005-2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::DispatchQuery;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request();
use DBI;
use Digest::MD5;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;

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
    
    my $view      = ($query->param('view'))?$query->param('view'):'';
    my $queryid   = $query->param('queryid') || '';

    # Main-Actions
    my $do_newquery      = $query->param('do_newquery')      || '';
    my $do_resultlist    = $query->param('do_resultlist')    || '';
    my $do_externalquery = $query->param('do_externalquery') || '';

    my $queryoptions_ref
        = $session->get_queryoptions($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        
        return OK;
    }

    if    ($do_newquery) {
        $r->internal_redirect("http://$config->{servername}$config->{searchframe_loc}?sessionID=$session->{ID}&queryid=$queryid&view=$view");
        return OK;
    }
    elsif ($do_resultlist) {
        $r->internal_redirect("http://$config->{servername}$config->{resultlists_loc}?sessionID=$session->{ID}&view=$view&trefferliste=choice&queryid=$queryid");
        return OK;
    }
    elsif ($do_externalquery) {
        $r->internal_redirect("http://$config->{servername}$config->{externaljump_loc}?sessionID=$session->{ID}&view=$view&queryid=$queryid");
        return OK;
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Aktion"),$r,$msg);
        return OK;
    }
  
    return OK;
}

1;
