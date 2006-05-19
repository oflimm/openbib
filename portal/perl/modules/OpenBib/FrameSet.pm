#####################################################################
#
#  OpenBib::FrameSet
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::FrameSet;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Common::Util();
use OpenBib::Config();
use OpenBib::L10N;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    # Verbindung zur SQL-Datenbank herstellen
    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
    
    my $sessionID      = $query->param('sessionID')      || '';
    my $view           = OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    my $setmask        = $query->param('setmask')        || '';
    my $headerframeurl = $query->param('headerframeurl') || $config{headerframe_loc};
    my $bodyframeurl   = $query->param('bodyframeurl')   || $config{searchframe_loc};

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if ($bodyframeurl eq $config{searchframe_loc}){
        $bodyframeurl="$bodyframeurl?sessionID=$sessionID;view=$view;setmask=$setmask";
    }
    else {
        $bodyframeurl="$bodyframeurl?sessionID=$sessionID;view=$view";
    }

    $headerframeurl="$headerframeurl?sessionID=$sessionID;view=$view";

    my $ttdata={
        view            => $view,
        sessionID       => $sessionID,

        headerframeurl  => $headerframeurl,
        bodyframeurl    => $bodyframeurl,
        
        config          => \%config,
        msg             => $msg,
    };

    OpenBib::Common::Util::print_page($config{tt_frameset_tname},$ttdata,$r);

    $sessiondbh->disconnect();

    return OK;
}

1;
