#####################################################################
#
#  OpenBib::Handler::Apache::Searchprofiles.pm
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

package OpenBib::Handler::Apache::Searchprofiles;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Record::Title;
use OpenBib::Template::Utilities;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_record');
    $self->run_modes(
        'show_record'             => 'show_record',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $profileid      = $self->strip_suffix($self->param('profileid'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang            = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');

    # CGI Args

    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    my @databases     = $config->get_databases_of_searchprofile($profileid);
    
    # TT-Data erzeugen
    my $ttdata={
        profileid   => $profileid,
        databases   => \@databases,
        dbinfo      => $dbinfotable,
    };

    $self->print_page($config->{tt_searchprofile_tname},$ttdata);

    $logger->debug("Done showing record");
    return Apache2::Const::OK;
}

1;
