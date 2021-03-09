#####################################################################
#
#  OpenBib::Handler::PSGI::viewadmin::Users
#
#  Dieses File ist (C) 2020 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Viewadmin::Users;

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

use base 'OpenBib::Handler::PSGI::Admin';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'           => 'show_collection',
        'show_record'               => 'show_record',
        'show_record_form'          => 'show_record_form',
        'show_search'               => 'show_search',
        'show_search_form'          => 'show_search_form',
        'update_record'             => 'update_record',
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
    my $view           = $self->param('view');

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');

    if (!$user->user_exists_in_view({ viewname => $view, userid => $user->{ID}})){
        return $self->print_authorization_error();
    }
    
    if (!$user->is_viewadmin($view) && !$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    # TT-Data erzeugen
    my $ttdata={
    };
    
    return $self->print_page($config->{tt_viewadmin_users_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';
    my $userid         = $self->param('userid')                 || '';

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

    $self->param('userid',$userid);

    if (!$user->user_exists_in_view({ viewname => $view, userid => $user->{ID}})){
        return $self->print_authorization_error();
    }
    
    if (!$user->is_viewadmin($view) && !$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    my $userinfo = new OpenBib::User({ID => $userid })->get_info;
        
    my $ttdata={
        userinfo   => $userinfo,
    };
    
    return $self->print_page($config->{tt_viewadmin_users_record_edit_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->strip_suffix($self->param('userid'));

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

    $self->param('userid',$userid);
    
    # Der anschauende Nutzer muss selbst zum View gehoeren
    if (!$user->user_exists_in_view({ viewname => $view, userid => $user->{ID}})){
        return $self->print_authorization_error();
    }

    # Nur Nutzer des Views duerfen angezeigt werden
    if (!$user->user_exists_in_view({ viewname => $view, userid => $userid})){
        return $self->print_authorization_error();
    }
    
    if (!$user->is_viewadmin($view) && !$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $userinfo = new OpenBib::User({ID => $userid })->get_info;

    if ($userinfo->{viewname} ne $view){
	return $self->print_authorization_error();
    }
    
    my $ttdata={
        userinfo   => $userinfo,
    };
    
    return $self->print_page($config->{tt_viewadmin_users_record_tname},$ttdata);
}

sub show_search_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');

    if (!$user->user_exists_in_view({ viewname => $view, userid => $user->{ID}})){
        return $self->print_authorization_error();
    }
    
    if (!$user->is_viewadmin($view) && !$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }
    
    # TT-Data erzeugen
    my $ttdata={
    };
    
    return $self->print_page($config->{tt_viewadmin_users_search_form_tname},$ttdata);
}

sub show_search {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    # Dispatched Args
    my $view           = $self->param('view')                   || '';


    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $user           = $self->param('user');

    # CGI Args
    my $args_ref = {};
    $args_ref->{roleid}     = $query->param('roleid') if ($query->param('roleid'));
    $args_ref->{username}   = $query->param('username') if ($query->param('username'));
    $args_ref->{surname}    = $query->param('surname') if ($query->param('surname'));
    $args_ref->{commonname} = $query->param('commonname') if ($query->param('commonname'));
    $args_ref->{viewname}   = $view;
    
    if (!$user->user_exists_in_view({ viewname => $view, userid => $user->{ID}})){
        return $self->print_authorization_error();
    }

    if (!$user->is_viewadmin($view) && !$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    if (!$args_ref->{roleid} && !$args_ref->{username} && !$args_ref->{surname} && !$args_ref->{commonname}){
        return $self->print_warning($msg->maketext("Bitte geben Sie einen Suchbegriff ein."));
    }

    my $userlist_ref = $user->search($args_ref);

    # TT-Data erzeugen
    my $ttdata={
        userlist   => $userlist_ref,
    };
    
    return $self->print_page($config->{tt_viewadmin_users_search_tname},$ttdata);
}

sub update_record {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->strip_suffix($self->param('userid'));

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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # Der aendernde Nutzer muss selbst zum View gehoeren
    if (!$user->user_exists_in_view({ viewname => $view, userid => $user->{ID}})){
        return $self->print_authorization_error();
    }

    # Nur Nutzer des Views duerfen geaendert werden
    if (!$user->user_exists_in_view({ viewname => $view, userid => $userid})){
        return $self->print_authorization_error();
    }
    
    if (!$user->is_viewadmin($view) && !$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

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
   
    $user->update_userinfo($input_data_ref) if (keys %$input_data_ref);

    if ($self->param('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{users_loc}/id/$user->{ID}/edit");
    }
    else {
        $logger->debug("Weiter zum Record");
        return $self->show_record;
    }    
}

1;
