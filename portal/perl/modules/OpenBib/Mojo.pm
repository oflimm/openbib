package OpenBib::Mojo;

use strict;
use warnings;
use utf8;
use feature ':5.16';

use Mojo::Base 'Mojolicious', -signatures;

use Log::Log4perl qw(get_logger :levels);
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Template::Provider;
use OpenBib::Mojo::Controller;


use Log::Log4perl qw(get_logger :levels);
use List::MoreUtils qw(none any);
use Benchmark ':hireswallclock';
use Encode qw(decode_utf8 encode_utf8);
use Crypt::GPG;
use HTML::Escape qw/escape_html/;
use HTTP::Negotiate;
use HTTP::BrowserDetect;
use JSON::XS;
use MIME::Base64;
use Template;
use URI::Escape;
use XML::RSS;
use Search::Tools;
use Text::CSV_PP;
use YAML ();

# From PSGI.pm
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Config::LocationInfoTable;
use OpenBib::Common::Util;
use OpenBib::Container;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::SearchQuery;
use OpenBib::Search::Factory;
use OpenBib::Template::Provider;
use OpenBib::User;
use OpenBib::Normalizer;
use Scalar::Util;


our $VERSION = 'pre-4.0';

# init web app
sub startup {
    my $app = shift;

    my $config = OpenBib::Config->new;
    
    Log::Log4perl->init($config->{log4perl_path});

    my $logger = get_logger();
    
    # Register app secret and hypnotoad config
    $app->secrets($config->{mojo_secrets});
    $app->config($config->{mojo_hypnotoad});

    # Sessions
    $app->sessions->cookie_name('openbib');
    $app->sessions->cookie_path('/portal');
    #$app->sessions->cookie_domain($app->req->url->to_abs->host);
    $app->sessions->default_expiration(3600);
    
    # Types (eg. include)
    $app->types->type('include' => 'text/html');
	
    # Plugins
    $app->_plugins;
    
    # Router
    my $r = $app->routes;
    $app->_register_routes($r);

    # Pre-processeing
    $app->hook(before_dispatch => \&_app_init);    
}

sub _register_routes {
    my $self   = shift;
    my $routes = shift;

    # Namespace fuer Controller
    $routes->namespaces(['OpenBib::Mojo::Controller']);
    
    my $logger = get_logger();

    $YAML::Syck::ImplicitTyping  = 1;
    $YAML::Syck::ImplicitUnicode = 1;
    
    my $dispatch_rules = YAML::Syck::LoadFile("/opt/openbib/conf/dispatch_mojo.yml");

    foreach my $item (@{$dispatch_rules}){
        my $rule       = $item->{rule};
        my $controller = $item->{controller};
        my $action     = $item->{action};
        my $method     = $item->{method};

	my @representations = ();
	    
        @representations = @{$item->{representations}} if (defined $item->{representations});
	if ($method eq "GET"){
	    $routes->get($rule => [ format => \@representations ])->to(controller => $controller, action => $action )
	}
	elsif ($method eq "POST"){
	    $routes->post($rule => [ format => \@representations ])->to(controller => $controller, action => $action )
	}
	elsif ($method eq "PUT"){
	    $routes->put($rule => [ format => \@representations ])->to(controller => $controller, action => $action )
	}
	elsif ($method eq "DELETE"){
	    $routes->delete($rule => [ format => \@representations ])->to(controller => $controller, action => $action )
	}
    }

    return $routes;
}

sub _plugins {
    my $app = shift;

    $app->plugin('Directory',{
	root => '/var/www/html'
		 });
        
}

sub _app_init {
    my $self = shift; # Controller-Object
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    $logger->debug("Entering _app_init");

    my $r            = $self->req;
    my $view         = $self->param('view');

    # Wenn kein Portal-URL (z.B. CSS, JS, Images), dann kein Preprocessing notwendig
    return if ($r->url->path !~m{^/portal/});
    
    my $config       = OpenBib::Config->new;
        
    $self->stash('config',$config);
    $self->stash('r',$r);
    
    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    if (!defined $r){
        $logger->error("No Request");
    }

    my $remote_ip = ''; # cgiapp: $r->remote_host || '';
    
    my $forwarded_for = $r->headers->header('X-Forwarded-For') || '';
    my $xclientip     = $r->headers->header('X-Client-IP')     || '';

    if ($logger->is_info){
	$logger->info("X-Forwarded-For: $forwarded_for");
	$logger->info("X-Client-IP: $xclientip");
    }
    
    if (defined $xclientip && $xclientip =~ /([^,\s]+)$/) {
        $remote_ip = $1;
    }

    $self->stash('remote_ip',$remote_ip);
    $self->stash('servername',$r->url->to_abs->host);
    #$self->app->sessions->cookie_domain($r->url->to_abs->host);

    my $sessionID    = $self->cookie('sessionID');

    my $session      = OpenBib::Session->new({ sessionID => $sessionID , view => $view, config => $config });
    
    $self->stash('session',$session);
    
    $logger->debug("Got sessionID $sessionID and effecitve sessionID is $session->{ID}");

    $logger->debug('Path'.$r->url->path);
    # Neuer Cookie?, dann senden
    if ($sessionID ne $session->{ID} ){
	$self->cookie('sessionID' => $session->{ID}, {domain => $self->stash('servername'), path => '/portal'}) ;
    }

    my $normalizer   = OpenBib::Normalizer->new();
    $self->stash('normalizer',$normalizer);
    
    my $user         = OpenBib::User->new({sessionID => $session->{ID}, config => $config});
    $self->stash('user',$user);
    
    my $statistics   = OpenBib::Statistics->new();
    $self->stash('statistics',$statistics);

    my $dbinfo       = OpenBib::Config::DatabaseInfoTable->new;
    $self->stash('dbinfo',$dbinfo);

    my $locinfo      = OpenBib::Config::LocationInfoTable->new;
    $self->stash('locinfo',$locinfo);

    my $useragent    = $self->tx->req->content->headers->user_agent;
    $self->stash('useragent',$useragent);
    
    my $browser      = HTTP::BrowserDetect->new($useragent);
    $self->stash('browser',$browser);

    my $queryoptions = OpenBib::QueryOptions->new({ query => $r, session => $session });

    $self->stash('qopts',$queryoptions);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 1 is ".timestr($timeall));
    }

    $logger->debug("This request: SessionID: $session->{ID}");

    if (defined $user->{ID}){
        $logger->debug("This request: User? $user->{ID}");
    }
    
    # Bestimmung diverser Parameter aus dem URI
    # Setzt: location,path,path_prefix,uri,scheme
    &process_uri($self);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 2 is ".timestr($timeall));
    }

    # Setzen von content_type/representation, wenn konkrete Repraesentation ausgewaehlt wurde
    &set_content_type_from_uri($self);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 3 is ".timestr($timeall));
    }

    # content_type, representation und lang durch content-Negotiation bestimmen
    # und ggf. zum konkreten Repraesenations-URI redirecten
    # Setzt: content_type,represenation,lang
    &negotiate_content($self);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 4 is ".timestr($timeall));
    }
    
    # Ggf Personalisiere URI
    &personalize_uri($self);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 5 is ".timestr($timeall));
    }

    # Bearbeitung HTTP Basic Authentication als Shortcut
    # Setzt ggf: basic_auth_failure (auf 1)
    &check_http_basic_authentication($self);

    # Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Parameter 'l' oder cookie
    &alter_negotiated_language($self);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 7 is ".timestr($timeall));
    }

    $user = $self->stash('user');

    if ($logger->is_info){
	my $path   = $self->stash('path');
	my $scheme = $self->stash('scheme');
	$logger->info("Remote IP set to $remote_ip for scheme $scheme and path $path");
    }
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($self->stash('lang')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    $self->stash('msg',$msg);
    
    if (!$user->can_access_view($view,$remote_ip)){
	my @always_allowed_paths = (
	    $self->stash('path_prefix')."/".$config->get('login_loc'),
	    $self->stash('path_prefix')."/".$config->get('logout_loc'),
	    $self->stash('path_prefix')."/".$config->get('info_loc')."/impressum",
	    $self->stash('path_prefix')."/".$config->get('info_loc')."/datenschutz",		
	    $self->stash('path_prefix')."/".$config->get('users_loc')."/".$config->get('registrations_loc'),
	    $self->stash('path_prefix')."/".$config->get('users_loc')."/".$config->get('passwords_loc'),
	    );
	
	my $do_dispatch = 1;
	
	foreach my $allowed_path (@always_allowed_paths){
	    if ($self->stash('url') =~ m/$allowed_path/){
		$do_dispatch = 0;
	    }
	}

	# Trennung der Zugangskontrolle zwischen API und Endnutzern
	if ($self->stash('representation') eq "html"){
	    my $scheme = ($config->get('use_https'))?'https':$self->stash('scheme');
	    
	    my $redirect_to = $scheme."://".$self->stash('servername').$self->stash('url');
	    
	    my $dispatch_url = $scheme."://".$self->stash('servername').$self->stash('path_prefix')."/".$config->get('login_loc')."?l=".$self->stash('lang').";redirect_to=".uri_escape($redirect_to);
	    
	    $logger->debug("force_login URLs: $redirect_to - ".$self->stash('url')." - ".$dispatch_url);
	    
	    if ($do_dispatch){
		$self->stash('dispatch_url',$dispatch_url);
	    }
	}
	else {
	    if ($do_dispatch){
		$self->stash('default_runmode','show_warning');
		$self->stash('warning_message',$msg->maketext("Zugriff verweigert."));
	    }
	}
    }
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 6 is ".timestr($timeall));
    }
    
    if (defined $user->{ID}){
        $logger->debug("This request after initialization: User? $user->{ID}");
    }

    if (defined $session->{ID}){
        $logger->debug("This request after initialization: SessionID: $session->{ID}");
    }
    else {
        $logger->error("No SessionID after initialization");
    }

    # Session abgelaufen?
    $session->is_expired;
    if (0 == 1 && $session->is_expired){
	if ($self->stash('representation') eq "html"){

	    my $scheme = ($config->get('use_https'))?'https':$self->stash('scheme');
	    
	    my $dispatch_url = $scheme."://".$self->stash('servername').$self->stash('path_prefix')."/".$config->get('logout_loc').".html?l=".$self->stash('lang').";expired=1";
	    
	    $logger->debug("Session expired. Force logout: ".$self->stash('url')." - ".$dispatch_url);
	    
	    $self->stash('dispatch_url',$dispatch_url);
	}
	else {
	    $self->stash('default_runmode','show_warning');
	    $self->stash('warning_message',$msg->maketext("Sitzung abgelaufen."));
	}
    }
    
    $logger->debug("Main objects initialized");        
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for cgiapp_init is ".timestr($timeall));
    }
	
}

sub cgiapp_prerun {
   my $self    = shift;
   my $runmode = shift;

   # Log4perl logger erzeugen
   my $logger = get_logger();

   $logger->debug("Entering cgiapp_prerun");

   my $r            = $self->param('r');
   my $user         = $self->param('user');
   my $config       = $self->param('config');
   
   {
       # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
       # zu verwenden
       
       my $method          = ($r->param('_method'))?escape_html($r->param('_method')):'';
       my $confirm         = ($r->param('confirm'))?escape_html($r->param('confirm')):0;
       
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
       if ($self->stash('dispatch_url')){
           $self->prerun_mode('dispatch_to_representation');
       }
       
   }

   {
       # Wenn default_runmode gesetzt, dann ausschliesslich in diesen wechseln
       if ($self->stash('default_runmode')){

	   # Zum default_runmode muss eine Methode in
	   # diesem Modul definiert sein, denn default_runmodes werden immer in
	   # OpenBib::Handler::PSGI definiert!

	   if (OpenBib::Mojo::Controller->can($self->stash('default_runmode'))){
	       $self->run_modes(
		   $self->stash('default_runmode')  => $self->stash('default_runmode'),
		   );
	       $self->prerun_mode($self->stash('default_runmode'));
	   }
	   else {
	       $logger->error("Invalid default runmode ".$self->stash('default_runmode'));
	   }
       }
   }
   
   
#   if ($config->get('cookies_everywhere') || $self->param('send_new_cookie')){
       # Cookie-Header ausgeben
   &finalize_cookies($self);
#   }
   
   $logger->debug("Exit cgiapp_prerun");
}

