#####################################################################
#
#  OpenBib::Authenticator::Backend::LDAP
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

package OpenBib::Authenticator::Backend::LDAP;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(OpenBib::Authenticator);

use Cache::Memcached::Fast;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use Net::LDAPS;
use SOAP::Lite;
use Storable ();
use YAML::Syck;

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
	$logger->error("No Viewid found: ".$@);

	return $userid;
    }

    my $authenticator_config;
    
    eval {
	$authenticator_config = $config->{authenticator}{ldap}{$self->get('name')};
    };

    if ($logger->is_debug){
	$logger->debug("No config found for ".$self->get('name'));
    }

    return 0 unless ($authenticator_config);

    my @ldap_parameters = ($authenticator_config->{hostname});

    foreach my $parameter ('scheme','port','verify','timeout','onerror','cafile'){
	push @ldap_parameters, ($parameter,$authenticator_config->{$parameter}) if ($authenticator_config->{$parameter});

    }

    if ($logger->is_debug){
	$logger->debug("Using Parameters ".YAML::Dump(\@ldap_parameters));
    }
    
    my $ldaps ;

    eval {
	$ldaps = Net::LDAPS->new(@ldap_parameters);
    };

    if ($@){
	$logger->error("LDAP-Fehler: ".$@);

	return 0;
    }

    my $success = 0;
    
    if (defined $ldaps) {
	my $admindn = $authenticator_config->{admindn};
	my $adminpw = $authenticator_config->{adminpw};
	
	my $mesg = $ldaps->bind(
	    $admindn, 
	    password => "$adminpw"
	    );

	if ($mesg && $mesg->code() == 0){
	    if ($logger->is_debug){
		$logger->debug("Authenticator LDAP: OK");
		$logger->debug("Returned: ".YAML::Dump($mesg));
	    }

	    my $result = $ldaps->search(
		base   => "",
		filter => "(dn=$userdn)",
		);

	    if ($result && $result->code){
		$logger->error("Error searching userdn $userdn: ".$result->error );
	    }

	    if ($result){
		foreach my $entry ($result->entries) {
		    $logger->debug(YAML::Dump($entry));
		}
	    }
	    $success = 1;
	}
	else {
	    $logger->debug("Received error ".$mesg->code().": ".$mesg->error());
	} 
    }
    else {
	$logger->error("LDAPS object NOT created");
	return 0;
    }
    
    
    $logger->debug("Authentication via LDAP done");
    
    if (!$success) {
	return -2;
    }
    
    # Gegebenenfalls Benutzer lokal eintragen
    $logger->debug("Get/Save new user");

    my $user = new OpenBib::User;
    
    # Eintragen, wenn noch nicht existent
    # OLWS-Kennungen werden NICHT an einen View gebunden, damit mit der gleichen Kennung verschiedene lokale Bibliothekssysteme genutzt werden koennen - spezifisch fuer die Universitaet zu Koeln
    if (!$user->user_exists_in_view({ username => $username, authenticatorid => $self->get('id'), viewid => $viewid })) {
	# Neuen Satz eintragen
	$userid = $user->add({
	    username        => $username,
	    hashed_password => undef,
	    authenticatorid => $self->get('id'),
	    viewid          => $viewid,
			     });
	
	$logger->debug("User added with new id $userid");
    }
    else {
	my $local_user = $config->get_schema->resultset('Userinfo')->search_rs(
	    {
		username        => $username,
		viewid          => $viewid,
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
    }
    
    return $userid;
}

1;
__END__

=head1 NAME

OpenBib::Authenticator::Backend::LDAP - Backend zur Authentifizierung an der Eigenen Nutzerdatenbank nach Selbstregistrierung

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
