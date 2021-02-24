
#####################################################################
#
#  OpenBib::Handler::PSGI::Extensions::FidPhil::Users::Passwords
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

package OpenBib::Handler::PSGI::Extensions::FidPhil::Users::Passwords;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use MIME::Lite;
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI::Users::Passwords';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'       => 'show_collection',
        'create_record'         => 'create_record',
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

    # TT-Data erzeugen
    
    my $ttdata={
    };
    
    return $self->print_page($config->{tt_users_passwords_tname},$ttdata);
}

sub create_record {
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

    # CGI / JSON input
    my $input_data_ref    = $self->parse_valid_input();
    my $username          = $input_data_ref->{username};
    
    # CGI Args
    #my $username  = ($query->param('username'))?$query->param('username'):'';
    my $result_ref = {
        success => 0,
    };
    my $loginfailed=0;
    
    if ($username eq "") {
        my $code   = -1;
	    my $reason = "Sie haben keine E-Mail Adresse eingegeben.";
        if ($self->param('representation') eq "html"){
           return $self->print_warning($msg->maketext("Sie haben keine E-Mail Adresse eingegeben"));
        }else{
          $result_ref->{reason} = $reason;
	      $result_ref->{errorcode} = $code;
	      return $self->print_json($result_ref);   
        }
    }

    if (!$user->user_exists($username)) {
        my $code   = -2;
	    my $reason = "Dieser Nutzer ist nicht registriert.";
        if ($self->param('representation') eq "html"){
             return $self->print_warning($msg->maketext("Dieser Nutzer ist nicht registriert."));
        }else{
          $result_ref->{reason} = $reason;
	      $result_ref->{errorcode} = $code;
	      return $self->print_json($result_ref);   
        }
    }

    # Zufaelliges 12-stelliges Passwort
    my $password = join '', map { ("a".."z", "A".."Z", 0..9)[rand 62] } 1..12;
    
    # Set new password

    my $userid = $user->get_userid_for_username($username, $view);

    if ($userid > 0){
	  $user->set_password({ userid => $userid, password => $password });
	  $user->reset_login_failure({ userid => $userid});
    }else {
      my $code   = -3;
	  my $reason = "Dieser Nutzer ist in diesem Portal nicht registriert.";
      if ($self->param('representation') eq "html"){
        return $self->print_warning($msg->maketext("Dieser Nutzer ist in diesem Portal nicht registriert."));
      }else{
        $result_ref->{reason} = $reason;
	    $result_ref->{errorcode} = $code;
	    return $self->print_json($result_ref);   
      }
    }
    
    $result_ref->{success} = 1;
    my $anschreiben="";
    my $afile = "an." . $$;
    
    my $mainttdata = {
        username  => $username,
        password  => $password,
        user      => $user,
        msg       => $msg,
    };
    
    my $maintemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #         ABSOLUTE      => 1,
        #         INCLUDE_PATH  => $config->{tt_include_path},
        # Es ist wesentlich, dass OUTPUT* hier und nicht im
        # Template::Provider definiert wird
        RECURSION      => 1,
        OUTPUT_PATH   => '/tmp',
        OUTPUT        => $afile,
    });
    
    $maintemplate->process($config->{tt_users_passwords_mail_body_tname}, $mainttdata ) || do {
        $logger->error($maintemplate->error());
        $self->header_add('Status',400); # Server Error
        return;
    };
    
    my $mailmsg = MIME::Lite->new(
        From            => $config->{contact_email},
        To              => $username,
        Subject         => $msg->maketext("Neues Passwort"),
        Type            => 'multipart/mixed'
    );
    
    my $anschfile="/tmp/" . $afile;
    
    $mailmsg->attach(
        Type            => 'TEXT',
        Encoding        => '8bit',
        #Data            => $anschreiben,
        Path            => $anschfile,
    );
    
    $mailmsg->send('sendmail', "/usr/lib/sendmail -t -oi -f$config->{contact_email}");
    
    
    my $ttdata={
    };
    if ($self->param('representation') eq "html"){
        # TODO GET?
        $self->header_add('Content-Type' => 'text/html');
        return $self->print_page($config->{tt_users_passwords_success_tname},$ttdata);
    }
    else {
	  return $self->print_json($result_ref);
    }
}

sub get_input_definition {
    my $self=shift;
    
    return {
        username => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
     };
}

1;
