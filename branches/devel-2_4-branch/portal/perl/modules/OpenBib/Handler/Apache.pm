#####################################################################
#
#  OpenBib::Handler::Apache
#
#  Dieses File ist (C) 2010-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use CGI::Application::Plugin::Apache qw(:all);
use Log::Log4perl qw(get_logger :levels);
use List::MoreUtils qw(none any);
use Apache2::URI ();
use APR::URI ();
use Encode qw(decode_utf8 encode_utf8);
use JSON::XS;
use Template;
use YAML ();

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Template::Provider;
use OpenBib::User;

use base 'CGI::Application';

sub cgiapp_init() {       # overrides
   my $self = shift;

   # Log4perl logger erzeugen
   my $logger = get_logger();

   $logger->debug("Entering cgiapp_init");
   
   my $r            = $self->param('r');

   my $config       = OpenBib::Config->instance;
   my $view         = $self->param('view') || $config->get('defaultview');
   my $session      = OpenBib::Session->instance({ apreq => $r , view => $view });
   my $user         = OpenBib::User->instance({sessionID => $session->{ID}});

   my $useragent    = $r->subprocess_env('HTTP_USER_AGENT');
   my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);
   my $queryoptions = OpenBib::QueryOptions->instance($self->query());

   my $servername = $r->get_server_name;
   
   my $path_prefix          = $config->get('base_loc');
   my $complete_path_prefix = "$path_prefix/$view";
   
   if (! $config->strip_view_from_uri($view)){
       $path_prefix = $complete_path_prefix;
   }

   # Letztes Pfad-Element bestimmen
   my $uri  = $r->parsed_uri;
   my $path = $uri->path;

   my ($last_uri_element) = $path =~m/([^\/]+)$/;

   $logger->debug("Full Internal Path: $path - Last URI Element: $last_uri_element ");
   

   my $representation = "";
   my $content_type   = "";
   
   my $id = "";
   if ($last_uri_element=~/^(.+?)(\.html|\.json|\.rdf|\.rss|\.include)$/){
       $id               = $1;
       ($representation) = $2 =~/^\.(.+?)$/;
       $content_type   = $config->{'content_type_map_rev'}{$representation};
   }
   # Sonst Aushandlung und Redirect
   elsif ($r->method eq "GET"){
       # Pfade sind immer mit base_loc und view
       my $baseloc    = $config->get('base_loc');
       $path =~s{^$baseloc/[^/]+}{$path_prefix};

       $logger->debug("Corrected External Path: $path");       

       my $args=$self->query->args();
       
       $args = "?$args" if ($args);
       
       my $negotiated_type_ref = $self->negotiate_type;

       $self->query->method('GET');
       $self->query->content_type($negotiated_type_ref->{content_type});
       $self->query->headers_out->add(Location => "$path.$negotiated_type_ref->{suffix}$args");
       $self->query->status(Apache2::Const::REDIRECT);
       
       return;
   }
   
   # Message Katalog laden
   my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
   $msg->fail_with( \&OpenBib::L10N::failure_handler );


   $self->param('config',$config);
   $self->param('session',$session);
   $self->param('user',$user);
   $self->param('useragent',$useragent);
   $self->param('stylesheet',$stylesheet);
   $self->param('msg',$msg);
   $self->param('qopts',$queryoptions);
   $self->param('servername',$servername);
   $self->param('path_prefix',$path_prefix);
   $self->param('id',$id);
   $self->param('representation',$representation);
   $self->param('content_type',$content_type);

   $logger->debug("Setting: id = $id , representation = $representation , content_type = $content_type , path_prefix = $path_prefix");
   $logger->debug("Exit cgiapp_init");
   #   $self->query->charset('UTF-8');  # cause CGI.pm to send a UTF-8 Content-Type header
}

sub negotiate_type {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    
    my $accept       = $r->headers_in->{Accept} || '';
    my @accept_types = map { (split ";", $_)[0] } split /\*s,\*s/, $accept;

    $logger->debug("Accept: $accept - Types: ".YAML::Dump(\@accept_types));
    
#     my $content_type_map_ref = {
#         "application/rdf+xml" => "rdf+xml",
#         "text/rdf+n3"         => "rdf+n3",
#         "text/html"           => "html",
#         "application/json"    => "json",
#     };

#     my $content_type_map_rev_ref = {
#         "rdf+xml" => "application/rdf+xml",
#         "rdf+n3"  => "text/rdf+n3",
#         "html"    => "text/html",
#         "json"    => "application/json",
#     };

    my $information_resource_found = 0;
    foreach my $information_resource_type (keys %{$config->{content_type_map}}){
        if (any { $_ eq $information_resource_type } @accept_types) {

            $logger->debug("Returning Type: $information_resource_type - Suffix: ".$config->{content_type_map}->{$information_resource_type});

            return {
                content_type => $information_resource_type,
                suffix       => $config->{content_type_map}->{$information_resource_type},
            };
        }                                                
    }

    $logger->debug("Returning Default Type: text/html - Suffix: html");

    return {
        content_type   => 'text/html',
        suffix => 'html',
    };
}

sub negotiate_url {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $uri  = $r->parsed_uri;
    my $path = $uri->path;

    # Pfade sind immer mit base_loc und view
    my $baseloc    = $self->param('config')->get('base_loc');
    my $pathprefix = $self->param('path_prefix');
    $path =~s{^$baseloc/[^/]+}{$pathprefix};

    my $args=$self->query->args();

    $args = "?$args" if ($args);
    
    my $negotiated_type_ref = $self->negotiate_type;

    $self->query->method('GET');
    $self->query->content_type($negotiated_type_ref->{content_type});
    $self->query->headers_out->add(Location => "$path.$negotiated_type_ref->{suffix}$args");
    $self->query->status(Apache2::Const::REDIRECT);

    $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $path.$negotiated_type_ref->{suffix}");

    return;
}

