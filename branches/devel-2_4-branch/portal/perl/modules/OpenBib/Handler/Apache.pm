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
use CGI::Application::Plugin::Redirect;
use Log::Log4perl qw(get_logger :levels);
use List::MoreUtils qw(none any);
use Apache2::URI ();
use APR::URI ();
use Encode qw(decode_utf8 encode_utf8);
use JSON::XS;
use Template;
use XML::RSS;
use YAML ();

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Template::Provider;
use OpenBib::User;

use base 'CGI::Application';


sub cgiapp_prerun {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    $logger->debug("Entering cgiapp_prerun");
   
    my $r            = $self->param('r');
    
    my $config       = OpenBib::Config->instance;
    my $view         = $self->param('view') || $config->get('defaultview');
    my $session      = OpenBib::Session->instance({ apreq => $r , view => $view });
    my $user         = OpenBib::User->instance({sessionID => $session->{ID}});

    my $useragent    = $r->headers_in->{'User-Agent'} || '';

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);
    my $queryoptions = OpenBib::QueryOptions->instance($self->query());
    
    my $servername   = $r->get_server_name;
    
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
    
    if ($r->method eq "GET" && $last_uri_element !~/(\.html|\.json|\.rdf|\.rss|\.include)$/){
       $self->negotiate_type;
       
       # Pfade sind immer mit base_loc und view
       my $baseloc    = $config->get('base_loc');
       $path =~s{^$baseloc/[^/]+}{$path_prefix};

       $logger->debug("Corrected External Path: $path");

       my $args="";
       if (!$self->query->param('l')){
           $self->negotiate_language;
           $args="?l=".$self->param('lang');
           if ($self->query->args()){
               $args="$args;".$self->query->args();
           }
       }
       else {
           $args="?".$self->query->args();
       }

#        $self->query->method('GET');
#        $self->query->content_type($self->param('content_type'));
#        $self->query->headers_out->add(Location => $path.$self->param('representation').$args);
#        $self->query->status(Apache2::Const::REDIRECT);
#        return;
       return $self->redirect($path.".".$self->param('representation').$args);
   }

   if ($r->method eq "GET" && !$self->query->param('l')){

       $self->negotiate_language;
       
       # Pfade sind immer mit base_loc und view
       my $baseloc    = $config->get('base_loc');
       $path =~s{^$baseloc/[^/]+}{$path_prefix};
       
       $logger->debug("Corrected External Path: $path");
       
       my $args = "?l=".$self->param('lang');

       $args=$args.";".$self->query->args() if ($self->query->args());

#        $self->query->method('GET');
#        $self->query->content_type($self->param('content_type'));
#        $self->query->headers_out->add(Location => $path.$self->param('representation').$args);
#        $self->query->status(Apache2::Const::REDIRECT);
#        return;
       return $self->redirect($path.$args);
   }

    return;
}

sub cgiapp_init() {
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
   
   my $id = "";
   if ($last_uri_element=~/^(.+?)(\.html|\.json|\.rdf|\.rss|\.include)$/){
       $id               = $1;
       my ($representation) = $2 =~/^\.(.+?)$/;
       my $content_type   = $config->{'content_type_map_rev'}{$representation};

       # Korrektur des ausgehandelten Typs bei direkter Auswahl einer bestimmten Repraesentation
       $self->param('content_type',$content_type);
       $self->param('representation',$representation);
   }
#    # Sonst Aushandlung und Redirect
#    elsif ($r->method eq "GET"){

#        $self->negotiate_type;
       
#        # Pfade sind immer mit base_loc und view
#        my $baseloc    = $config->get('base_loc');
#        $path =~s{^$baseloc/[^/]+}{$path_prefix};

#        $logger->debug("Corrected External Path: $path");

#        my $args=$self->query->args();
       
#        $args = "?$args" if ($args);
       
#        if (!$self->query->param('l')){
#            $args="$args;l=".$self->param('lang');
#        }
       
#        $self->query->method('GET');
#        $self->query->content_type($self->param('content_type'));
#        $self->query->headers_out->add(Location => $path.$self->param('representation').$args);
#        $self->query->status(Apache2::Const::REDIRECT);
       
#        return;
#    }

   # Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Parameter 'l'
   if ($self->query->param('l')){
       $self->param('lang',$self->query->param('l'));
   }
#    elsif ($r->method eq "GET"){

#        $self->negotiate_language;
       
#        # Pfade sind immer mit base_loc und view
#        my $baseloc    = $config->get('base_loc');
#        $path =~s{^$baseloc/[^/]+}{$path_prefix};
       
#        $logger->debug("Corrected External Path: $path");
       
#        my $args = "?l=".$self->param('lang');

#        $args=$args.";".$self->query->args() if ($self->query->args());
       
#        $self->query->method('GET');
#        $self->query->content_type($self->param('content_type'));
#        $self->query->headers_out->add(Location => $path.$self->param('representation').$args);
#        $self->query->status(Apache2::Const::REDIRECT);
       
#        return;
#    }
   
   # Message Katalog laden
   my $msg = OpenBib::L10N->get_handle($self->param('lang')) || $logger->error("L10N-Fehler");
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
   
   $logger->debug("Exit cgiapp_init");
   #   $self->query->charset('UTF-8');  # cause CGI.pm to send a UTF-8 Content-Type header
}

