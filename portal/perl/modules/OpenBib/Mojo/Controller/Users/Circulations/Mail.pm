#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Circulations::Mail
#
#  Dieses File ist (C) 2020-2022 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Users::Circulations::Mail;

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
use URI::Escape qw(uri_unescape);

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Session;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub dispatch_to_user {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view           = $self->param('view');
    my $mailtype       = $self->strip_suffix($self->param('mailtype'));

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

	my $args = $self->to_cgi_querystring;

        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{circulations_loc}/id/mail/${mailtype}.html?$args";

	$logger->debug("Redirecting to user location $new_location");
        
	return $self->redirect($new_location,303);
    }

    return;
}

sub show_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $mailtype       = $self->strip_suffix($self->param('mailtype'));
    
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

    my $mailtype_noauth_ref = {
	"kmb" => 1,
    };
    
    # Zentrale Ueberpruefung der Authentifizierung

    unless (defined $mailtype_noauth_ref->{$mailtype}){
    
	# Nutzer muss am richtigen Target authentifiziert sein    
	my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
	my $sessionuserid        = $user->get_userid_of_session($session->{ID});

	
	if (!$self->authorization_successful || $userid ne $sessionuserid){
	    if ($self->stash('representation') eq "html"){
		return $self->tunnel_through_authenticator('GET');            
	    }
	    else  {
		return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
	    }
	}
    }
    
    my $mailtype_is_valid_ref = {
	"handset"   => 1,
        "kmb"       => 1,
        "testothek" => 1,
        "default"   => 1,
    };
    
    my $show_handler   = "show_$mailtype";

    if (defined $mailtype_is_valid_ref->{$mailtype} && $self->can($show_handler)){
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
    my $userid         = $self->param('userid');
    my $mailtype       = $self->strip_suffix($self->param('mailtype'));
    
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

    my $mailtype_noauth_ref = {
	"kmb" => 1,
    };
    
    # Zentrale Ueberpruefung der Authentifizierung

    unless (defined $mailtype_noauth_ref->{$mailtype}){
	
	# Nutzer muss am richtigen Target authentifiziert sein    
	my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
	my $sessionuserid        = $user->get_userid_of_session($session->{ID});
	
	if (!$self->authorization_successful || $userid ne $sessionuserid){
	    if ($self->stash('representation') eq "html"){
		return $self->tunnel_through_authenticator('POST');            
	    }
	    else  {
		return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
	    }
	}
    }

    my $mailtype_is_valid_ref = {
	"handset"   => 1,
        "kmb"       => 1,
        "testothek" => 1,
        "default"   => 1,
    };
    
    my $mail_handler   = "mail_$mailtype";

    if (defined $mailtype_is_valid_ref->{$mailtype} && $self->can($mail_handler)){
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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CGI Args
    my $realm          = $input_data_ref->{'realm'}; # defines sender, recipient via portal.yml
    my $database       = $input_data_ref->{'dbname'};
    my $titleid        = $input_data_ref->{'titleid'};
    my $label          = $input_data_ref->{'label'};
    my $location       = $input_data_ref->{'location'};
    
    $logger->debug("Dispatched to show_handset");
    
    if (!$titleid || !$realm || !$label || !$location || !$database){
	return $self->print_warning("Zuwenige Parameter übergeben");
    }

    if (!$config->db_exists($database)){
	return $self->print_warning("Datenbank existiert nicht");
    }

    # Zentrale Ueberpruefung der Authentifizierung bereits in show_form
        
    my ($loginname,$password,$access_token) = $user->get_credentials();
    
    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_brief_record;

    my $userinfo_ref = $user->get_info($user->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
	realm      => $realm,
	userinfo   => $userinfo_ref,
	title_location   => $location, # Standort = Zweigstelle / Abteilung
	label      => $label,    # Signatur
	record     => $record,
	database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_mail_handset_tname},$ttdata);
}

