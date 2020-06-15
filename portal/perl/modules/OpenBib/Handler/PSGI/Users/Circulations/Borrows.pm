#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Circulations::Borrows
#
#  Dieses File ist (C) 2004-2013 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Users::Circulations::Borrows;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Digest::MD5;
use Email::Valid;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Socket;
use Template;
use URI::Escape;
use JSON::XS qw/encode_json decode_json/;
use LWP::UserAgent;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI::Users';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_record'           => 'show_record',
        'renew_loans'           => 'renew_loans',
        'show_collection'       => 'show_collection',
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
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
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
    my $scheme         = $self->param('scheme');
    my $servername     = $self->param('servername');

    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});

    if (!$self->authorization_successful || $database ne $sessionauthenticator){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }
    
    my ($loginname,$password,$access_token) = $user->get_credentials();

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->new;

    my $circexlist=undef;

    my $url = $scheme."://".$servername.$path_prefix."/".$config->get('databases_loc')."/id/".$sessionauthenticator."/paia/core/".uri_escape($loginname)."/items";

    my $ua = LWP::UserAgent->new();
    $ua->agent('USB Koeln/1.0');
    $ua->timeout(30);

    my $paia_failure = 0;
    
    eval {
	if ($logger->is_debug()){
	    $logger->debug("Request URL: $url");
	}
	
	my $response = $ua->get($url,
				'Authorization' => "Bearer $access_token",
	    );
	
	
	if ($logger->is_debug){
	    $logger->debug("Response: ".$response->content);
	}
	
	if (!$response->is_success) {
	    $logger->info($response->code . ' - ' . $response->message);
	    return;
	}

	$circexlist = decode_json $response->content;
	
	if ($logger->is_debug){
	    $logger->debug("PAIA Result: ".YAML::Dump($circexlist));
	}
    };
    
    if ($@){
	$logger->error("PAIA-Target $url konnte nicht erreicht werden :".$@);
    }
    
    my $authenticator = $session->get_authenticator;

    my $itemlist_ref = [];

    foreach my $this_item (@$circexlist){
	push @$itemlist_ref, $this_item if ($this_item->{status} == 3);
    }
    
    # TT-Data erzeugen
    my $ttdata={
        authenticator => $authenticator,
        loginname  => $loginname,
        password   => $password,
        
        borrows    => $itemlist_ref,
        
        database   => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_borrows_tname},$ttdata);
}


1;
__END__

=head1 NAME

OpenBib::Circulation - Benutzerkonto

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs bietet dem Benutzer des 
Suchportals einen Einblick in das jeweilige Benutzerkonto und gibt
eine Aufstellung der ausgeliehenen, vorgemerkten sowie ueberzogenen
Medien.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
