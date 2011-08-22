#####################################################################
#
#  OpenBib::Handler::Apache::Registration
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

package OpenBib::Handler::Apache::Registration;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Connection ();
use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request();          # CGI-Handling (or require)
use APR::Table;

use Digest::MD5;
use DBI;
use Email::Valid;               # EMail-Adressen testen
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Captcha::reCAPTCHA;
use POSIX;

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
        'show'              => 'show',
        'register'          => 'register',
        'mail_confirmation' => 'mail_confirmation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';

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
    my $action              = ($query->param('action'))?$query->param('action'):'none';
    my $targetid            = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $loginname           = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password1           = ($query->param('password1'))?$query->param('password1'):'';
    my $password2           = ($query->param('password2'))?$query->param('password2'):'';
    my $recaptcha_challenge = $query->param('recaptcha_challenge_field');
    my $recaptcha_response  = $query->param('recaptcha_response_field');

    
    my $recaptcha = Captcha::reCAPTCHA->new;

    # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
    # Client-IP setzen
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $r->connection->remote_ip($1);
    }

    # TT-Data erzeugen
    my $ttdata={
        recaptcha  => $recaptcha,
        
        lang       => $queryoptions->get_option('l'),
    };
    $self->print_page($config->{tt_registration_tname},$ttdata);
 
    return Apache2::Const::OK;
}

sub register {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $registrationid = $self->param('registrationid') || '';

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
    

    my $recaptcha = Captcha::reCAPTCHA->new;

    # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
    # Client-IP setzen
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $r->connection->remote_ip($1);
    }

    # ab jetzt ist klar, dass es den Benutzer noch nicht gibt.
    # Jetzt eintragen und session mit dem Benutzer assoziieren;

    my $confirmation_info_ref = $user->get_confirmation_request({registrationid => $registrationid});

    my $loginname = $confirmation_info_ref->{loginname};
    my $password  = $confirmation_info_ref->{password};

    $user->add({
        loginname => $loginname,
        password  => $password,
        email     => $loginname,
    });

    
    my $userid   = $user->get_userid_for_username($loginname);
    my $targetid = $user->get_id_of_selfreg_logintarget();

    $user->connect_session({
        sessionID => $session->{ID},
        userid    => $userid,
        targetid  => $targetid,
    });

    $user->clear_confirmation_request;
    
    # TT-Data erzeugen
    my $ttdata={
        username   => $loginname,
    };

    $self->print_page($config->{tt_registration_success_tname},$ttdata);

    return Apache2::Const::OK;
}

sub mail_confirmation {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';

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
    my $action              = ($query->param('action'))?$query->param('action'):'none';
    my $targetid            = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $loginname           = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password1           = ($query->param('password1'))?$query->param('password1'):'';
    my $password2           = ($query->param('password2'))?$query->param('password2'):'';
    my $recaptcha_challenge = $query->param('recaptcha_challenge_field');
    my $recaptcha_response  = $query->param('recaptcha_response_field');
    
    my $recaptcha = Captcha::reCAPTCHA->new;

    # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
    # Client-IP setzen
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $r->connection->remote_ip($1);
    }

    if ($loginname eq "" || $password1 eq "" || $password2 eq "") {
        $self->print_warning($msg->maketext("Es wurde entweder kein Benutzername oder keine zwei Passworte eingegeben"));
        return Apache2::Const::OK;
    }

    if ($password1 ne $password2) {
        $self->print_warning($msg->maketext("Die beiden eingegebenen Passworte stimmen nicht überein."));
        return Apache2::Const::OK;
    }
    
    # Ueberpruefen, ob es eine gueltige Mailadresse angegeben wurde.
    unless (Email::Valid->address($loginname)){
        $self->print_warning($msg->maketext("Sie haben keine gütige Mailadresse eingegeben. Gehen Sie bitte [_1]zurück[_2] und korrigieren Sie Ihre Eingabe","<a href=\"$path_prefix/$config->{selfreg_loc}?action=show\">","</a>"));
        return Apache2::Const::OK;
    }
    
    if ($user->user_exists($loginname)) {
        $self->print_warning($msg->maketext("Ein Benutzer mit dem Namen [_1] existiert bereits. Haben Sie vielleicht Ihr Passwort vergessen? Dann gehen Sie bitte [_2]zurück[_3] und lassen es sich zumailen.","$loginname","<a href=\"http://$r->get_server_name$path_prefix/$config->{selfreg_loc}?action=show\">","</a>"));
        return Apache2::Const::OK;
    }
    
    # Recaptcha nur verwenden, wenn Zugriffsinformationen vorhanden sind
    if ($config->{recaptcha_private_key}){
        # Recaptcha pruefen
        my $recaptcha_result = $recaptcha->check_answer(
            $config->{recaptcha_private_key}, $r->connection->remote_ip,
            $recaptcha_challenge, $recaptcha_response
        );
        
        unless ( $recaptcha_result->{is_valid} ) {
            $self->print_warning($msg->maketext("Sie haben ein falsches Captcha eingegeben! Gehen Sie bitte [_1]zurück[_2] und versuchen Sie es erneut.","<a href=\"$path_prefix/$config->{selfreg_loc}?action=show\">","</a>"));
            return Apache2::Const::OK;
        }
    }

    my $gmtime    = localtime(time);
    my $md5digest = Digest::MD5->new();
    
    $md5digest->add($gmtime . rand('1024'). $$);
    my $registrationid = $md5digest->hexdigest;

    # Bestaetigungsmail versenden

    my $afile = "an." . $$;

    my $subject = $msg->maketext("Bestaetigen Sie Ihre Registrierung");

    my $mainttdata = {        
                      registrationid => $registrationid,
                      view           => $view,
                      config         => $config,
		      msg            => $msg,
		     };

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

    $maintemplate->process($config->{tt_registration_mail_message_tname}, $mainttdata ) || do { 
        $r->log_error($maintemplate->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };

    my $mailmsg = MIME::Lite->new(
        From            => $config->{contact_email},
        To              => $loginname,
        Subject         => $subject,
        Type            => 'multipart/mixed'
    );

    my $anschfile="/tmp/" . $afile;

    $mailmsg->attach(
        Type            => 'TEXT',
        Encoding        => '8bit',
	Path            => $anschfile,
    );
  
    $mailmsg->send('sendmail', "/usr/lib/sendmail -t -oi -f$config->{contact_email}");


    $user->add_confirmation_request({registrationid => $registrationid, loginname => $loginname, password => $password1});
    
    # TT-Data erzeugen
    my $ttdata={
        loginname      => $loginname,
    };

    $self->print_page($config->{tt_registration_confirmation_tname},$ttdata);

    return Apache2::Const::OK;
}

1;
