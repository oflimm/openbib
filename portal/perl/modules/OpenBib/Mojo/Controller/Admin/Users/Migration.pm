#####################################################################
#
#  OpenBib::Mojo::Controller::Admin::Users::Migration
#
#  Dieses File ist (C) 2013-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Admin::Users::Migration;

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
use OpenBib::Schema::System;
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

    # Dispatched Ards
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $userinfo_ref            = $user->get_info();
    
    my $username                = $userinfo_ref->{'username'};
    my $password                = $userinfo_ref->{'password'};
    
    # TT-Data erzeugen
    my $ttdata={
        username            => $username,
        password            => $password,
        userinfo            => $userinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_users_migration_tname},$ttdata);
}

sub migrate_ugc {
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
    my $input_data_ref        = $self->parse_valid_input();

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

    if (! $input_data_ref->{oldusername} && ! $input_data_ref->{newusername}){
        return $self->print_warning($msg->maketext("Bitte geben Sie eine alte und neue Kennung ein."));
    }

    my $olduserid = $user->get_userid_for_username($input_data_ref->{oldusername},$view);
    my $newuserid = $user->get_userid_for_username($input_data_ref->{newusername},$view);

    if (!$olduserid){
        return $self->print_warning($msg->maketext("Die Ursprungs-Kennung existiert nicht."));
    }

    if (!$newuserid){
        return $self->print_warning($msg->maketext("Die Ziel-Kennung existiert nicht."));
    }

    $input_data_ref->{olduserid} = $olduserid;
    $input_data_ref->{newuserid} = $newuserid;
    
    $user->migrate_ugc($input_data_ref);

    # TT-Data erzeugen
    my $ttdata={
    };
    
    return $self->print_page($config->{tt_admin_users_migration_success_tname},$ttdata);
}

sub get_input_definition {
    my $self=shift;
    
    return {
        oldusername => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        newusername => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        migrate_collections => {
            default  => 0,
            encoding => 'none',
            type     => 'scalar',
        },
        migrate_litlists => {
            default  => 0,
            encoding => 'none',
            type     => 'scalar',
        },
        migrate_tags => {
            default  => 0,
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
