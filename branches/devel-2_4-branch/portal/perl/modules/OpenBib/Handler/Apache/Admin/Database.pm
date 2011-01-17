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
        'show_collection_negotiate' => 'show_collection_negotiate',
        'show_collection_as_html'   => 'show_collection_as_html',
        'show_collection_as_json'   => 'show_collection_as_json',
        'show_collection_as_rdf'    => 'show_collection_as_rdf',
        'show_collection_form'      => 'show_collection_form',
        'create_record'             => 'create_record',
        'show_record_negotiate'     => 'show_record_negotiate',
        'show_record_form'          => 'show_record_form',
        'update_record'             => 'update_record',
        'delete_record'             => 'delete_record',        
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $config  = OpenBib::Config->instance;

    my $negotiated_type_ref = $self->negotiate_type;

    my $new_location = "$config->{base_loc}/$config->{handler}{admin_database_loc}{name}.$negotiated_type_ref->{suffix}";

    $self->query->method('GET');
    $self->query->content_type($negotiated_type_ref->{content_type});
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $new_location");

    return;
}

sub show_collection_as_html {
    my $self = shift;

    $self->param('representation','html');

    $self->show_collection;

    return;
}

sub show_collection_as_json {
    my $self = shift;

    $self->param('representation','json');

    $self->show_collection;

    return;
}

sub show_collection_as_rdf {
    my $self = shift;

    $self->param('representation','rdf');

    $self->show_collection;

    return;
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $representation = $self->param('representation') || '';

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

    $logger->debug("Server: ".$r->get_server_name."Representation: $representation");
           
    my $dbinfo_ref = $config->get_dbinfo_overview();
    
    my $ttdata={
        representation => $representation,

        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },
        
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        kataloge   => $dbinfo_ref,
        
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_database_tname},$ttdata,$r);

    return Apache2::Const::OK;
}

sub show_record_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $id             = $self->param('id')             || '';

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

    # Mit Suffix, dann keine Aushandlung des Typs

    my $representation = "";
    my $content_type   = "";

    my $dbname         = "";
    if ($id=~/^(.+?)(\.html|\.json|\.rdf\+xml)$/){
        $dbname           = $1;
        ($representation) = $2 =~/^\.(.+?)$/;
        $content_type   = $config->{'content_type_map_rev'}{$representation};
    }
    # Sonst Aushandlung
    else {
        $dbname = $id;
        my $negotiated_type = $self->negotiate_type;
        $representation = $negotiated_type->{suffix};
        $content_type   = $negotiated_type->{content_type};
    }
    
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        representation => $representation,
        content_type   => $content_type,
        
        stylesheet => $stylesheet,
        
        databaseinfo => $dbinfo_ref,
        
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_database_record_tname},$ttdata,$r);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $representation = $self->param('representation') || '';

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

    # Variables
    my $description     = decode_utf8($query->param('description'))     || '';
    my $shortdesc       = $query->param('shortdesc')       || '';
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
    
    if ($dbname eq "" || $description eq "") {
        
        OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Katalognamen und eine Beschreibung eingeben."),$r,$msg);
        
        return Apache2::Const::OK;
    }
    
    if ($config->db_exists($dbname)) {
        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein Katalog unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }
    
    $config->new_databaseinfo($thisdbinfo_ref);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$config->{base_loc}/$config->{handler}{admin_database_loc}{name}/$dbname/edit");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $dbname         = $self->param('id')             || '';

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

    my $dbname         = $self->param('id')             || '';

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
            $logger->debug("Redirecting to delete location");
            $self->query->method('DELETE');    
            $self->query->headers_out->add(Location => "$config->{base_loc}/$config->{handler}{admin_database_loc}{name}/$dbname");
            $self->query->status(Apache2::Const::REDIRECT);
            return;
        }
    }

    # Ansonsten POST oder PUT => Aktualisieren
    
    my $description     = decode_utf8($query->param('description'))     || '';
    my $shortdesc       = $query->param('shortdesc')       || '';
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
    $self->query->headers_out->add(Location => "$config->{base_loc}/$config->{handler}{admin_database_loc}{name}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $dbname         = $self->param('id')             || '';

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
    $self->query->headers_out->add(Location => "$config->{base_loc}/$config->{handler}{admin_database_loc}{name}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
