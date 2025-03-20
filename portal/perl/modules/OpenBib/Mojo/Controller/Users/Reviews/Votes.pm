#####################################################################
#
#  OpenBib::Mojo::Controller::Reviews.pm
#
#  Copyright 2007-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Reviews;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;
use URI::Escape;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $reviewid       = $self->param('reviewid');

    # Shared Args
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $location       = $self->stash('location');
    
    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if ($input_data_ref == 1){
        return $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
    }

    if (! $user->{ID}){
        if ($self->stash('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning("Sie müssen sich authentifizieren, um diese Rezension zu beurteilen");
        }
    }

    $logger->debug("Vote abgeben fuer Review");

    my $status = $user->vote_for_review({
        reviewid  => $reviewid,
        rating    => $input_data_ref->{rating},
        username  => $user->get_username,
    });
    
    if ($status == 1){
        return $self->print_warning("Sie haben bereits diese Rezension beurteilt");
    }
    
    if ($self->stash('representation') eq "html"){
        return $self->return_baseurl;
    }
    
    return;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->stash('view');
    my $reviewid       = $self->stash('reviewid');
    my $path_prefix    = $self->stash('path_prefix');

    my $config         = $self->stash('config');

    my $new_location = "$path_prefix/$config->{reviews_loc}/id/$reviewid.html";

    # TODO GET?
    $self->res->headers->content_type('text/html');
    $self->redirect($new_location);

    return;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        rating => {
            default  => '3',
            encoding => 'none',
            type     => 'scalar',
        },
        
    };
}

1;
