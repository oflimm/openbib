####################################################################
#
#  OpenBib::Mojo::Controller::Connector::Cover
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

package OpenBib::Mojo::Controller::Connector::Cover;

use strict;
use warnings;
no warnings 'redefine';

use Business::ISBN;
use Benchmark;
use DBI;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Mojo::UserAgent;
use Template;
use XML::LibXML;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub process_vlb {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->param('id');
    
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

    my $client_ip="";
    if ($r->headers->header('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $size         = $r->param('size')              || 's';

    my $redirect_url = "/images/openbib/no_img.png";

    # Notloesung, wenn 'falsche' Cover bei der Anzeige gemeldet werden:
    # Nachweislich problematische ISBNs, z.B. mehrfach vom Verlag vergeben.
    my $isbn_is_invalid_ref = {
	'3453520130' => 1,
	    '3886800563'    => 1,
	    '3518067443'    => 1,
	    '3518065823'    => 1,
	    '0810103249'    => 1,
	    '9783931596453' => 1,
	    '3807701605'    => 1,
	    '9788841861998' => 1,
	    '3880100004'    => 1,
	    '3701707847'    => 1,
	    '9783774306073' => 1,
	    '3776612606'    => 1,
	    '3590290234'    => 1,
	    '3290234'       => 1,
	    '3170330489'    => 1,
    };
    
    my $isbn = $self->id2isbnX($id);
    
    if ($logger->is_debug){
        $logger->debug("ISBN von ID $id: ".YAML::Dump($isbn));
    }

    # Kein Cover bei 'problematischen' ISBNs
    if (defined $isbn_is_invalid_ref->{$isbn->{isbn10}} || defined $isbn_is_invalid_ref->{$isbn->{isbn13}}){
	$logger->debug("Kein Cover zur ISBN $id");
	return $self->redirect($redirect_url);
    }
    
    my $api_config_ref = $config->{'covers'}{'vlb'};

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($api_config_ref));
    }
    
    if ($isbn->{isbn13}){
        my $ua       = Mojo::UserAgent->new();

	$ua->transactor->name($api_config_ref->{'agent_id'});
	$ua->connect_timeout(10);
	$ua->max_redirects(2);

	my $headers_ref = {};
        $headers_ref->{'X-Forwarded-For'} = $client_ip if ($client_ip);

        my $url      = $api_config_ref->{'api_url'}."/".$isbn->{isbn13}."/$size?access_token=".$api_config_ref->{'api_token'};

	$logger->info("Trying to get cover from $url");

	my $response_p = $ua->get_p($url => $headers_ref);

	$response_p->then( sub {
	    my $response = shift;
	    
	    if ( $response->is_error() ) {
		$logger->info("ISBN $isbn->{isbn13} NOT found in VLB");
		$logger->debug("Error-Code:".$response->code());
		$logger->debug("Fehlermeldung:".$response->message());
		$self->redirect($redirect_url);
	    }
	    else {
		$logger->info("ISBN $isbn->{isbn13} found in VLB");
		$self->res->headers->content_type('image/jpeg');
		$self->render( data => $response->content());
	    }
			   
	    $self->redirect($redirect_url);
			   })->catch(sub {
			       return $self->redirect($redirect_url);
				     })->wait;
    }

    return $self->redirect($redirect_url);
}

sub id2isbnX {
    my ($self,$id) = @_;

    my $normalizer = $self->stash('normalizer');

    my $isbn13="";
    my $isbn10="";
        
    # Ist es eine ISBN? Dann Normierung auf ISBN10/13
    my $isbnXX     = Business::ISBN->new($id);
    
    if (defined $isbnXX && $isbnXX->is_valid){
        $isbn13 = $isbnXX->as_isbn13->as_string;
        $isbn10 = $isbnXX->as_isbn10->as_string;
        
        $isbn13 = $normalizer->normalize({
            field => 'T0540',
            content  => $isbn13,
        });
        
        $isbn10 = $normalizer->normalize({
            field => 'T0540',
            content  => $isbn10,
        });
    }

    return {
        isbn13 => $isbn13,
        isbn10 => $isbn10,
    };        
}
    
1;
