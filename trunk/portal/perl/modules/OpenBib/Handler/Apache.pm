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
use Apache2::RequestRec ();
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_UNAUTHORIZED MODE_READBYTES);
use Apache2::URI ();
use APR::URI ();
use Benchmark ':hireswallclock';
use Encode qw(decode_utf8 encode_utf8);
use HTTP::Negotiate;
use HTTP::BrowserDetect;
use JSON::XS;
use Template;
use URI::Escape;
use XML::RSS;
use YAML ();

use APR::Brigade ();
use APR::Bucket ();
use Apache2::Filter ();

use APR::Const -compile => qw(SUCCESS BLOCK_READ);

use constant IOBUFSIZE => 8192;

use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Common::Util;
use OpenBib::Container;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Template::Provider;
use OpenBib::User;

use base 'CGI::Application';

# Reihenfolgen der Abarbeitung
#
# 1) cgiapp_init   : Content-Negotiation
# 2) cgiapp_prerun : Benoetigte Informationen fuer die Handler sammeln und anbieten

sub cgiapp_init {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    $logger->debug("Entering cgiapp_init");


    my $r            = $self->param('r');
    my $view         = $self->param('view');
    my $config       = OpenBib::Config->instance;

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $session      = OpenBib::Session->instance({ apreq => $r , view => $view });
    my $user         = OpenBib::User->instance({sessionID => $session->{ID}});
    my $dbinfo       = OpenBib::Config::DatabaseInfoTable->instance;
    my $useragent    = $r->headers_in->get('User-Agent');
    my $browser      = HTTP::BrowserDetect->new($useragent);

    $self->param('config',$config);
    $self->param('session',$session);
    $self->param('user',$user);
    $self->param('useragent',$useragent);
    $self->param('browser',$browser);
    $self->param('dbinfo',$dbinfo);

    $self->param('qopts',OpenBib::QueryOptions->instance($self->query()));
    $self->param('servername',$r->get_server_name);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 1 is ".timestr($timeall));
    }

    $logger->debug("This request: SessionID: $session->{ID} - User? $user->{ID}");

    # Bestimmung diverser Parameter aus dem URI
    # Setzt: location,path,path_prefix,uri
    $self->process_uri;

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 2 is ".timestr($timeall));
    }

    # Setzen von content_type/representation, wenn konkrete Repraesentation ausgewaehlt wurde
    $self->set_content_type_from_uri;

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 3 is ".timestr($timeall));
    }

    # content_type, representation und lang durch content-Negotiation bestimmen
    # und ggf. zum konkreten Repraesenations-URI redirecten
    # Setzt: content_type,represenation,lang
    $self->negotiate_content;

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 4 is ".timestr($timeall));
    }
    
    # Ggf Personalisiere URI
    $self->personalize_uri;

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 5 is ".timestr($timeall));
    }

    # Bearbeitung HTTP Basic Authentication als Shortcut
    # Setzt ggf: basic_auth_failure (auf 1)
    $self->check_http_basic_authentication;

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 6 is ".timestr($timeall));
    }

    # Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Parameter 'l' oder cookie
    $self->alter_negotiated_language;

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 7 is ".timestr($timeall));
    }
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($self->param('lang')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    $self->param('msg',$msg);

    $logger->debug("This request after initialization: SessionID: $session->{ID} - User? $user->{ID}");

    $logger->debug("Main objects initialized");    

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for cgiapp_init is ".timestr($timeall));
    }

    return;
}

sub cgiapp_prerun {
   my $self    = shift;
   my $runmode = shift;

   # Log4perl logger erzeugen
   my $logger = get_logger();

   $logger->debug("Entering cgiapp_prerun");

   my $r            = $self->param('r');
   
   {
       # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
       # zu verwenden
       
       my $method          = $self->query->param('_method') || '';
       my $confirm         = $self->query->param('confirm') || 0;
       
       if ($method eq "DELETE" || $r->method eq "DELETE"){
           $logger->debug("Deletion shortcut");
           
           if ($confirm){
               $self->prerun_mode('confirm_delete_record');
           }
           else {
               $self->prerun_mode('delete_record');
           }
       }
   }

   {
       # Wenn dispatch_url, dann Runmode dispatch_to_representation mit externem Redirect
       if ($self->param('dispatch_url')){
           $self->prerun_mode('dispatch_to_representation');
       }
       
   }
   
   $logger->debug("Exit cgiapp_prerun");
}

