#####################################################################
#
#  OpenBib::Handler::PSGI::Admin::Databases
#
#  Dieses File ist (C) 2004-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Admin::Databases;

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
        'show_record'               => 'show_record',
        'show_record_form'          => 'show_record_form',
        'create_record'             => 'create_record',
        'update_record'             => 'update_record',
        'delete_record'             => 'delete_record',
        'confirm_delete_record'     => 'confirm_delete_record',
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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    my $dbinfo_ref = $config->get_dbinfo_overview();
    
    my $ttdata={                # 
        catalogs   => $dbinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_databases_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $user           = $self->param('user');
    my $lang           = $self->param('lang');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input($self->get_input_definition);

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if ($input_data_ref->{dbname} eq "" || $input_data_ref->{description} eq "") {
        return $self->print_warning($msg->maketext("Sie müssen mindestens einen Katalognamen und eine Beschreibung eingeben."),2);
    }
    
    if ($config->db_exists($input_data_ref->{dbname})) {
        return $self->print_warning($msg->maketext("Es existiert bereits ein Katalog unter diesem Namen"),3);
    }

    if ($input_data_ref->{locationid} eq ""){
        delete $input_data_ref->{locationid};
    }
    
    my $new_databaseid = $config->new_databaseinfo($input_data_ref);

    if ($self->param('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{databases_loc}/id/$input_data_ref->{dbname}/edit.html?l=$lang");
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_databaseid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zur DB $input_data_ref->{dbname}");
            $self->param('status',201); # created
            $self->param('databaseid',$input_data_ref->{dbname});
            $self->param('location',"$location/$input_data_ref->{dbname}");
            return $self->show_record;
        }
    }

    return;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $dbname         = $self->strip_suffix($self->param('databaseid'));

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
    $logger->debug("Show Record $dbname");

    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;

    if (!$dbinfo_ref){
        $logger->error("Database $dbname couldn't be found.");
    }
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_databases_record_tname},$ttdata);
}


sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $dbname         = $self->param('databaseid')             || '';

    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }
    
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_databases_record_edit_tname},$ttdata);
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $query          = $self->query();
    
    my $view           = $self->param('view')           || '';
    my $dbname         = $self->param('databaseid')             || '';
    my $path_prefix    = $self->param('path_prefix');
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{dbname} = $dbname; # dbname wird durch Resourcenbestandteil ueberschrieben
    
    if ($logger->is_debug){
        $logger->debug("Info: ".YAML::Dump($input_data_ref));
    }

    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }

    if ($input_data_ref->{locationid} eq ""){
        delete $input_data_ref->{locationid};
    }
    else {
        my $location = $config->get_locationinfo->single({identifier => $input_data_ref->{locationid} });

        if ($location){
            $input_data_ref->{locationid} = $location->id;
        }
    }

    $config->update_databaseinfo($input_data_ref);

    if ($self->param('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{databases_loc}");
    }
    else {
        $logger->debug("Weiter zum Record");
        $logger->debug("Weiter zur DB $dbname");
        return $self->show_record;
    }
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $dbname         = $self->strip_suffix($self->param('databaseid'));
    my $config         = $self->param('config');

    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_databases_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');
    my $path_prefix    = $self->param('path_prefix');
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }

    $logger->debug("Deleting database record $dbname");
    
    $config->del_databaseinfo($dbname);

    return unless ($self->param('representation') eq "html");
    
    # TODO GET?
    return $self->redirect("$path_prefix/$config->{databases_loc}");
}

sub get_input_definition {
    my $self=shift;
    
    return {
        description => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        shortdesc => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        system => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        dbname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        sigel => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        url => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        locationid => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        active => {
            default  => 'false',
            encoding => 'none',
            type     => 'scalar',
        },
        host => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        protocol => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        remotepath => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        remoteuser => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        remotepassword => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        titlefile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        personfile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        corporatebodyfile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        subjectfile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        classificationfile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        holdingfile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        autoconvert => {
            default  => 'false',
            encoding => 'none',
            type     => 'bool',
        },
        circ => {
            default  => 'false',
            encoding => 'none',
            type     => 'bool',
        },
        circurl => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        circwsurl => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        circdb => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
