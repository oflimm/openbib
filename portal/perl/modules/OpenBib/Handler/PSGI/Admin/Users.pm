#####################################################################
#
#  OpenBib::Handler::PSGI::Admin::Users
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

package OpenBib::Handler::PSGI::Admin::Users;

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
        'delete_record'             => 'delete_record',
        'confirm_delete_record'     => 'confirm_delete_record',
        'dispatch_to_representation' => 'dispatch_to_representation',
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

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    # TT-Data erzeugen
    my $ttdata={
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
    
    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $userinfo = new OpenBib::User({ID => $userid })->get_info;
        
    my $ttdata={
        userinfo   => $userinfo,
    };
    
    return $self->print_page($config->{tt_admin_users_record_tname},$ttdata);
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
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful('right_update')){
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

    my $user = new OpenBib::User({ ID => $userid });
    $user->update_userinfo($input_data_ref) if (keys %$input_data_ref);

    if ($self->param('representation') eq "html"){
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
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $userid         = $self->strip_suffix($self->param('userid'));
    my $config         = $self->param('config');

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
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }

    $user->wipe_account($userid);

    if ($self->param('representation') eq "html"){
        return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{users_loc}");
    }

    return;
}

sub show_search_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $config         = $self->param('config');

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
    
    my $r              = $self->param('r');

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $user           = $self->param('user');
    my $queryoptions   = $self->param('qopts');

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
	strasse => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	ort => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	plz => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	gebdatum => {
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
