#####################################################################
#
#  OpenBib::Handler::Apache::Admin::OrganizationalUnit
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

package OpenBib::Handler::Apache::Admin::OrganizationalUnit;

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
use JSON::XS;
use List::MoreUtils qw(none any);
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

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'           => 'show_collection',
        'show_collection_form'      => 'show_collection_form',
        'create_record'             => 'create_record',
        'show_record'               => 'show_record',
        'show_record_form'          => 'show_record_form',
        'update_record'             => 'update_record',
        'delete_record'             => 'delete_record',
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
    my $view           = $self->param('view')                   || '';
    my $profilename    = $self->param('profileid')      || '';

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

    if (!$config->profile_exists($profilename)) {
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }
    
    my $orgunits_ref = $config->get_orgunits($profilename);

    my $ttdata={
        orgunits   => $orgunits_ref,
    };
    
    $self->print_page($config->{tt_admin_orgunit_tname},$ttdata);

    return Apache2::Const::OK;
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
    
    if (!$config->profile_exists($profilename)) {        
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {        
        $self->print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"));
        return Apache2::Const::OK;
    }
    
    my $profileinfo_ref = $config->get_profileinfo({ profilename => $profilename })->single();
    my $orgunitinfo_ref = $config->get_orgunitinfo($profilename,$orgunitname);
    
    my @orgunitdbs   = $config->get_profiledbs($profilename,$orgunitname);
    
    $orgunitinfo_ref->{dbnames} = \@orgunitdbs;
    
    my $ttdata={
        profileinfo    => $profileinfo_ref,
        orgunitinfo    => $orgunitinfo_ref,
    };

    $self->print_page($config->{tt_admin_orgunit_record_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';
    my $profilename    = $self->param('profileid')      || '';

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
    my $orgunit         = $query->param('orgunit')                      || '';
    my $description     = decode_utf8($query->param('description'))     || '';

    if (!$self->is_authenticated('admin')){
        return;
    }

    if (!$config->profile_exists($profilename)) {
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }

    if ($profilename eq "" || $orgunit eq "" || $description eq "") {
        $self->print_warning($msg->maketext("Sie müssen mindestens einen Profilnamen, den Namen einer Organisationseinheit und deren Beschreibung eingeben."));
        return Apache2::Const::OK;
    }
    
    my $ret = $config->new_orgunit({
        profilename => $profilename,
        orgunit     => $orgunit,
        description => $description,
    });
    
    if ($ret == -1){
        $self->print_warning($msg->maketext("Es existiert bereits eine Organisationseinheit unter diesem Namen"));
        return Apache2::Const::OK;
    }

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_profile_loc}/$profilename/orgunit/$orgunit/edit");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $profilename    = $self->param('profileid');
    my $orgunitname    = $self->param('orgunitid');

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

    if (!$self->is_authenticated('admin')){
        return;
    }

    if (!$config->profile_exists($profilename)) {
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }
    
    if (!$config->profile_exists($profilename)) {
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {
        $self->print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"));
    }

    my $profileinfo_ref = $config->get_profileinfo({ profilename => $profilename })->single();
    my $orgunitinfo_ref = $config->get_orgunitinfo($profilename,$orgunitname);

    my @dbnames      = $config->get_active_database_names();

    my @orgunitdbs   = $config->get_profiledbs($profilename,$orgunitname);
    
    $orgunitinfo_ref->{dbnames} = \@orgunitdbs;
    
    my $ttdata={
        profileinfo    => $profileinfo_ref,
        orgunitinfo    => $orgunitinfo_ref,
        dbnames    => \@dbnames,
    };
    
    $self->print_page($config->{tt_admin_orgunit_record_edit_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $profilename    = $self->param('profileid');
    my $orgunitname    = $self->param('orgunitid');

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
    my $method          = decode_utf8($query->param('_method')) || '';
    my $confirm         = $query->param('confirm') || 0;
    my $description     = decode_utf8($query->param('description'))     || '';
    my @orgunitdb       = ($query->param('orgunitdb'))?$query->param('orgunitdb'):();
    my $nr              = $query->param('nr')              || 0;

    if (!$self->is_authenticated('admin')){
        return;
    }

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden

    if (!$config->profile_exists($profilename)) {
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {
        $self->print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"));
        return Apache2::Const::OK;
    }

    if ($method eq "DELETE"){
        $logger->debug("About to delete $orgunitname");
        
        if ($confirm){
            my $orgunitinfo_ref = $config->get_orgunitinfo($profilename,$orgunitname);

            my $ttdata={
                orgunitinfo => $orgunitinfo_ref,
            };

            $logger->debug("Asking for confirmation");
            $self->print_page($config->{tt_admin_orgunit_record_delete_confirm_tname},$ttdata);

            return Apache2::Const::OK;
        }
        else {
            $logger->debug("Redirecting to delete location");
            $self->delete_record;
            return;
        }
    }

    $config->update_orgunit({
        profilename => $profilename,
        orgunit     => $orgunitname,
        description => $description,
        orgunitdb   => \@orgunitdb,
        nr          => $nr,
    });

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_profile_loc}/$profilename");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $profilename    = $self->param('profileid')      || '';
    my $orgunitname    = $self->param('orgunitid')      || '';

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

    if (!$self->is_authenticated('admin')){
        return;
    }

    if (!$config->profile_exists($profilename)) {
        $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
        return Apache2::Const::OK;
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {
        $self->print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"));
        return Apache2::Const::OK;
    }

    $config->del_orgunit($profilename,$orgunitname);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_profile_loc}/$profilename");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
