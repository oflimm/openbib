#####################################################################
#
#  OpenBib::Login::Util
#
#  Dieses File ist (C) 2004-2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Login::Util;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Reload;
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config=\%OpenBib::Config::config;

sub authenticate_self_user {
    my ($arg_ref) = @_;

    # Set defaults
    my $username            = exists $arg_ref->{username}
        ? $arg_ref->{username}            : undef;
    my $pin                 = exists $arg_ref->{pin}
        ? $arg_ref->{pin}                 : undef;
    my $userdbh             = exists $arg_ref->{userdbh}
        ? $arg_ref->{userdbh}             : undef;
    my $sessionID           = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $userresult=$userdbh->prepare("select userid from user where loginname = ? and pin = ?") or $logger->error($DBI::errstr);
  
    $userresult->execute($username,$pin) or $logger->error($DBI::errstr);

    my $res=$userresult->fetchrow_hashref();

    my $userid = decode_utf8($res->{'userid'});

    $userresult->finish();

    return (defined $userid)?$userid:-1;
}

sub authenticate_olws_user {
    my ($arg_ref) = @_;

    # Set defaults
    my $username            = exists $arg_ref->{username}
        ? $arg_ref->{username}            : undef;
    my $pin                 = exists $arg_ref->{pin}
        ? $arg_ref->{pin}                 : undef;
    my $circcheckurl        = exists $arg_ref->{circcheckurl}
        ? $arg_ref->{circcheckurl}        : undef;
    my $circdb              = exists $arg_ref->{circdb}
        ? $arg_ref->{circdb}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $soap = SOAP::Lite
        -> uri("urn:/Authentication")
            -> proxy($circcheckurl);

    my $result = $soap->authenticate_user($username,$pin,$circdb);

    my %userinfo=();

    unless ($result->fault) {
        if (defined $result->result) {
            %userinfo = %{$result->result};
            $userinfo{'erfolgreich'}="1";
        }
        else {
            $userinfo{'erfolgreich'}="0";
        }
    }
    else {
        $logger->error("SOAP Authentication Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
    }
  
    return \%userinfo;
}

1;