sub process_uri {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r          = $self->stash('r');
    my $config     = $self->stash('config');
    my $view       = $self->stash('view');
    my $servername = $self->stash('servername');

    my $path_prefix          = $config->get('base_loc');
    my $complete_path_prefix = "$path_prefix/$view";
    
    # Letztes Pfad-Element bestimmen
    my $uri    = $r->url->base;
    my $path   = $r->url->path;
    my $scheme = $r->url->scheme || 'http';
    my $args_ref = $r->url->query;
#    my $args   = &to_cgi_querystring($self);

    my $forwarded_proto = $r->headers->header('X-Forwarded-Proto');

    $logger->debug("X-Forwarded-Proto: $forwarded_proto") if (defined $forwarded_proto);

    if (defined $forwarded_proto && $forwarded_proto=~/^https/){
	$scheme = "https";
    }

    # use-https overrides everything
    $scheme = ($config->get('use_https'))?'https':$scheme;
    
    my ($location_uri,$last_uri_element) = $path =~m/^(.+?)\/([^\/]+)$/;
 
    # if ($logger->is_debug && defined $path && defined $last_uri_element && defined $r->escaped_args){
    # 	$logger->debug("Full Internal Path: $path - Last URI Element: $last_uri_element - Args: ".$r->escaped_args);
    # }
    
    if (! $config->strip_view_from_uri($view)){
        $path_prefix = $complete_path_prefix;
    }
    else {
        $path =~s/^(\/[^\/]+)\/[^\/]+(\/.+)$/$1$2/;
	$location_uri =~s/^(\/[^\/]+)\/[^\/]+(\/.+)$/$1$2/;
    }

    my $suffixes = join '|', keys %{$config->{content_type_map_rev}};
    my $regexp = "^(.+?)\.($suffixes)\$";
    
    $logger->debug("Suffixes: $suffixes");
    $logger->debug("Scheme: $scheme");
    $logger->debug("Path: $path");
    $logger->debug("Location_uri: $location_uri");
    

    my $id;

    if ($last_uri_element){
#    my ($id) = $last_uri_element =~m/^(.+?)\.($suffixes)$/;
	($id) = $last_uri_element =~m/^(.+?)\.($suffixes)$/;
    }
    
    $logger->debug("ID: $id") if ($id);
    
    if ($id){
        $location_uri.="/$id";
    }
    elsif ($last_uri_element) {
        $location_uri.="/$last_uri_element";
    }

    my $location = "$scheme://$servername$location_uri";
    if (@$args_ref){
	my $args = join(';',@$args_ref);
        $location.="?$args";
    }

    $self->stash('location',$location);
    $self->stash('path_prefix',$path_prefix);
    $self->stash('path',$path);
    $self->stash('scheme',$scheme);

    my $url = $r->url->base;
    
    $self->stash('url',$url);
}

