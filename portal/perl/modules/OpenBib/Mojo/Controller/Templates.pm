####################################################################
#
#  OpenBib::Mojo::Controller::Templates.pm
#
#  Copyright 2014 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Templates;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use DBI;
use JSON::XS;
use Data::Pageset;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;
use URI::Escape;
use XML::RSS;

use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->stash('config');

    my $templateinfo_ref = $config->get_templateinfo_overview();

    my $ttdata={                # 
        templateinfos   => $templateinfo_ref,
    };
    
    return $self->print_page($config->{tt_templates_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $templateid     = $self->strip_suffix($self->param('templateid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');

    $logger->debug("Show Record $templateid");

    my $templateinfo_ref = $config->get_templateinfo->search_rs({ id => $templateid})->single;

    if (!$templateinfo_ref){
        $logger->error("Template $templateid couldn't be found.");
    }
    
    my $ttdata={
        templateinfo => $templateinfo_ref,
    };
    
    return $self->print_page($config->{tt_templates_record_tname},$ttdata);
}


1;