sub set_paging {
    my $self = shift;

    my $query        = $self->query();
    my $queryoptions = $self->param('qopts');
    my $config       = $self->param('config');
    
    my $page = $query->param('page') || 1;

    my $num    = $queryoptions->get_option('num') || $config->{queryoptions}{num}{value};
    my $offset = $page*$num-$num;

    $self->param('num',$num);
    $self->param('offset',$offset);
    $self->param('page',$page);

    return;
}

sub negotiate_content {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r       = $self->param('r');
    my $view    = $self->param('view');
    my $config  = $self->param('config');
    my $session = $self->param('session');
    
    if (!$self->param('disable_content_negotiation')){
        $logger->debug("Doing content negotiation");

        # Wird keine konkrete Reprasentation angesprochen, dann
        # - Typ verhandeln
        # - Sprache verhandeln
        if ($r->method eq "GET"){
            if (!$self->param('representation') && !$self->param('content_type')){

                $logger->debug("No specific representation given - negotiating content and language");

                $logger->debug("Path: ".$self->param('path'));
                
                $self->negotiate_type;
                
                # Pfade sind immer mit base_loc und view
                #my $baseloc    = $config->get('base_loc');
                #$path =~s{^$baseloc/[^/]+}{$path_prefix};

                # Zusaetzlich auch Sprache verhandeln
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

                my $path = "";

                $self->param('path',$self->param('path').".".$self->param('representation'));

                my $dispatch_url = $self->param('scheme')."://".$self->param('servername').$self->param('path').$args;

                $self->param('dispatch_url',$dispatch_url);
                
                $logger->debug("Negotiating type -> Dispatching to $dispatch_url");

                return;
            }

            # Wenn eine konkrete Repraesentation angesprochen wird, jedoch ohne Sprach-Parameter,
            # dann muss dieser verhandelt werden.
            if (!$self->query->param('l') ){
                $logger->debug("Specific representation given, but without language - negotiating");
                
                # Pfade sind immer mit base_loc und view
                #my $baseloc    = $config->get('base_loc');
                #$path =~s{^$baseloc/[^/]+}{$path_prefix};
                
                if ($session->{lang}){
                    $logger->debug("Sprache definiert durch Cookie: ".$session->{lang});
                    $self->param('lang',$session->{lang});
                }
                else {
                    $self->negotiate_language;
                }
                
                my $args = "?l=".$self->param('lang');
                
                $args=$args.";".$self->query->args() if ($self->query->args());

                my $dispatch_url = $self->param('scheme')."://".$self->param('servername').$self->param('path').$args;
            
                $logger->debug("Negotiated language -> Dispatching to $dispatch_url");

                $self->param('dispatch_url',$dispatch_url);

                return ;
            }
        }
        # CUD-operations always use the resource-URI, so no redirect neccessary
        elsif ($r->method eq "POST" || $r->method eq "PUT" || $r->method eq "DELETE"){
            $self->negotiate_type;
            $self->negotiate_language;
        }
        else {
            $logger->debug("No additional negotiation necessary");
            $logger->debug("Current URL is ".$self->param('path')." with args ".$self->query->args());
        }
    }
    

    return;
}

sub alter_negotiated_language {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r       = $self->param('r');
    my $session = $self->param('session');

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

    return;
}

