#####################################################################
#
#  OpenBib::Authenticator::Backend::SelfRegistration
#
#  Dieses File ist (C) 2019 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Authenticator::Backend::SelfRegistration;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(OpenBib::Authenticator);

use Cache::Memcached::Fast;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use Storable ();

use OpenBib::Config;
use OpenBib::Config::File;

sub authenticate {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $viewname    = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}       : undef;
    
    my $username    = exists $arg_ref->{username}
        ? $arg_ref->{username}       : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}       : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($userid,$viewid) = (0,0);

    my $config = $self->get_config;

    eval {
	$viewid = $config->get_viewinfo->single({ viewname => $viewname })->id;
    };

    if ($@){
	$logger->error($@);

	return $userid;
    }
    
    # DBI: "select userid from user where username = ? and password = ?"
    my $authentication = $config->get_schema->resultset('Userinfo')->search_rs(
        {
            username        => $username,
	    viewid          => $viewid,
	    authenticatorid => $self->{id},
        },
        {
            select => ['id', \"me.password  = crypt('$password',me.password)"],
            as     => ['thisid','is_authenticated'],
        }
            
    )->first;
    
    if ($authentication && $authentication->get_column('is_authenticated')){
        $userid = $authentication->get_column('thisid');
    }
    else { # Fallback ohne View
       $authentication = $config->get_schema->resultset('Userinfo')->search_rs(
           {
               username        => $username,
	       viewid          => undef,
	       authenticatorid => $self->{id},
           },
           {
               select => ['id', \"me.password  = crypt('$password',me.password)"],
               as     => ['thisid','is_authenticated'],
           }
        )->first;

       if ($authentication && $authentication->get_column('is_authenticated')){
           $userid = $authentication->get_column('thisid');
       }
    }

    $logger->debug("Got Userid $userid");

    return $userid;    
}

1;
__END__

=head1 NAME

OpenBib::Authenticator::Backend::SelfRegistration - Backend zur Authentifizierung an der Eigenen Nutzerdatenbank nach Selbstregistrierung

=head1 DESCRIPTION

Dieses Backend stellt die Methode authenticate zur Authentifizierung eines Nutzer an der lokalen Nutzerdatenbank bereit

=head1 SYNOPSIS

 use OpenBib::Authenticator::Factory;

 my $authenticator = OpenBib::Authenticator::Factory->create_authenticator(1);

 my $userid = $authenticator->authenticate({ viewname => 'kug', username => 'abc', password => '123' });

 if ($userid > 0){
    # Erfolgreich authentifiziert und Userid in $userid gespeichert
 }
 else {
    # $userid ist Fehlercode
 }


=head1 METHODS

=over 4

=item new

Erzeugung des Objektes

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Der Verzicht auf den Exporter 
bedeutet weniger Speicherverbrauch und mehr Performance auf 
Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut