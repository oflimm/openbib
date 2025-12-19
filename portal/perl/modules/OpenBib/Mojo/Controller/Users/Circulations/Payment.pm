#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Circulations::Payment
#
#  Dieses File ist (C) 2025- Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Users::Circulations::Payment;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Crypt::JWT qw(decode_jwt encode_jwt);
use Date::Manip qw/ParseDate UnixDate ParseDateDelta/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;
use URI::Escape qw(uri_unescape);

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection' => 'show_collection',
    );
}

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
    my $lang           = $self->stash('lang');
    my $servername     = $self->stash('servername');
   
    if (!$self->authorization_successful || $userid ne $user->{ID}){
	return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
    }
    
    my $userinfo_ref = $user->get_info($user->{ID});
    my $payment_ref  = $config->get('payment');
    
    my $external_id  = $userinfo_ref->{external_id};

    my $return_url = "https://$servername$path_prefix/$config->{users_loc}/id/$user->{ID}/circulations.html?l=$lang";
    
    my $payload = {
	language    => $lang,
	user        => $external_id,
	return_url  => $return_url,
	institution => $payment_ref->{institution}
    };
       
    my $jwt =  encode_jwt(payload => $payload, alg =>'HS256', key => $payment_ref->{secret}, auto_iat => 1, relative_exp => 300, relative_nbf => 0);

    my $payment_url = $payment_ref->{base_url}."?apikey=$payment_ref->{apikey}&jwt=$jwt";

    my $ttdata={
	userinfo        => $userinfo_ref,
	payload         => $payload,
	payment_url     => $payment_url,
    };
    
    return $self->print_page($config->{tt_users_circulations_payment_tname},$ttdata);
}

1;
__END__

=head1 NAME

OpenBib::Users::Circulations::Payment - Elektronische Bezahlung angefallener Gebühren

=head1 DESCRIPTION

Das Modul OpenBib::Users::Circulations::Payment stellt einen Dienst
zur verfuegung, um fuer Nutzer eine elektronische Bezahlung
angefallener Gebühren über eine Payment Service Provider (PSP) zu ermöglichen.

Sie spricht dafür eine Middleware des Hochschulbibliothekszentrums NRW
(hbz) an, die die Abwicklung der Zahlung und Verbuchung im
Bibliothekssystem Alma durchführt.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
