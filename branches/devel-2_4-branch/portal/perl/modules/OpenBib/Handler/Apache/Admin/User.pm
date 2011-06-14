#####################################################################
#
#  OpenBib::Handler::Apache::Admin::User
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

package OpenBib::Handler::Apache::Admin::User;

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
        'show_search_negotiate'     => 'show_search_negotiate',
        'show_search_as_html'       => 'show_search_as_html',
        'show_search_as_json'       => 'show_search_as_json',
        'show_search_as_rdf'        => 'show_search_as_rdf',
        'show_search_form'          => 'show_search_form',
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
    my $view           = $self->param('view')                   || '';

    my $config  = OpenBib::Config->instance;

    my $negotiated_type_ref = $self->negotiate_type;

    my $new_location = "$config->{base_loc}/$view/$config->{admin_user_loc}.$negotiated_type_ref->{suffix}";

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

    $logger->debug("Server: ".$r->get_server_name."Representation: $representation");
    
    # TT-Data erzeugen
    my $ttdata={
        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },

        view       => $view,

        sessionID  => $session->{ID},
        
        session    => $session,
        
        user       => $user,
        config     => $config,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_user_tname},$ttdata,$r);

}


sub show_search_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')                   || '';
    my $representation = $self->param('representation')         || '';

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
    
    # TT-Data erzeugen
    my $ttdata={
        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },

        view       => $view,

        sessionID  => $session->{ID},
        
        session    => $session,
        
        user       => $user,
        config     => $config,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_user_search_form_tname},$ttdata,$r);

}

sub show_search_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $view           = $self->param('view')                   || '';

    my $config  = OpenBib::Config->instance;

    my $negotiated_type_ref = $self->negotiate_type;

    my $new_location = "$config->{base_loc}/$view/$config->{admin_user_loc}/search.$negotiated_type_ref->{suffix}";

    $self->query->method('GET');
    $self->query->content_type($negotiated_type_ref->{content_type});
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $new_location");

    return;
}

sub show_search_as_html {
    my $self = shift;

    $self->param('representation','html');

    $self->show_search;

    return;
}

sub show_search_as_json {
    my $self = shift;

    $self->param('representation','json');

    $self->show_search;

    return;
}

sub show_search_as_rdf {
    my $self = shift;

    $self->param('representation','rdf');

    $self->show_search;

    return;
}

sub show_search {
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

    $logger->debug("Server: ".$r->get_server_name."Representation: $representation");

    my $roleid          = $query->param('roleid')          || '';
    my $username        = $query->param('username')        || '';    
    my $surname         = decode_utf8($query->param('surname'))         || '';
    my $commonname      = decode_utf8($query->param('commonname'))      || '';

    my $userlist_ref = [];
    
    # Verbindung zur SQL-Datenbank herstellen
    my $userdbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);
    
    my $sql_stmt = "select userid from user where ";
    my @sql_where = ();
    my @sql_args = ();
    
    if ($roleid) {
        $sql_stmt = "select userid from userrole where roleid=?";
        push @sql_args, $roleid;
    }
    else {
        if ($username) {
            push @sql_where,"loginname = ?";
            push @sql_args, $username;
        }
        
        if ($commonname) {
            push @sql_where, "nachname = ?";
            push @sql_args, $commonname;
        }
        
        if ($surname) {
            push @sql_where, "vorname = ?";
            push @sql_args, $surname;
        }
        
        if (!@sql_where){
            OpenBib::Common::Util::print_warning($msg->maketext("Bitte geben Sie einen Suchbegriff ein."),$r,$msg);
            return Apache2::Const::OK;
        }
        
        $sql_stmt.=join(" and ",@sql_where);
    }
    
    
    $logger->debug($sql_stmt);
    
    my $request = $userdbh->prepare($sql_stmt);
    $request->execute(@sql_args);
    
    $logger->debug("Looking up user $username/$surname/$commonname");
    
    while (my $result=$request->fetchrow_hashref){
        $logger->debug("Found ID $result->{userid}");
        my $single_user = new OpenBib::User({ID => $result->{userid}});
        push @$userlist_ref, $single_user->get_info;
    }
    
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        
        sessionID  => $session->{ID},
        
        session    => $session,
        
        userlist   => $userlist_ref,
        
        user       => $user,
        config     => $config,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_admin_user_search_tname},$ttdata,$r);    
}
    
1;
