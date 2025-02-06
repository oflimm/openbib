####################################################################
#
#  OpenBib::Mojo::Controller::Users::Searchlocations
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

package OpenBib::Mojo::Controller::Users::Searchlocations;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Users';

sub dispatch_to_user {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
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

    if (! $user->{ID}){
        return $self->tunnel_through_authenticator;            
    }
    else {
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{searchlocations_loc}/edit";
        
      return $self->redirect($new_location,303);
    }

    return;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $checkedloc_ref = {};
    
    foreach my $location ($user->get_searchlocations){
        $checkedloc_ref->{$location}=1;
    }
    
    my $targettype     = $user->get_targettype_of_session($session->{ID});

    my $searchlocations_ref  = $config->get_searchlocations_of_view($view);

    my @sorted_searchlocations = sort { $a->{description} cmp $b->{description} } @$searchlocations_ref;	
    
    # TT-Data erzeugen
    
    my $ttdata={
        targettype     => $targettype,
	checkedloc     => $checkedloc_ref,
	searchlocations=> \@sorted_searchlocations,
    };
    
    return $self->print_page($config->{tt_users_searchlocations_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $checkedloc_ref = {};
    
    foreach my $location ($user->get_searchlocations){
        $checkedloc_ref->{$location}=1;
    }
    
    my $targettype     = $user->get_targettype_of_session($session->{ID});

    my $searchlocations_ref  = $config->get_searchlocations_of_view($view);

    my @sorted_searchlocations = sort { $a->{description} cmp $b->{description} } @$searchlocations_ref;	
    
    # TT-Data erzeugen
    
    my $ttdata={
        targettype     => $targettype,
	checkedloc     => $checkedloc_ref,
	searchlocations=> \@sorted_searchlocations,
    };
    
    return $self->print_page($config->{tt_users_searchlocations_edit_tname},$ttdata);
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
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

    # CGI Args
    my @locations  = ($query->stash('location'))?$query->param('location'):();

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    $user->update_searchlocation(\@locations);

    return $self->return_baseurl;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    $user->delete_searchlocation;

    return $self->return_baseurl;
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    my $ttdata={
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_users_searchlocations_delete_confirm_tname},$ttdata);
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->stash('view')           || '';
    my $userid         = $self->stash('userid')         || '';
    my $path_prefix    = $self->stash('path_prefix');
    my $lang           = $self->stash('lang');
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{preferences_loc}.html?l=$lang";

    # TODO Get?
    $self->header_add('Content-Type' => 'text/html');
    return $self->redirect($new_location);
}

1;
