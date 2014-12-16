#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Statistics
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

package OpenBib::Handler::Apache::Admin::Statistics;

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
use Date::Calc qw/Days_in_Month/;
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
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Handler::Apache::Admin';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'           => 'show_collection',
        'show_statistics'           => 'show_statistics',
        'show_graph'                => 'show_graph',
        'dispatch_to_representation'           => 'dispatch_to_representation',
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

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $statistics = new OpenBib::Statistics();
    
    # TT-Data erzeugen
    my $ttdata={
        statistics     => $statistics,
    };
    
    my $templatename = "tt_admin_statistics_tname";
    
    $self->print_page($config->{$templatename},$ttdata);

}

sub show_graph {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $statisticsid    = $self->param('statisticsid')    || '';
    my $statisticsid2   = $self->param('statisticsid2')   || '';

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
    my $month      = $query->param('month')      || '';
    my $day        = $query->param('month')      || '';
    
    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $statistics = new OpenBib::Statistics();
    
    # TT-Data erzeugen
    my $ttdata={
        year       => $year,
        month      => $month,
        day        => $day,
        statistics => $statistics,
    };

    my $templatename = "tt_admin_statistics_";

    if ($statisticsid && $statisticsid2){
        $templatename = $templatename.$statisticsid."_".$statisticsid2."_graph";
    }

    $templatename.="_tname";
    
    $self->print_page($config->{$templatename},$ttdata);

}

sub show_statistics {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $statisticsid   = $self->param('statisticsid')    || '';
    my $statisticsid2  = $self->param('statisticsid2')   || '';
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
    my $month      = $query->param('month')      || '';
    my $day        = $query->param('day')        || '';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $id  = ($statisticsid && $statisticsid2)?$statisticsid2:$statisticsid;
    my $laststatisticsid = $self->strip_suffix($id);
    
    my $statistics = new OpenBib::Statistics();

    unless ($year){
        ($year,$month,$day) = (localtime)[5,4,3];
        $year+=1900;
        $month+=1;
    }

    $month = sprintf "%02d",$month;
    $day   = sprintf "%02d",$day;
    
    # TT-Data erzeugen
    my $ttdata={
        year       => $year,
        month      => $month,
        day        => $day,

        days_in_month => sub {
            return Days_in_Month(@_);
        },
            
        statistics => $statistics,
    };

    
    my $templatename = "tt_admin_statistics_tname";

    if ($statisticsid && $statisticsid2 && $laststatisticsid){
        $templatename = "tt_admin_statistics_".$statisticsid."_".$laststatisticsid."_tname";
    }
    elsif ($statisticsid && !$statisticsid2 && $laststatisticsid){
        $templatename = "tt_admin_statistics_".$laststatisticsid."_tname";
    }

    $logger->debug("Template: $templatename");
    
    $self->print_page($config->{$templatename},$ttdata);

}


1;