sub set_content_type_from_uri {
    my $self = shift;
    my $uri  = shift || $self->stash('path');

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->stash('config');

    my $suffixes = join '|', keys %{$config->{content_type_map_rev}};

    my ($representation) = $uri =~m/^.*?\/[^\/]*?\.($suffixes)$/;

    if (defined $representation){
        $logger->debug("Setting type from URI $uri. Got Represenation $representation");
    }
    
    # Korrektur des ausgehandelten Typs bei direkter Auswahl einer bestimmten Repraesentation
    if (defined $representation && $config->{content_type_map_rev}{$representation}){
        $self->stash('content_type',$config->{content_type_map_rev}{$representation});
        $self->stash('representation',$representation);
    }
    
    return;
}

sub negotiate_type {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');

    
    my $content_type = $r->headers->header('Content-Type') || '';
    my $accept       = $r->headers->header('Accept') || '';
    my @accepted_types = ();

    foreach my $item (split '\s*,\s*', $accept){
        $item=~s/;.+$//;
        push @accepted_types, $item;
    }

    if ($content_type){
        if ($logger->is_debug){
            $logger->debug("Content-Type: |$content_type|");
            #$logger->debug(YAML::Dump($config->{content_type_map}));
        }
        
        if ($config->{content_type_map}{$content_type}){
            $self->stash('content_type',$content_type);
            $self->stash('representation',$config->{content_type_map}->{$content_type});
        }
        $logger->debug("content_type: ".$self->stash('content_type')." - representation: ".$self->stash('representation')) if (defined $self->stash('content_type') && defined $self->stash('represenation'));
    }
    elsif (@accepted_types){
        #if ($logger->is_debug){
        #    $logger->debug("Accept: $accept - Types: ".YAML::Dump(\@accepted_types));
        #}
    
        foreach my $information_type (@accepted_types){
            if ($config->{content_type_map}{$information_type}){
                $logger->debug("Negotiated Type: $information_type - Suffix: ".$config->{content_type_map}->{$information_type});
                $self->stash('content_type',$information_type);
                $self->stash('representation',$config->{content_type_map}->{$information_type});
                last;
            }
        }

        if ($logger->is_debug){
            $logger->debug("content_type: ".$self->stash('content_type')) if ($self->stash('content_type'));
            $logger->debug("representation: ".$self->stash('representation')) if ($self->stash('representation'));
        }
    }

    # Korrektur bei mobilen Endgeraeten, wenn die Repraesentation in portal.yml definiert ist
    if (defined $config->{enable_mobile}{$self->stash('view')} && $self->stash('representation') eq "html" && $self->stash('browser')->mobile() ){
        $self->stash('content_type','text/html');
        $self->stash('representation','mobile');
    }
    
    if (!$self->stash('content_type') && !$self->stash('representation') ){
        $logger->debug("Default Type: text/html - Suffix: html");
        $self->stash('content_type','text/html');
        $self->stash('representation','html');
    }

    return;
}

sub negotiate_language {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    
    my $lang           = $r->headers->header('Accept-Language') || '';
    my @accepted_languages  = map { ($_)=$_=~/^(..)/} map { (split ";", $_)[0] } split /\*s,\*s/, $lang;
    
    #if ($logger->is_debug){
    #    $logger->debug("Accept-Language: $lang - Languages: ".YAML::Dump(\@accepted_languages));
    #}
    
    foreach my $language (@{$config->{lang}}){
        if (any { $_ eq $language } @accepted_languages) {
            $logger->debug("Negotiated Language: $language");
            $self->stash('lang',$language);
            last;
        }
    }

    if (!$self->stash('lang')){
        $logger->debug("Default Language: de");
        $self->stash('lang','de');
    }

    return;
}

