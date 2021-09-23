#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Circulations::Mail
#
#  Dieses File ist (C) 2020-2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Users::Circulations::Mail;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Digest::MD5;
use Email::Valid;
use Email::Stuffer;
use File::Slurper 'read_binary';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Socket;
use Template;
use URI::Escape;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'mail_form'       => 'mail_form',
        'show_form'       => 'show_form',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $mailtype       = $self->strip_suffix($self->param('mailtype'));
    
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
    
    # Zentrale Ueberpruefung der Authentifizierung
    
    # Nutzer muss am richtigen Target authentifiziert sein    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }
    
    my $show_handler   = "show_$mailtype";

    if ($self->can($show_handler)){
	return $self->$show_handler;
    }
    else {
        return $self->print_warning($msg->maketext("Die aufgerufene Funktion existiert nicht"));
    }
}

sub mail_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $mailtype       = $self->strip_suffix($self->param('mailtype'));
    
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

    # Zentrale Ueberpruefung der Authentifizierung
    
    # Nutzer muss am richtigen Target authentifiziert sein    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }
    
    my $mail_handler   = "mail_$mailtype";

    if ($self->can($mail_handler)){
	return $self->$mail_handler;
    }
    else {
        return $self->print_warning($msg->maketext("Die aufgerufene Funktion existiert nicht"));
    }
}

sub show_handset {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    
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
    my $scope          = $query->param('scope'); # defines sender, recipient via portal.yml
    my $titleid        = ($query->param('titleid'    ))?$query->param('titleid'):'';
    my $label          = ($query->param('label'      ))?$query->param('label'):'';
    my $holdingid      = ($query->param('holdingid'  ))?$query->param('holdingid'):'';

    $logger->debug("Dispatched to show_handset");
    
    if (!$titleid || !$scope){
	return $self->print_warning("Zuwenige Parameter übergeben");
    }

    # Zentrale Ueberpruefung der Authentifizierung bereits in show_form
        
    my ($loginname,$password,$access_token) = $user->get_credentials();
    
    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_brief_record;

    my $userinfo_ref = $user->get_info($user->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
	scope      => $scope,
	userinfo   => $userinfo_ref,
	label      => $label, # Signatur
	holdingid  => $holdingid,
	record     => $record,
	database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_mail_handset_tname},$ttdata);
}

sub mail_handset {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $database       = $self->param('database')       || '';

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
    my $scope         = $query->param('scope'); # defines sender, recipient via portal.yml
    my $title         = $query->param('title');
    my $titleid       = $query->param('titleid');
    my $location_mark = $query->param('location_mark');
    my $corporation   = $query->param('corporation');
    my $person        = $query->param('person');
    my $publisher     = $query->param('publisher');
    my $year          = $query->param('year');
    my $loginname     = $query->param('loginname'); # = username in userinfo
    my $username      = $query->param('username');  # = forename surname 
    my $remark        = $query->param('remark');
    my $email         = ($query->param('email'))?$query->param('email'):'';
    my $receipt       = $query->param('receipt');

#    my $titleid        = ($query->param('titleid'    ))?$query->param('titleid'):'';
    my $label          = ($query->param('label'      ))?$query->param('label'):'';
    my $holdingid      = ($query->param('holdingid'  ))?$query->param('holdingid'):'';

    $logger->debug("Dispatched to show_handset");
    
    if (!$titleid){
	return $self->print_warning("Zuwenige Parameter übergeben");
    }

    # Zentrale Ueberpruefung der Authentifizierung bereits in show_form
    
    my ($accountname,$password,$access_token) = $user->get_credentials();

    my $userinfo_ref = $user->get_info($user->{ID});

    my $accountemail = $userinfo_ref->{email};
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if ($email ne $accountemail) {
        return $self->print_warning($msg->maketext("Ihre Mailadresse stimmt nicht mit der im Benutzerkonto ueberein."));
    }

    if ($username ne $accountname) {
        return $self->print_warning($msg->maketext("Ihr Benutzername entspricht nicht dem verwendeten Parameter."));
    }
    
    if (!defined $config->get('mail')->{scope}{$scope}) {
        return $self->print_warning($msg->maketext("Eine Bestellung ist nicht moeglich."));
    }

    if (!$accountname || !$accountemail){
        return $self->print_warning($msg->maketext("Sie müssen alle Pflichtfelder ausfüllen."));
    }

    unless (Email::Valid->address($accountemail)) {
        return $self->print_warning($msg->maketext("Sie verwenden eine ungültige Mailadresse."));
    }	

    my $current_date = strftime("%d.%m.%Y, %H:%M Uhr", localtime);
    $current_date    =~ s!^\s!0!;
    
    # TT-Data erzeugen
    
    my $ttdata={
        view         => $view,
	current_date => $current_date,

	scope       => $scope,
	title       => $title,
	titleid     => $titleid,
	holdingid   => $holdingid,
	corporation => $corporation,
	person      => $person,
	publisher   => $publisher,
	label       => $label,
	username    => $username,
	remark      => $remark,
	email       => $email,
	    
        config      => $config,
        user        => $user,
        msg         => $msg,
    };

    my $anschreiben="";
    my $afile = "an." . $$;

    my $maintemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        ABSOLUTE      => 1,
        #        INCLUDE_PATH  => $config->{tt_include_path},
        # Es ist wesentlich, dass OUTPUT* hier und nicht im
        # Template::Provider definiert wird
        RECURSION      => 1,
        OUTPUT_PATH   => '/tmp',
        OUTPUT        => $afile,
    });

    $maintemplate->process($config->{tt_user_circulations_mail_handset_mail_body_tname}, $ttdata ) || do { 
        $logger->error($maintemplate->error());
        $self->header_add('Status',400); # server error
        return;
    };

    my $mail_to = $config->{mail}{scope}{$scope}{recipient};

    if ($receipt){
	$mail_to.=",$accountemail";
    }
    
    my $anschfile="/tmp/" . $afile;

    Email::Stuffer->to($mail_to)
	->from($config->{mail}{scope}{$scope}{sender})
	->subject("$scope: Bestellung per Mail")
	->text_body(read_binary($anschfile))
	->send;
    
    unlink $anschfile;
    
    return $self->print_page($config->{tt_users_circulations_mail_handset_mail_success_tname},$ttdata);
}

1;
__END__

=head1 NAME

OpenBib::Users::Circulations::Mail - Bestellung/Kontakt/... von Nutzern per Mail

=head1 DESCRIPTION

Das Modul OpenBib::Users::Circulations::Mail stellt einen Dienst zur 
verfuegung, um fuer Nutzer u.a. eine vereinfachte Bestellmoeglichkeit
von Medien abzuwickeln.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
