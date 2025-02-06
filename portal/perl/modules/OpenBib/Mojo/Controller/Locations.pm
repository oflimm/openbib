#####################################################################
#
#  OpenBib::Mojo::Controller::Locations.pm
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

package OpenBib::Mojo::Controller::Locations;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use Date::Manip;
use DBI;
use JSON::XS;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Session;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    my $locationlist_ref = $config->get_locationinfo_overview;
    
    # TT-Data erzeugen
    my $ttdata={
        queryoptions_ref => $queryoptions->get_options,
        locations        => $locationlist_ref,
    };
    
    return $self->print_page($config->{tt_locations_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $locationid     = $self->strip_suffix($self->param('locationid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    my $from = "";
    my $to   = "";

    if ( $locationid ){ # Valide Informationen etc.
        my $search_args_ref = {};
        
        if ($locationid){
            $logger->debug("Id: $locationid");
                    
            $search_args_ref->{identifier} = $locationid;
        }
        
        my $locationinfo = $config->get_locationinfo->single({identifier => $locationid});
        
        my $locationinfo_ref = {};
        
        if ($locationinfo){

	    my $date      = ParseDate("now");
	    my $timestamp = UnixDate($date,"%Y-%m-%d");

	    unless ($from) {
		$from = "$timestamp 00:00:00";
	    }

	    unless ($to) {
		$to   = "$timestamp 23:59:50";
	    }

            $locationinfo_ref = {
                id          => $locationinfo->id,
                identifier  => $locationinfo->identifier,
                description => $locationinfo->description,
                shortdesc   => $locationinfo->shortdesc,
                type        => $locationinfo->type,
                fields      => $config->get_locationinfo_fields($locationid),
                occupancy   => $config->get_locationinfo_occupancy($locationid,$from,$to),
            };

            if ($logger->is_debug){
                $logger->debug("Found record:".YAML::Dump($locationinfo_ref));
            }

        }
        else {
            $logger->info("Can't find location with id $locationid")
        }
            
	my $locationlist_ref = $config->get_locationinfo_overview;
    
        my $ttdata = {
	    locations      => $locationlist_ref,
            locationid     => $locationid,
            locationinfo   => $locationinfo_ref,
        };

        return $self->print_page($config->{tt_locations_record_tname},$ttdata);

    }
    else {
        return $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit einer Id spezifiziert."));
    }
}

1;
