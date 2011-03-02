#####################################################################
#
#  OpenBib::Handler::Apache::Info
#
#  Dieses File ist (C) 2006-2011 Oliver Flimm <flimm@openbib.org>
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
use JSON::XS;
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

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_negotiate');
    $self->run_modes(
        'show_negotiate'       => 'show_negotiate',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $stid           = $self->param('stid')           || '';
    
    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');    
    
    # CGI Args

    my $format         = $query->param('format')         || '';
    
    my $statistics  = new OpenBib::Statistics();
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $utils       = new OpenBib::Template::Utilities;


    # Mit Suffix, dann keine Aushandlung des Typs

    my $representation = "";
    my $content_type   = "";

    my $thisstid         = "";
    if ($stid=~/^(.+?)(\.html|\.json|\.rdf)$/){
        $thisstid         = $1;
        ($representation) = $2 =~/^\.(.+?)$/;
        $content_type   = $config->{'content_type_map_rev'}{$representation};
    }
    # Sonst Aushandlung
    else {
        $thisstid = $stid;
        my $negotiated_type = $self->negotiate_type;
        $representation = $negotiated_type->{suffix};
        $content_type   = $negotiated_type->{content_type};
    }

    $stid = $thisstid;

    my $viewdesc      = $config->get_viewdesc_from_viewname($view);
    
    # TT-Data erzeugen
    my $ttdata={
        representation=> $representation,
        format        => $format,
        stid          => $stid,
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
        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },
    };

    my $templatename = ($stid && $stid ne "default")?"tt_info_".$stid."_tname":"tt_info_tname";

    OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

    return Apache2::Const::OK;
}

1;
