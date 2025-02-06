#####################################################################
#
#  OpenBib::Mojo::Controller::Profiles
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

package OpenBib::Mojo::Controller::Profiles;

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
use SOAP::Lite;
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
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $config         = $self->stash('config');

    my $profileinfo_ref = $config->get_profileinfo_overview();

    my $ttdata = {
        profiles   => $profileinfo_ref,
    };
    
    return $self->print_page($config->{tt_profiles_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $profilename    = $self->strip_suffix($self->param('profileid'));

    # Shared Args
    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');

    if (!$config->profile_exists($profilename)) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }

    my $profileinfo_ref = $config->get_profileinfo->search_rs({ profilename => $profilename })->single();
    my $orgunits_ref    = $config->get_orgunitinfo_overview($profilename);
    
    my $activedbs_ref = $config->get_active_database_names();

    my @profiledbs    = $config->get_profiledbs($profilename);
    
    my $ttdata = {
        profileinfo => $profileinfo_ref,
        profiledbs  => \@profiledbs,
        orgunits    => $orgunits_ref,
        activedbs   => $activedbs_ref,
    };

    return $self->print_page($config->{tt_profiles_record_tname},$ttdata);
}

1;
