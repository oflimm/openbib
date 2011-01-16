#####################################################################
#
#  OpenBib::Handler::Apache::Admin::OrganizationalUnit
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

package OpenBib::Handler::Apache::Admin::OrganizationalUnit;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
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
use SOAP::Lite;
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

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection_negotiate');
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
    my $view           = $self->param('view')           || '';
    my $profilename    = $self->param('profileid')      || '';

    my $config  = OpenBib::Config->instance;

    my $negotiated_type_ref = $self->negotiate_type;
    
    $r->content_type($negotiated_type_ref->{content_type});

    my $new_location = "$config->{base_loc}/$config->{handler}{admin_profile_loc}{name}/$profilename/orgunit.$negotiated_type_ref->{suffix}";
    $r->headers_out->add("Location" => $new_location);
    $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $new_location");
    
    return Apache2::Const::HTTP_SEE_OTHER;
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

    my $view           = $self->param('view')           || '';
    my $profilename    = $self->param('profileid')      || '';
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

    if (!$config->profile_exists($profilename)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }
    
    my $orgunits_ref = $config->get_orgunits($profilename);

    my $ttdata={
        view       => $view,

        representation => $representation,

        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },
        
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        orgunits   => $orgunits_ref,
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_orgunit_tname},$ttdata,$r);

    return Apache2::Const::OK;
}

sub show_record_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $profilename    = $self->param('profileid')      || '';    
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

    my $orgunitname    = "";
    if ($id=~/^(.+?)(\.html|\.json|\.rdf\+xml)$/){
        $orgunitname      = $1;
        ($representation) = $2 =~/^\.(.+?)$/;
        $content_type     = $config->{'content_type_map_rev'}{$representation};
    }
    # Sonst Aushandlung
    else {
        $orgunitname = $id;
        my $negotiated_type = $self->negotiate_type;
        $representation = $negotiated_type->{suffix};
        $content_type   = $negotiated_type->{content_type};
    }

    if (!$config->profile_exists($profilename)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"),$r,$msg);
        
        return Apache2::Const::OK;
    }
    
    my $profileinfo_ref = $config->get_profileinfo({ profilename => $profilename })->single();
    my $orgunitinfo_ref = $config->get_orgunitinfo($profilename,$orgunitname);
    
    my @orgunitdbs   = $config->get_profiledbs($profilename,$orgunitname);
    
    $orgunitinfo_ref->{dbnames} = \@orgunitdbs;
    
    my $ttdata={
        view       => $view,

        representation => $representation,

        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },
        
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        
        profileinfo    => $profileinfo_ref,
        
        orgunitinfo    => $orgunitinfo_ref,
        
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_orgunit_record_tname},$ttdata,$r);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $profilename    = $self->param('profileid')      || '';
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

    if (!$config->profile_exists($profilename)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }

    my $orgunit         = $query->param('orgunit')         || '';
    my $description     = decode_utf8($query->param('description'))     || '';

    if ($profilename eq "" || $orgunit eq "" || $description eq "") {
        
        OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Profilnamen, den Namen einer Organisationseinheit und deren Beschreibung eingeben."),$r,$msg);
        
        return Apache2::Const::OK;
    }
    
    my $ret = $config->new_orgunit({
        profilename => $profilename,
        orgunit     => $orgunit,
        description => $description,
    });
    
    if ($ret == -1){
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits eine Organisationseinheit unter diesem Namen"),$r,$msg);
        return Apache2::Const::OK;
    }
    
    $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$config->{handler}{admin_profile_loc}{name}/$profilename/orgunit/$orgunit/edit");
    return Apache2::Const::OK;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $profilename    = $self->param('profileid')      || '';
    my $orgunitname    = $self->param('id')             || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

#     if (!$config->profile_exists($dbname)) {        
#         OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"),$r,$msg);
        
#         return Apache2::Const::OK;
#     }
            
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

    if (!$config->profile_exists($profilename)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }
    
    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->profile_exists($profilename)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"),$r,$msg);
        
        return Apache2::Const::OK;
    }

    my $profileinfo_ref = $config->get_profileinfo({ profilename => $profilename })->single();
    my $orgunitinfo_ref = $config->get_orgunitinfo($profilename,$orgunitname);

    my @dbnames      = $config->get_active_database_names();

    my @orgunitdbs   = $config->get_profiledbs($profilename,$orgunitname);
    
    $orgunitinfo_ref->{dbnames} = \@orgunitdbs;
    
    my $ttdata={
        view       => $view,
        
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        
        profileinfo    => $profileinfo_ref,
        
        orgunitinfo    => $orgunitinfo_ref,
        
        dbnames    => \@dbnames,
        
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_orgunit_record_edit_tname},$ttdata,$r);
    
    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $profilename    = $self->param('profileid')      || '';
    my $orgunitname    = $self->param('id')             || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$config->profile_exists($profilename)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);
        
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

    if ($method eq "DELETE"){
        $self->query->method('DELETE');
        $self->query->headers_out->add(Location => "$config->{base_loc}/$config->{handler}{admin_profile_loc}{name}/$profilename/orgunit/$orgunitname");
        $self->query->status(Apache2::Const::REDIRECT);
    }

    if (!$config->profile_exists($profilename)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"),$r,$msg);
        
        return Apache2::Const::OK;
    }

    my $description     = decode_utf8($query->param('description'))     || '';
    my @orgunitdb       = ($query->param('orgunitdb'))?$query->param('orgunitdb'):();
    my $nr              = $query->param('nr')              || 0;

    $config->update_orgunit({
        profilename => $profilename,
        orgunit     => $orgunitname,
        description => $description,
        orgunitdb   => \@orgunitdb,
        nr          => $nr,
    });
    
    $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$config->{handler}{admin_profile_loc}{name}/$profilename");
    
    return Apache2::Const::OK;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $profilename    = $self->param('profileid')      || '';
    my $orgunitname    = $self->param('id')             || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$config->profile_exists($profilename)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);
        
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

    if (!$config->profile_exists($profilename)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }

    if (!$config->orgunit_exists($profilename,$orgunitname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert keine Organisationseinheit unter diesem Namen in diesem Profil"),$r,$msg);
        
        return Apache2::Const::OK;
    }
    
    $logger->debug("Server: ".$r->get_server_name);

    $config->del_orgunit($profilename,$orgunitname);
    
    $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$config->{handler}{admin_profile_loc}{name}/$profilename");
    return Apache2::Const::OK;
}

1;
