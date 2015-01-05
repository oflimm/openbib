#####################################################################
#
#  OpenBib::Handler::PSGI::Admin::Searchprofiles
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Admin::Searchprofiles;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use JSON::XS;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI::Admin';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'           => 'show_collection',
        'show_collection_form'      => 'show_collection_form',
        'show_record'               => 'show_record',
        'show_record_form'          => 'show_record_form',
        'update_record'             => 'update_record',
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
    my $config         = $self->param('config');

    # CGI Args
    my $year           = $query->param('year');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $statistics  = new OpenBib::Statistics();

    my $ttdata={
        dbinfo     => $dbinfotable,
        statistics => $statistics,
        year       => $year,
    };
    
    return $self->print_page($config->{tt_admin_searchprofiles_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view            = $self->param('view');
    my $searchprofileid = $self->strip_suffix($self->param('searchprofileid'));

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $searchprofile_obj = $config->get_searchprofile->single({ id => $searchprofileid });

    my $ttdata={
        searchprofileid => $searchprofileid,
        searchprofile   => $searchprofile_obj,
        dbinfo          => $dbinfotable,
    };
    
    return $self->print_page($config->{tt_admin_searchprofiles_record_tname},$ttdata);
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view            = $self->param('view');
    my $searchprofileid = $self->param('searchprofileid');

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $statistics  = new OpenBib::Statistics();

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $searchprofile_obj = $config->get_searchprofile->single({ id => $searchprofileid });

    my $ttdata={
        searchprofileid => $searchprofileid,
        searchprofile   => $searchprofile_obj,
        statistics      => $statistics,
        dbinfo          => $dbinfotable,
    };
    
    return $self->print_page($config->{tt_admin_searchprofiles_record_edit_tname},$ttdata);
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $view            = $self->param('view');
    my $searchprofileid = $self->param('searchprofileid');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $path_prefix    = $self->param('path_prefix');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if (!$config->searchprofile_exists($searchprofileid)) {
        return $self->print_warning($msg->maketext("Es existiert kein Suchprofil mit dieser ID"));
    }

    # POST oder PUT => Aktualisieren

    $config->update_searchprofile($searchprofileid,$input_data_ref->{own_index});

    if ($self->param('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{searchprofiles_loc}");
    }
    else {
        $logger->debug("Weiter zum Record $searchprofileid");
        return $self->show_record;
    }
}

sub get_input_definition {
    my $self=shift;
    
    return {
        own_index => {
            default  => 'false',
            encoding => 'none',
            type     => 'scalar',
        },        
    };
}

1;
