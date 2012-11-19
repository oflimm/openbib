####################################################################
#
#  OpenBib::Handler::Apache::Users::Preferences
#
#  Dieses File ist (C) 2004-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Users::Preferences;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::SubRequest (); # internal_redirect
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

use base 'OpenBib::Handler::Apache::Users';

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
        'update_bibsonomy_sync'                => 'update_bibsonomy_sync',
        'update_spelling'                      => 'update_spelling',
        'update_livesearch'                    => 'update_livesearch',
        'update_autocompletion'                => 'update_autocompletion',
        'delete_account'                       => 'delete_account',
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
        $self->print_authorization_error();
        return;
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
    
    my $targettype=$user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        qopts               => $queryoptions->get_options,
        username            => $username,
        password            => $password,
        email_valid         => $email_valid,
        targettype          => $targettype,
        searchfields        => $searchfields_ref,
        spelling_suggestion => $spelling_suggestion_ref,
        livesearch          => $livesearch_ref,
        userinfo            => $userinfo_ref,
    };
    
    $self->print_page($config->{tt_users_preferences_tname},$ttdata);

    return Apache2::Const::OK;
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

    # CGI Args
    my $freesearch     = ($query->param('freesearch'))?$query->param('freesearch'):'0';
    my $title          = ($query->param('title'))?$query->param('title'):'0';
    my $titlestring    = ($query->param('titlestring'))?$query->param('titlestring'):'0';
    my $source         = ($query->param('source'))?$query->param('source'):'0';
    my $person         = ($query->param('person'))?$query->param('person'):'0';
    my $corporatebody  = ($query->param('corporatebody'))?$query->param('corporatebody'):'0';
    my $subject        = ($query->param('subject'))?$query->param('subject'):'0';
    my $classification = ($query->param('classification'))?$query->param('classification'):'0';
    my $isbn           = ($query->param('isbn'))?$query->param('isbn'):'0';
    my $issn           = ($query->param('issn'))?$query->param('issn'):'0';
    my $mark           = ($query->param('mark'))?$query->param('mark'):'0';
    my $content        = ($query->param('content'))?$query->param('content'):'0';
    my $mediatype      = ($query->param('mediatype'))?$query->param('mediatype'):'0';
    my $year           = ($query->param('year'))?$query->param('year'):'0';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $user->set_searchfields({
        freesearch     => $freesearch,
        title          => $title,
        titlestring    => $titlestring,
        person         => $person,
        corporatebody  => $corporatebody,
        subject        => $subject,
        classification => $classification,
        isbn           => $isbn,
        issn           => $issn,
        mark           => $mark,
        mediatype      => $mediatype,
        year           => $year,
        content        => $content,
        source         => $source,
    });

    $self->return_baseurl;
    
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

    # CGI Args
    my $bibsonomy_sync = ($query->param('bibsonomy_sync'))?$query->param('bibsonomy_sync'):'off';
    my $bibsonomy_user = ($query->param('bibsonomy_user'))?$query->param('bibsonomy_user'):0;
    my $bibsonomy_key  = ($query->param('bibsonomy_key'))?$query->param('bibsonomy_key'):0;

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $user->set_bibsonomy({
        sync      => $bibsonomy_sync,
        user      => $bibsonomy_user,
        key       => $bibsonomy_key,
    });

    $self->return_baseurl;

    return;
}

sub update_bibsonomy_sync {
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
        $self->print_authorization_error();
        return;
    }

    $user->sync_all_to_bibsonomy;

    $self->return_baseurl;

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

    # CGI Args
    my $setmask       = ($query->param('setmask'))?$query->param('setmask'):'';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    if ($setmask eq "") {
        $self->print_warning($msg->maketext("Es wurde keine Standard-Recherchemaske ausgewählt"));
        return Apache2::Const::OK;
    }

    $user->set_mask($setmask);
    $session->set_mask($setmask);

    $self->return_baseurl;

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

    # CGI Args
    my $password1     = ($query->param('password1'))?$query->param('password1'):'';
    my $password2     = ($query->param('password2'))?$query->param('password2'):'';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    if ($password1 eq "" || $password1 ne $password2) {
        $self->print_warning($msg->maketext("Sie haben entweder kein Passwort eingegeben oder die beiden Passworte stimmen nicht überein"));
        return Apache2::Const::OK;
    }

    $user->set_credentials({
        password => $password1,
    });

    $self->return_baseurl;

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

    # CGI Args
    my $spelling_as_you_type   = ($query->param('spelling_as_you_type'))?$query->param('spelling_as_you_type'):'0';
    my $spelling_resultlist    = ($query->param('spelling_resultlist'))?$query->param('spelling_resultlist'):'0';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $user->set_spelling_suggestion({
        as_you_type        => $spelling_as_you_type,
        resultlist         => $spelling_resultlist,
    });

    $self->return_baseurl;

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

    # CGI Args
    my $livesearch_freesearch       = ($query->param('livesearch_freesearch'))?$query->param('livesearch_freesearch'):'0';
    my $livesearch_freesearch_exact = ($query->param('livesearch_freesearch_exact'))?$query->param('livesearch_freesearch_exact'):'0';
    my $livesearch_person           = ($query->param('livesearch_person'))?$query->param('livesearch_person'):'0';
    my $livesearch_person_exact     = ($query->param('livesearch_person_exact'))?$query->param('livesearch_person_exact'):'0';
    my $livesearch_subject          = ($query->param('livesearch_subject'))?$query->param('livesearch_subject'):'0';
    my $livesearch_subject_exact    = ($query->param('livesearch_subject_exact'))?$query->param('livesearch_subject_exact'):'0';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $user->set_livesearch({
        freesearch       => $livesearch_freesearch,
        freesearch_exact => $livesearch_freesearch_exact,
        person           => $livesearch_person,
        person_exact     => $livesearch_person_exact,
        subject          => $livesearch_subject,
        subject_exact    => $livesearch_subject_exact,
    });

    $self->return_baseurl;

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

    # CGI Args
    my $setautocompletion = ($query->param('setautocompletion'))?$query->param('setautocompletion'):'livesearch';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $user->set_autocompletion($setautocompletion);

    $self->return_baseurl;

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

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
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
