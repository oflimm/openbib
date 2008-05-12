#####################################################################
#
#  OpenBib::Handler::Apache::UserPrefs
#
#  Dieses File ist (C) 2004-2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::UserPrefs;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
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

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache::Request->instance($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $user      = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

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

    my $bibsonomy_sync = ($query->param('bibsonomy_sync'))?$query->param('bibsonomy_sync'):'off';
    my $bibsonomy_user = ($query->param('bibsonomy_user'))?$query->param('bibsonomy_user'):0;
    my $bibsonomy_key  = ($query->param('bibsonomy_key'))?$query->param('bibsonomy_key'):0;

    my $setmask       = ($query->param('setmask'))?$query->param('setmask'):'';
    my $action        = ($query->param('action'))?$query->param('action'):'none';
    my $targetid      = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $loginname     = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password      = ($query->param('password'))?$query->param('password'):'';
    my $password1     = ($query->param('password1'))?$query->param('password1'):'';
    my $password2     = ($query->param('password2'))?$query->param('password2'):'';

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return OK;
    }

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    unless($user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Diese Session ist nicht authentifiziert."),$r,$msg);
        return OK;
    }
  
    if ($action eq "showfields") {
        my $fieldchoice_ref = $user->get_fieldchoice();
        my $userinfo_ref    = $user->get_info();
        
        my $loginname           = $userinfo_ref->{'loginname'};
        my $password            = $userinfo_ref->{'password'};
    
        my $passwortaenderung = "";
        my $loeschekennung    = "";
    
        # Wenn wir eine gueltige Mailadresse als Loginnamen haben,
        # dann liegt Selbstregistrierung vor und das Passwort kann
        # geaendert werden
        my $email_valid=Email::Valid->address($loginname);

        my $targettype=$user->get_targettype_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            view             => $view,
            stylesheet       => $stylesheet,
            sessionID        => $session->{ID},
            user             => $user,
            
            loginname        => $loginname,
            password         => $password,
            email_valid      => $email_valid,
            targettype       => $targettype,
            fieldchoice      => $fieldchoice_ref,
            
            userinfo         => $userinfo_ref,

            config           => $config,
            user             => $user,
            msg              => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_userprefs_tname},$ttdata,$r);
    }
    elsif ($action eq "changefields") {
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

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_userprefs_changefields_tname},$ttdata,$r);
    }
    elsif ($action eq "changebibsonomy") {
        $user->set_bibsonomy({
            sync      => $bibsonomy_sync,
            user      => $bibsonomy_user,
            key       => $bibsonomy_key,
        });

        if ($bibsonomy_sync eq "on"){
            $user->initial_sync_to_bibsonomy;
        }
        
        $r->internal_redirect("http://$config->{servername}$config->{userprefs_loc}?sessionID=$session->{ID}&action=showfields");
    }
    elsif ($action eq "delaccount_ask") {
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_userprefs_ask_delete_tname},$ttdata,$r);
    }
    elsif ($action eq "delaccount") {
        $user->wipe_account();
        
        # Als naechstes werden die 'normalen' Sessiondaten geloescht

        $session->clear_data();

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_userprefs_userdeleted_tname},$ttdata,$r);
    }
    elsif ($action eq "changepw") {
        if ($password1 eq "" || $password1 ne $password2) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben entweder kein Passwort eingegeben oder die beiden Passworte stimmen nicht überein"),$r,$msg);
            return OK;
        }
    
        $user->set_credentials({
            password => $password1,
        });
    
        $r->internal_redirect("http://$config->{servername}$config->{userprefs_loc}?sessionID=$session->{ID}&action=showfields");
    }
    elsif ($action eq "changemask") {
        if ($setmask eq "") {
            OpenBib::Common::Util::print_warning($msg->maketext("Es wurde keine Standard-Recherchemaske ausgewählt"),$r,$msg);
            return OK;
        }

        $user->set_mask($setmask);
        $session->set_mask($setmask);

        $r->internal_redirect("http://$config->{servername}$config->{userprefs_loc}?sessionID=$session->{ID}&action=showfields");
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Unerlaubte Aktion"),$r,$msg);
    }
    return OK;
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
