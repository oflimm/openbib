#####################################################################
#
#  OpenBib::Mojo::Controller::Admin::Users
#
#  Dieses File ist (C) 2004-2019 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Admin::Users;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Data::Pageset;
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
use OpenBib::SearchQuery;
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

    # Shared Args
    my $config         = $self->stash('config');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $viewinfo_ref = $config->get_viewinfo_overview();
    
    # TT-Data erzeugen
    my $ttdata={
	views      => $viewinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_users_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';
    my $userid         = $self->param('userid')                 || '';

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

    $self->stash('userid',$userid);
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    my $userinfo = new OpenBib::User({ID => $userid })->get_info;

    my $viewinfo_ref = $config->get_viewinfo_overview();

    my $ttdata={
        userinfo   => $userinfo,
	views      => $viewinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_users_record_edit_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->strip_suffix($self->param('userid'));

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

    $self->stash('userid',$userid);
    
    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $userinfo = new OpenBib::User({ID => $userid })->get_info;
        
    my $ttdata={
        userinfo   => $userinfo,
    };
    
    return $self->print_page($config->{tt_admin_users_record_tname},$ttdata);
}

sub create_record {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

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
    my $representation = $self->stash('representation');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CSRF-Checking
    if ($representation ne "json" && $self->validation->csrf_protect->has_error('csrf_token')){
	
	$logger->debug("CSRF-Check: ".$self->validation->csrf_protect->has_error);
    
	my $code   = -1;
	my $reason = $msg->maketext("Fehler mit CSRF-Token");
	return $self->print_warning($reason,$code);
    }
    
    if (!$self->authorization_successful('right_create')){
        return $self->print_authorization_error();
    }

    my $username         = $input_data_ref->{username};
    my $password         = $input_data_ref->{password};
    my $password_again   = $input_data_ref->{password_again};
    my $viewid           = $input_data_ref->{viewid};

    unless ($username && $viewid && $password && $password_again){
	my $code   = -1;
	my $reason = $msg->maketext("Es wurden nicht alle notwendigen Daten eingegeben");
	return $self->print_warning($reason,$code);
    }

    unless ($password eq $password_again){
	my $code   = -2;
	my $reason = $msg->maketext("Die beiden eingegebenen Passworte stimmen nicht überein.");
	return $self->print_warning($reason,$code);
    }
    
    my $authenticator_self_ref = $config->get_authenticator_self;
    
    
    # Wurde dieser Nutzername inzwischen bereits registriert?
    if ($user->user_exists_in_view({ username => $username, viewid => $viewid, authenticatorid => $authenticator_self_ref->{id} })) {
	my $code   = -3;
	my $reason = $msg->maketext("Ein Nutzer mit dieser Kennung existiert bereits im angegebenen Portal.");
	return $self->print_warning($reason,$code);
    }
    
    # OK, neuer Nutzer -> eintragen
    my $userid = $user->add({
	username         => $username,
	password         => $password,
	viewid           => $viewid,
	email            => $username,
	authenticatorid  => $authenticator_self_ref->{id},
	       });
    
    return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{users_loc}/id/$userid/edit");
}

sub update_record {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->strip_suffix($self->param('userid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $representation = $self->stash('representation');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CSRF-Checking
    if ($representation ne "json" && $self->validation->csrf_protect->has_error('csrf_token')){
	
	$logger->debug("CSRF-Check: ".$self->validation->csrf_protect->has_error);
    
	my $code   = -1;
	my $reason = $msg->maketext("Fehler mit CSRF-Token");
	return $self->print_warning($reason,$code);
    }
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    if ($logger->is_debug){
	$logger->debug("Input Args: ".YAML::Dump($input_data_ref));
    }
    
    # Unnecessary args
    delete $input_data_ref->{password_again};
    delete $input_data_ref->{roleid};
    delete $input_data_ref->{username};

    if (defined $input_data_ref->{mixed_bag}){
	my $contentstring = {};
	
	eval {
	    $contentstring= JSON::XS->new->utf8->canonical->encode($input_data_ref->{mixed_bag});
	};

	if ($@){
	    $logger->error("Canonical Encoding failed: ".YAML::Dump($input_data_ref->{mixed_bag}));
	}

	$input_data_ref->{mixed_bag} = $contentstring; 
    }

    # Leere Felder entfernen

    foreach my $key (keys %$input_data_ref){
	next if ($key eq "login_failure" || $key eq "viewid"); # kann valide 0 sein
	delete $input_data_ref->{$key} unless (defined $input_data_ref->{$key} && $input_data_ref->{$key});	
    }
    
    my $user = new OpenBib::User({ ID => $userid });
    $user->update_userinfo($input_data_ref) if (keys %$input_data_ref);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{users_loc}/id/$userid/edit");
    }
    else {
        $logger->debug("Weiter zum Record");
        return $self->show_record;
    }    
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $userid         = $self->strip_suffix($self->stash('userid'));
    my $config         = $self->stash('config');

    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }

    my $ttdata={
        userid => $userid,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_users_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->strip_suffix($self->param('userid'));

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');
    my $path_prefix    = $self->stash('path_prefix');
    my $lang           = $self->stash('lang');
    my $msg            = $self->stash('msg');
    my $representation = $self->stash('representation');

    # CSRF-Checking
    if ($representation ne "json" && $self->validation->csrf_protect->has_error('csrf_token')){
	
	$logger->debug("CSRF-Check: ".$self->validation->csrf_protect->has_error);
    
	my $code   = -1;
	my $reason = $msg->maketext("Fehler mit CSRF-Token");
	return $self->print_warning($reason,$code);
    }
    
    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }

    if ($self->param('confirm')){
	return $self->confirm_delete_record;
    }
    
    $user->wipe_account($userid);

    return $self->render( json => { success => 1, id => $userid }) unless ($self->stash('representation') eq "html");

    $self->res->headers->content_type('text/html');    
    $self->redirect("$path_prefix/$config->{admin_loc}/$config->{users_loc}.html?l=$lang");

    return;
}

sub show_search_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $config         = $self->stash('config');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }
    
    # TT-Data erzeugen
    my $ttdata={
    };
    
    return $self->print_page($config->{tt_admin_users_search_form_tname},$ttdata);
}

