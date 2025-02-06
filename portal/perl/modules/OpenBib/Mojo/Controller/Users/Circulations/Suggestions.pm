#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Circulations::Suggestions
#
#  Dieses File ist (C) 2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Users::Circulations::Suggestions;

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

use OpenBib::API::HTTP::JOP;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::ILS::Factory;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;
use JSON::XS qw/encode_json decode_json/;
use LWP::UserAgent;

use base 'OpenBib::Mojo::Controller::Users';

sub show_collection {
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
   
    unless ($config->get('active_suggestion')){
	return $self->print_warning($msg->maketext("Der Dienst für Neuanschaffungsvorschläge ist aktuell systemweit deaktiviert."));	
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    my $sessionuserid        = $user->get_userid_of_session($session->{ID});

    $self->stash('userid',$sessionuserid);
    
    if ($logger->debug){
	$logger->debug("Auth successful: ".$self->authorization_successful." - Authenticator: $sessionauthenticator");
    }
    
    if (!$self->authorization_successful || $userid ne $sessionuserid){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    my ($accountname,$password,$access_token) = $user->get_credentials();

    my $authenticator = $session->get_authenticator;

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $sessionauthenticator });
    
    my $userinfo_ref = $ils->get_userdata($accountname);

    # TT-Data erzeugen
    my $ttdata={
	userinfo       => $userinfo_ref,
    };
	
    return $self->print_page($config->{tt_users_circulations_suggestions_tname},$ttdata);
}

sub create_record {
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
    my $title          = $input_data_ref->{'title'};
    my $person         = $input_data_ref->{'person'};
    my $corporation    = $input_data_ref->{'corporation'};
    my $publisher      = $input_data_ref->{'publisher'};
    my $year           = $input_data_ref->{'year'};
    my $isbn           = $input_data_ref->{'isbn'};
    my $price          = $input_data_ref->{'price'};
    my $classification = $input_data_ref->{'classification'};
    my $reservation    = $input_data_ref->{'reservation'};
    my $receipt        = $input_data_ref->{'receipt'};
    my $remark         = $input_data_ref->{'remark'};
    my $confirm        = $input_data_ref->{'confirm'};
   
    unless ($config->get('active_suggestion')){
	return $self->print_warning($msg->maketext("Der Dienst für Neuanschaffungsvorschläge ist aktuell systemweit deaktiviert."));	
    }

    if ($logger->is_debug){
	$logger->debug("Input: ".YAML::Dump($input_data_ref));
    }
    
    unless ($title && $year && $publisher){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt"));
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    my $sessionuserid        = $user->get_userid_of_session($session->{ID});

    $self->stash('userid',$sessionuserid);
    
    if ($logger->debug){
	$logger->debug("Auth successful: ".$self->authorization_successful." - Authenticator: $sessionauthenticator");
    }
    
    if (!$self->authorization_successful || $userid ne $sessionuserid){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    my ($accountname,$password,$access_token) = $user->get_credentials();

    my $authenticator = $session->get_authenticator;

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $sessionauthenticator });
    
    my $userinfo_ref = $ils->get_userdata($accountname);

    my $email = $userinfo_ref->{email};
    
    if (!$email){
	return $self->print_warning("Für einen Anschaffungsvorschlag ist eine E-Mail-Adresse in Ihrem Bibliothekskonto erforderlich.");
    }

    if (!$title || !$person || !$year || !$publisher){
	return $self->print_warning("Bitte geben Sie alle Pflichtfelder ein.");
    }
    
    my $current_date = strftime("%d.%m.%Y, %H:%M Uhr", localtime);
    $current_date    =~ s!^\s!0!;

    # TT-Data erzeugen    
    my $ttdata={
        view         => $view,
	userinfo     => $userinfo_ref,
	current_date => $current_date,
	title        => $title,
	person       => $person,
	corporation  => $corporation,
	publisher    => $publisher,
	year         => $year,
	isbn         => $isbn,
	reservation  => $reservation,
	receipt      => $receipt,
	remark       => $remark,
	
        config       => $config,
        user         => $user,
        msg          => $msg,
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

    $maintemplate->process($config->{tt_users_circulations_suggestions_mail_body_tname}, $ttdata ) || do { 
        $logger->error($maintemplate->error());
        $self->header_add('Status',400); # server error
        return;
    };

    my $mail_to = $config->{mail}{realm}{suggestion}{recipient};
    
    # Fuer Tests erstmal deaktiviert...
    # if ($receipt){
    # 	$mail_to.=",$email";
    # }
    
    my $anschfile="/tmp/" . $afile;

    Email::Stuffer->to($mail_to)
	->from($config->{mail}{realm}{suggestion}{sender})
	->reply_to($email)
	->subject("Neuanschaffungsvorschlag")
	->text_body(read_binary($anschfile))
	->send;
    
    unlink $anschfile;
        
    return $self->print_page($config->{tt_users_circulations_suggestions_success_tname},$ttdata);

}

sub get_input_definition {
    my $self=shift;
    
    return {
        title => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        titleid => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        database => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        person => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        corporation => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        publisher => {
            default  => 0,
            encoding => 'utf8',
            type     => 'scalar',
        },
        year => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        isbn => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        price => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        classification => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        reservation => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        remark => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        receipt => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        confirm => {
            default  => 0,
            encoding => 'utf8',
            type     => 'scalar',
        },
    };
}

1;
__END__

=head1 NAME

OpenBib::Mojo::Controller::Users::Circulation::Suggestions - Anschaffungsvorschlaege

=head1 DESCRIPTION

Mit diesem Handler werden Bestellungen im Buchhandel via PDA ermoeglicht.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
