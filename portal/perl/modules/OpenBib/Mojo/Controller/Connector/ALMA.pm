####################################################################
#
#  OpenBib::Mojo::Controller::Connector::ALMA
#
#  Endpunkt fuer ALMA Webhooks
#
#  Dieses File ist (C) 2023- Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Connector::ALMA;

use strict;
use warnings;
no warnings 'redefine';

use Benchmark;
use Digest::SHA qw(hmac_sha256_base64);
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use MIME::Base64;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::SearchQuery;
use OpenBib::Search::Factory;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

# Beschreibung Alma Webhooks: https://developers.exlibrisgroup.com/alma/integrations/webhooks/anatomy/
# Anlegen in Alma unter: Konfiguration -> Allgemein -> Externe Systeme -> Integrationsprofile
# SHA256 Digests in versch. Sprachen: https://www.jokecamp.com/blog/examples-of-creating-base64-hashes-using-hmac-sha256-in-different-languages/

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args

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

    my $signature      = $r->header('X-Exl-Signature') || '';
    my $body           = $r->content();

    unless ( $self->check_signature({ signature => $signature, body => $body })) {
    	$logger->error("No Challenge secret given");
    	$self->header_add( 'Status', 401 );    # Invalid Signature
    	return encode_json({ errorMessage => 'Invalid Signature'});
    }
    
    eval {
	if ($logger->is_debug){
	    $logger->debug("Webhook Result body: $body");
	    $logger->debug("Webhook Result: ".YAML::Dump(decode_json($body)));
	}
    };

    # No response content, just status 200    
    return;
}

sub challenge {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args

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

    # CGI Args
    my $challenge_secret = $r->param('challenge')     || '';

    unless ( $challenge_secret ) {
	$logger->error("No Challenge secret given");
	$self->header_add( 'Status', 406 );    # not acceptable
	return;
    }
    
    my $response_ref = { challenge => $challenge_secret };

    return encode_json $response_ref;
}

sub check_signature {
    my ($self,$args_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $signature = $args_ref->{signature} || '';
    my $body      = $args_ref->{body} || '';
    
    # Shared Args
    my $config    = $self->stash('config');

    my $secret = $config->get('alma')->{webhook_secret};
    
    $logger->debug("Webhook: Checking body $body with signature $signature");

    my $digest = hmac_sha256_base64($body, $secret);

    while (length($digest) % 4) {
	$digest .= '=';
    }
        
    $logger->debug("Digest is $digest");
    
    return ($digest eq $signature);
}

1;