sub negotiate_content {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r       = $self->stash('r');
    my $view    = $self->stash('view');
    my $config  = $self->stash('config');
    my $session = $self->stash('session');
    
    if ($logger->is_debug){
	$logger->debug("r-Method: ".$r->method);
    }
    
    if (!$self->stash('disable_content_negotiation')){
        $logger->debug("Doing content negotiation");

        # Wird keine konkrete Reprasentation angesprochen, dann
        # - Typ verhandeln
        # - Sprache verhandeln
        if ($r->method eq "GET"){
            if (!$self->stash('representation') && !$self->stash('content_type')){

                $logger->debug("No specific representation given - negotiating content and language");

                $logger->debug("Path: ".$self->stash('path'));
                
                &negotiate_type($self);
                
                # Pfade sind immer mit base_loc und view
                #my $baseloc    = $config->get('base_loc');
                #$path =~s{^$baseloc/[^/]+}{$path_prefix};

                # Zusaetzlich auch Sprache verhandeln
                my $args="";
                if (!$r->param('l')){
                    if ($session->{lang}){
                        $logger->debug("Sprache definiert durch Cookie: ".$session->{lang});
                        $self->stash('lang',&cleanup_lang($self,$session->{lang}));
                    }
		    elsif ($self->cookie('lang')){
                        $self->stash('lang',$r->cookies->{lang});
		    }
                    else {
                        &negotiate_language($self);
                    }
                    
                    $args="?l=".$self->stash('lang');
                    if ($r->url->query){
                        $args="$args;".$r->url->query;
                    }
                }
                else {
                    $args="?".$r->url->query;
                }

                my $path = "";

                $self->stash('path',$self->stash('path').".".$self->stash('representation'));

                my $dispatch_url = $self->stash('scheme')."://".$self->stash('servername').$self->stash('path').$args;

                $self->stash('dispatch_url',$dispatch_url);
                
                $logger->debug("Negotiating type -> Dispatching to $dispatch_url");

                return;
            }

            # Wenn eine konkrete Repraesentation angesprochen wird, jedoch ohne Sprach-Stasheter,
            # dann muss dieser verhandelt werden.
            if (!$self->param('l') ){
                $logger->debug("Specific representation given, but without language - negotiating");
                
                # Pfade sind immer mit base_loc und view
                #my $baseloc    = $config->get('base_loc');
                #$path =~s{^$baseloc/[^/]+}{$path_prefix};
                
                if ($session->{lang}){
                    $logger->debug("Sprache definiert durch Cookie: ".$session->{lang});
                    $self->stash('lang',&cleanup_lang($self,$session->{lang}));
                }
                else {
                    &negotiate_language($self);
                }
                
                my $args = "?l=".$self->stash('lang');
                
                $args=$args.";".$r->url->query if ($r->url->query);

                my $dispatch_url = $self->stash('scheme')."://".$self->stash('servername').$self->stash('path').$args;
            
                $logger->debug("Negotiated language -> Dispatching to $dispatch_url");

                $self->stash('dispatch_url',$dispatch_url);

                return ;
            }
        }
        # CUD-operations always use the resource-URI, so no redirect neccessary
        elsif ($r->method eq "POST" || $r->method eq "PUT" || $r->method eq "DELETE"){
            &negotiate_type($self);
            &negotiate_language($self);
        }
        else {
            $logger->debug("No additional negotiation necessary");
            $logger->debug("Current URL is ".$self->stash('path')." with args ".$r->url->query);
        }
    }
    else {
	# Respektiere und verarbeite ggf. mitgegebene Repraesentation fuer API-Zugriff
	my $content_type = $r->headers->header('Content-Type') || '';
	
	if ($config->{content_type_map}{$content_type}){
            $self->stash('content_type',$content_type);
            $self->stash('representation',$config->{content_type_map}->{$content_type});
        }
    }

    if ($logger->is_debug && defined $self->stash('representation')){
	$logger->debug("Leaving with representation ".$self->stash('representation'));
    }
    else {
	$logger->debug("Leaving without representation");
    }
    
    return;
}

