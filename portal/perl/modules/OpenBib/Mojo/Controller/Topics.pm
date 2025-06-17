#####################################################################
#
#  OpenBib::Mojo::Controller::Topics
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

package OpenBib::Mojo::Controller::Topics;

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

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    my $topics_p = $user->get_topics_p;

    $topics_p->then(sub {
	my $topics_ref = shift;
	my $ttdata={
	    topics   => $topics_ref,
	};
    
	return $self->print_page($config->{tt_topics_tname},$ttdata);
		    });
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $topicid        = $self->strip_suffix($self->param('topicid'));

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    my $topic_p = $user->get_topic_p({ id => $topicid });

    $topic_p->then(sub {
	my $topic_ref = shift;
	
	my $ezb         = OpenBib::Catalog::Factory->create_catalog({database => 'ezb' });;
	my $dbis        = OpenBib::Catalog::Factory->create_catalog({database => 'dbis' });
	
	my $ttdata={
	    topic      => $topic_ref,
	    ezb        => $ezb,
	    dbis       => $dbis,
	};
	
	return $self->print_page($config->{tt_topics_record_tname},$ttdata);
		   });
}


    
1;
