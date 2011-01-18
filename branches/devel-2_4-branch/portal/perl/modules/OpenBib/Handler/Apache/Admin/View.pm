#####################################################################
#
#  OpenBib::Handler::Apache::Admin::View
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

package OpenBib::Handler::Apache::Admin::View;

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

    my $new_location = "$config->{base_loc}/$config->{handler}{admin_view_loc}{name}.$negotiated_type_ref->{suffix}";

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

    my $viewinfo_ref = $config->get_viewinfo_overview();
    
    my $ttdata={
        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },
        
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        views      => $viewinfo_ref,
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_view_tname},$ttdata,$r);
    
    return Apache2::Const::OK;
}

sub show_record_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $id             = $self->param('viewid')             || '';

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

    my $viewname         = "";
    if ($id=~/^(.+?)(\.html|\.json|\.rdf\+xml)$/){
        $viewname           = $1;
        ($representation) = $2 =~/^\.(.+?)$/;
        $content_type   = $config->{'content_type_map_rev'}{$representation};
    }
    # Sonst Aushandlung
    else {
        $viewname = $id;
        my $negotiated_type = $self->negotiate_type;
        $representation = $negotiated_type->{suffix};
        $content_type   = $negotiated_type->{content_type};
    }

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $viewinfo_obj  = $config->get_viewinfo($viewname);

    my $viewname    = $viewinfo_obj->viewname;
    my $description = $viewinfo_obj->description;
    my $primrssfeed = $viewinfo_obj->rssfeed;
    my $start_loc   = $viewinfo_obj->start_loc;
    my $start_stid  = $viewinfo_obj->start_stid;
    my $profilename = $viewinfo_obj->profilename;
    my $active      = $viewinfo_obj->active;
             
    my @profiledbs       = $config->get_profiledbs($profilename);
    
    my @viewdbs          = $config->get_viewdbs($viewname);
    
    my $all_rssfeeds_ref = $config->get_rssfeed_overview();
    
    my $viewrssfeed_ref=$config->get_rssfeeds_of_view($viewname);

    my $viewinfo={
        viewname     => $viewname,
        description  => $description,
        active       => $active,
        start_loc    => $start_loc,
        start_stid   => $start_stid,
        profilename  => $profilename,
        viewdbs      => \@viewdbs,
        allrssfeeds  => $all_rssfeeds_ref,
        viewrssfeed  => $viewrssfeed_ref,
        primrssfeed  => $primrssfeed,
    };

    
    my $ttdata={
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        
        dbnames    => \@profiledbs,
        
        viewinfo   => $viewinfo,
        
        dbinfo     => $dbinfotable,
        
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_view_record_tname},$ttdata,$r);
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
    my $viewname        = $query->param('viewname')                     || '';
    my $profilename     = $query->param('profilename')                  || '';
    my $active          = $query->param('active')          || 0;
    my $viewstart_loc   = $query->param('viewstart_loc')             || '';
    my $viewstart_stid  = $query->param('viewstart_stid')            || '';

    if ($viewname eq "" || $description eq "" || $profilename eq "") {
        
        OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Viewnamen, eine Beschreibung sowie ein Katalog-Profil eingeben."),$r,$msg);
        
        return Apache2::Const::OK;
    }

    # Profile muss vorhanden sein.
    if (!$config->profile_exists($profilename)) {
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);

        return Apache2::Const::OK;
    }

    # View darf noch nicht existieren
    if ($config->view_exists($viewname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }
    
    my $ret = $config->new_view({
        viewname    => $viewname,
        description => $description,
        profilename => $profilename,
        active      => $active,
        start_loc   => $viewstart_loc,
        start_stid  => $viewstart_stid,
    });
    
    if ($ret == -1){
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"),$r,$msg);
        return Apache2::Const::OK;
    }

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$config->{base_loc}/$config->{handler}{admin_view_loc}{name}/$viewname/edit");
    $self->query->status(Apache2::Const::REDIRECT);
    
    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $viewname       = $self->param('viewid')             || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$config->view_exists($viewname)) {        
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

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $viewinfo_obj  = $config->get_viewinfo($viewname);

    my $viewname    = $viewinfo_obj->viewname;
    my $description = $viewinfo_obj->description;
    my $primrssfeed = $viewinfo_obj->rssfeed;
    my $start_loc   = $viewinfo_obj->start_loc;
    my $start_stid  = $viewinfo_obj->start_stid;
    my $profilename = $viewinfo_obj->profilename;
    my $active      = $viewinfo_obj->active;
             
    my @profiledbs       = $config->get_profiledbs($profilename);
    
    my @viewdbs          = $config->get_viewdbs($viewname);
    
    my $all_rssfeeds_ref = $config->get_rssfeed_overview();
    
    my $viewrssfeed_ref=$config->get_rssfeeds_of_view($viewname);

    my $viewinfo={
        viewname     => $viewname,
        description  => $description,
        active       => $active,
        start_loc    => $start_loc,
        start_stid   => $start_stid,
        profilename  => $profilename,
        viewdbs      => \@viewdbs,
        allrssfeeds  => $all_rssfeeds_ref,
        viewrssfeed  => $viewrssfeed_ref,
        primrssfeed  => $primrssfeed,
    };

    
    my $ttdata={
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        
        dbnames    => \@profiledbs,
        
        viewinfo   => $viewinfo,
        
        dbinfo     => $dbinfotable,
        
        config     => $config,
        session    => $session,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_view_record_edit_tname},$ttdata,$r);

    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $viewname         = $self->param('viewid')             || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$config->view_exists($viewname)) {        
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

    if (!$config->view_exists($viewname)) {        
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"),$r,$msg);
        
        return Apache2::Const::OK;
    }

    # Variables

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden
    
    my $method          = decode_utf8($query->param('_method')) || '';
    my $confirm         = $query->param('confirm') || 0;

    if ($method eq "DELETE"){
        $logger->debug("About to delete $viewname");
        
        if ($confirm){
            my $viewinfo_ref = $config->get_viewinfo->search({ viewname => $viewname})->single;
            
            my $ttdata={
                stylesheet => $stylesheet,
                viewinfo   => $viewinfo_ref,
                
                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };

            $logger->debug("Asking for confirmation");
            OpenBib::Common::Util::print_page($config->{tt_admin_view_record_delete_confirm_tname},$ttdata,$r);

            return Apache2::Const::OK;
        }
        else {
            $logger->debug("Redirecting to delete location");
            $self->query->method('DELETE');    
            $self->query->headers_out->add(Location => "$config->{base_loc}/$config->{handler}{admin_view_loc}{name}/$viewname");
            $self->query->status(Apache2::Const::REDIRECT);
            return;
        }
    }

    # Ansonsten POST oder PUT => Aktualisieren

    my $description     = decode_utf8($query->param('description'))     || '';
    my $active          = $query->param('active')          || 0;
    my $primrssfeed     = $query->param('primrssfeed')     || '';
    my $viewstart_loc   = $query->param('viewstart_loc')             || '';
    my $viewstart_stid  = $query->param('viewstart_stid')            || '';
    my $profilename     = $query->param('profilename')     || '';
    my @viewdb          = ($query->param('viewdb'))?$query->param('viewdb'):();
    my @rssfeeds        = ($query->param('rssfeeds'))?$query->param('rssfeeds'):();


    # Profile muss vorhanden sein.
    if (!$config->profile_exists($profilename)) {
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil unter diesem Namen"),$r,$msg);

        return Apache2::Const::OK;
    }

    my $thisviewinfo_ref = {
        viewname    => $viewname,
        description => $description,
        active      => $active,
        primrssfeed => $primrssfeed,
        start_loc   => $viewstart_loc,
        start_stid  => $viewstart_stid,
        profilename => $profilename,
        viewdb      => \@viewdb,
        rssfeeds    => \@rssfeeds,
    };        

    $logger->debug("Info: ".YAML::Dump($thisviewinfo_ref));
    
    $config->update_view($thisviewinfo_ref);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$config->{base_loc}/$config->{handler}{admin_view_loc}{name}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r                = $self->param('r');

    my $viewname         = $self->param('viewid')             || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$config->view_exists($viewname)) {        
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

    $config->del_view($viewname);
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$config->{base_loc}/$config->{handler}{admin_view_loc}{name}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
