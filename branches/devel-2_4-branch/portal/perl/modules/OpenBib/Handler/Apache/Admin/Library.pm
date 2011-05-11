#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Library
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

package OpenBib::Handler::Apache::Admin::Library;

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

    $self->start_mode('show_record_negotiate');
    $self->run_modes(
        'show_record_negotiate'     => 'show_record_negotiate',
        'show_record_as_html'       => 'show_record_as_html',
        'show_record_as_json'       => 'show_record_as_json',
        'show_record_as_rdf'        => 'show_record_as_rdf',
        'show_record_form'          => 'show_record_form',
        'create_record'             => 'create_record',
        'update_record'             => 'update_record',
        'delete_record'             => 'delete_record',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_record_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $view           = $self->param('view')                   || '';
    my $dbname         = $self->param('databaseid')             || '';

    my $config  = OpenBib::Config->instance;

    my $negotiated_type_ref = $self->negotiate_type;

    my $new_location = "$config->{base_loc}/$view/$config->{admin_database_loc}/$dbname/library.$negotiated_type_ref->{suffix}";

    $self->query->method('GET');
    $self->query->content_type($negotiated_type_ref->{content_type});
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $new_location");

    return;
}

sub show_record_as_html {
    my $self = shift;

    $self->param('representation','html');

    $self->show_record;

    return;
}

sub show_record_as_json {
    my $self = shift;

    $self->param('representation','json');

    $self->show_record;

    return;
}

sub show_record_as_rdf {
    my $self = shift;

    $self->param('representation','rdf');

    $self->show_record;

    return;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $view           = $self->param('view')                   || '';
    my $dbname         = $self->param('databaseid')             || '';

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

    if (!$config->db_exists($dbname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }
    
    my $libinfo_ref = $config->get_libinfo($dbname);
    
    my $ttdata={
        representation => $representation,
        
        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },

        view       => $view,
        
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        dbname     => $dbname,
        libinfo    => $libinfo_ref,
        
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_library_record_tname},$ttdata,$r);

    return Apache2::Const::OK;
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')                   || '';
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
    $self->query->headers_out->add(Location => "$config->{base_loc}/$view/$config->{admin_database_loc}/$dbname/edit");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')                   || '';
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

    if (!$config->db_exists($dbname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }

    my $libinfo_ref = $config->get_libinfo($dbname);
    
    my $ttdata={
        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },

        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        dbname     => $dbname,
        libinfo    => $libinfo_ref,
        
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_library_record_edit_tname},$ttdata,$r);

    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')                   || '';
    my $dbname         = $self->param('databaseid')             || '';

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
            my $libinfo_ref = $config->get_libinfo($dbname);
            
            my $ttdata={
                stylesheet   => $stylesheet,
                libinfo      => $libinfo_ref,

                view       => $view,
                dbname     => $dbname,
                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };

            $logger->debug("Asking for confirmation");
            OpenBib::Common::Util::print_page($config->{tt_admin_library_record_delete_confirm_tname},$ttdata,$r);

            return Apache2::Const::OK;
        }
        else {
            $logger->debug("Redirecting to delete location");
            $self->query->method('DELETE');    
            $self->query->headers_out->add(Location => "$config->{base_loc}/$view/$config->{admin_database_loc}/$dbname/library");
            $self->query->status(Apache2::Const::REDIRECT);
            return;
        }
    }

    # Ansonsten POST oder PUT => Aktualisieren

    # Kategorien der Bibliotheksinfos
    my $li_0010         = $query->param('I0010')          || '';
    my $li_0020         = $query->param('I0020')          || '';
    my $li_0030         = $query->param('I0030')          || '';
    my $li_0040         = $query->param('I0040')          || '';
    my $li_0050         = $query->param('I0050')          || '';
    my $li_0060         = $query->param('I0060')          || '';
    my $li_0070         = $query->param('I0070')          || '';
    my $li_0080         = $query->param('I0080')          || '';
    my $li_0090         = $query->param('I0090')          || '';
    my $li_0100         = $query->param('I0100')          || '';
    my $li_0110         = $query->param('I0110')          || '';
    my $li_0120         = $query->param('I0120')          || '';
    my $li_0130         = $query->param('I0130')          || '';
    my $li_0140         = $query->param('I0140')          || '';
    my $li_0150         = $query->param('I0150')          || '';
    my $li_0160         = $query->param('I0160')          || '';
    my $li_0170         = $query->param('I0170')          || '';
    my $li_0180         = $query->param('I0180')          || '';
    my $li_0190         = $query->param('I0190')          || '';
    my $li_0200         = $query->param('I0200')          || '';
    my $li_0210         = $query->param('I0210')          || '';
    my $li_0220         = $query->param('I0220')          || '';
    my $li_0230         = $query->param('I0230')          || '';
    my $li_0240         = $query->param('I0240')          || '';
    my $li_0250         = $query->param('I0250')          || '';
    my $li_0260         = $query->param('I0260')          || '';
    my $li_1000         = $query->param('I1000')          || '';

    my $thislibinfo_ref = {
        I0010      => $li_0010,
        I0020      => $li_0020,
        I0030      => $li_0030,
        I0040      => $li_0040,
        I0050      => $li_0050,
        I0060      => $li_0060,
        I0070      => $li_0070,
        I0080      => $li_0080,
        I0090      => $li_0090,
        I0100      => $li_0100,
        I0110      => $li_0110,
        I0120      => $li_0120,
        I0130      => $li_0130,
        I0140      => $li_0140,
        I0150      => $li_0150,
        I0160      => $li_0160,
        I0170      => $li_0170,
        I0180      => $li_0180,
        I0190      => $li_0190,
        I0200      => $li_0200,
        I0210      => $li_0210,
        I0220      => $li_0220,
        I0230      => $li_0230,
        I0240      => $li_0240,
        I0250      => $li_0250,
        I0260      => $li_0260,
        I1000      => $li_1000,
    };

    
    $logger->debug("Info: ".YAML::Dump($thislibinfo_ref));
    
    $config->update_libinfo($dbname,$thislibinfo_ref);
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$config->{base_loc}/$view/$config->{admin_database_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')                   || '';
    my $dbname         = $self->param('databaseid')             || '';

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
    
    $config->del_libinfo($dbname);
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$config->{base_loc}/$view/$config->{admin_database_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
