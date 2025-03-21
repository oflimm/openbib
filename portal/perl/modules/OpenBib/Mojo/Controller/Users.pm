####################################################################
#
#  OpenBib::Mojo::Controller::Users
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

package OpenBib::Mojo::Controller::Users;

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
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Ards
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
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $searchfields_ref        = $user->get_searchfields();
    my $userinfo_ref            = $user->get_info();
    my $spelling_suggestion_ref = $user->get_spelling_suggestion();
    my $livesearch_ref          = $user->get_livesearch();
    
    # Wenn wir eine gueltige Mailadresse als Usernamen haben,
    # dann liegt Selbstregistrierung vor und das Passwort kann
    # geaendert werden

    my $userinfo = new OpenBib::User({ID => $userid })->get_info;
    
    my $email_valid=Email::Valid->address($userinfo->{username});
    
    my $authenticator=$session->get_authenticator;

    # TT-Data erzeugen
    my $ttdata={
	userid              => $userid,
	userinfo            => $userinfo,
        qopts               => $queryoptions->get_options,
        email_valid         => $email_valid,
        authenticator       => $authenticator,
        searchfields        => $searchfields_ref,
        spelling_suggestion => $spelling_suggestion_ref,
        livesearch          => $livesearch_ref,
    };
    
    return $self->print_page($config->{tt_users_record_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Ards
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
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $userinfo_ref            = $user->get_info();
    
    # Wenn wir eine gueltige Mailadresse als Usernamen haben,
    # dann liegt Selbstregistrierung vor und das Passwort kann
    # geaendert werden

    my $userinfo = new OpenBib::User({ID => $userid })->get_info;
    
    my $email_valid=Email::Valid->address($userinfo->{username});
    
    my $authenticator=$session->get_authenticator;

    # TT-Data erzeugen
    my $ttdata={
	userid              => $userid,
	userinfo            => $userinfo,
        qopts               => $queryoptions->get_options,
        email_valid         => $email_valid,
        authenticator       => $authenticator,
    };
    
    return $self->print_page($config->{tt_users_record_edit_tname},$ttdata);
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
    
    if (!$self->is_authenticated('user',$userid)){
        return;
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

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $userid      = $self->strip_suffix($self->stash('userid'));
    my $config         = $self->stash('config');

    my $ttdata={
        userid => $userid,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_users_record_delete_confirm_tname},$ttdata);
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

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    if ($self->param('confirm')){
	return $self->confirm_delete_record;
    }
    
    $user->wipe_account();

    if ($self->stash('representation') eq "html"){
        $self->redirect("$path_prefix/$config->{home_loc}");
    }

    return;
}

# Authentifizierung wird spezialisiert

sub authorization_successful {
    my $self   = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $user               = $self->stash('user');    
    my $basic_auth_failure = $self->stash('basic_auth_failure') || 0;
    my $userid             = $self->stash('userid')             || '';

    $logger->debug("Basic http auth failure: $basic_auth_failure / Userid: $userid ");

    # Bei Fehler grundsaetzlich Abbruch
    if ($basic_auth_failure || !$userid){
        return 0;
    }
    
    # Der zugehoerige Nutzer darf auch zugreifen (admin darf immer)
    if ($self->is_authenticated('user',$userid)){
	return 1;
    }

    # Default: Kein Zugriff
    return 0;
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

    };
}


1;
__END__

=head1 NAME

OpenBib::UserPrefs - Verwaltung von Benutzer-Profil-Einstellungen

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs stellt dem Benutzer des 
Suchportals Einstellmoeglichkeiten seines persoenlichen Profils
zur Verfuegung.

=head2 Loeschung seiner Kennung

Loeschung seiner Kennung, so es sich um eine Kennung handelt, die 
im Rahmen der Selbstregistrierung angelegt wurde. Sollte der
Benutzer sich mit einer Kennung aus einer Sisis-Datenbank 
authentifiziert haben, so wird ihm die Loeschmoeglichkeit nicht 
angeboten
 

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
