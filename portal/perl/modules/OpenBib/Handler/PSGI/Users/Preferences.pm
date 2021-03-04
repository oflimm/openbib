####################################################################
#
#  OpenBib::Handler::PSGI::Users::Preferences
#
#  Dieses File ist (C) 2004-2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Users::Preferences;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Email::Valid;
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI::Users';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'                      => 'show_collection',
        'update_password'                      => 'update_password',
        'update_searchfields'                  => 'update_searchfields',
        'update_searchform'                    => 'update_searchform',
        'update_bibsonomy'                     => 'update_bibsonomy',
        'update_bibsonomysync'                 => 'update_bibsonomysync',
        'update_spelling'                      => 'update_spelling',
        'update_livesearch'                    => 'update_livesearch',
        'update_autocompletion'                => 'update_autocompletion',
        'delete_account'                       => 'delete_account',
        'dispatch_to_representation'           => 'dispatch_to_representation',
        'dispatch_to_user'                     => 'dispatch_to_user',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub dispatch_to_user {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view           = $self->param('view');

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

    if (! $user->{ID}){
        return $self->tunnel_through_authenticator;            
    }
    else {
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{preferences_loc}";
        
        return $self->redirect($new_location,303);
    }

    return;
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Ards
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $searchfields_ref        = $user->get_searchfields();
    my $userinfo_ref            = $user->get_info();
    my $spelling_suggestion_ref = $user->get_spelling_suggestion();
    my $livesearch_ref          = $user->get_livesearch();
    
    my $username                = $userinfo_ref->{'username'};
    my $password                = $userinfo_ref->{'password'};
    
    # Wenn wir eine gueltige Mailadresse als Usernamen haben,
    # dann liegt Selbstregistrierung vor und das Passwort kann
    # geaendert werden
    my $email_valid=Email::Valid->address($username);
    
    my $authenticator=$session->get_authenticator;
    
    # TT-Data erzeugen
    my $ttdata={
        qopts               => $queryoptions->get_options,
        username            => $username,
        password            => $password,
        email_valid         => $email_valid,
        authenticator       => $authenticator,
        searchfields        => $searchfields_ref,
        spelling_suggestion => $spelling_suggestion_ref,
        livesearch          => $livesearch_ref,
        userinfo            => $userinfo_ref,
    };
    
    return $self->print_page($config->{tt_users_preferences_tname},$ttdata);
}


sub update_searchfields {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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

    my $searchfields_ref = {};

    my $input_data_ref = $self->parse_valid_input('get_input_definition_searchfields');
    
    # CGI Args
    foreach my $searchfield (keys %{$config->{default_searchfields}}){
        $searchfields_ref->{$searchfield} = ($input_data_ref->{$searchfield})?$input_data_ref->{$searchfield}:'0';
    }
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    $user->set_searchfields($searchfields_ref);

    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
        return;
    }
    else {
	return $self->print_json({ success => 1 });
    }
    
    return;
}

sub update_bibsonomy {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';

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

    my $input_data_ref = $self->parse_valid_input('get_input_definition_bibsonomy');
    
    my $bibsonomy_sync = ($input_data_ref->{'bibsonomy_sync'})?$input_data_ref->{'bibsonomy_sync'}:'off';
    my $bibsonomy_user = ($input_data_ref->{'bibsonomy_user'})?$input_data_ref->{'bibsonomy_user'}:0;
    my $bibsonomy_key  = ($input_data_ref->{'bibsonomy_key'})?$input_data_ref->{'bibsonomy_key'}:0;

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    $user->set_bibsonomy({
        sync      => $bibsonomy_sync,
        user      => $bibsonomy_user,
        key       => $bibsonomy_key,
    });

    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
        return;
    }
    else {
	return $self->print_json({ success => 1 });
    }

    return;
}

sub update_bibsonomysync {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    $user->sync_all_to_bibsonomy;

    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
        return;
    }
    else {
	return $self->print_json({ success => 1 });
    }

    return;
}

sub update_searchform {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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
    my $input_data_ref = $self->parse_valid_input('get_input_definition_searchform');

    my $searchform     = ($input_data_ref->{searchform})?$input_data_ref->{searchform}:'';


    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if ($searchform eq "") {
        my $code   = -1;
	my $reason = $msg->maketext("Es wurde keine Standard-Recherchemaske ausgewählt");
	
	return $self->print_warning($msg->maketext($reason),$code);
    }

    $user->set_mask($searchform);
    $session->set_mask($searchform);

    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
        return;
    }
    else {
	return $self->print_json({ success => 1 });
    }

    return;
}

