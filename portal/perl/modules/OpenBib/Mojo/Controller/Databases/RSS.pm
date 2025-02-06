#####################################################################
#
#  OpenBib::Mojo::Controller::Databases::RSS
#
#  Dieses File ist (C) 2004-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Databases::RSS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use JSON::XS;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Admin';

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    if (!$config->db_exists($dbname)) {
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }

    my $rssfeed_ref= $config->get_rssfeeds_of_db($dbname);;
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $katalog={
        dbname      => $dbname,
        rssfeeds    => $rssfeed_ref,
    };
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
        katalog      => $katalog,
    };
    
    return $self->print_page($config->{tt_databases_rss_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');
    my $rssid          = $self->strip_suffix($self->param('rssid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }

    my $rssinfo_ref = $config->get_rssfeed_by_id($rssid);
    my $dbinfo_ref  = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
        rssinfo      => $rssinfo_ref,
        dbname       => $dbname,
    };
    
    return $self->print_page($config->{tt_databases_rss_record_tname},$ttdata);
}

1;
