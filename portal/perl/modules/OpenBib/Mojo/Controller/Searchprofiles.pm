#####################################################################
#
#  OpenBib::Mojo::Controller::Searchprofiles.pm
#
#  Copyright 2011-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Searchprofiles;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Record::Title;
use OpenBib::Template::Utilities;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $config         = $self->stash('config');

    # CGI Args
    my $year           = $r->param('year');

    my $statistics  = new OpenBib::Statistics();

    my $ttdata={
        statistics => $statistics,
        year       => $year,
    };
    
    return $self->print_page($config->{tt_searchprofiles_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view            = $self->param('view');
    my $searchprofileid = $self->strip_suffix($self->param('searchprofileid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang            = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');

    # CGI Args

    my @databases     = $config->get_databases_of_searchprofile($searchprofileid);

    my $searchprofile = $config->get_searchprofile->single({ id => $searchprofileid});
    
    # TT-Data erzeugen
    my $ttdata={
        searchprofileid   => $searchprofileid,
        searchprofile     => $searchprofile,
        databases         => \@databases,
    };

    return $self->print_page($config->{tt_searchprofiles_record_tname},$ttdata);
}

1;
