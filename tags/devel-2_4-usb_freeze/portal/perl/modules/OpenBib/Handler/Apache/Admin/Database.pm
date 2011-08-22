#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Database
#
#  Dieses File ist (C) 2004-2011 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Database::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use CGI::Application::Plugin::Redirect;

use base 'OpenBib::Handler::Apache';

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

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $dbinfo_ref = $config->get_dbinfo_overview();
    
    my $ttdata={                # 
        kataloge   => $dbinfo_ref,
    };
    
    $self->print_page($config->{tt_admin_database_tname},$ttdata);

    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $dbname         = $self->param('id');

    if (!$self->is_authenticated('admin')){
        return;
    }
    
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
    };
    
    $self->print_page($config->{tt_admin_database_record_tname},$ttdata);

    return Apache2::Const::OK;
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $description     = decode_utf8($query->param('description'))     || '';
    my $shortdesc       = decode_utf8($query->param('shortdesc'))       || '';
    my $system          = $query->param('system')          || '';
    my $dbname          = $query->param('dbname')          || '';
    my $sigel           = $query->param('sigel')           || '';
    my $url             = $query->param('url')             || '';
    my $use_libinfo     = $query->param('use_libinfo')     || 0;
    my $active          = $query->param('active')          || 0;

    my $host            = $query->param('host')            || '';
    my $protocol        = $query->param('protocol')        || '';
    my $remotepath      = $query->param('remotepath')      || '';
    my $remoteuser      = $query->param('remoteuser')      || '';
    my $remotepasswd    = $query->param('remotepasswd')    || '';
    my $titfilename     = $query->param('titfilename')     || '';
    my $autfilename     = $query->param('autfilename')     || '';
    my $korfilename     = $query->param('korfilename')     || '';
    my $swtfilename     = $query->param('swtfilename')     || '';
    my $notfilename     = $query->param('notfilename')     || '';
    my $mexfilename     = $query->param('mexfilename')     || '';
    my $autoconvert     = $query->param('autoconvert')     || '';
    my $circ            = $query->param('circ')            || '';
    my $circurl         = $query->param('circurl')         || '';
    my $circcheckurl    = $query->param('circcheckurl')    || '';
    my $circdb          = $query->param('circdb')          || '';

    if (!$self->is_authenticated('admin')){
        return;
    }

    if ($dbname eq "" || $description eq "") {
        $self->print_warning($msg->maketext("Sie müssen mindestens einen Katalognamen und eine Beschreibung eingeben."));
        return Apache2::Const::OK;
    }
    
    if ($config->db_exists($dbname)) {
        $self->print_warning($msg->maketext("Es existiert bereits ein Katalog unter diesem Namen"));
        return Apache2::Const::OK;
    }

    my $thisdbinfo_ref = {
        description        => $description,
        shortdesc          => $shortdesc,
        system             => $system,
        dbname             => $dbname,
        sigel              => $sigel,
        url                => $url,
        use_libinfo        => $use_libinfo,
        active             => $active,
        host               => $host,
        protocol           => $protocol,
        remotepath         => $remotepath,
        remoteuser         => $remoteuser,
        remotepassword     => $remotepasswd,
        titlefile          => $titfilename,
        personfile         => $autfilename,
        corporatebodyfile  => $korfilename,
        subjectfile        => $swtfilename,
        classificationfile => $notfilename,
        holdingsfile       => $mexfilename,
        autoconvert        => $autoconvert,
        circ               => $circ,
        circurl            => $circurl,
        circwsurl          => $circcheckurl,
        circdb             => $circdb,
    };

    $config->new_databaseinfo($thisdbinfo_ref);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}/$dbname/edit");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $dbname         = $self->param('databaseid')             || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$config->db_exists($dbname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }
            
    my $adminuser   = $config->{adminuser};
    my $adminpasswd = $config->{adminpasswd};
    
    # Ist der Nutzer ein Admin?
    my $user         = OpenBib::User->instance({sessionID => $session->{ID}});

    # Admin-SessionID ueberpruefen
    # Entweder als Master-Adminuser eingeloggt, oder der Benutzer besitzt die Admin-Rolle
    my $adminsession = $session->is_authenticated_as($adminuser) || $user->is_admin;

    if (!$adminsession) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"),$r,$msg);
        return Apache2::Const::OK;
    }

    $logger->debug("Server: ".$r->get_server_name);

    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        stylesheet   => $stylesheet,        
        databaseinfo => $dbinfo_ref,

        view       => $view,
        
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_database_record_edit_tname},$ttdata,$r);
        
    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $dbname         = $self->param('databaseid')             || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    my $adminuser   = $config->{adminuser};
    my $adminpasswd = $config->{adminpasswd};
    
    # Ist der Nutzer ein Admin?
    my $user         = OpenBib::User->instance({sessionID => $session->{ID}});

    # Admin-SessionID ueberpruefen
    # Entweder als Master-Adminuser eingeloggt, oder der Benutzer besitzt die Admin-Rolle
    my $adminsession = $session->is_authenticated_as($adminuser) || $user->is_admin;

    if (!$adminsession) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"),$r,$msg);
        return Apache2::Const::OK;
    }

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"),$r,$msg);
        
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
                stylesheet   => $stylesheet,
                databaseinfo => $dbinfo_ref,

                view       => $view,
                
                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };

            $logger->debug("Asking for confirmation");
            OpenBib::Common::Util::print_page($config->{tt_admin_database_record_delete_confirm_tname},$ttdata,$r);

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
    
    my $description     = decode_utf8($query->param('description'))     || '';
    my $shortdesc       = decode_utf8($query->param('shortdesc'))       || '';
    my $system          = $query->param('system')          || '';
    my $sigel           = $query->param('sigel')           || '';
    my $url             = $query->param('url')             || '';
    my $use_libinfo     = $query->param('use_libinfo')     || 0;
    my $active          = $query->param('active')          || 0;

    my $host            = $query->param('host')            || '';
    my $protocol        = $query->param('protocol')        || '';
    my $remotepath      = $query->param('remotepath')      || '';
    my $remoteuser      = $query->param('remoteuser')      || '';
    my $remotepasswd    = $query->param('remotepasswd')    || '';
    my $titfilename     = $query->param('titfilename')     || '';
    my $autfilename     = $query->param('autfilename')     || '';
    my $korfilename     = $query->param('korfilename')     || '';
    my $swtfilename     = $query->param('swtfilename')     || '';
    my $notfilename     = $query->param('notfilename')     || '';
    my $mexfilename     = $query->param('mexfilename')     || '';
    my $autoconvert     = $query->param('autoconvert')     || '';
    my $circ            = $query->param('circ')            || '';
    my $circurl         = $query->param('circurl')         || '';
    my $circcheckurl    = $query->param('circcheckurl')    || '';
    my $circdb          = $query->param('circdb')          || '';

    
    my $thisdbinfo_ref = {
        description        => $description,
        shortdesc          => $shortdesc,
        system             => $system,
        dbname             => $dbname,
        sigel              => $sigel,
        url                => $url,
        use_libinfo        => $use_libinfo,
        active             => $active,
        host               => $host,
        protocol           => $protocol,
        remotepath         => $remotepath,
        remoteuser         => $remoteuser,
        remotepassword     => $remotepasswd,
        titlefile          => $titfilename,
        personfile         => $autfilename,
        corporatebodyfile  => $korfilename,
        subjectfile        => $swtfilename,
        classificationfile => $notfilename,
        holdingsfile       => $mexfilename,
        autoconvert        => $autoconvert,
        circ               => $circ,
        circurl            => $circurl,
        circwsurl          => $circcheckurl,
        circdb             => $circdb,
    };
        
    $logger->debug("Info: ".YAML::Dump($thisdbinfo_ref));
    
    $config->update_databaseinfo($thisdbinfo_ref);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $dbname         = $self->param('databaseid')             || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$config->db_exists($dbname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }
            
    my $adminuser   = $config->{adminuser};
    my $adminpasswd = $config->{adminpasswd};
    
    # Ist der Nutzer ein Admin?
    my $user         = OpenBib::User->instance({sessionID => $session->{ID}});

    # Admin-SessionID ueberpruefen
    # Entweder als Master-Adminuser eingeloggt, oder der Benutzer besitzt die Admin-Rolle
    my $adminsession = $session->is_authenticated_as($adminuser) || $user->is_admin;

    if (!$adminsession) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"),$r,$msg);
        return Apache2::Const::OK;
    }

    $logger->debug("Server: ".$r->get_server_name);

    $config->del_databaseinfo($dbname);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
