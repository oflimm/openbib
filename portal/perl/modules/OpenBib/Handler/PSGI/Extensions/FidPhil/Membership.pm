#####################################################################
#
#  OpenBib::Handler::PSGI::Extensions::FidPhil::Membership
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

package OpenBib::Handler::PSGI::Extensions::FidPhil::Membership;

use strict;
use warnings;
no warnings 'redefine';
use utf8;
use Log::Log4perl qw(get_logger :levels);
use OpenBib::User;
use Data::Dumper;
use Cwd;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_record_form');
    $self->run_modes(
        'show_record_form'           => 'show_record_form',
        'request_membership'         => 'request_membership',
        'dispatch_to_representation' => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
    #    $self->tmpl_path('./');
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Ards
    my $view = $self->param('view');

    # Shared Args
    my $query        = $self->query();
    my $r            = $self->param('r');
    my $config       = $self->param('config');
    my $session      = $self->param('session');
    my $user         = $self->param('user');
    my $msg          = $self->param('msg');
    my $queryoptions = $self->param('qopts');
    my $stylesheet   = $self->param('stylesheet');
    my $useragent    = $self->param('useragent');
    my $path_prefix  = $self->param('path_prefix');

    if ( !$self->authorization_successful ) {
        return $self->print_authorization_error();
    }
    my $userid     = $user->{ID};
    my $userObject = new OpenBib::User( { ID => $userid } );
    my $userinfo   = $userObject->get_info;
    my $role       = 'registered';

    if ( $userObject->has_role( 'fidphil_society_pending', $userid ) ) {
        $role = 'fidphil_society_pending';
    }
    elsif ( $userObject->has_role( 'fidphil_society', $userid ) ) {
        $role = 'fidphil_society';
    }

    return $self->redirect(
            "$path_prefix/$config->{users_loc}/id/$userid/edit");
}

#how to handle
#users which already have the membership

sub request_membership {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Ards
    my $view = $self->param('view');

    # Shared Args
    my $query        = $self->query();
    my $r            = $self->param('r');
    my $config       = $self->param('config');
    my $session      = $self->param('session');
    my $user         = $self->param('user');
    my $msg          = $self->param('msg');
    my $queryoptions = $self->param('qopts');
    my $stylesheet   = $self->param('stylesheet');
    my $useragent    = $self->param('useragent');
    my $path_prefix  = $self->param('path_prefix');

    if ( !$self->authorization_successful ) {
        return $self->print_authorization_error();
    }
    my $userid          = $user->{ID};
    my $userinfo        = new OpenBib::User( { ID => $userid } )->get_info;
    my $all_roles       = $user->get_all_roles();
    my $user_roles      = $user->get_roles_of_user($userid);
    my $input_data_ref  = $self->parse_valid_input();
    my $society         = $input_data_ref->{'society'};
    my $mitgliedsnummer = $input_data_ref->{'mitgliedsnummer'};
    if (   !$user_roles->{'admin'}
        && !$user_roles->{'fidphil_society'} )
    {
        my $updateInfo = {};
        $userinfo->{mixed_bag}->{bag_society} = [$society];
        $userinfo->{mixed_bag}->{bag_mitgliedsnummer} = [$mitgliedsnummer];
        $updateInfo->{mixed_bag} =
          JSON::XS->new->utf8->canonical->encode( $userinfo->{mixed_bag} );
        $user->update_userinfo($updateInfo) if ( keys %$updateInfo );

    }
    return $self->redirect(
            "$path_prefix/$config->{users_loc}/id/$userid/edit");

}


sub renew_membership {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Ards
    my $view = $self->param('view');

    # Shared Args
    my $query        = $self->query();
    my $r            = $self->param('r');
    my $config       = $self->param('config');
    my $session      = $self->param('session');
    my $user         = $self->param('user');
    my $msg          = $self->param('msg');
    my $queryoptions = $self->param('qopts');
    my $stylesheet   = $self->param('stylesheet');
    my $useragent    = $self->param('useragent');
    my $path_prefix  = $self->param('path_prefix');
    if ( !$self->authorization_successful ) {
        return $self->print_authorization_error();
    }
    my $userid = $user->{ID};
    my $userinfo = new OpenBib::User( { ID => $userid } )->get_info;

    #we need a way to retrieve the ID of the role
    my @roles            = (6);
    my $thisuserinfo_ref = {
        id    => $userid,
        roles => \@roles,
    };

    # CGI / JSON input
    $user->update_user_rights_role($thisuserinfo_ref);

    return "Request Membership";

    #get Society as param
    #return $self->print_page("users_membership", $ttdata);
}

sub authorization_successful {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $user               = $self->param('user');
    my $basic_auth_failure = $self->param('basic_auth_failure') || 0;
    my $userid             = $user->{ID} || '';

    $logger->debug(
        "Basic http auth failure: $basic_auth_failure / Userid: $userid ");

    # Bei Fehler grundsaetzlich Abbruch
    if ( $basic_auth_failure || !$userid ) {
        return 0;
    }

    # Der zugehoerige Nutzer darf auch zugreifen (admin darf immer)
    if ( $self->is_authenticated( 'user', $userid ) ) {
        return 1;
    }

    # Default: Kein Zugriff
    return 0;

}

sub get_input_definition {
    my $self = shift;

    return {
        society => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        mitgliedsnummer => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        }, bag => {
            default  => '',
            encoding => 'utf8',
            type     => 'mixed_bag', # always arrays
        },
    };
}

1;
