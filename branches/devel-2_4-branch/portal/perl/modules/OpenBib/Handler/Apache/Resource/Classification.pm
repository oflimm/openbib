#####################################################################
#
#  OpenBib::Handler::Apache::Resource::Classification.pm
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

package OpenBib::Handler::Apache::Resource::Classification;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Record::Classification;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_record');
    $self->run_modes(
        'show_record' => 'show_record',
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
    my $view             = $self->param('view');
    my $database         = $self->param('database');
    my $classificationid = $self->strip_suffix($self->param('classificationid'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $stid          = $query->param('stid')     || '';
    my $callback      = $query->param('callback') || '';
    my $lang          = $query->param('lang')     || $queryoptions->get_option('l') || 'de';
    my $format        = $query->param('format')   || 'full';
    my $no_log         = $query->param('no_log')  || '';

    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    my $searchquery   = OpenBib::SearchQuery->instance;

    if ($database && $classificationid ){ # Valide Informationen etc.
        $logger->debug("ID: $classificationid - DB: $database");
        
        my $record = OpenBib::Record::Classification->new({database => $database, id => $classificationid})->load_full_record;
        
        my $logintargetdb = $user->get_targetdb_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            database      => $database, # Zwingend wegen common/subtemplate
            dbinfo        => $dbinfotable,
            qopts         => $queryoptions->get_options,
            record        => $record,
            id            => $classificationid,
            format        => $format,
            searchquery   => $searchquery,
            activefeed    => $config->get_activefeeds_of_db($database),
            logintargetdb => $logintargetdb,
        };

        $self->print_page('tt_resource_classification_tname',$ttdata);

        # Log Event
        
        if (!$no_log){
            $session->log_event({
                type      => 13,
                content   => {
                    id       => $classificationid,
                    database => $database,
                },
                serialize => 1,
            });
        }
    }
    else {
        $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname/Id spezifiziert."));
    }

    return Apache2::Const::OK;
}

1;
