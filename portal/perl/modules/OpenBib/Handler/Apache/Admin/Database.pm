#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Database
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

package OpenBib::Handler::Apache::Admin::Database;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Apache2::Log;
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::Request ();
use Apache2::SubRequest ();
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

use CGI::Application::Plugin::Redirect;

use base 'OpenBib::Handler::Apache::Admin';

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
        $self->print_authorization_error();
        return;
    }

    my $dbinfo_ref = $config->get_dbinfo_overview();
    
    my $ttdata={                # 
        kataloge   => $dbinfo_ref,
    };
    
    $self->print_page($config->{tt_admin_database_tname},$ttdata);

    return Apache2::Const::OK;
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
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input($self->get_input_definition);

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    if ($input_data_ref->{dbname} eq "" || $input_data_ref->{description} eq "") {
        $self->print_warning($msg->maketext("Sie müssen mindestens einen Katalognamen und eine Beschreibung eingeben."),2);
        return Apache2::Const::OK;
    }
    
    if ($config->db_exists($input_data_ref->{dbname})) {
        $self->print_warning($msg->maketext("Es existiert bereits ein Katalog unter diesem Namen"),3);
        return Apache2::Const::OK;
    }

    my $new_databaseid = $config->new_databaseinfo($input_data_ref);

    if ($self->param('representation') eq "html"){
        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}/$input_data_ref->{dbname}/edit");
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_databaseid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zur DB $input_data_ref->{dbname}");
            $self->param('status',Apache2::Const::HTTP_CREATED);
            $self->param('databaseid',$input_data_ref->{dbname});
            $self->param('location',"$location/$input_data_ref->{dbname}");
            $self->show_record;
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
        $self->print_authorization_error();
        return;
    }

    $logger->debug("Show Record $dbname");

    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;

    if (!$dbinfo_ref){
        $logger->error("Database $dbname couldn't be found.");
    }
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
    };
    
    $self->print_page($config->{tt_admin_database_record_tname},$ttdata);

    return;
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
        $self->print_authorization_error();
        return;
    }

    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
    };
    
    $self->print_page($config->{tt_admin_database_record_edit_tname},$ttdata);
        
    return Apache2::Const::OK;
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
        $self->print_authorization_error();
        return;
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{dbname} = $dbname; # dbname wird durch Resourcenbestandteil ueberschrieben
    
    $logger->debug("Info: ".YAML::Dump($input_data_ref));

    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }

    # Variables

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden
    
    my $method          = decode_utf8($query->param('_method')) || '';
    my $confirm         = $query->param('confirm') || 0;

    if ($method eq "DELETE"){
        $logger->debug("About to delete $dbname");
        
        if ($confirm){
            my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
            
            my $ttdata={
                databaseinfo => $dbinfo_ref,
            };

            $logger->debug("Asking for confirmation");
            $self->print_page($config->{tt_admin_database_record_delete_confirm_tname},$ttdata);

            return Apache2::Const::OK;
        }
        else {
            $self->delete_record;
#             $logger->debug("Redirecting to delete location");
#             $self->query->method('DELETE');    
#             $self->query->headers_out->add(Location => "$config->{base_loc}/$config->{admin_database_loc}/$dbname");
#             $self->query->status(Apache2::Const::REDIRECT);
            return;
        }
    }
    
    # Ansonsten POST oder PUT => Aktualisieren
    
    $config->update_databaseinfo($input_data_ref);

    if ($self->param('representation') eq "html"){
        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}");
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $logger->debug("Weiter zum Record");
        $logger->debug("Weiter zur DB $databaseid");
        $self->show_record;
    }
    

    return;
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
        $self->print_authorization_error();
        return;
    }
    
    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }
            
    $config->del_databaseinfo($dbname);

    return unless ($self->param('representation') eq "html");
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
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
        use_libinfo => {
            default  => 'false',
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
