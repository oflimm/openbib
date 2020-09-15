####################################################################
#
#  OpenBib::Handler::PSGI::Extensions::FidPhil::Users
#
#  Dieses File ist (C) 2004-2020 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Extensions::FidPhil::Users;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Email::Valid;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Extensions::FidPhil::User;
use Data::Dumper;

# Doi we really need to inherit from Admin Users - Base PSGI should be enough???
use base 'OpenBib::Handler::PSGI::Users';

# Run at startup
sub setup {
    my $self = shift;
    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'            => 'show_collection',
        'update_record'              => 'update_record',
        'dispatch_to_representation' => 'dispatch_to_representation',
    );
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger  = get_logger();
    my $view    = $self->param('view');
    my $user    = $self->param('user');
    my $session = $self->param('session');

    # Shared Args
    my $config = $self->param('config');
    if ( !$self->authorization_successful('right_read') ) {
        return $self->print_authorization_error();
    }
    $user = OpenBib::Extensions::FidPhil::User->new(
        { sessionID => $session->{ID}, config => $config } );
    my $args_ref = {};

    #benoetigt wird eine ID
    $args_ref->{view} = 2;
    my $userlist_ref = $user->showUsersForView($args_ref);

    # TT-Data erzeugen
    my $ttdata = { userlist => $userlist_ref, };

    # return $self->print_page("$config->{tt_manager_users_tname}",$ttdata);
    return $self->print_page( "manager_users", $ttdata );
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view   = $self->param('view');
    my $userid = $self->strip_suffix( $self->param('userid') );

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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if ( !$self->is_authenticated( 'user', $userid ) ) {
        return;
    }

    if ( defined $input_data_ref->{mixed_bag} ) {
        my $contentstring = {};

        eval {
            $contentstring = JSON::XS->new->utf8->canonical->encode(
                $input_data_ref->{mixed_bag} );
        };

        if ($@) {
            $logger->error( "Canonical Encoding failed: "
                  . YAML::Dump( $input_data_ref->{mixed_bag} ) );
        }

        $input_data_ref->{mixed_bag} = $contentstring;
    }

    my $all_roles  = $user->get_all_roles();
    my $user_roles = $user->get_roles_of_user($userid);

    #only update user is without a role
    #maybe use has_role?
    if (   !$user_roles->{'fidphil_user'}
        && !$user_roles->{'admin'}
        && !$user_roles->{'fidphil_society'} )
    {
        my $roleid = 0;
        foreach my $role ( @{$all_roles} ) {
            if ( $role->{rolename} eq 'fidphil_user' ) {
                $roleid = $role->{id};
            }
        }
        my @roles            = ($roleid);
        my $thisuserinfo_ref = {
            id    => $userid,
            roles => \@roles,
        };
        $user->update_user_rights_role($thisuserinfo_ref);
    }
    $user->update_userinfo($input_data_ref) if ( keys %$input_data_ref );
    if ( $self->param('representation') eq "html" ) {

        # TODO GET?
        return $self->redirect(
            "$path_prefix/$config->{users_loc}/id/$user->{ID}/edit");
    }
    else {
        $logger->debug("Weiter zum Record");
        return $self->show_record;
    }
}

sub get_input_definition {
    my $self=shift;
    
    return {
        vorname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        nachname => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },       
        bag => {
            default  => '',
            encoding => 'utf8',
            type     => 'mixed_bag', # always arrays
        },
    };
}

#    return $self->print_page($config->{tt_admin_users_search_tname},$ttdata);

1;