sub process_uri {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r          = $self->param('r');
    my $config     = $self->param('config');
    my $view       = $self->param('view');
    my $servername = $self->param('servername');

    my $path_prefix          = $config->get('base_loc');
    my $complete_path_prefix = "$path_prefix/$view";
    
    # Letztes Pfad-Element bestimmen
    my $uri    = $r->parsed_uri;
    my $path   = $uri->path;
    my $scheme = $uri->scheme || 'http';
    my $args   = $r->args;

    
    my ($location_uri,$last_uri_element) = $path =~m/^(.+?)\/([^\/]+)$/;
    
    $logger->debug("Full Internal Path: $path - Last URI Element: $last_uri_element - Args: ".$self->query->args());
    
    if (! $config->strip_view_from_uri($view)){
        $path_prefix = $complete_path_prefix;
    }
    else {
        $path =~s/^(\/[^\/]+)\/[^\/]+(\/.+)$/$1$2/;
    }

    my $suffixes = join '|', keys %{$config->{content_type_map_rev}};
    my $regexp = "^(.+?)\.($suffixes)\$";
    
    $logger->debug("Suffixes: $suffixes");
    
#    my ($id) = $last_uri_element =~m/^(.+?)\.($suffixes)$/;
    my ($id) = $last_uri_element =~m/^(.+?)\.($suffixes)$/;

    $logger->debug("ID: $id");
    
    if ($id){
        $location_uri.="/$id";
    }
    else {
        $location_uri.="/$last_uri_element";
    }

    my $location = "$scheme://$servername$location_uri";
    if ($args){
        $location.="?$args";
    }
    
    $self->param('location',$location);
    $self->param('path_prefix',$path_prefix);
    $self->param('path',$path);
    $self->param('scheme',$scheme);

    my $url = $uri->unparse;
    
    $self->param('url',$url);
}

sub personalize_uri {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Personalisierte URIs
    if ($self->param('users_loc')){
        my $dispatch_url = ""; #$self->param('scheme')."://".$self->param('servername');   
        
        my $user           = $self->param('user');
        my $config         = $self->param('config');
        my $path_prefix    = $self->param('path_prefix');
        my $path           = $self->param('path');
        my $representation = $self->param('representation');
        
#        # Interne Pfade sind immer mit base_loc und view
#        my $baseloc    = $config->get('base_loc');
#        $path =~s{^$baseloc/[^/]+}{$path_prefix};

        # Eine Weiterleitung haengt vom angemeldeten Nutzer ab
        # und gilt immer nur fuer Repraesentationen.
        if ($user->{ID} && $representation){
            my $loc = $self->param('users_loc');
            $logger->debug("Replacing $path_prefix/$loc with $path_prefix/users/$user->{ID}/$loc");
            my $old_loc = "$path_prefix/$loc";
            my $new_loc = "$path_prefix/users/id/$user->{ID}/$loc";
            $path=~s{^$old_loc}{$new_loc};

            $self->param('path',$path);
            
            $dispatch_url .=$path;
            
            if ($self->query->args()){
                $dispatch_url.="?".$self->query->args();
            }

            $logger->debug("Dispatching to $dispatch_url");
            $self->param('dispatch_url',$dispatch_url);

            return;            
        }
        else {
            $logger->debug("No Dispatch: User: $user->{ID} / Representation:$representation:");
        }   
    }
    elsif ($self->param('admin_loc')){
        my $dispatch_url = ""; #$self->param('scheme')."://".$self->param('servername');   
        
        my $user           = $self->param('user');
        my $config         = $self->param('config');
        my $path_prefix    = $self->param('path_prefix');
        my $path           = $self->param('path');
        my $representation = $self->param('representation');
        
#        # Interne Pfade sind immer mit base_loc und view
#        my $baseloc    = $config->get('base_loc');
#        $path =~s{^$baseloc/[^/]+}{$path_prefix};

        # Eine Weiterleitung haengt vom angemeldeten Nutzer ab
        # und gilt immer nur fuer Repraesentationen.
        if ($user->is_admin && $representation){
            my $loc = $self->param('admin_loc');
            $logger->debug("Replacing $path_prefix/$loc with $path_prefix/$config->{admin_loc}/$loc");
            my $old_loc = "$path_prefix/$loc";
            my $new_loc = "$path_prefix/$config->{admin_loc}/$loc";
            $path=~s{^$old_loc}{$new_loc};

            $self->param('path',$path);
            
            $dispatch_url .=$path;
            
            if ($self->query->args()){
                $dispatch_url.="?".$self->query->args();
            }

            $logger->debug("Dispatching to $dispatch_url");
            $self->param('dispatch_url',$dispatch_url);

            return;            
        }
        else {
            $logger->debug("No Dispatch: User: $user->{ID} / Representation:$representation:");
        }   
    }
    
    return;
}