sub show_record_negotiate {
    my $self = shift;

    $self->show_collection_negotiate;

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

sub show_collection_as_rss {
    my $self = shift;

    $self->param('representation','rss');

    $self->show_collection;

    return;
}

sub show_collection_as_include {
    my $self = shift;

    $self->param('representation','include');

    $self->show_collection;

    return;
}

sub show_collection_recent_as_html {
    my $self = shift;

    $self->param('representation','html');

    $self->show_collection_recent;

    return;
}

sub show_collection_recent_as_json {
    my $self = shift;

    $self->param('representation','json');

    $self->show_collection_recent;

    return;
}

sub show_collection_recent_as_rdf {
    my $self = shift;

    $self->param('representation','rdf');

    $self->show_collection_recent;

    return;
}

sub show_collection_recent_as_rss {
    my $self = shift;

    $self->param('representation','rss');

    $self->show_collection_recent;

    return;
}

sub show_collection_recent_as_include {
    my $self = shift;

    $self->param('representation','include');

    $self->show_collection_recent;

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

sub show_record_as_rss {
    my $self = shift;

    $self->param('representation','rss');

    $self->show_record;

    return;
}

sub show_record_as_include {
    my $self = shift;

    $self->param('representation','include');

    $self->show_record;

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

sub show_search_as_rss {
    my $self = shift;

    $self->param('representation','rss');

    $self->show_search;

    return;
}

sub show_search_as_include {
    my $self = shift;

    $self->param('representation','include');

    $self->show_search;

    return;
}


sub show_index_as_html {
    my $self = shift;

    $self->param('representation','html');

    $self->show_index;

    return;
}

sub show_index_as_json {
    my $self = shift;

    $self->param('representation','json');

    $self->show_index;

    return;
}

sub show_index_as_rdf {
    my $self = shift;

    $self->param('representation','rdf');

    $self->show_index;

    return;
}

sub show_index_as_include {
    my $self = shift;

    $self->param('representation','include');

    $self->show_index;

    return;
}

sub show_popular_as_html {
    my $self = shift;

    $self->param('representation','html');

    $self->show_popular;

    return;
}

sub show_popular_as_json {
    my $self = shift;

    $self->param('representation','json');

    $self->show_popular;

    return;
}

sub show_popular_as_rdf {
    my $self = shift;

    $self->param('representation','rdf');

    $self->show_popular;

    return;
}

sub show_popular_as_include {
    my $self = shift;

    $self->param('representation','include');

    $self->show_popular;

    return;
}

sub is_authenticated {
    my $self   = shift;
    my $role   = shift;
    my $userid = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $r              = $self->param('r');
    my $path_prefix    = $self->param('path_prefix');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');

    $logger->debug("Args: Role: $role UserID: $userid");
    $logger->debug("Session-UserID: ".$user->{ID});
    
    if (! $user->{ID}){
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;
        
        # Return-URL in der Session abspeichern
        
        $session->set_returnurl($return_url);
        
        $r->internal_redirect("$path_prefix/$config->{login_loc}");
        
        return Apache2::Const::OK;
    }

    if ($role eq "admin" && $user->is_admin){
        return 1;
    }
    elsif ($role eq "user" && ( $user->is_admin || $user->{ID} eq $userid)){
        return 1;
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"),$r,$msg);
        return 0;
    }
}

sub print_warning {
    my $self = shift;
    my $warning= shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    
    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $servername     = $self->param('servername');
    my $path_prefix    = $self->param('path_prefix');
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type') || $config->{'content_type_map_rev'}{$representation} || 'text/html';

    my $ttdata         = {};
    
    # View- und Datenbank-spezifisches Templating
    my $database  = $ttdata->{'database'};
    my $sessionID = $session->{ID};
    
    my $sysprofile= $config->get_viewinfo->search({ viewname => $view })->single()->profilename;

    # Nutzer-DB zugreifbar? Falls nicht, dann wird der Menu-Punkt
    # Einloggen/Mein KUG automatisch deaktiviert
    
    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }

    my $loginname="";

    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $loginname=$user->get_username();
    }

    # TT-Data anreichern
    $ttdata->{'view'}           = $view;
    $ttdata->{'sessionID'}      = $sessionID;
    $ttdata->{'representation'} = $representation;
    $ttdata->{'content_type'}   = $content_type;
    $ttdata->{'session'}        = $session;
    $ttdata->{'config'}         = $config;
    $ttdata->{'user'}           = $user;
    $ttdata->{'msg'}            = $msg;
    $ttdata->{'stylesheet'}     = $stylesheet;
    $ttdata->{'servername'}     = $servername;
    $ttdata->{'loginname'}      = $loginname;
    $ttdata->{'sysprofile'}     = $sysprofile;
    $ttdata->{'to_json'}        = sub {
        my $ref = shift;
        return encode_json $ref;
    };

    $ttdata->{'errmsg'} = $warning;
    
    my $templatename = $config->{tt_error_tname};
    
    $logger->debug("Using base Template $templatename");
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '',
        view         => $view,
        profile      => $sysprofile,
        templatename => $templatename,
    });

    $logger->debug("Using database/view specific Template $templatename");
  
    my $template = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
	    ABSOLUTE       => 1,
        }) ],
         OUTPUT         => $r,    # Output geht direkt an Apache Request
         RECURSION      => 1,
    });
  
    # Dann Ausgabe des neuen Headers
    $r->content_type($content_type);
  
    $template->process($templatename, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
  
    return;
}

