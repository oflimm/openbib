#####################################################################
#
#  OpenBib::Mojo::Controller::viewadmin::Users
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

package OpenBib::Mojo::Controller::Viewadmin::Users;

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

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

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
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

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

    if (!$user->user_exists_in_view({ viewname => $view, userid => $user->{ID}})){
        return $self->print_authorization_error();
    }

    if (!$user->is_viewadmin($view) && !$self->authorization_successful('right_read')){
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
    $args_ref->{viewname}     = $view;
    
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
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

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

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{users_loc}/id/$user->{ID}/edit");
    }
    else {
        $logger->debug("Weiter zum Record");
        return $self->show_record;
    }    
}

sub get_input_definition {
    my $self=shift;
    
    return {
	viewname => {
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
	surname => {
            default  => undef,
            encoding => 'none',
            type     => 'scalar',
        },
	commonname => {
            default  => undef,
            encoding => 'none',
            type     => 'scalar',
        },

    };
}

1;
