#####################################################################
#
#  OpenBib::Handler::Apache::Databases.pm
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

package OpenBib::Handler::Apache::Databases;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Search::Backend::Xapian;
use OpenBib::Record::Title;
use OpenBib::Template::Utilities;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_record');
    $self->run_modes(
        'show_collection'         => 'show_collection',
        'show_popular'            => 'show_popular',
        'show_record'             => 'show_record',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->param('config');

    my $dbinfo_ref = $config->get_dbinfo_overview();
    
    my $ttdata={
        databases   => $dbinfo_ref,
    };
    
    $self->print_page($config->{tt_databases_tname},$ttdata);

    return Apache2::Const::OK;
}

sub show_popular {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->param('config');

    my $statistics     = OpenBib::Statistics->instance;
    
    my $dbinfo_ref = $config->get_dbinfo_overview();
    
    my $ttdata={
        statistics  => $statistics,
        databases   => $dbinfo_ref,
    };
    
    $self->print_page($config->{tt_databases_popular_tname},$ttdata);

    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $databaseid     = $self->strip_suffix($self->param('databaseid'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');

    # CGI Args

    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $databaseid})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
    };
    
    $self->print_page($config->{tt_databases_record_tname},$ttdata);

    $logger->debug("Done showing record");
    return Apache2::Const::OK;
}

1;
