#####################################################################
#
#  OpenBib::Handler::PSGI::Admin::Profiles
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

package OpenBib::Handler::PSGI::Admin::Profiles;

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

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $profileinfo_ref = $config->get_profileinfo_overview();

    my $ttdata = {
        profiles   => $profileinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_profiles_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $profilename    = $self->strip_suffix($self->param('profileid'));

    # Shared Args
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

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

    return $self->print_page($config->{tt_admin_profiles_record_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                   || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful('right_create')){
        return $self->print_authorization_error();
    }

    if ($input_data_ref->{profilename} eq "" || $input_data_ref->{description} eq "") {
        return $self->print_warning($msg->maketext("Sie müssen mindestens einen Profilnamen und eine Beschreibung eingeben."));
    }

    # Profile darf noch nicht existieren
    if ($config->profile_exists($input_data_ref->{profilename})) {
        return $self->print_warning($msg->maketext("Ein Profil dieses Namens existiert bereits."));
    }

    # newprofilename ggf. loeschen
    delete $input_data_ref->{newprofilename} if (defined $input_data_ref->{newprofilename});
    
    my $new_profileid = $config->new_profile({
        profilename => $input_data_ref->{profilename},
        description => $input_data_ref->{description},
    });
    
    if (!$new_profileid){
        return $self->print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"));
    }

    if ($self->param('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{profiles_loc}/id/$input_data_ref->{profilename}/edit.html?l=$lang");
        return;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_profileid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zum Record $input_data_ref->{profilename}");
            $self->param('status',201); # created
            $self->param('profileid',$input_data_ref->{profilename});
            $self->param('location',"$location/$input_data_ref->{profilename}");
            $self->show_record;
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

    # Shared Args
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    if (!$config->profile_exists($profilename)) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }

    my $profileinfo_ref = $config->get_profileinfo->search_rs({ profilename => $profilename })->single();
    my $orgunits_ref    = $config->get_orgunitinfo_overview($profilename);
    
    my $ttdata = {
        profileinfo => $profileinfo_ref,
        orgunits    => $orgunits_ref,
    };
    
    return $self->print_page($config->{tt_admin_profiles_record_edit_tname},$ttdata);
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $profilename    = $self->param('profileid');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $path_prefix    = $self->param('path_prefix');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    $input_data_ref->{profilename} = $profilename;
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    if (!$config->profile_exists($profilename)) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }

    if ($input_data_ref->{newprofilename}){
	# Profile darf noch nicht existieren
	if ($config->profile_exists($input_data_ref->{newprofilename})) {
	    return $self->print_warning($msg->maketext("Ein Profil dieses Namens existiert bereits."));
	}

	$config->clone_profile($input_data_ref);	
    }
    else {
       delete $input_data_ref->{newprofilename};
       $config->update_profile({
	   profilename => $input_data_ref->{profilename},
	   description => $input_data_ref->{description},
			       });
    }
    
    if ($self->param('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{profiles_loc}");
    }
    else {
        $logger->debug("Weiter zum Record $profilename");
        return $self->show_record;
    }
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $profilename    = $self->strip_suffix($self->param('profileid'));
    my $config         = $self->param('config');

    my $profileinfo_ref = $config->get_profileinfo->search_rs({ profilename => $profilename })->single();
    
    my $ttdata={
        profileinfo => $profileinfo_ref,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_profiles_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $profilename    = $self->param('profileid');

    # Shared Args
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }

    if (!$config->profile_exists($profilename)) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"));
    }

    $config->del_profile($profilename);

    return unless ($self->param('representation') eq "html");

    # TODO GET?
    $self->redirect("$path_prefix/$config->{profiles_loc}");

    return;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        profilename => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        description => {
            default  => 'false',
            encoding => 'utf8',
            type     => 'scalar',
        },
        newprofilename => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	
    };
}

1;