sub show_search {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');
    my $user           = $self->stash('user');
    my $queryoptions   = $self->stash('qopts');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$input_data_ref->{roleid} && !$input_data_ref->{username} && !$input_data_ref->{surname} && !$input_data_ref->{commonname}){
        return $self->print_warning($msg->maketext("Bitte geben Sie einen Suchbegriff ein."));
    }

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $searchquery = new OpenBib::SearchQuery;
    
    # CGI Args
    $searchquery->set_searchfield('roleid', $input_data_ref->{'roleid'}) if ($input_data_ref->{'roleid'});
    $searchquery->set_searchfield('username', $input_data_ref->{'username'}) if ($input_data_ref->{'username'});
    $searchquery->set_searchfield('surname', $input_data_ref->{'surname'}) if ($input_data_ref->{'surname'});
    $searchquery->set_searchfield('commonname', $input_data_ref->{'commonname'}) if ($input_data_ref->{'commonname'});

    my $args_ref = {};
    
    $args_ref->{searchquery}  = $searchquery;
    $args_ref->{queryoptions} = $queryoptions;
    
    # Pagination parameters
    my $page              = ($queryoptions->get_option('page'))?$queryoptions->get_option('page'):1;
    my $num               = ($queryoptions->get_option('num'))?$queryoptions->get_option('num'):20;
    
    my $result_ref = $user->search($args_ref);

    my $nav = Data::Pageset->new({
	'total_entries'    => $result_ref->{hits},
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
				 });
    
    # TT-Data erzeugen
    my $ttdata={
	hits         => $result_ref->{hits},
        userlist     => $result_ref->{users},
	nav          => $nav,
	searchquery  => $searchquery,
	queryoptions => $queryoptions,
    };
    
    return $self->print_page($config->{tt_admin_users_search_tname},$ttdata);
}

sub get_input_definition {
    my $self=shift;
    
    return {
        bag => {
            default  => '',
            encoding => 'utf8',
            type     => 'mixed_bag', # always arrays
        },
	nachname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	vorname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	email => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	viewid => {
            default  => undef,
            encoding => 'none',
            type     => 'scalar',
        },
	roleid => {
            default  => undef,
            encoding => 'none',
            type     => 'scalar',
        },
	username => {
            default  => undef,
            encoding => 'none',
            type     => 'scalar',
        },
	password => {
            default  => undef,
            encoding => 'none',
            type     => 'scalar',
        },
	password_again => {
            default  => undef,
            encoding => 'none',
            type     => 'scalar',
        },
	login_failure => {
            default  => 0,
            encoding => 'none',
            type     => 'scalar',
        },

    };
}

1;
