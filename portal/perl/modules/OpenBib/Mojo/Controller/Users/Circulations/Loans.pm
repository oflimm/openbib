#####################################################################
#
#  OpenBib::Mojo::Controller::Users::Circulations::Loans
#
#  Dieses File ist (C) 2004-2022 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Users::Circulations::Loans;

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
use OpenBib::ILS::Factory;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

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
    my $scheme         = $self->stash('scheme');
    my $servername     = $self->stash('servername');

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

    my $page = $queryoptions->get_option('page') || 1;
    
    my $database = $sessionauthenticator ;
    
    my ($loginname,$password,$access_token) = $user->get_credentials();

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    if ($logger->is_debug){
	$logger->debug("Trying to get loans for user $loginname in ils for $database");
    }
    
    my $loans_ref = $ils->get_loans($loginname,$page);

    if ($logger->is_debug){
	$logger->debug("Got loans: ".YAML::Dump($loans_ref));
    }

    # Sortierung der Ausleihen nach Rueckgabedatum aufsteigend
    
    if (defined $loans_ref->{items} && @{$loans_ref->{items}}){
	my $loans_items = $loans_ref->{items};

	# my @sorted_loans_items = sort _by_enddate_asc @$loans_items;

	# $loans_ref->{items} = \@sorted_loans_items;

	$loans_ref->{items} = $loans_items;
    }
    
    my $authenticator = $session->get_authenticator;
    
    # TT-Data erzeugen
    my $ttdata={
        authenticator => $authenticator,
        loginname     => $loginname,
        password      => $password,
	
        loans         => $loans_ref,
        page          => $page,
	
        database      => $database,
    };
    
    return $self->print_page($config->{tt_users_circulations_loans_tname},$ttdata);
}

sub _by_enddate_asc {
    my %line1=%{$a};
    my %line2=%{$b};

    my $line1=(defined $line1{endtime} && $line1{endtime})?$line1{endtime}:"00.00.0000";
    my $line2=(defined $line2{endtime} && $line2{endtime})?$line2{endtime}:"00.00.0000";

    my ($day1,$month1,$year1)=$line1=~m/(\d\d)\.(\d\d)\.(\d\d\d\d)/;
    my ($day2,$month2,$year2)=$line2=~m/(\d\d)\.(\d\d)\.(\d\d\d\d)/;

    my $dateline1 = "$year1$month1$day1";
    my $dateline2 = "$year2$month2$day2";

    $dateline1 <=> $dateline2;
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
