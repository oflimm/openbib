####################################################################
#
#  OpenBib::Handler::Apache::User::Preferences
#
#  Dieses File ist (C) 2004-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::User::Preferences;

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

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'                      => 'show_collection',
        'update_searchfields'                  => 'update_searchfields',
        'update_searchform'                    => 'update_searchform',
        'update_bibsonomy'                     => 'update_bibsonomy',
        'update_bibsonomy_sync'                => 'update_bibsonomy_sync',
        'update_spelling'                      => 'update_spelling',
        'update_livesearch'                    => 'update_livesearch',
        'update_autocompletion'                => 'update_autocompletion',
        'delete_account'                       => 'delete_account',
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

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    my $fieldchoice_ref         = $user->get_fieldchoice();
    my $userinfo_ref            = $user->get_info();
    my $spelling_suggestion_ref = $user->get_spelling_suggestion();
    my $livesearch_ref          = $user->get_livesearch();
    
    my $loginname               = $userinfo_ref->{'loginname'};
    my $password                = $userinfo_ref->{'password'};
    
    # Wenn wir eine gueltige Mailadresse als Loginnamen haben,
    # dann liegt Selbstregistrierung vor und das Passwort kann
    # geaendert werden
    my $email_valid=Email::Valid->address($loginname);
    
    my $targettype=$user->get_targettype_of_session($session->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
        qopts               => $queryoptions->get_options,
        loginname           => $loginname,
        password            => $password,
        email_valid         => $email_valid,
        targettype          => $targettype,
        fieldchoice         => $fieldchoice_ref,
        spelling_suggestion => $spelling_suggestion_ref,
        livesearch          => $livesearch_ref,
        userinfo            => $userinfo_ref,
    };
    
    $self->print_page($config->{tt_user_preferences_tname},$ttdata);

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
    my $showfs        = ($query->param('showfs'))?$query->param('showfs'):'0';
    my $showhst       = ($query->param('showhst'))?$query->param('showhst'):'0';
    my $showhststring = ($query->param('showhststring'))?$query->param('showhststring'):'0';
    my $showgtquelle  = ($query->param('showgtquelle'))?$query->param('showgtquelle'):'0';
    my $showverf      = ($query->param('showverf'))?$query->param('showverf'):'0';
    my $showkor       = ($query->param('showkor'))?$query->param('showkor'):'0';
    my $showswt       = ($query->param('showswt'))?$query->param('showswt'):'0';
    my $shownotation  = ($query->param('shownotation'))?$query->param('shownotation'):'0';
    my $showisbn      = ($query->param('showisbn'))?$query->param('showisbn'):'0';
    my $showissn      = ($query->param('showissn'))?$query->param('showissn'):'0';
    my $showsign      = ($query->param('showsign'))?$query->param('showsign'):'0';
    my $showinhalt    = ($query->param('showinhalt'))?$query->param('showinhalt'):'0';
    my $showmart      = ($query->param('showmart'))?$query->param('showmart'):'0';
    my $showejahr     = ($query->param('showejahr'))?$query->param('showejahr'):'0';

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    $user->set_fieldchoice({
        fs        => $showfs,
        hst       => $showhst,
        hststring => $showhststring,
        verf      => $showverf,
        kor       => $showkor,
        swt       => $showswt,
        notation  => $shownotation,
        isbn      => $showisbn,
        issn      => $showissn,
        sign      => $showsign,
        mart      => $showmart,
        ejahr     => $showejahr,
        inhalt    => $showinhalt,
        gtquelle  => $showgtquelle,
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

    if (!$self->is_authenticated('user',$userid)){
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

    if (!$self->is_authenticated('user',$userid)){
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

    if (!$self->is_authenticated('user',$userid)){
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

    if (!$self->is_authenticated('user',$userid)){
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

    if (!$self->is_authenticated('user',$userid)){
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
    my $livesearch_fs   = ($query->param('livesearch_fs'))?$query->param('livesearch_fs'):'0';
    my $livesearch_verf = ($query->param('livesearch_verf'))?$query->param('livesearch_verf'):'0';
    my $livesearch_swt  = ($query->param('livesearch_swt'))?$query->param('livesearch_swt'):'0';
    my $livesearch_exact= ($query->param('livesearch_exact'))?$query->param('livesearch_exact'):'0';

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    $user->set_livesearch({
        fs        => $livesearch_fs,
        verf      => $livesearch_verf,
        swt       => $livesearch_swt,
        exact     => $livesearch_exact,
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

    if (!$self->is_authenticated('user',$userid)){
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

    my $new_location = "$path_prefix/$config->{user_loc}/$userid/preferences.html";

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