sub show_default {
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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CGI Args
    my $realm          = $input_data_ref->{'realm'}; # defines sender, recipient via portal.yml
    my $database       = $input_data_ref->{'dbname'};
    my $titleid        = $input_data_ref->{'titleid'};
    my $label          = $input_data_ref->{'label'};
    my $location       = $input_data_ref->{'location'};

    $logger->debug("Dispatched to show_default");
    
    if (!$titleid || !$realm || !$label || !$location || !$database){
	return $self->print_warning("Zuwenige Parameter übergeben");
    }

    if (!$config->db_exists($database)){
	return $self->print_warning("Datenbank existiert nicht");
    }
    
    # Zentrale Ueberpruefung der Authentifizierung bereits in show_form
        
    my ($loginname,$password,$access_token) = $user->get_credentials();
    
    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_brief_record;

    my $userinfo_ref = $user->get_info($user->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
	realm      => $realm,
	userinfo   => $userinfo_ref,
	title_location   => $location, # Standort = Zweigstelle / Abteilung
	label      => $label,    # Signatur
	record     => $record,
	database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_mail_default_tname},$ttdata);
}

sub show_kmb {
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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CGI Args
    my $realm          = $input_data_ref->{'realm'}; # defines sender, recipient via portal.yml
    my $database       = $input_data_ref->{'dbname'};
    my $titleid        = $input_data_ref->{'titleid'};
    my $label          = $input_data_ref->{'label'};
    my $location       = $input_data_ref->{'location'};

    $logger->debug("Dispatched to show_kmb");
    
    if (!$titleid || !$realm || !$label || !$location || !$database){
	return $self->print_warning("Zuwenige Parameter übergeben");
    }

    if (!$config->db_exists($database)){
	return $self->print_warning("Datenbank existiert nicht");
    }
    
    # Zentrale Ueberpruefung der Authentifizierung bereits in show_form
        
    my ($loginname,$password,$access_token) = $user->get_credentials();
    
    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_full_record;

    my $userinfo_ref = $user->get_info($user->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
	realm      => $realm,
	userinfo   => $userinfo_ref,
	label      => $label, # Signatur
	title_location   => $location, # Standort = Zweigstelle / Abteilung
	record     => $record,
	database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_mail_kmb_tname},$ttdata);
}

sub show_testothek {
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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CGI Args
    my $realm          = $input_data_ref->{'realm'}; # defines sender, recipient via portal.yml
    my $database       = $input_data_ref->{'dbname'};
    my $titleid        = $input_data_ref->{'titleid'};
    my $label          = $input_data_ref->{'label'};
    my $location       = $input_data_ref->{'location'};

    $logger->debug("Dispatched to show_testothek");
    
    if (!$titleid || !$realm || !$label || !$location || !$database){
	return $self->print_warning("Zuwenige Parameter übergeben");
    }

    if (!$config->db_exists($database)){
	return $self->print_warning("Datenbank existiert nicht");
    }
    
    # Zentrale Ueberpruefung der Authentifizierung bereits in show_form
        
    my ($loginname,$password,$access_token) = $user->get_credentials();
    
    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_brief_record;

    my $userinfo_ref = $user->get_info($user->{ID});
    
    # TT-Data erzeugen
    my $ttdata={
	realm      => $realm,
	userinfo   => $userinfo_ref,
	label      => $label, # Signatur
	title_location   => $location, # Standort = Zweigstelle / Abteilung
	record     => $record,
	database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_mail_testothek_tname},$ttdata);
}