sub set_content_type_from_uri {
    my $self = shift;
    my $uri  = shift || $self->param('path');

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->param('config');

    my $suffixes = join '|', keys %{$config->{content_type_map_rev}};

    my ($representation) = $uri =~m/^.*?\/[^\/]*?\.($suffixes)$/;

    $logger->debug("Setting type from URI $uri. Got Represenation $representation");

    # Korrektur des ausgehandelten Typs bei direkter Auswahl einer bestimmten Repraesentation
    if (defined $representation && $config->{content_type_map_rev}{$representation}){
        $self->param('content_type',$config->{content_type_map_rev}{$representation});
        $self->param('representation',$representation);
    }
    
    return;
}

sub negotiate_type {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $config         = OpenBib::Config->instance;    

    
    my $content_type = $r->headers_in->{'Content-Type'} || '';
    my $accept       = $r->headers_in->{'Accept'} || '';
    my @accepted_types = ();

    foreach my $item (split '\s*,\s*', $accept){
        $item=~s/;.+$//;
        push @accepted_types, $item;
    }

    if ($content_type){
        $logger->debug("Content-Type: |$content_type|");
        $logger->debug(YAML::Dump($config->{content_type_map}));
        if ($config->{content_type_map}{$content_type}){
            $self->param('content_type',$content_type);
            $self->param('representation',$config->{content_type_map}->{$content_type});
        }
        $logger->debug("content_type: ".$self->param('content_type')." - representation: ".$self->param('representation'));
    }
    elsif (@accepted_types){
        $logger->debug("Accept: $accept - Types: ".YAML::Dump(\@accepted_types));
    
        foreach my $information_type (@accepted_types){
            if ($config->{content_type_map}{$information_type}){
                $logger->debug("Negotiated Type: $information_type - Suffix: ".$config->{content_type_map}->{$information_type});
                $self->param('content_type',$information_type);
                $self->param('representation',$config->{content_type_map}->{$information_type});
                last;
            }
        }

        $logger->debug("content_type: ".$self->param('content_type')." - representation: ".$self->param('representation'));
    }

    # Korrektur bei mobilen Endgeraeten, wenn die Repraesentation in portal.yml definiert ist
    if (defined $config->{enable_mobile}{$self->param('view')} && $self->param('representation') eq "html" && $self->param('browser')->mobile() ){
        $self->param('content_type','text/html');
        $self->param('representation','mobile');
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
    my $role   = shift || '';
    my $userid = shift || '';

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
    
    if (! $user->{ID} && $self->param('represenation') eq "html"){
        # Aufruf-URL
        my $return_uri  = uri_escape($r->parsed_uri->path);
        
        # Return-URL in der Session abspeichern
        
        return $self->redirect("$path_prefix/$config->{login_loc}?redirect_to=$return_uri",'303 See Other');
    }

    if ($role eq "admin" && $user->is_admin){
        return 1;
    }
    elsif ($role eq "user" && ( $user->is_admin || $user->{ID} eq $userid )){
        return 1;
    }
    else {
      $logger->debug("User authenticated as $user->{ID}, but doesn't match required userid $userid");
#      $self->print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"));
      return 0;
    }
}

sub print_warning {
    my $self      = shift;
    my $warning   = shift;
    my $warningnr = shift || 1;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->param('config');

    my $ttdata = {
        err_nr  => $warningnr,
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
    my $status         = $self->param('status') || Apache2::Const::OK;
    my $content_type   = $self->param('content_type') || $ttdata->{'content_type'} || $config->{'content_type_map_rev'}{$representation} || 'text/html';
    my $location       = $self->param('location');
    my $url            = $self->param('url');

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

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
            STAT_TTL => 60,  # one minute
        }) ],
        COMPILE_EXT => '.ttc',
        COMPILE_DIR => '/tmp/ttc',
        STAT_TTL => 60,  # one minute
        OUTPUT         => $r,    # Output geht direkt an Apache Request
        RECURSION      => 1,
    });
  
    # Dann Ausgabe des neuen Headers
    $r->content_type($content_type);

    # Location- und Content-Location-Header setzen
    my $head = $r->headers_out;
    $head->set('Location' => $location);
    $head->set('Content-Location' => $location);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time until stage 1 is ".timestr($timeall));
    }

    $template->process($templatename, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };

    if ($self->param('status')){
        $r->status($self->param('status'));
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time until stage 2 is ".timestr($timeall));
    }

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
    my $dbinfo         = $self->param('dbinfo');
    my $path_prefix    = $self->param('path_prefix');
    my $path           = $self->param('path');
    my $url            = $self->param('url');
    my $location       = $self->param('location');
    my $scheme         = $self->param('scheme');
    my $representation = $self->param('representation');
    my $content_type   = $self->param('content_type') || $ttdata->{'content_type'} || $config->{'content_type_map_rev'}{$representation} || 'text/html';
    my $query          = $self->query();
    my $container      = OpenBib::Container->instance;
    
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
    $ttdata->{'query'}          = $query;
    $ttdata->{'scheme'}         = $scheme;
    $ttdata->{'view'}           = $view;
    $ttdata->{'dbinfo'}         = $dbinfo;
    $ttdata->{'sessionID'}      = $sessionID;
    $ttdata->{'representation'} = $representation;
    $ttdata->{'content_type'}   = $content_type;
    $ttdata->{'session'}        = $session;
    $ttdata->{'config'}         = $config;
    $ttdata->{'qopts'}          = $queryoptions;
    $ttdata->{'user'}           = $user;
    $ttdata->{'msg'}            = $msg;
    $ttdata->{'lang'}           = $lang;
    $ttdata->{'stylesheet'}     = $stylesheet;
    $ttdata->{'servername'}     = $servername;
    $ttdata->{'username'}       = $username;
    $ttdata->{'sysprofile'}     = $sysprofile;
    $ttdata->{'path_prefix'}    = $path_prefix;
    $ttdata->{'path'}           = $path;
    $ttdata->{'url'}            = $url;
    $ttdata->{'location'}       = $location;
    $ttdata->{'cgiapp'}         = $self;
    $ttdata->{'container'}      = $container;
    
    # Helper functions
    $ttdata->{'to_json'}        = sub {
        my $ref = shift;
        return encode_json $ref;
    };
    
    $ttdata->{'uri_escape'}     = sub {
        my $string = shift;
        return uri_escape_utf8($string);
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
#         $self->query->headers_out->add(Location => "$path_prefix/$config->{titles_loc}/$record->{database}/$record->{id}.html");
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

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->param('config');
    
    my $suffixes = join '|', map { '\.'.$_ } keys %{$config->{content_type_map_rev}};

    $logger->debug("Suffixes: $suffixes");
    
    if ($element=~/^(.+?)($suffixes)$/){
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

#    $logger->debug("Args".YAML::Dump($arg_ref));

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
        push @cgiparams, "$arg_ref->{param}=".uri_escape($arg_ref->{val});
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
    
#    $logger->debug("Args".YAML::Dump($arg_ref));

    my @cgiparams = ();

    foreach my $arg_ref ($self->to_cgi_params($arg_ref)){
        push @cgiparams, "<input type=\"hidden\" name=\"$arg_ref->{param}\" value=\"$arg_ref->{val}\" />";
    }   

    return join("\n",@cgiparams);
}

# Kudos to Stas Bekman: mod_per2 Users's Guide

sub read_json_input {
    my $self = shift;
    
    my $r  = $self->param('r');
    
    my $bb = APR::Brigade->new($r->pool,
                               $r->connection->bucket_alloc);
    
    my $data = '';
    my $seen_eos = 0;
    do {
        $r->input_filters->get_brigade($bb, Apache2::Const::MODE_READBYTES,
                                       APR::Const::BLOCK_READ, IOBUFSIZE);
        
        for (my $b = $bb->first; $b; $b = $bb->next($b)) {
            if ($b->is_eos) {
                $seen_eos++;
                last;
            }
            
            if ($b->read(my $buf)) {
                $data .= $buf;
            }
            
            $b->remove; # optimization to reuse memory
        }
        
    } while (!$seen_eos);
    
    $bb->destroy;
    
    return $data;
}

sub parse_valid_input {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $query = $self->query();

    my $valid_input_params_ref = $self->get_input_definition;
    
    my $input_params_ref = {};

    # JSON Processing
    if ($self->param('representation') eq "json"){
        my $json_input=$self->read_json_input();
        
        $logger->debug("JSON Input $json_input");

        my $input_data_ref;
        
        eval {
            $input_data_ref = decode_json $json_input;
        };

        
        if ($@){
            $logger->error("Couldn't decode JSON POST-data");
            return { error => 1 };
        }

        foreach my $param (keys %$valid_input_params_ref){
            my $type     = $valid_input_params_ref->{$param}{type};
            my $encoding = $valid_input_params_ref->{$param}{encoding};
            my $default  = $valid_input_params_ref->{$param}{default};

            $input_params_ref->{$param} = $input_data_ref->{$param} || $default;
        }    

    }
    # CGI Processing
    else {
        $logger->debug("CGI Input");

        foreach my $param (keys %$valid_input_params_ref){
            my $type     = $valid_input_params_ref->{$param}{type};
            my $encoding = $valid_input_params_ref->{$param}{encoding};
            my $default  = $valid_input_params_ref->{$param}{default};
            
            if ($type eq "scalar"){
                if ($encoding eq "utf8"){
                    $input_params_ref->{$param} = decode_utf8($query->param($param)) || $default;
                }
                else {
                    $input_params_ref->{$param} = $query->param($param)  || $default;
                }
            }
            # sonst array
            elsif ($type eq "array") {
                if ($query->param($param)){
                    @{$input_params_ref->{$param}} = $query->param($param);
                }
                else {
                    $input_params_ref->{$param} = $default;
                }
            }
            elsif ($type eq "fields") {
                my $fields_ref = $default;
                foreach my $qparam ($query->param){
                    if ($qparam=~/^fields_([TXPCSNL])(\d+)_([a-z0-9])?_(\d+)$/){
                        my $prefix   = $1;
                        my $field    = $2;
                        my $subfield = $3;
                        my $mult     = $4;

                        my $content  = $query->param($qparam);
                        
                        $logger->debug("Got $field - $prefix - $subfield - $mult - $content");

                        push @{$fields_ref->{$field}}, {
                            subfield => $subfield,
                            mult     => $mult,
                            content  => $content,
                        };
                    }
                    else {
                        $logger->debug("Can't parse $qparam");
                    }
                }
                $input_params_ref->{$param} = $fields_ref;
            }
        }
    }
    
    return $input_params_ref;
}

sub dispatch_to_representation {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Dispatching to representation ".$self->param('dispatch_url'));
    return $self->redirect($self->param('dispatch_url'),'303 See Other');
}

sub print_authorization_error {
    my $self = shift;

    my $r   = $self->param('r');
    my $msg = $self->param('msg');

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($self->param('representation') ne "html"){
        $r->status(Apache2::Const::FORBIDDEN);
    }

    $self->print_warning($msg->maketext("Sie sind nicht authorisiert"));
    
    return;
}

sub authorization_successful {
    my $self   = shift;

    # On Success 1
    return 1;
}

sub check_http_basic_authentication {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r       = $self->param('r');
    my $config  = $self->param('config');
    my $user    = $self->param('user');
    my $session = $self->param('session');
    
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
        
        $logger->debug("get_basic_auth: Status $status");
        
        return $status unless $status == Apache2::Const::OK;
        
        my $http_user     = $r->user;
        
        $logger->debug("Authentication Shortcut for user $http_user : Status $status / Password: $password");
        
        my $userid   = $user->authenticate_self_user({ username => $http_user, password => $password });
        
        my $targetid = $config->get_authenticator_self();

        if ($userid > 0){
            $user->connect_session({
                sessionID => $session->{ID},
                userid    => $userid,
                targetid  => $targetid,
            });
            $user->{ID} = $userid;
        }
        else {
            $self->param('basic_auth_failure',1);
        }

        # User zurueckchreiben
        $self->param('user',$user);
        
    }
}

sub tunnel_through_authenticator {
    my ($self,$method) = @_;

    my $config   = $self->param('config');
    my $view     = $self->param('view');    
    my $location = $self->param('location');    
    my $args     = $self->to_cgi_querystring;

    if ($args){
        $location.="?$args";
        if ($method){
            $location.=";_method=$method";
        }
    }
    elsif ($method) {
        $location.="?_method=$method";
    }
    
    my $return_uri = uri_escape($location);
    
    my $new_location = "$config->{base_loc}/$view/$config->{login_loc}?redirect_to=$return_uri";
    
    return $self->redirect($new_location,'303 See Other');
}


1;