sub alter_negotiated_language {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r       = $self->stash('r');
    my $session = $self->stash('session');

    # Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Stasheter 'l'
    if ($self->param('l')){
        $logger->debug("Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Stasheter: ".$self->param('l'));
        $self->stash('lang',&cleanup_lang($self,$self->param('l')));
        
        # Setzen als Cookie
        &set_cookie($self,'lang',$self->stash('lang'));
    }
    # alterantiv Korrektur der ausgehandelten Sprache wenn durch cookie festgelegt
    elsif ($session->{lang}){
        $logger->debug("Korrektur der ausgehandelten Sprache durch Cookie: ".$session->{lang});
        $self->stash('lang',&cleanup_lang($self,$session->{lang}));
    }

    return;
}

sub cleanup_lang {
    my ($self,$lang)=@_;

    my $config = $self->stash('config');

    my $is_valid_ref = {};
    
    foreach my $lang (@{$config->{lang}}){
	$is_valid_ref->{$lang} = 1;
    }

    return (defined $is_valid_ref->{$lang} && $is_valid_ref->{$lang})?$lang:'de';
}

sub set_cookie {
    my ($self,$name,$value)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->stash('config');
    my $servername = $self->stash('servername');

    # Strip port from servername
    $servername =~s/:\d+$//;
    
    if (!($name || $value)){
        $logger->debug("Invalid cookie stasheters for cookie: $name / value: $value");
        return;
    }   

    my $cookie_jar_ref = (defined $self->stash('cookie_jar'))?$self->stash('cookie_jar'):[];

    $logger->debug("Adding cookie $name to $value for domain $servername");
    
    my $cookie = CGI::Cookie->new(
        -name     => $name,
        -value    => $value,
        -expires  => '+24h',
        -path     => $config->{base_loc},
	-domain   => $servername,
	-httponly => 1,
	-samesite => "Strict",
    );
    
    push @$cookie_jar_ref, $cookie;
    
    $self->stash('cookie_jar',$cookie_jar_ref);
    
    return;
}

sub finalize_cookies {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    if (defined $self->stash('cookie_jar')){
        $self->header_add('Set-Cookie', $self->stash('cookie_jar'));
    }
    
    return;
}

sub personalize_uri {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r = $self->stash('r');
    
    # Personalisierte URIs
    if ($self->stash('users_loc')){
        my $dispatch_url = ""; #$self->param('scheme')."://".$self->param('servername');   
        
        my $user           = $self->stash('user');
        my $config         = $self->stash('config');
        my $path_prefix    = $self->stash('path_prefix');
        my $path           = $self->stash('path');
        my $representation = $self->stash('representation');
        
#        # Interne Pfade sind immer mit base_loc und view
#        my $baseloc    = $config->get('base_loc');
#        $path =~s{^$baseloc/[^/]+}{$path_prefix};

        # Eine Weiterleitung haengt vom angemeldeten Nutzer ab
        # und gilt immer nur fuer Repraesentationen.
        if ($user->{ID} && $representation){
            my $loc = $self->stash('users_loc');
            $logger->debug("Replacing $path_prefix/$loc with $path_prefix/users/$user->{ID}/$loc");
            my $old_loc = "$path_prefix/$loc";
            my $new_loc = "$path_prefix/users/id/$user->{ID}/$loc";
            $path=~s{^$old_loc}{$new_loc};

            $self->stash('path',$path);
            
            $dispatch_url .=$path;
            
            if ($self->to_cgi_querystring()){
                $dispatch_url.="?".$self->to_cgi_querystring();
            }

            $logger->debug("Dispatching to $dispatch_url");
            $self->stash('dispatch_url',$dispatch_url);

            return;            
        }
        else {
            if (defined $user->{ID} && defined $representation){
                $logger->debug("No Dispatch: User: $user->{ID} / Representation:$representation:");
            }   
        }   
    }
    elsif ($self->stash('admin_loc')){
        my $dispatch_url = ""; #$self->stash('scheme')."://".$self->stash('servername');   
        
        my $user           = $self->stash('user');
        my $config         = $self->stash('config');
        my $path_prefix    = $self->stash('path_prefix');
        my $path           = $self->stash('path');
        my $representation = $self->stash('representation');
        
#        # Interne Pfade sind immer mit base_loc und view
#        my $baseloc    = $config->get('base_loc');
#        $path =~s{^$baseloc/[^/]+}{$path_prefix};

        # Eine Weiterleitung haengt vom angemeldeten Nutzer ab
        # und gilt immer nur fuer Repraesentationen.
        if ($user->is_admin && $representation){
            my $loc = $self->stash('admin_loc');
            $logger->debug("Replacing $path_prefix/$loc with $path_prefix/$config->{admin_loc}/$loc");
            my $old_loc = "$path_prefix/$loc";
            my $new_loc = "$path_prefix/$config->{admin_loc}/$loc";
            $path=~s{^$old_loc}{$new_loc};

            $self->stash('path',$path);
            
            $dispatch_url .=$path;
            
            if ($self->to_cgi_querystring()){
                $dispatch_url.="?".$self->to_cgi_querystring();
            }

            $logger->debug("Dispatching to $dispatch_url");
            $self->stash('dispatch_url',$dispatch_url);

            return;            
        }
        else {
            $logger->debug("No Dispatch: User: $user->{ID} / Representation:$representation:");
        }   
    }
    
    return;
}

