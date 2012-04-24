#####################################################################
#
#  OpenBib::Handler::Apache
#
#  Dieses File ist (C) 2010-2012 Oliver Flimm <flimm@openbib.org>
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
use Apache2::Access ();
use Apache2::RequestUtil ();
use Apache2::Const -compile => qw(OK DECLINED HTTP_UNAUTHORIZED);
use Apache2::URI ();
use APR::URI ();
use Encode qw(decode_utf8 encode_utf8);
use JSON::XS;
use Template;
use URI::Escape;
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
   my $query        = $self->query();
   
   my $useragent    = $r->headers_in->{'User-Agent'} || "OpenBib Search Portal: http://search.openbib.org/";
   
   my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);
   my $queryoptions = OpenBib::QueryOptions->instance($query);

   my $servername   = $r->get_server_name;
   
   my $path_prefix          = $config->get('base_loc');
   my $complete_path_prefix = "$path_prefix/$view";

   # Shortcut fuer HTTP Basic Authentication anhand lokaler Datenbank
   # Wenn beim Aufruf ein Username und ein Passwort uebergeben wird, dann
   # wird der Nutzer damit authentifiziert und die Session automatisch authorisiert

   # Es interessiert nicht der per so in der Apache-Konfiguration openbib.conf definierte Authentifizierungstyp,
   # sondern der etwaig mit dem aktuellen Request gesendete Typ!
   my ($http_authtype) = $r->headers_in->{'Authorization'} =~/^(\S+)\s+/; #  $r->ap_auth_type(); #

   $logger->debug("HTTP Authtype: $http_authtype");

   # Nur wenn konkrete Authentifizierungsinformationen geliefert wurden, wird per shortcut
   # und HTTP Basic Authentication authentifiziert, ansonsten gilt die Cookie based authentication
   if ($http_authtype eq "Basic"){

       my ($status, $password) = $r->get_basic_auth_pw;

       $logger->debug("get_basic_auth: Status $status / Password $password");
       
       return $status unless $status == Apache2::Const::OK;

       my $http_user     = $r->user;

       $logger->debug("Authentication Shortcut for user $http_user : Status $status / Password: $password");

       my $userid = $user->authenticate_self_user({ username => $http_user, password => $password });

       my $targetid = $config->get_logintarget_self();
       
       if ($userid > 0){
           $user->connect_session({
               sessionID => $session->{ID},
               userid    => $userid,
               targetid  => $targetid,
           });
           $user->{ID} = $userid;
       }
       else {
           $r->note_basic_auth_failure;
           $logger->debug("Unauthorized");
           return Apache2::Const::HTTP_UNAUTHORIZED;
       }
   }

   $logger->debug("User-ID:".$user->{ID});
   
   # Letztes Pfad-Element bestimmen
   my $uri  = $r->parsed_uri;
   my $path = $uri->path;

   my ($last_uri_element) = $path =~m/([^\/]+)$/;

   $logger->debug("Full Internal Path: $path - Last URI Element: $last_uri_element ");

   if (! $config->strip_view_from_uri($view)){
       $path_prefix = $complete_path_prefix;
   }
   else {
       $path =~s/^(\/[^\/]+)\/[^\/]+(\/.+)$/$1$2/;
   }

   my $id = "";
   if ($last_uri_element=~/^(.+?)(\.html|\.json|\.rdf|\.rss|\.include)$/){
       $id               = $1;
       my ($representation) = $2 =~/^\.(.+?)$/;
       my $content_type   = $config->{'content_type_map_rev'}{$representation};

       # Korrektur des ausgehandelten Typs bei direkter Auswahl einer bestimmten Repraesentation
       $self->param('content_type',$content_type);
       $self->param('representation',$representation);
   }

   # Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Parameter 'l'
   if ($self->query->param('l')){
       $logger->debug("Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Parameter: ".$self->query->param('l'));
       $self->param('lang',$self->query->param('l'));

       # Setzen als Cookie
       $session->set_cookie($r,'lang',$self->param('lang'));
   }
   # alterantiv Korrektur der ausgehandelten Sprache wenn durch cookie festgelegt
   elsif ($session->{lang}){
       $logger->debug("Korrektur der ausgehandelten Sprache durch Cookie: ".$session->{lang});
       $self->param('lang',$session->{lang});
   }

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
   $self->param('path',$path);
   
   $logger->debug("Exit cgiapp_init");
   #   $self->query->charset('UTF-8');  # cause CGI.pm to send a UTF-8 Content-Type header
}