sub negotiate_content {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    
    my $accept       = $r->headers_in->{'Accept'} || '';
    my @accepted_types      = map { (split ";", $_)[0] } split /\*s,\*s/, $accept;

    my $lang         = $r->headers_in->{'Accept-Language'} || '';
    my @accepted_languages  = map { ($_)=$_=~/^(..)/} map { (split ";", $_)[0] } split /\*s,\*s/, $lang;
    
    $logger->debug("Accept: $accept - Types: ".YAML::Dump(\@accepted_types));
    $logger->debug("Accept-Language: $lang - Languages: ".YAML::Dump(\@accepted_languages));
    
    foreach my $information_resource_type (keys %{$config->{content_type_map}}){
        if (any { $_ eq $information_resource_type } @accepted_types) {
            $logger->debug("Negotiated Type: $information_resource_type - Suffix: ".$config->{content_type_map}->{$information_resource_type});
            $self->param('content_type',$information_resource_type);
            $self->param('represenatione',$config->{content_type_map}->{$information_resource_type});
            last;
        }
    }

    if (!$self->param('content_type') && !$self->param('representation') ){
        $logger->debug("Default Type: text/html - Suffix: html");
        $self->param('content_type','text/html');
        $self->param('representation','html');
    }
    
    if (!$self->param('lang')){
        my $language_found = 0;
        foreach my $language (@{$config->{lang}}){
            if (any { $_ eq $language } @accepted_languages) {
                $logger->debug("Negotiated Language: $language");
                $self->param('lang',$language);
                last;
            }
        }

        if (!$self->param('lang')){
            # Default language ist die erste definierte Sprache unter 'lang' in portal.yml
            $logger->debug("Default Language: ".$config->{lang}[0]);
            $self->param('lang',$config->{lang}[0]);
        }
    }

    return;
}

sub negotiate_type {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    
    my $accept       = $r->headers_in->{'Accept'} || '';
    my @accepted_types      = map { (split ";", $_)[0] } split /\*s,\*s/, $accept;

    $logger->debug("Accept: $accept - Types: ".YAML::Dump(\@accepted_types));
    
    foreach my $information_resource_type (keys %{$config->{content_type_map}}){
        if (any { $_ eq $information_resource_type } @accepted_types) {
            $logger->debug("Negotiated Type: $information_resource_type - Suffix: ".$config->{content_type_map}->{$information_resource_type});
            $self->param('content_type',$information_resource_type);
            $self->param('represenatione',$config->{content_type_map}->{$information_resource_type});
            last;
        }
    }

    if (!$self->param('content_type') && !$self->param('representation') ){
        $logger->debug("Default Type: text/html - Suffix: html");
        $self->param('content_type','text/html');
        $self->param('representation','html');
    }

    return;
}

sub negotiate_language {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    
    my $lang         = $r->headers_in->{'Accept-Language'} || '';
    my @accepted_languages  = map { ($_)=$_=~/^(..)/} map { (split ";", $_)[0] } split /\*s,\*s/, $lang;
    
    $logger->debug("Accept-Language: $lang - Languages: ".YAML::Dump(\@accepted_languages));
    
    foreach my $language (@{$config->{lang}}){
        if (any { $_ eq $language } @accepted_languages) {
            $logger->debug("Negotiated Language: $language");
            $self->param('lang',$language);
            last;
        }
    }

    if (!$self->param('lang')){
        $logger->debug("Default Language: de");
        $self->param('lang','de');
    }

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
        $self->print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"));
        return 0;
    }
}

sub print_warning {
    my $self = shift;
    my $warning = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->param('config');

    my $ttdata = {
        err_msg => $warning,
    };

    $self->print_page($config->{tt_error_tname},$ttdata);
  
    return;
}

sub print_info {
    my $self = shift;
    my $info = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->param('config');

    my $ttdata = {
        info_msg => $info,
    };

    $self->print_page($config->{tt_info_message_tname},$ttdata);
  
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
    my $lang           = $self->param('lang');
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

    if ($self->param('representation') eq "rss"){
        my $rss = new XML::RSS ( version => '1.0' ) ;
        $ttdata->{'rss'}           = $rss;
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
    $ttdata->{'lang'}           = $lang;
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
