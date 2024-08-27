#####################################################################
#
#  OpenBib::Authenticator::OLWS
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

package OpenBib::Authenticator::Backend::OLWS;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(OpenBib::Authenticator);

use Cache::Memcached::Fast;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use SOAP::Lite;
use Storable ();
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Config::File;
use OpenBib::Config::CirculationInfoTable;

sub authenticate {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $username    = exists $arg_ref->{username}
        ? $arg_ref->{username}       : undef;

    my $password    = exists $arg_ref->{password}
        ? $arg_ref->{password}       : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $userid = 0;

    my $config = $self->get_config;

    my $olwsconfig = ($config->get('olws')->{$config->{authenticator}{olws}{$self->get('name')}{dbname}})?$config->get('olws')->{$config->{authenticator}{olws}{$self->get('name')}{dbname}}:$config->get('olws')->{'default'};

#    my $circcheckurl  = $circinfotable->get($config->{authenticator}{olws}{$self->get('name')}{dbname})->{circcheckurl};
#    my $circdb        = $circinfotable->get($config->{authenticator}{olws}{$self->get('name')}{dbname})->{circdb};

    my $circcheckurl  = $olwsconfig->{circwsurl};
    my $circdb        = $olwsconfig->{circdb};
	
    if ($logger->is_debug){
	$logger->debug("Trying to authenticate via OLWS: ".YAML::Dump($olwsconfig));
    }

    my %userinfo=();

    eval {
        my $soap = SOAP::Lite
            -> uri("urn:/Authentication")
	    -> proxy($circcheckurl);
        
        my $result = $soap->authenticate_user(
            SOAP::Data->name(parameter  =>\SOAP::Data->value(
				 SOAP::Data->name(username => $username)->type('string'),
				 SOAP::Data->name(password => $password)->type('string'),
				 SOAP::Data->name(database => $circdb)->type('string')))
	    );
        
        if ($logger->is_debug){
            $logger->debug("Result: ".YAML::Dump($result->result));
        }
        
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
	    return 0;
        }
        
    };
    
    $logger->debug("Authentication via OLWS done");
    
    if ($userinfo{'erfolgreich'} ne "1") {
	return -2;
    }
    
    # Gegebenenfalls Benutzer lokal eintragen
    $logger->debug("Save new user");

    my $user = new OpenBib::User;
    
    # Eintragen, wenn noch nicht existent
    # OLWS-Kennungen werden NICHT an einen View gebunden, damit mit der gleichen Kennung verschiedene lokale Bibliothekssysteme genutzt werden koennen - spezifisch fuer die Universitaet zu Koeln
    if (!$user->user_exists_in_view({ username => $username, authenticatorid => $self->get('id'), viewid => undef })) {
	# Neuen Satz eintragen

	my $userinfo_ref = {
	    username        => $username,
	    authenticatorid => $self->get('id'),
	    viewid          => undef,
	};

	if ($config->get('cache_external_password_for_ugc_migration')){
	    $userinfo_ref->{'password'} = $password;
	}
	else {
	    $userinfo_ref->{'hashed_password'} = undef;
	}

	$userid = $user->add($userinfo_ref);
	
	$logger->debug("User added with new id $userid");
    }
    else {
	my $local_user = $config->get_schema->resultset('Userinfo')->search_rs(
	    {
		username        => $username,
		viewid          => undef,
		authenticatorid => $self->get('id'),
	    },
	    {
		select => ['id'],
		as     => ['thisid'],
	    }
	    )->first;
	
       if ($local_user){
           $userid = $local_user->get_column('thisid');
       }

	$logger->debug("User exists with id $userid");
	
    }
    
    # Benuzerinformationen eintragen
    $user->set_private_info($userid,\%userinfo);
    
    $logger->debug("Updated private user info");

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