sub cgiapp_prerun {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    $logger->debug("Entering cgiapp_prerun");
   
    my $r            = $self->param('r');
    my $config       = OpenBib::Config->instance;
    my $view         = $self->param('view');    # || $config->get('defaultview');
    my $session      = $self->param('session'); #OpenBib::Session->instance({ apreq => $r , view => $view });

    if (!$self->param('disable_content_negotiation')){
#        my $config       = OpenBib::Config->instance;
#        my $view         = $self->param('view') || $config->get('defaultview');
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

            # Personalisierte URIs
            if ($self->param('personalized_loc')){
                my $user = OpenBib::User->instance({sessionID => $session->{ID}});
                if ($user->{ID}){
                    my $loc = $self->param('personalized_loc');
                    $logger->debug("Replacing $path_prefix/$loc with $path_prefix/user/$user->{ID}/$loc");
                    my $old_loc = "$path_prefix/$loc";
                    my $new_loc = "$path_prefix/user/$user->{ID}/$loc";
                    $path=~s{$old_loc}{$new_loc};
                }
            }

            $logger->debug("Corrected External Path: $path");
            
            my $args="";
            if (!$self->query->param('l')){
                if ($session->{lang}){
                    $logger->debug("Sprache definiert durch Cookie: ".$session->{lang});
                    $self->param('lang',$session->{lang});
                }
                else {
                    $self->negotiate_language;
                }
                
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
            return $self->redirect($path.".".$self->param('representation').$args,'303 See Other');
        }

    }

    if ($r->method eq "GET" && !$self->query->param('l')){
#        my $config       = OpenBib::Config->instance;
#        my $view         = $self->param('view') || $config->get('defaultview');
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

        if ($session->{lang}){
            $logger->debug("Sprache definiert durch Cookie: ".$session->{lang});
            $self->param('lang',$session->{lang});
        }
        else {
            $self->negotiate_language;
        }
        
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
        return $self->redirect($path.$args,'303 See Other');
    }
    
    return;
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
    
    foreach my $information_type (keys %{$config->{content_type_map}}){
        if (any { $_ eq $information_type } @accepted_types) {
            $logger->debug("Negotiated Type: $information_type - Suffix: ".$config->{content_type_map}->{$information_type});
            $self->param('content_type',$information_type);
            $self->param('represenatione',$config->{content_type_map}->{$information_type});
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
    
    foreach my $information_type (keys %{$config->{content_type_map}}){
        if (any { $_ eq $information_type } @accepted_types) {
            $logger->debug("Negotiated Type: $information_type - Suffix: ".$config->{content_type_map}->{$information_type});
            $self->param('content_type',$information_type);
            $self->param('representation',$config->{content_type_map}->{$information_type});
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
    my $path           = $self->param('path');
    my $servername     = $self->param('servername');
    my $msg            = $self->param('msg');

    $logger->debug("Args: Role: $role UserID: $userid");
    $logger->debug("Session-UserID: ".$user->{ID});
    
    if (! $user->{ID}){
        # Aufruf-URL
        my $return_uri  = uri_escape($r->parsed_uri->path);
        
        # Return-URL in der Session abspeichern
        
        return $self->redirect("$path_prefix/$config->{login_loc}?redirect_to=$return_uri",'303 See Other');
    }

    if ($role eq "admin" && $user->is_admin){
        return 1;
    }
    elsif ($role eq "user" && ( $user->is_admin || $user->{ID} eq $userid)){
        return 1;
    }
    else {
      $logger->debug("User authenticated as $user->{ID}, but doesn't match required userid $userid");
#      $self->print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"));
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
    my $path           = $self->param('path');
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type') || $ttdata->{'content_type'} || $config->{'content_type_map_rev'}{$representation} || 'text/html';

    $ttdata = $self->add_default_ttdata($ttdata);
    
    $logger->debug("Using base Template $templatename");

    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $ttdata->{database},
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
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

sub add_default_ttdata {
    my ($self,$ttdata) = @_; 

    my $view           = $self->param('view');
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
    my $path           = $self->param('path');
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type') || $ttdata->{'content_type'} || $config->{'content_type_map_rev'}{$representation} || 'text/html';
    
    # View- und Datenbank-spezifisches Templating
    my $database  = $ttdata->{'database'};
    my $sessionID = $session->{ID};
    
    my $sysprofile= $config->get_profilename_of_view($view);

    # Nutzer-DB zugreifbar? Falls nicht, dann wird der Menu-Punkt
    # Einloggen/Mein KUG automatisch deaktiviert
    
    if (!$user->userdb_accessible()){
        $config->{login_active} = 0;
    }

    my $username="";

    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $username=$user->get_username();
    }

    # Mitgelieferter Username geht vor:
    if ($ttdata->{'username'}){
        $username = $ttdata->{'username'};
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
    $ttdata->{'username'}       = $username;
    $ttdata->{'sysprofile'}     = $sysprofile;
    $ttdata->{'path'}           = $path;
    $ttdata->{'cgiapp'}         = $self;
    $ttdata->{'to_json'}        = sub {
        my $ref = shift;
        return encode_json $ref;
    };
    $ttdata->{'uri_escape'}     = sub {
        my $string = shift;
        return uri_escape($string);
    };

    $ttdata->{'iso2utf'}        = sub {
        my $string=shift;
        $string=Encode::encode("iso-8859-1",$string);
        return $string;
    };

    $ttdata->{'decode_utf8'}    = sub {
        my $string=shift;
        return decode_utf8($string);
    };
    
    return $ttdata;
}

# sub print_recordlist {
#     my $self = shift;
#     my ($recordlist,$templatename,$ttdata)=@_;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     # Dispatched Args
#     my $view           = $self->param('view')           || '';
    
#     # Shared Args
#     my $r              = $self->param('r');
#     my $config         = $self->param('config');
#     my $session        = $self->param('session');
#     my $user           = $self->param('user');
#     my $msg            = $self->param('msg');
#     my $lang           = $self->param('lang');
#     my $queryoptions   = $self->param('qopts');
#     my $stylesheet     = $self->param('stylesheet');
#     my $useragent      = $self->param('useragent');
#     my $servername     = $self->param('servername');
#     my $path_prefix    = $self->param('path_prefix');
#     my $path           = $self->param('path');
#     my $representation = $self->param('representation');
#     my $content_type   = $self->param('content_type') || $ttdata->{'content_type'} || $config->{'content_type_map_rev'}{$representation} || 'text/html';
    
# #     # Set defaults
# #     my $database          = exists $arg_ref->{database}
# #         ? $arg_ref->{database}          : undef;
# #     my $hits              = exists $arg_ref->{hits}
# #         ? $arg_ref->{hits}              : -1;
# #     my $hitrange          = exists $arg_ref->{hitrange}
# #         ? $arg_ref->{hitrange}          : 50;
# #     my $sortorder         = exists $arg_ref->{sortorder}
# #         ? $arg_ref->{sortorder}         : 'up';
# #     my $sorttype          = exists $arg_ref->{sorttype}
# #         ? $arg_ref->{sorttype}          : 'author';
# #     my $offset            = exists $arg_ref->{offset}
# #         ? $arg_ref->{offset}            : undef;
# #     my $template          = exists $arg_ref->{template}
# #         ? $arg_ref->{template}          : 'tt_search_tname';
# #     my $location          = exists $arg_ref->{location}
# #         ? $arg_ref->{location}          : 'search_loc';
# #     my $parameter         = exists $arg_ref->{parameter}
# #         ? $arg_ref->{parameter}         : {};


#     my $query             = $self->query();

#     my $hitrange          = $query->param('hitrange') || 50;
#     my $sortorder         = $query->param('srto')     || 'up';
#     my $sorttype          = $query->param('srt')      || 'author';
#     my $offset            = $query->param('offset')   || undef;
    
#     my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;
#     my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;

#     my $searchtitofcnt = decode_utf8($query->param('searchtitofcnt'))    || '';

#     $logger->debug("Representation: $representation - Content-Type: $content_type ");
    
#     if ($recordlist->get_size() == 0) {
#         $self->print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"));
#     }
#     elsif ($recordlist->get_size() == 1) {
#         my $record = $recordlist->{recordlist}[0];

#         $self->query->method('GET');
#         $self->query->headers_out->add(Location => "$path_prefix/$config->{title_loc}/$record->{database}/$record->{id}.html");
#         $self->query->status(Apache2::Const::REDIRECT);
#         return;
#     }
#     elsif ($recordlist->get_size() > 1) {
#         my ($atime,$btime,$timeall);
        
#         if ($config->{benchmark}) {
#             $atime=new Benchmark;
#         }

#         # Kurztitelinformationen fuer RecordList laden
#         $recordlist->load_brief_records;
        
#         if ($config->{benchmark}) {
#             $btime   = new Benchmark;
#             $timeall = timediff($btime,$atime);
#             $logger->info("Zeit fuer : ".($recordlist->get_size)." Titel : ist ".timestr($timeall));
#             undef $atime;
#             undef $btime;
#             undef $timeall;
#         }

#         # Anreicherung mit OLWS-Daten
#         if (defined $query->param('olws') && $query->param('olws') eq "Viewer"){            
#             foreach my $record ($recordlist->get_records()){
#                 if (exists $circinfotable->{$record->{database}} && exists $circinfotable->{$record->{database}}{circcheckurl}){
#                     $logger->debug("Endpoint: ".$circinfotable->{$record->{database}}{circcheckurl});
#                     my $soapresult;
#                     eval {
#                         my $soap = SOAP::Lite
#                             -> uri("urn:/Viewer")
#                                 -> proxy($circinfotable->{$record->{database}}{circcheckurl});
                        
#                         my $result = $soap->get_item_info(
#                             SOAP::Data->name(parameter  =>\SOAP::Data->value(
#                                 SOAP::Data->name(collection => $circinfotable->{$record->{database}}{circdb})->type('string'),
#                                 SOAP::Data->name(item       => $record->{id})->type('string'))));
                        
#                         unless ($result->fault) {
#                             $soapresult=$result->result;
#                         }
#                         else {
#                             $logger->error("SOAP Viewer Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
#                         }
#                     };
                    
#                     if ($@){
#                         $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
#                     }
                    
#                     $record->{olws}=$soapresult;
#                 }
#             }
#         }
        
#         $logger->debug("Sorting $sorttype with order $sortorder");
        
#         $recordlist->sort({order=>$sortorder,type=>$sorttype});
        
#         # Navigationselemente erzeugen
#         my @args=();
#         foreach my $param ($query->param()) {
#             $logger->debug("Adding Param $param with value ".$query->param($param));
#             push @args, $param."=".$query->param($param) if ($param ne "offset" && $param ne "hitrange");
#         }
        
#         my $baseurl="http://$config->{servername}$config->{search_loc}?".join(";",@args);
        
#         my @nav=();
        
#         if ($hitrange > 0) {
#             for (my $i=0; $i <= $hits-1; $i+=$hitrange) {
#                 my $active=0;
                
#                 if ($i == $offset) {
#                     $active=1;
#                 }
                
#                 my $item={
#                     start  => $i+1,
#                     end    => ($i+$hitrange>$hits)?$hits:$i+$hitrange,
#                     url    => $baseurl.";hitrange=$hitrange;offset=$i",
#                     active => $active,
#                 };
#                 push @nav,$item;
#             }
#         }
        
#         # TT-Data erzeugen
#         my $ttdata={
#             representation => $representation,
#             content_type   => $content_type,
            
#             searchtitofcnt => $searchtitofcnt,
#             lang           => $lang,
#             view           => $view,
#             stylesheet     => $stylesheet,
#             sessionID      => $session->{ID},
            
#             database       => $record->{database},
            
#             hits           => $hits,
            
#             dbinfo         => $dbinfotable,

#             recordlist     => $recordlist,

#             parameter      => $parameter,

#             baseurl        => $baseurl,
            
#             qopts          => $queryoptions->get_options,
#             query          => $query,
#             hitrange       => $hitrange,
#             offset         => $offset,
#             nav            => \@nav,
            
#             config         => $config,
#             user           => $user,
#             msg            => $msg,
#             decode_utf8    => sub {
#                 my $string=shift;
#                 return decode_utf8($string);
#             },
#         };
        
#         $self->print_page($config->{$template},$ttdata);
        
#         $session->updatelastresultset($recordlist->to_ids);
#     }	
    
#     return;
# }

sub strip_suffix {
    my $self    = shift;
    my $element = shift;

    if ($element=~/^(.+?)(\.html|\.json|\.rdf|\.rss|\.include)$/){
        return $1;
    }
    
    return $element;
}

sub to_cgi_params {
    my ($self,$arg_ref)=@_;
    
    # Set defaults
    my $exclude_array_ref    = exists $arg_ref->{exclude}
        ? $arg_ref->{exclude}        : [];
    
    my $change_ref           = exists $arg_ref->{change}
        ? $arg_ref->{change}         : {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Modify Query");
    
    my $exclude_ref = {};
    
    foreach my $param (@{$exclude_array_ref}){
        $exclude_ref->{$param} = 1;
    }

    $logger->debug("Args".YAML::Dump($arg_ref));

    my @cgiparams = ();

    if ($self->query->param){
        foreach my $param (keys %{$self->query->param}){
            next unless ($self->query->param($param));
            $logger->debug("Processing $param");
            if (exists $arg_ref->{change}->{$param}){
                push @cgiparams, {
                    param => $param,
                    val   => $arg_ref->{change}->{$param},
                };
            }
            elsif (! exists $exclude_ref->{$param}){
                my @values = $self->query->param($param);
                if (@values){
                    foreach my $value (@values){
                        push @cgiparams, {
                            param => $param,
                            val   => $value
                        };
                    }
                }
                else {
                    push @cgiparams, {
                        param => $param,
                        val => $self->query->param($param)
                    };
                }
            }
        }
    }
    
    return @cgiparams;
}

sub to_cgi_querystring {
    my ($self,$arg_ref)=@_;
    
    # Set defaults
    my $exclude_array_ref    = exists $arg_ref->{exclude}
        ? $arg_ref->{exclude}        : [];
    
    my $change_ref           = exists $arg_ref->{change}
        ? $arg_ref->{change}         : {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Modify Querystring");

    my @cgiparams = ();
    
    foreach my $arg_ref ($self->to_cgi_params($arg_ref)){
        push @cgiparams, "$arg_ref->{param}=$arg_ref->{val}";
    }   
        
    return join(';',@cgiparams);
}

sub to_cgi_hidden_input {
    my ($self,$arg_ref)=@_;
    
    # Set defaults
    my $exclude_array_ref    = exists $arg_ref->{exclude}
        ? $arg_ref->{exclude}        : [];
    
    my $change_ref           = exists $arg_ref->{change}
        ? $arg_ref->{change}         : {};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Modify Querystring as hidden input");
    
    $logger->debug("Args".YAML::Dump($arg_ref));

    my @cgiparams = ();

    foreach my $arg_ref ($self->to_cgi_params($arg_ref)){
        push @cgiparams, "<input type=\"hidden\" name=\"$arg_ref->{param}\" value=\"$arg_ref->{val}\" />";
    }   

    return join("\n",@cgiparams);
}

1;
