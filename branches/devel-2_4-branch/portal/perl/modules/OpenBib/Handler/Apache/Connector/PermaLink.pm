####################################################################
#
#  OpenBib::Handler::Apache::Connector::PermaLink.pm
#
#  Dieses File ist (C) 2007 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::PermaLink;

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::URI ();
use APR::URI ();

use Benchmark;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    my $session = OpenBib::Session->instance;

    my $uri  = $r->parsed_uri;
    my $path = $uri->path;

    my $lang = "de"; # TODO: Ausweitung auf andere Sprachen

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    # Basisipfad entfernen
    my $basepath = $config->{connector_permalink_loc};
    $path=~s/$basepath//;

    # RSS-Feedparameter aus URI bestimmen
    #
    # 

    my ($id1,$id2,$type,$view);
    if ($path=~m/^\/([^\/]+?)\/([^\/]+?)\/(\d+?)\/index.html$/){
        ($id1,$id2,$type)=($1,$2,$3);
    }
    elsif ($path=~m/^\/([^\/]+?)\/([^\/]+?)\/(\d+?)\/([^\/]+?)\/index.html$/){
        ($id1,$id2,$type,$view)=($1,$2,$3,$4);
    }

    # Zugriffe loggen
    if ($type == 1){
        # Titel
        $session->log_event({
            type      => 802,
            content   => "$id1:$id2:$view",
        });
    }
    elsif ($type == 6){
        # Literaturliste
        $session->log_event({
            type      => 803,
            content   => "$id1:$id2:$view",
        });
    }
    
    my $ttdata={
        view            => $view,
        id1             => $id1,
        id2             => $id2,
        type            => $type,
        config          => $config,
        msg             => $msg,
    };

    OpenBib::Common::Util::print_page($config->{tt_connector_permalink_tname},$ttdata,$r);

    
    return Apache2::Const::OK;
}

1;
