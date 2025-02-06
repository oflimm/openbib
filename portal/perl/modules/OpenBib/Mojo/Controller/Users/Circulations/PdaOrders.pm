#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Circulations::PdaOrders
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

package OpenBib::Mojo::Controller::Users::Circulations::PdaOrders;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Digest::MD5;
use Email::Valid;
use HTML::Entities qw/decode_entities/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Socket;
use Template;
use URI::Escape qw(uri_unescape);

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
    my $titleid        = $input_data_ref->{'titleid'};
    my $database       = $input_data_ref->{'database'};
    my $author         = $input_data_ref->{'author'};
    my $corporation    = $input_data_ref->{'corporation'};
    my $publisher      = $input_data_ref->{'publisher'};
    my $year           = $input_data_ref->{'year'};
    my $isbn           = $input_data_ref->{'isbn'};
    my $price          = $input_data_ref->{'price'};
    my $classification = $input_data_ref->{'classification'};
    my $reservation    = $input_data_ref->{'reservation'};
    my $receipt        = $input_data_ref->{'receipt'};
    my $confirm        = $input_data_ref->{'confirm'};
   
    unless ($config->get('active_pdaorder')){
	return $self->print_warning($msg->maketext("Der PDA-Dienst ist aktuell systemweit deaktiviert."));	
    }

    if ($logger->is_debug){
	$logger->debug("Input: ".YAML::Dump($input_data_ref));
    }
    
    unless ($database && $titleid){
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

    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_full_record;
    
    if ($confirm){
	$logger->debug("Showing pda orderform");
	
	# TT-Data erzeugen
	my $ttdata={
	    userinfo       => $userinfo_ref,
	    record         => $record,
	    database       => $database,
	    titleid        => $titleid,
	};
	
	return $self->print_page($config->{tt_users_circulations_check_pda_order_tname},$ttdata);
    }
    else {
	$logger->debug("Making pda order");

	unless ($accountname =~ m/^([ABCKRSTVW]|I00011011#7)/){
	    return $self->print_warning($msg->maketext("Ihre Benutzergruppe ist nicht für diese Funktion zugelassen."));
	}
		
	if (!$userinfo_ref->{email}){
	    return $self->print_warning("Zur Nutzung der Bestellung über den Buchhandel ist eine E-Mail-Adresse in Ihrem Bibliothekskonto erforderlich.");
	}
	
	if (!$titleid){
	    return $self->print_warning("Fehler bei der Übertragung der Datensatz-ID.");
	}
	
	# Wesentliche Informationen zur Identitaet des Bestellers werden nicht per Webformular entgegen genommen,
	# sondern aus dem Bibliothekskonto des Nutzers via $userinfo_ref.

	# Cleanup der URI und ggf. HTML-encodierten Inhalte
	eval {
	    $title       = decode_entities(uri_unescape($title)) if ($title);
	    $author      = decode_entities(uri_unescape($author)) if ($author);
	    $corporation = decode_entities(uri_unescape($corporation)) if ($corporation);
	    $publisher   = decode_entities(uri_unescape($publisher)) if ($publisher);
	};

	if ($@){
	    $logger->error($@);
	}
	
	if ($logger->is_debug){
	    $logger->debug("Title: $title - Author: $author - Corporation: $corporation - Publisher: $publisher - Classification: $classification");
	}
	
	# Production
	my $response_make_pda_order_ref = $ils->make_pda_order({ title => $title, titleid => $titleid, database => $database, author => $author, corporation => $corporation, publisher => $publisher, year => $year, isbn => $isbn, price => $price, classification => $classification, userid => $userinfo_ref->{username}, external_userid => $userinfo_ref->{external_id}, username => $userinfo_ref->{fullname}, reservation => $reservation, receipt => $receipt, email => $userinfo_ref->{email}});

	# Test
	# my $response_make_pda_order_ref = {
	#     successful => 1,
	# };
    	
	if ($logger->is_debug){
	    $logger->debug("Result make_order:".YAML::Dump($response_make_pda_order_ref));	
	}
	
	if ($response_make_pda_order_ref->{error}){
            return $self->print_warning($response_make_pda_order_ref->{error_description});
	}
	elsif ($response_make_pda_order_ref->{successful}){
	    # TT-Data erzeugen
	    my $ttdata={
		database   => $database,
		pda_order  => $response_make_pda_order_ref,
	    };
	    
	    return $self->print_page($config->{tt_users_circulations_make_pda_order_tname},$ttdata);
	    
	}		
    }
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
        author => {
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

OpenBib::Mojo::Controller::Users::Circulation::PdaOrders - Bestellungen im Buchhandel via PDA

=head1 DESCRIPTION

Mit diesem Handler werden Bestellungen im Buchhandel via PDA ermoeglicht.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
