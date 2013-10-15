#####################################################################
#
#  OpenBib::Handler::Apache::Locations.pm
#
#  Copyright 2009-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Locations;

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
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'                      => 'show_collection',
        'show_record'                          => 'show_record',
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

    # Dispatched Args
    my $view           = $self->param('view');

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

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $locationlist_ref = $config->get_locationinfo_overview;
    
    # TT-Data erzeugen
    my $ttdata={
        queryoptions_ref => $queryoptions->get_options,
        dbinfo           => $dbinfotable,
        locations        => $locationlist_ref,
    };
    
    $self->print_page($config->{tt_locations_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $locationid     = $self->strip_suffix($self->param('locationid'));

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

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    if ( $locationid ){ # Valide Informationen etc.
        my $search_args_ref = {};
        
        if ($locationid){
            $logger->debug("Id: $locationid");
                    
            $search_args_ref->{identifier} = $locationid;
        }
        
        my $locationinfo = $config->get_locationinfo->single({identifier => $locationid});
        
        my $locationinfo_ref = {};
        
        if ($locationinfo){
            $locationinfo_ref = {
                id          => $locationinfo->id,
                identifier  => $locationinfo->identifier,
                description => $locationinfo->description,
                type        => $locationinfo->type,
                fields      => $config->get_locationinfo_fields($locationid),
            };

            if ($logger->is_debug){
                $logger->debug("Found record:".YAML::Dump($locationinfo_ref));
            }

        }
        else {
            $logger->info("Can't find location with id $locationid")
        }
                
        my $ttdata = {
            locationid     => $locationid,
            locationinfo   => $locationinfo_ref,
            dbinfo         => $dbinfotable,
        };

        $self->print_page($config->{tt_locations_record_tname},$ttdata);

    }
    else {
        $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit einer Id spezifiziert."));
    }


    return Apache2::Const::OK;
}

1;
