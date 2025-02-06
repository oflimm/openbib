#####################################################################
#
#  OpenBib::Mojo::Controller::OrganizationalUnits
#
#  Dieses File ist (C) 2004-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::OrganizationalUnits;

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

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $profilename    = $self->param('profileid')      || '';

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

    if (!$config->profile_exists($profilename)) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }
    
    my $orgunits_ref = $config->get_orgunitinfo_overview($profilename);

    my $ttdata={
        profilename => $profilename,
        orgunits    => $orgunits_ref,
    };
    
    return $self->print_page($config->{tt_orgunits_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $profilename    = $self->param('profileid');
    my $orgunitname    = $self->strip_suffix($self->param('orgunitid'));

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

    if (!$config->profile_exists($profilename)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {        
        return $self->print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"));
    }

    my $profileinfo_ref = $config->get_profileinfo->search_rs({ profilename => $profilename })->single();
    my $orgunitinfo_ref = $config->get_orgunitinfo->search_rs({ profileid => $profileinfo_ref->id, orgunitname => $orgunitname})->single();
    
    my @orgunitdbs   = $config->get_orgunitdbs($profilename,$orgunitname);
    
    $orgunitinfo_ref->{dbnames} = \@orgunitdbs;
    
    my $ttdata={
        profileinfo    => $profileinfo_ref,
        orgunitinfo    => $orgunitinfo_ref,
        orgunitdbs     => \@orgunitdbs,
    };

    return $self->print_page($config->{tt_orgunits_record_tname},$ttdata);
}

1;
