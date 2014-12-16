####################################################################
#
#  OpenBib::Handler::Apache::Templates::Revisions.pm
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

package OpenBib::Handler::Apache::Templates::Revisions;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Apache2::Reload;
use Apache2::Request;
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
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_record'                => 'show_record',
        'show_collection'            => 'show_collection',
        'dispatch_to_representation' => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection {
    my $self = shift;

    my $templateid     = $self->param('templateid');
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->param('config');

    my $revisions_ref = $config->get_templateinforevision_overview($templateid);

    my $ttdata={                #
        templateid => $templateid,
        revisions  => $revisions_ref,
    };
    
    $self->print_page($config->{tt_templates_revisions_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $templateid     = $self->param('templateid');
    my $revisionid     = $self->strip_suffix($self->param('revisionid'));

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');

    my $revision_ref = $config->get_templateinforevision->search(
        {
            id => $revisionid,
        }
    )->single;

    unless ($revision_ref){
        $self->print_warning($msg->maketext("Es existiert keine Revision mit dieser ID"));
        
        return Apache2::Const::OK;
    }   
    
    my $ttdata={
        templateid => $templateid,
        revisionid => $revisionid,
        revision   => $revision_ref,
    };
    
    $self->print_page($config->{tt_templates_revisions_record_tname},$ttdata);

    return;
}

1;