sub print_info {
    my $self = shift;
    my $info = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    
    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $servername     = $self->param('servername');
    my $path_prefix    = $self->param('path_prefix');
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type') || $config->{'content_type_map_rev'}{$representation} || 'text/html';

    my $ttdata         = {};
    
    # View- und Datenbank-spezifisches Templating
    my $database  = $ttdata->{'database'};
    my $sessionID = $session->{ID};
    
    my $sysprofile= $config->get_viewinfo->search({ viewname => $view })->single()->profilename;

    # Nutzer-DB zugreifbar? Falls nicht, dann wird der Menu-Punkt
    # Einloggen/Mein KUG automatisch deaktiviert
    
    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }

    my $loginname="";

    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $loginname=$user->get_username();
    }

    # TT-Data anreichern
    $ttdata->{'view'}           = $view;
    $ttdata->{'sessionID'}      = $sessionID;
    $ttdata->{'representation'} = $representation;
    $ttdata->{'content_type'}   = $content_type;
    $ttdata->{'session'}        = $session;
    $ttdata->{'config'}         = $config;
    $ttdata->{'user'}           = $user;
    $ttdata->{'msg'}            = $msg;
    $ttdata->{'stylesheet'}     = $stylesheet;
    $ttdata->{'servername'}     = $servername;
    $ttdata->{'loginname'}      = $loginname;
    $ttdata->{'sysprofile'}     = $sysprofile;
    $ttdata->{'to_json'}        = sub {
        my $ref = shift;
        return encode_json $ref;
    };

    $ttdata->{'errmsg'} = $info;

    my $templatename = $config->{tt_info_message_tname};
    
    $logger->debug("Using base Template $templatename");
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '',
        view         => $view,
        profile      => $sysprofile,
        templatename => $templatename,
    });

    $logger->debug("Using database/view specific Template $templatename");
  
    my $template = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
	    ABSOLUTE       => 1,
        }) ],
         OUTPUT         => $r,    # Output geht direkt an Apache Request
         RECURSION      => 1,
    });
  
    # Dann Ausgabe des neuen Headers
    $r->content_type($content_type);
  
    $template->process($templatename, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
  
    return;
}   

sub print_page {
    my $self = shift;
    my ($templatename,$ttdata)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    
    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $servername     = $self->param('servername');
    my $path_prefix    = $self->param('path_prefix');
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type') || $ttdata->{'content_type'} || $config->{'content_type_map_rev'}{$representation} || 'text/html';
    
    # View- und Datenbank-spezifisches Templating
    my $database  = $ttdata->{'database'};
    my $sessionID = $session->{ID};
    
    my $sysprofile= $config->get_viewinfo->search({ viewname => $view })->single()->profilename;

    # Nutzer-DB zugreifbar? Falls nicht, dann wird der Menu-Punkt
    # Einloggen/Mein KUG automatisch deaktiviert
    
    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }

    my $loginname="";

    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $loginname=$user->get_username();
    }

    # TT-Data anreichern
    $ttdata->{'view'}           = $view;
    $ttdata->{'sessionID'}      = $sessionID;
    $ttdata->{'representation'} = $representation;
    $ttdata->{'content_type'}   = $content_type;
    $ttdata->{'session'}        = $session;
    $ttdata->{'config'}         = $config;
    $ttdata->{'user'}           = $user;
    $ttdata->{'msg'}            = $msg;
    $ttdata->{'stylesheet'}     = $stylesheet;
    $ttdata->{'servername'}     = $servername;
    $ttdata->{'loginname'}      = $loginname;
    $ttdata->{'sysprofile'}     = $sysprofile;
    $ttdata->{'to_json'}        = sub {
        my $ref = shift;
        return encode_json $ref;
    };
    $ttdata->{'iso2utf'}        = sub {
        my $string=shift;
        $string=Encode::encode("iso-8859-1",$string);
        return $string;
    };

    $logger->debug("Using base Template $templatename");

    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $database,
        view         => $view,
        profile      => $sysprofile,
        templatename => $templatename,
    });

    $logger->debug("Using database/view specific Template $templatename");
  
    my $template = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
	    ABSOLUTE       => 1,
        }) ],
         OUTPUT         => $r,    # Output geht direkt an Apache Request
         RECURSION      => 1,
    });
  
    # Dann Ausgabe des neuen Headers
    $r->content_type($content_type);
  
    $template->process($templatename, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
  
    return;
}

sub strip_suffix {
    my $self    = shift;
    my $element = shift;

    if ($element=~/^(.+?)(\.html|\.json|\.rdf|\.rss|\.include)$/){
        return $1;
    }
    
    return $element;
}

1;
