#####################################################################
#
#  OpenBib::Mojo::Controller::Topics::Mappings
#
#  Dieses File ist (C) 2004-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Topics::Mappings;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Catalog::Factory;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Admin';

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view');
    my $topicid          = $self->param('topicid');

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');

    my $topic_ref = $user->get_topic({ id => $topicid});

    my $ttdata={
        topic    => $topic_ref,
    };
    
    return $self->print_page($config->{tt_topics_mappings_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view');
    my $topicid          = $self->param('topicid');
    my $mappingid        = $self->strip_suffix($self->param('mappingid'));

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');

    my $topic_ref = $user->get_topic({ id => $topicid});

    my $mapping = $self->get_mapping_by_id($mappingid);

    unless (defined $mapping) {
        return $self->print_warning($msg->maketext("Das Mapping ist nicht definiert."));
    }
    
    my $ttdata={
        topic      => $topic_ref,
        type       => $mappingid,
        mapping    => $mapping,
    };
    
    return $self->print_page($config->{tt_topics_mappings_record_tname},$ttdata);
}

sub get_mapping_by_id {
    my $self=shift;
    my $mappingid = shift;

    my $mapping = OpenBib::Catalog::Factory->create_catalog({database => $mappingid });
    
    return $mapping;
}

1;
