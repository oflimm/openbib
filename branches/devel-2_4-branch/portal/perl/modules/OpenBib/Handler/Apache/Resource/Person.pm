#####################################################################
#
#  OpenBib::Handler::Apache::Resource::Person.pm
#
#  Copyright 2009-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Resource::Person;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Record::Person;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show' => 'show',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;
    my $r    = $self->param('r');

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $personid       = $self->param('personid');

    my $config  = OpenBib::Config->instance;
    
    # Mit Suffix, dann keine Aushandlung des Typs
    
    my $representation = "";
    my $content_type   = "";
    
    my $id             = "";
    if ($personid=~/^(.+?)(\.html|\.json|\.rdf|\.include)$/){
        $id            = $1;
        ($representation) = $2 =~/^\.(.+?)$/;
        $content_type   = $self->param('config')->{'content_type_map_rev'}{$representation};
    }
    # Sonst Aushandlung
    else {
        $id = $personid;
        my $negotiated_type_ref = $self->negotiate_type;

        my $new_location = "$config->{base_loc}/$view/$config->{resource_person_loc}/$database/$id.$negotiated_type_ref->{suffix}";

        $self->query->method('GET');
        $self->query->content_type($negotiated_type_ref->{content_type});
        $self->query->headers_out->add(Location => $new_location);
        $self->query->status(Apache2::Const::REDIRECT);
        
        $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $new_location");

        return;
    }
    
    if ($database && $id ){ # Valide Informationen etc.
        $logger->debug("Key: $id - DB: $database - ID: $id");

        OpenBib::Record::Person->new({database => $database, id => $id})
              ->load_full_record->print_to_handler({
                  apachereq          => $r,
                  representation     => $representation,
                  content_type       => $content_type,
                  view               => $view,
              });
    }

    return Apache2::Const::OK;
}

1;
