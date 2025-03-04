#####################################################################
#
#  OpenBib::Request
#
#  Dieses File ist (C) 2014 Oliver Flimm <flimm@ub.uni-koeln.de>
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

package OpenBib::Request;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Plack::Request);

use Log::Log4perl qw(get_logger :levels);
use Encode qw/encode_utf8 decode_utf8/;
use YAML::Syck;
use CGI::Cookie;
use URI::Escape;

sub psgi_header {
    my($self, @header_props) = @_;

    my $logger = get_logger();

    if ($logger->is_debug){
        $logger->debug("IN-header: ".YAML::Syck::Dump(\@header_props));
    }
    
    my @headers;
    
    my $status = 200;

    for (my $i = 0; $i < @header_props; $i += 2) {
        my $header = $header_props[$i];
        my $value  = $header_props[$i+1];

        next unless ($header && $value);
        
        if ($header =~m/Status/i){
            $status = $value;
            if ($logger->is_debug){
                $logger->debug("Got Status $value");
            }
        }
        elsif ($header =~m/type/i){
            push @headers, "Content-Type", $value;
        }
        elsif ($header =~m/Set-Cookie/i){
            my(@cookie) = ref($value) && ref($value) eq 'ARRAY' ? @{$value} : $value;
            for (@cookie) {
                my $cs = UNIVERSAL::isa($_,'CGI::Cookie') ? $_->as_string : $_;
                push @headers, "Set-Cookie", $cs if $cs ne '';
            }
        }
        else {
            push @headers, $header, $value;
        }

    }

    if ($logger->is_debug){
        $logger->debug("OUT-status: $status - header: ".YAML::Syck::Dump(\@headers));
    }
    
    return ($status,\@headers);
}

sub psgi_redirect {
    my($self, @header_props) = @_;

    my $logger = get_logger();

    if ($logger->is_debug){
        $logger->debug("IN-header: ".YAML::Syck::Dump(\@header_props));
    }
    
    my $default_status   = 302;

    # Nur ein Element, dann Location setzen
    if ($#header_props == 0){
        my $location = shift @header_props;
        push @header_props, "Location", $location;
    }

    my $have_status = 0;
    for (my $i = 0; $i < @header_props; $i += 2) {
        my $header = $header_props[$i];

        if ($header =~m/Status/i){
            $have_status = 1;
        }
    }

    if (!$have_status){
        push @header_props, "Status", $default_status
    }

    if ($logger->is_debug){
        $logger->debug("OUT-have_status: $have_status - header: ".YAML::Syck::Dump(\@header_props));
    }
    
    return $self->psgi_header(@header_props);
}

sub args {
    my $self = shift;

    my @parameters = ();
    foreach my $param ($self->parameters->keys){
        foreach my $value ($self->parameters->get_all($param)){
            push @parameters, "$param=$value";
        }
    }

    return join('&',@parameters);
}

sub escaped_args {
    my $self = shift;

    my @parameters = ();
    foreach my $param ($self->parameters->keys){
        foreach my $value ($self->parameters->get_all($param)){
            push @parameters, "$param=".uri_escape_utf8(decode_utf8($value));
        }
    }

    return join('&',@parameters);
}

sub get_server_name {
    my $self = shift;

    my $logger = get_logger();

    my ($hostname) = $self->uri =~m/http.*:\/\/(.+?)\//;

    $logger->debug($hostname);
        
    return $hostname;
}

sub remote_host {
    my $self = shift;

    my $logger = get_logger();

    my ($hostname) = $self->SUPER::remote_host =~m/(\d+\.\d+\.\d+\.\d+)/;

    $logger->debug($hostname);
        
    return $hostname;
}

sub get_basic_auth_credentials {
    my $self = shift;

    my $env = $self->env;
    
    my $auth = $env->{HTTP_AUTHORIZATION}
        or return (404,'','');
    
    if ($auth =~ /^Basic (.*)$/i) {
        my($user, $pass) = split /:/, (MIME::Base64::decode($1) || ":"), 2;

        if (defined $pass && $pass){
            return (200,$user,$pass);
        }
    }

    return (401,'','');        
}

sub print {
    my $self   = shift;
    my $string = join('',@_);

    my $logger = get_logger();

    $logger->debug("Input $string");
    
    if (!defined $self->{_openbib_print_buffer}){
        $self->{_openbib_print_buffer} = [];
    }

    push @{$self->{_openbib_print_buffer}}, $string;
    
    return;
}
    
sub print_buffer {
    my $self = shift;

    my $logger = get_logger();

    if (!defined $self->{_openbib_print_buffer}){
        $self->{_openbib_print_buffer} = [];
    }

    return join('',@{$self->{_openbib_print_buffer}});
}

1;
__END__

=head1 NAME

OpenBib::Request - Request-Objekt

=head1 DESCRIPTION

Dieses Objekt enthalt das PSGI-Request als abgeleitete Klasse von Plack::Request und fuegt die fuer den
PSGI-Support notwendigen Methoden psgi_header und psgi_redirect.

=head1 SYNOPSIS

 use OpenBib::Request;

 my $r = OpenBib::Request->new($env);

 # Zugriff auf Request-Variablen
 my $foo        = $r->param('foo'); # foo-Parameter
 my $method     = $r->method;       # HTTP-Methode


=head1 METHODS

=over 4

=item new

Erzeugung des Objektes

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@ub.uni-koeln.de>

=cut
