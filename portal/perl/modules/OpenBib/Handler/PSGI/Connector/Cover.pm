####################################################################
#
#  OpenBib::Handler::PSGI::Connector::Cover
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

package OpenBib::Handler::PSGI::Connector::Cover;

use strict;
use warnings;
no warnings 'redefine';

use Business::ISBN;
use Benchmark;
use DBI;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use Template;
use XML::LibXML;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('process_vlb');
    $self->run_modes(
        'vlb'        => 'process_vlb',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub process_vlb {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->param('id');
    
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

    my $client_ip="";
    if ($r->header('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $size           = $query->param('size')              || 's';
    
    my $isbn = $self->id2isbnX($id);

    if ($logger->is_debug){
        $logger->debug("ISBN von ID $id: ".YAML::Dump($isbn));
    }

    my $redirect_url = "/images/openbib/no_img.png";

    my $api_config_ref = $config->{'covers'}{'vlb'};

    if ($logger->is_debug){
	$logger->debug(YAML::Dump($api_config_ref));
    }
    
    if ($isbn->{isbn13}){
        my $ua       = LWP::UserAgent->new();

        $ua->agent($api_config_ref->{'agent_id'});
        $ua->default_header('X-Forwarded-For' => $client_ip) if ($client_ip);

        my $url      = $api_config_ref->{'api_url'}."/".$isbn->{isbn13}."/$size?access_token=".$api_config_ref->{'api_token'};

	$logger->info("Trying to get cover from $url");

        my $request  = HTTP::Request->new('GET', $url);
        my $response = $ua->request($request);

	my $redirect_url = "/images/openbib/no_img.png";
	
        if ( $response->is_error() ) {
            $logger->info("ISBN $isbn->{isbn13} NOT found in VLB");
            $logger->debug("Error-Code:".$response->code());
            $logger->debug("Fehlermeldung:".$response->message());
	    $self->redirect($redirect_url);
        }
        else {
	    $logger->info("ISBN $isbn->{isbn13} found in VLB");
	    $self->param('content_type','image/jpeg');
	    return $response->content();
        }
    }

    return '';
}

sub id2isbnX {
    my ($self,$id) = @_;

    my $isbn13="";
    my $isbn10="";
        
    # Ist es eine ISBN? Dann Normierung auf ISBN10/13
    my $isbnXX     = Business::ISBN->new($id);
    
    if (defined $isbnXX && $isbnXX->is_valid){
        $isbn13 = $isbnXX->as_isbn13->as_string;
        $isbn10 = $isbnXX->as_isbn10->as_string;
        
        $isbn13 = OpenBib::Common::Util::normalize({
            field => 'T0540',
            content  => $isbn13,
        });
        
        $isbn10 = OpenBib::Common::Util::normalize({
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
