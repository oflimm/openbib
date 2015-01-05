#####################################################################
#
#  OpenBib::Handler::PSGI::Admin::OrganizationalUnits
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

package OpenBib::Handler::PSGI::Admin::OrganizationalUnits;

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
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI::Admin';

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
        'confirm_delete_record'     => 'confirm_delete_record',
        'delete_record'             => 'delete_record',
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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if (!$config->profile_exists($profilename)) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }
    
    my $orgunits_ref = $config->get_orgunitinfo_overview($profilename);

    my $ttdata={
        profilename => $profilename,
        orgunits    => $orgunits_ref,
    };
    
    return $self->print_page($config->{tt_admin_orgunits_tname},$ttdata);
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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
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

    return $self->print_page($config->{tt_admin_orgunits_record_tname},$ttdata);
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
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # Profilenamen aus Pfad hinzufuegen
    $input_data_ref->{profilename} = $profilename;

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if (!$config->profile_exists($profilename)) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }

    if ($input_data_ref->{orgunitname} eq "" || $input_data_ref->{description} eq "") {
        return $self->print_warning($msg->maketext("Sie müssen mindestens den Namen einer Organisationseinheit und deren Beschreibung eingeben."));
    }

    if ($config->orgunit_exists($profilename,$input_data_ref->{orgunitname})){
        return $self->print_warning($msg->maketext("In diesem Profil existiert bereits eine Organisationseinheit diesen Namens"));
    }
    
    my $new_orgunitid = $config->new_orgunit($input_data_ref);
    
    if (!$new_orgunitid){
        return $self->print_warning($msg->maketext("Es existiert bereits eine Organisationseinheit unter diesem Namen"));
    }

    if ($self->param('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{profiles_loc}/id/$profilename/$config->{orgunits_loc}/id/$input_data_ref->{orgunitname}/edit.html?l=$lang");
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_orgunitid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zum Record $input_data_ref->{orgunitname}");
            $self->param('status',201); # created
            $self->param('orgunitid',$input_data_ref->{orgunitname});
            $self->param('location',"$location/$input_data_ref->{orgunitname}");
            return $self->show_record;
        }
    }

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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if (!$config->profile_exists($profilename)) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }
    
    if (!$config->orgunit_exists($profilename,$orgunitname)) {
        return $self->print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"));
    }

    my $profileinfo_ref = $config->get_profileinfo->search_rs({ 'profilename' => $profilename })->single();
    my $orgunitinfo_ref = $config->get_orgunitinfo->search_rs({ 'profileid.profilename' => $profilename, orgunitname => $orgunitname},{ join => 'profileid'})->single();
    my $activedbs_ref   = $config->get_databaseinfo->search_rs({'active' => 1},{ order_by => 'dbname'});

    my $orgunitdb_map_ref = {};
    
    foreach my $dbname ($config->get_orgunitdbs($profilename,$orgunitname)){
        $logger->debug("Adding $dbname");
        $orgunitdb_map_ref->{$dbname} = 1;
    }
    
    my $ttdata={
        profileinfo    => $profileinfo_ref,
        orgunitinfo    => $orgunitinfo_ref,
        orgunitdb_map  => $orgunitdb_map_ref,
        activedbs      => $activedbs_ref,
    };
    
    return $self->print_page($config->{tt_admin_orgunits_record_edit_tname},$ttdata);
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
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # Profilenamen und Orgunit aus Pfad hinzufuegen
    $input_data_ref->{profilename} = $profilename;
    $input_data_ref->{orgunitname} = $orgunitname;
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if (!$config->profile_exists($profilename)) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {
        return $self->print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"));
    }

    $config->update_orgunit($input_data_ref);

    if ($self->param('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{profiles_loc}/id/$profilename/edit?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record $orgunitname");
        $self->show_record;
    }

    return;
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $profilename    = $self->param('profileid');
    my $orgunitname    = $self->strip_suffix($self->param('orgunitid'));
    my $config         = $self->param('config');

    my $orgunitinfo_ref = $config->get_orgunitinfo->search_rs({ 'profileid.profilename' => $profilename, 'me.orgunitname' => $orgunitname},{ join => ['profileid']})->single();
    
    my $ttdata={
        profilename => $profilename,
        orgunitinfo => $orgunitinfo_ref,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_orgunits_record_delete_confirm_tname},$ttdata);
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
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if (!$config->profile_exists($profilename)) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {
        return $self->print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"));
    }

    $config->del_orgunit($profilename,$orgunitname);

    return unless ($self->param('representation') eq "html");

    # TODO GET?
    return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{profiles_loc}/id/$profilename/edit.html?l=$lang");
}

sub get_input_definition {
    my $self=shift;
    
    return {
        orgunitname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        description => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        profilename => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        nr => {
            default  => 1,
            encoding => 'none',
            type     => 'scalar',
        },
        databases => {
            default  => [],
            encoding => 'none',
            type     => 'array',
        },
        
    };
}

1;