sub check_http_basic_authentication {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r       = $self->stash('r');
    my $config  = $self->stash('config');
    my $user    = $self->stash('user');
    my $session = $self->stash('session');
    my $view    = $self->stash('view');

#    if ($logger->is_debug){
#        $logger->debug("User Pre: ".YAML::Dump($user));
#    }
    
    # Shortcut fuer HTTP Basic Authentication anhand lokaler Datenbank
    # Wenn beim Aufruf ein Username und ein Passwort uebergeben wird, dann
    # wird der Nutzer damit authentifiziert und die Session automatisch authorisiert
    
    # Es interessiert nicht der per so in der PSGI-Konfiguration portal.psgi definierte Authentifizierungstyp,
    # sondern der etwaig mit dem aktuellen Request gesendete Typ!
    my $http_authtype = "";
    
    if (defined $r->headers->header('Authorization')){
        ($http_authtype) = $r->headers->header('Authorization') =~/^(\S+)\s+/; #  $r->ap_auth_type(); 
    }
    
    $logger->debug("HTTP Authtype: $http_authtype");
    
    # Nur wenn konkrete Authentifizierungsinformationen geliefert wurden, wird per shortcut
    # und HTTP Basic Authentication authentifiziert, ansonsten gilt die Cookie based authentication
    if ($http_authtype eq "Basic"){
        
        my ($status, $http_user, $password) = $r->get_basic_auth_credentials;
        
        $logger->debug("get_basic_auth: Status $status");
        
        return $status unless $status == 200; # OK
        
        $logger->debug("Authentication Shortcut for user $http_user : Status $status / Password: $password");
        
        my $userid   = $user->authenticate_self_user({ username => $http_user, password => $password, viewname => $view });
        
        my $authenticator   = $config->get_authenticator_self();
        my $authenticatorid = $authenticator->{id};

        $logger->debug("authenticatortarget: $authenticatorid");
        
        if ($userid > 0 && $authenticatorid){
            $user->connect_session({
                sessionID       => $session->{ID},
                userid          => $userid,
                authenticatorid => $authenticatorid,
            });
            $user->{ID} = $userid;
        }
        else {
            $self->stash('basic_auth_failure',1);
        }

        #if ($logger->is_debug){
        #    $logger->debug("User post: ".YAML::Dump($user));
        #}
        
        # User zurueckchreiben
        $self->stash('user',$user);
        
    }
}

1;
