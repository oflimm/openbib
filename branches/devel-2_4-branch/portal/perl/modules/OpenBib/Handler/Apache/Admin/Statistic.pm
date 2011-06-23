#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Statistic
#
#  Dieses File ist (C) 2004-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Admin::Statistic;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::SubRequest ();
use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Database::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'           => 'show_collection',
        'show_statistic'            => 'show_statistic',
        'show_graph'                => 'show_graph',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $statistics = new OpenBib::Statistics();
    
    # TT-Data erzeugen
    my $ttdata={
        statistics     => $statistics,
    };
    
    my $templatename = "tt_admin_statistic_tname";
    
    $self->print_page($config->{$templatename},$ttdata);

}

sub show_graph {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $statisticid    = $self->param('statisticid')    || '';
    my $statisticid2   = $self->param('statisticid2')   || '';

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $year       = $query->param('year')       || '';
    
    if (!$self->is_authenticated('admin')){
        return;
    }

    my $statistics = new OpenBib::Statistics();
    
    # TT-Data erzeugen
    my $ttdata={
        year       => $year,
        statistics => $statistics,
    };

    my $templatename = "tt_admin_statistic_";

    if ($statisticid && $statisticid2){
        $templatename = $templatename.$statisticid."_".$statisticid2."_graph";
    }

    $templatename.="_tname";
    
    $self->print_page($config->{$templatename},$ttdata);

}

sub show_statistic {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $statisticid    = $self->param('statisticid')    || '';
    my $statisticid2   = $self->param('statisticid2')   || '';
    my $graph          = $self->param('graph')          || '';

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $year       = $query->param('year')       || '';

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $id        = ($statisticid && $statisticid2)?$statisticid2:$statisticid;
    my $statistic = $self->strip_suffix($id);
    
    my $statistics = new OpenBib::Statistics();
    
    # TT-Data erzeugen
    my $ttdata={
        year       => $year,
        statistics => $statistics,
    };

    
    my $templatename = "tt_admin_statistic_tname";

    if ($statisticid && $statisticid2 && $statistic){
        $templatename = "tt_admin_statistic_".$statisticid."_".$statistic."_tname";
    }
    elsif ($statisticid && !$statisticid2 && $statistic){
        $templatename = "tt_admin_statistic_".$statistic."_tname";
    }
    
    $self->print_page($config->{$templatename},$ttdata);

}


1;