sub mail_handset {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')       || '';

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
    my $servername     = $self->stash('servername');    
    
    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CGI Args
    my $realm          = $input_data_ref->{'realm'}; # defines sender, recipient via portal.yml
    my $database       = $input_data_ref->{'dbname'};
    my $titleid        = $input_data_ref->{'titleid'};
    my $label          = $input_data_ref->{'label'};
    my $location       = $input_data_ref->{'location'};
    my $receipt        = $input_data_ref->{'receipt'};
    my $remark         = $input_data_ref->{'remark'};
    
    $logger->debug("Dispatched to mail_handset");
    
    if (!$titleid || !$label || !$realm || !$location || !$database){
	$logger->debug("titleid $titleid / label $label / realm $realm / location $location / database $database");
	return $self->print_warning("Zuwenige Parameter übergeben");
    }

    if (!$config->db_exists($database)){
	return $self->print_warning("Datenbank existiert nicht");
    }
    
    # Zentrale Ueberpruefung der Authentifizierung bereits in show_form
    
    my ($accountname,$password,$access_token) = $user->get_credentials();

    my $userinfo_ref = $user->get_info($user->{ID});

    my $accountemail = $userinfo_ref->{email};
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
        if (!defined $config->get('mail')->{realm}{$realm}) {
        return $self->print_warning($msg->maketext("Eine Bestellung ist nicht moeglich."));
    }

    unless (Email::Valid->address($accountemail)) {
        return $self->print_warning($msg->maketext("Sie verwenden eine ungültige Mailadresse."));
    }	

    my $current_date = strftime("%d.%m.%Y, %H:%M Uhr", localtime);
    $current_date    =~ s!^\s!0!;

    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_brief_record;

    # TT-Data erzeugen
    
    my $ttdata={
	servername   => $servername,
	path_prefix  => $path_prefix,
	
        view         => $view,
	current_date => $current_date,

	userinfo    => $userinfo_ref,
	record      => $record,
	
	realm       => $realm,
        label       => uri_unescape($label),
	title_location    => $location, # Standort = Zweigstelle / Abteilung
	email       => $accountemail,
	loginname   => $accountname,
	remark      => $remark,
	
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

    $maintemplate->process($config->{tt_users_circulations_mail_handset_mail_body_tname}, $ttdata ) || do { 
        $logger->error($maintemplate->error());
        $self->res->code(400); # server error
        return;
    };

    my $mail_to = $config->{mail}{realm}{$realm}{recipient};
    
    # Fuer Tests erstmal deaktiviert...
    # if ($receipt){
    # 	$mail_to.=",$accountemail";
    # }
    
    my $anschfile="/tmp/" . $afile;

    Email::Stuffer->to($mail_to)
	->from($config->{mail}{realm}{$realm}{sender})
	->subject("Bestellung aus Handapparat per Mail ($realm)")
	->text_body(read_binary($anschfile))
	->send;
    
    unlink $anschfile;
    
    return $self->print_page($config->{tt_users_circulations_mail_handset_mail_success_tname},$ttdata);
}

sub mail_kmb {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')       || '';

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

    # CGI Args
    my $realm          = $input_data_ref->{'realm'}; # defines sender, recipient via portal.yml
    my $database       = $input_data_ref->{'dbname'};
    my $titleid        = $input_data_ref->{'titleid'};
    my $label          = $input_data_ref->{'label'};
    my $location       = $input_data_ref->{'location'};
    # Kein Receipt, da unauthentifiziert!
    my $remark         = $input_data_ref->{'remark'};
    my $freeusername   = $input_data_ref->{'freeusername'};
    my $email          = $input_data_ref->{'email'};
    my $pickup_location= $input_data_ref->{'pickup_location'};
    
    $logger->debug("Dispatched to mail_kmb");
    
    if (!$titleid || !$label || !$realm || !$location || !$database){
	return $self->print_warning("Zuwenige Parameter übergeben");
    }

    if (!$config->db_exists($database)){
	return $self->print_warning("Datenbank existiert nicht");
    }
    
    # Zentrale Ueberpruefung der Authentifizierung bereits in show_form

    if (!$freeusername){
	return $self->print_warning("Bitte geben Sie Ihren Namen an.");
    }

    if (!$email){
	return $self->print_warning("Bitte geben Sie Ihre E-Mail-Adresse an.");
    }

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
        if (!defined $config->get('mail')->{realm}{$realm}) {
        return $self->print_warning($msg->maketext("Eine Bestellung ist nicht moeglich."));
    }

    unless (Email::Valid->address($email)) {
        return $self->print_warning($msg->maketext("Sie verwenden eine ungültige Mailadresse."));
    }	

    my $current_date = strftime("%d.%m.%Y, %H:%M Uhr", localtime);
    $current_date    =~ s!^\s!0!;

    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_full_record;

    $logger->debug("User: $freeusername");
    # TT-Data erzeugen
    
    my $ttdata={
        view         => $view,
	current_date => $current_date,

	record      => $record,
	database    => $database,
	
	realm       => $realm,
        label       => $label,
	title_location    => $location, # Standort = Zweigstelle / Abteilung
	email       => $email,
	freeusername  => $freeusername,
	remark      => $remark,
	pickup_location => $pickup_location,	
	
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

    $maintemplate->process($config->{tt_users_circulations_mail_kmb_mail_body_tname}, $ttdata ) || do { 
        $logger->error($maintemplate->error());
        $self->res->code(400); # server error
        return;
    };

    my $mail_to = $config->{mail}{realm}{$realm}{recipient};
    
    # Fuer Tests erstmal deaktiviert...
    # if ($receipt){
    # 	$mail_to.=",$accountemail";
    # }
    
    my $anschfile="/tmp/" . $afile;

    # $pickup_location =~ s!f\xC3\xBCr!=?ISO-8859-15?Q?f=FCr?=!;
    
    Email::Stuffer->to($mail_to)
	->from("no-reply\@ub.uni-koeln.de")
	->reply_to($config->{mail}{realm}{$realm}{sender})
	->header("Content-Type" => 'text/plain; charset="utf-8"')
	->subject("KMB-Bestellung: $pickup_location ($realm)")
	->text_body(read_binary($anschfile))
	->send;
    
    unlink $anschfile;
    
    return $self->print_page($config->{tt_users_circulations_mail_kmb_mail_success_tname},$ttdata);
}

sub mail_testothek {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';

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
    my $servername     = $self->stash('servername');    
    
    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CGI Args
    my $realm          = $input_data_ref->{'realm'}; # defines sender, recipient via portal.yml
    my $database       = $input_data_ref->{'dbname'};
    my $titleid        = $input_data_ref->{'titleid'};
    my $label          = $input_data_ref->{'label'};
    my $location       = $input_data_ref->{'location'};
    my $receipt        = $input_data_ref->{'receipt'};
    my $remark         = $input_data_ref->{'remark'};
    my $amount         = $input_data_ref->{'amount'};
    my $forview        = $input_data_ref->{'forview'};
    my $materialonly   = $input_data_ref->{'materialonly'};
    
    $logger->debug("Dispatched to mail_testothek");
    
    if (!$titleid || !$label || !$realm || !$location || !$database){
	return $self->print_warning("Zuwenige Parameter übergeben");
    }
    
    if (!$config->db_exists($database)){
	return $self->print_warning("Datenbank existiert nicht");
    }

    # Zentrale Ueberpruefung der Authentifizierung bereits in show_form
    
    my ($accountname,$password,$access_token) = $user->get_credentials();

    my $userinfo_ref = $user->get_info($user->{ID});

    my $accountemail = $userinfo_ref->{email};
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if (!defined $config->get('mail')->{realm}{$realm}) {
        return $self->print_warning($msg->maketext("Eine Bestellung ist nicht moeglich."));
    }

    unless (Email::Valid->address($accountemail)) {
        return $self->print_warning($msg->maketext("Sie verwenden eine ungültige Mailadresse."));
    }	

    my $current_date = strftime("%d.%m.%Y, %H:%M Uhr", localtime);
    $current_date    =~ s!^\s!0!;

    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_brief_record;

    # TT-Data erzeugen
    
    my $ttdata={
	servername   => $servername,
	path_prefix  => $path_prefix,
        view         => $view,
	current_date => $current_date,

	userinfo    => $userinfo_ref,
	record      => $record,
	
	realm       => $realm,
        label       => uri_unescape($label),
	title_location    => $location, # Standort = Zweigstelle / Abteilung
	email       => $accountemail,
	loginname   => $accountname,
	remark      => $remark,
	amount        => $amount,
	forview       => $forview,
	materialonly  => $materialonly,
	
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

    $maintemplate->process($config->{tt_users_circulations_mail_testothek_mail_body_tname}, $ttdata ) || do { 
        $logger->error($maintemplate->error());
        $self->res->code(400); # server error
        return;
    };

    my $mail_to = $config->{mail}{realm}{$realm}{recipient};
    
    # Fuer Tests erstmal deaktiviert...
    if ($receipt){
    	$mail_to.=",$accountemail";
    }
    
    my $anschfile="/tmp/" . $afile;

    # $pickup_location =~ s!f\xC3\xBCr!=?ISO-8859-15?Q?f=FCr?=!;
    
    Email::Stuffer->to($mail_to)
	->from($config->{mail}{realm}{$realm}{sender})	
	->reply_to($config->{mail}{realm}{$realm}{sender})
	->header("Content-Type" => 'text/plain; charset="utf-8"')
	->subject("Bestellung Testothek: $label")
	->text_body(read_binary($anschfile))
	->send;
    
    unlink $anschfile;
    
    return $self->print_page($config->{tt_users_circulations_mail_testothek_mail_success_tname},$ttdata);
}

sub mail_default {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';

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

    # CGI Args
    my $realm          = $input_data_ref->{'realm'}; # defines sender, recipient via portal.yml
    my $database       = $input_data_ref->{'dbname'};
    my $titleid        = $input_data_ref->{'titleid'};
    my $label          = $input_data_ref->{'label'};
    my $location       = $input_data_ref->{'location'};
    my $receipt        = $input_data_ref->{'receipt'};
    my $remark         = $input_data_ref->{'remark'};
    my $period         = $input_data_ref->{'period'};

    $logger->debug("Dispatched to mail_default");
    
    if (!$titleid || !$label || !$realm || !$location || !$database){
	return $self->print_warning("Zuwenige Parameter übergeben");
    }

    if (!$config->db_exists($database)){
	return $self->print_warning("Datenbank existiert nicht");
    }
    
    # Zentrale Ueberpruefung der Authentifizierung bereits in show_form
    
    my ($accountname,$password,$access_token) = $user->get_credentials();

    my $userinfo_ref = $user->get_info($user->{ID});

    my $accountemail = $userinfo_ref->{email};
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if (!defined $config->get('mail')->{realm}{$realm}) {
        return $self->print_warning($msg->maketext("Eine Bestellung ist nicht moeglich."));
    }

    unless (Email::Valid->address($accountemail)) {
        return $self->print_warning($msg->maketext("Sie verwenden eine ungültige Mailadresse."));
    }	

    my $current_date = strftime("%d.%m.%Y, %H:%M Uhr", localtime);
    $current_date    =~ s!^\s!0!;

    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_brief_record;

    # TT-Data erzeugen
    
    my $ttdata={
        view         => $view,
	current_date => $current_date,

	userinfo    => $userinfo_ref,
	record      => $record,
	
	realm       => $realm,
        label       => $label,
	title_location    => $location, # Standort = Zweigstelle / Abteilung
	email       => $accountemail,
	loginname   => $accountname,
	remark      => $remark,
	period      => $period,
	
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

    $maintemplate->process($config->{tt_users_circulations_mail_default_mail_body_tname}, $ttdata ) || do { 
        $logger->error($maintemplate->error());
        $self->res->code(400); # server error
        return;
    };

    my $mail_to = $config->{mail}{realm}{$realm}{recipient};
    
    # Fuer Tests erstmal deaktiviert...
    # if ($receipt){
    # 	$mail_to.=",$accountemail";
    # }
    
    my $anschfile="/tmp/" . $afile;

    Email::Stuffer->to($mail_to)
	->from($config->{mail}{realm}{$realm}{sender})
	->subject("Bestellung per Mail ($realm)")
	->text_body(read_binary($anschfile))
	->send;
    
    unlink $anschfile;
    
    return $self->print_page($config->{tt_users_circulations_mail_default_mail_success_tname},$ttdata);
}

sub get_input_definition {
    my $self=shift;
    
    return {
        dbname => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        titleid => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        label => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        location => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        email => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        realm => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        receipt => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        remark => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        period => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        source => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        articleauthor => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        articletitle => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        volume => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        issue => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        pages => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        year => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        shipment => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        customergroup => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        username => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        freeusername => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        address => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        numbering => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        pickup_location => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        confirm => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
	# Testothek
        amount => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        forview => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        materialonly => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
    };
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