sub update_password {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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
    my $input_data_ref = $self->parse_valid_input('get_input_definition_password');

    my $password1         = $input_data_ref->{password1};
    my $password2         = $input_data_ref->{password2};

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if ($password1 eq "" || $password1 ne $password2) {
        my $code   = -1;
	my $reason = $msg->maketext("Sie haben entweder kein Passwort eingegeben oder die beiden Passworte stimmen nicht überein");
	
	return $self->print_warning($msg->maketext($reason),$code);
    }

    $user->set_credentials({
        password => $password1,
    });

    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
        return;
    }
    else {
	return $self->print_json({ success => 1 });
    }

    return;
}

sub update_spelling {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';

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
    my $input_data_ref = $self->parse_valid_input('get_input_definition_spelling');
    my $spelling_as_you_type   = ($input_data_ref->{'spelling_as_you_type'})?$input_data_ref->{'spelling_as_you_type'}:'0';
    my $spelling_resultlist    = ($input_data_ref->{'spelling_resultlist'})?$input_data_ref->{'spelling_resultlist'}:'0';

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    $user->set_spelling_suggestion({
        as_you_type        => $spelling_as_you_type,
        resultlist         => $spelling_resultlist,
    });

    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
        return;
    }
    else {
	return $self->print_json({ success => 1 });
    }

    return;
}

sub update_livesearch {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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

    my $input_data_ref = $self->parse_valid_input('get_input_definition_livesearch');
    my $livesearch_freesearch       = ($input_data_ref->{'livesearch_freesearch'})?$input_data_ref->{'livesearch_freesearch'}:'0';
    my $livesearch_freesearch_exact = ($input_data_ref->{'livesearch_freesearch_exact'})?$input_data_ref->{'livesearch_freesearch_exact'}:'0';
    my $livesearch_person           = ($input_data_ref->{'livesearch_person'})?$input_data_ref->{'livesearch_person'}:'0';
    my $livesearch_person_exact     = ($input_data_ref->{'livesearch_person_exact'})?$input_data_ref->{'livesearch_person_exact'}:'0';
    my $livesearch_subject          = ($input_data_ref->{'livesearch_subject'})?$input_data_ref->{'livesearch_subject'}:'0';
    my $livesearch_subject_exact    = ($input_data_ref->{'livesearch_subject_exact'})?$input_data_ref->{'livesearch_subject_exact'}:'0';
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    $user->set_livesearch({
        freesearch       => $livesearch_freesearch,
        freesearch_exact => $livesearch_freesearch_exact,
        person           => $livesearch_person,
        person_exact     => $livesearch_person_exact,
        subject          => $livesearch_subject,
        subject_exact    => $livesearch_subject_exact,
    });

    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
        return;
    }
    else {
	return $self->print_json({ success => 1 });
    }

    return;
}

sub update_autocompletion {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

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

    my $input_data_ref = $self->parse_valid_input('get_input_definition_autocompletion');
    my $autocompletion = ($input_data_ref->{'autocompletion'})?$input_data_ref->{'autocompletion'}:'livesearch';
    

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    $user->set_autocompletion($autocompletion);

    if ($self->param('representation') eq "html"){
        $self->return_baseurl;
        return;
    }
    else {
	return $self->print_json({ success => 1 });
    }

    return;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';

    # Shared Args
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/preferences.html";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

    return;
}

sub get_input_definition_password {
    my $self=shift;
    
    return {
	password1 => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	password2 => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

sub get_input_definition_spelling {
    my $self=shift;
    
    return {
	'spelling_as_you_type' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	'spelling_resultlist' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

sub get_input_definition_autocompletion {
    my $self=shift;
    
    return {
	'autocompletion' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
    };
}

sub get_input_definition_searchform {
    my $self=shift;
    
    return {
	'searchform' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
    };
}

sub get_input_definition_bibsonomy {
    my $self=shift;
    
    return {
	'bibsonomy_sync' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	'bibsonomy_user' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	'bibsonomy_key' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
    };
}

sub get_input_definition_searchfields {
    my $self=shift;

    my $config         = $self->param('config');

    my $return_ref = { };

    foreach my $searchfield (keys %{$config->{default_searchfields}}){
	$return_ref->{$searchfield} = {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	};
    }
    
    return $return_ref;
}


sub get_input_definition_livesearch {
    my $self=shift;
    
    return {
	'livesearch_freesearch' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	'livesearch_freesearch_exact' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	'livesearch_person' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	'livesearch_person_exact' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
	'livesearch_subject' => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
	},
	'livesearch_subject_exact' => {
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
