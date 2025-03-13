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
sub startup ($app){

    my $config = OpenBib::Config->new;
    
    Log::Log4perl->init($config->{log4perl_path});

    my $logger = get_logger();
    
    # Register app secret and hypnotoad config
    $app->secrets($config->{mojo}{secrets});
    $app->config(hypnotoad => $config->{mojo}{hypnotoad});

    # Sessions setup
    $app->sessions->cookie_name($config->{mojo}{cookie}{name});
    $app->sessions->cookie_path($config->{base_loc});
    $app->sessions->default_expiration($config->{mojo}{cookie}{expiration});
    $app->sessions->samesite($config->{mojo}{cookie}{samesite});

    # Renderer Path (for mojo default ep templates
    push @{$app->renderer->paths}, $config->{'tt_include_path'};
    
    # Types (eg. include)
    $app->types->type('include' => 'text/html');
	
    # Plugins
    $app->_plugins;
    
    # Router
    my $r = $app->routes;
    $app->_register_routes($r);

    # Pre-processeing mit Hooks
    #
    # Abarbeitungsreihenfolge der Hooks
    #
    #    before_command.
    #    before_server_start.
    #    after_build_tx.
    #    around_dispatch.
    #    before_dispatch.
    #    after_static.
    #    before_routes.
    #    around_action.
    #    before_render.
    #    after_render.
    #    after_dispatch.
    #
    # see https://docs.mojolicious.org/Mojolicious#HOOKS
    
    $app->hook(before_dispatch => sub ($c){
	\&_before_dispatch($c)
	       }
	);
    
    $app->hook(before_routes => sub ($c){
	\&_before_routes($c)
	       }
	);    

    $app->hook(around_action => sub ($next, $c, $action, $last) {
	# Log4perl logger erzeugen
	my $logger = get_logger();
	
	my $r            = $c->req;
	my $path         = $r->url->path;
	my $config       = $c->stash('config');
	my $base_loc     = $config->{'base_loc'};

	$logger->debug("Mojo - Entering _around_action");
	
	return $next->() if ($path !~m{^$base_loc/});
	
	$logger->debug("Mojo - View: ".$c->param('view'));
	$logger->debug("Mojo - Path: ".$r->url->path);
	$logger->debug("Mojo - Route: ".$c->match);
	$logger->debug("Mojo - Format: ".$c->stash('format'));
	$logger->debug("Mojo - Repraesentation: ".$c->stash('representation'));

	# Ggf Personalisiere URI
	&personalize_uri($c);
	
	return $next->();
	       });
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
        my $method     = $item->{method} || 'GET'; # Default: GET
        my $args       = $item->{args};

	if ($method eq "GET"){
	    if (defined $item->{representations}){
		$routes->get($rule => [ format => $item->{representations} ])->to(controller => $controller, action => $action, dispatch_args => $args );
	    }
	    else {
		$routes->get($rule)->to(controller => $controller, action => $action, args => $args );
	    }	    
	}
	elsif ($method eq "POST"){
	    $routes->post($rule)->to(controller => $controller, action => $action )
	}
	elsif ($method eq "PUT"){
	    $routes->put($rule)->to(controller => $controller, action => $action )
	}
	elsif ($method eq "DELETE"){
	    $routes->delete($rule)->to(controller => $controller, action => $action )
	}
    }

    # Add Catchall-Route to Homepage
    $self->routes->any('/portal/*')->to(controller => 'Home', action => 'print_warning' );
    
    return $routes;
}

sub _plugins {
    my $app = shift;

    $app->plugin('DefaultHelpers');
    
    $app->plugin('Directory',{
	root => '/var/www/html'
		 });

}

sub _before_dispatch($c){
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r            = $c->req;
    my $path         = $r->url->path;

    # Wenn kein Portal-URL (z.B. CSS, JS, Images), dann kein Preprocessing notwendig
    # hardcoded for performance
    return if ($path !~m{^/portal/});
    
    my ($view)       = $path =~ m{^/portal/([^/]+)/}; # $c->param('view') for placeholder :view not yet available at this stage
    
    $logger->debug("Mojo - Entering _before_dispatch");
    $logger->debug("Mojo - View c: ".YAML::Dump($c->param('view')));
    $logger->debug("Mojo - Path: ".$r->url->path);
    $logger->debug("Mojo - Route: ".$c->match);
    $logger->debug("Mojo - Format: ".$c->stash('format'));
    $logger->debug("Mojo - View regexp: ".$view);

    my $config       = OpenBib::Config->new;

    $c->stash('view',$view);    
    $c->stash('config',$config);
    $c->stash('r',$r);
    
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
    my $servername    = $r->url->to_abs->host;
    my $port          = $r->url->to_abs->port;

    if ($port){
	$servername = "$servername:$port";
    }
    
    if ($logger->is_debug){
	$logger->debug("X-Forwarded-For: $forwarded_for");
	$logger->debug("X-Client-IP: $xclientip");
	$logger->debug("Servername: $servername");
    }
    
    if (defined $xclientip && $xclientip =~ /([^,\s]+)$/) {
        $remote_ip = $1;
    }

    $c->stash('remote_ip',$remote_ip);
    $c->stash('servername',$servername);

    my $sessionID    = $c->session('sessionID');

    my $session      = OpenBib::Session->new({ sessionID => $sessionID , view => $view, config => $config });
    
    $c->stash('session',$session);
    
    $logger->debug("Got sessionID $sessionID and effecitve sessionID is $session->{ID}");

    $logger->debug('Path'.$r->url->path);
    # Neuer Cookie?, dann senden
    if ($sessionID ne $session->{ID} ){
	$c->session({'sessionID' => $session->{ID}}) ;
    }

    my $normalizer   = OpenBib::Normalizer->new();
    $c->stash('normalizer',$normalizer);
    
    my $user         = OpenBib::User->new({sessionID => $session->{ID}, config => $config});
    $c->stash('user',$user);
    
    my $statistics   = OpenBib::Statistics->new();
    $c->stash('statistics',$statistics);

    my $dbinfo       = OpenBib::Config::DatabaseInfoTable->new;
    $c->stash('dbinfo',$dbinfo);

    my $locinfo      = OpenBib::Config::LocationInfoTable->new;
    $c->stash('locinfo',$locinfo);

    my $useragent    = $c->tx->req->content->headers->user_agent;
    $c->stash('useragent',$useragent);
    
    my $browser      = HTTP::BrowserDetect->new($useragent);
    $c->stash('browser',$browser);

    my $queryoptions = OpenBib::QueryOptions->new({ query => $r, session => $session });

    $c->stash('qopts',$queryoptions);

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
    &process_uri($c);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 2 is ".timestr($timeall));
    }

    # Setzen von content_type/representation, wenn konkrete Repraesentation ausgewaehlt wurde
    &set_content_type_from_uri($c);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 3 is ".timestr($timeall));
    }

    # content_type, representation und lang durch content-Negotiation bestimmen
    # und ggf. zum konkreten Repraesenations-URI redirecten
    # Setzt: content_type,represenation,lang
    &negotiate_content($c);
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 4 is ".timestr($timeall));
    }
    
    # Ggf Personalisiere URI
#    &personalize_uri($c);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 5 is ".timestr($timeall));
    }

    # Bearbeitung HTTP Basic Authentication als Shortcut
    # Setzt ggf: basic_auth_failure (auf 1)
    &check_http_basic_authentication($c);

    # Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Parameter 'l' oder cookie
    &alter_negotiated_language($c);

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 7 is ".timestr($timeall));
    }

    $user = $c->stash('user');

    if ($logger->is_info){
	my $path   = $c->stash('path');
	my $scheme = $c->stash('scheme');
	$logger->info("Remote IP set to $remote_ip for scheme $scheme and path $path");
    }

    $logger->debug("Lang is: ".$c->stash('lang'));
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($c->stash('lang')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    $c->stash('msg',$msg);
    
    if (!$user->can_access_view($view,$remote_ip)){
	my @always_allowed_paths = (
	    $c->stash('path_prefix')."/".$config->get('login_loc'),
	    $c->stash('path_prefix')."/".$config->get('logout_loc'),
	    $c->stash('path_prefix')."/".$config->get('info_loc')."/impressum",
	    $c->stash('path_prefix')."/".$config->get('info_loc')."/datenschutz",		
	    $c->stash('path_prefix')."/".$config->get('users_loc')."/".$config->get('registrations_loc'),
	    $c->stash('path_prefix')."/".$config->get('users_loc')."/".$config->get('passwords_loc'),
	    );
	
	my $do_dispatch = 1;
	
	foreach my $allowed_path (@always_allowed_paths){
	    if ($c->stash('url') =~ m/$allowed_path/){
		$do_dispatch = 0;
	    }
	}

	# Trennung der Zugangskontrolle zwischen API und Endnutzern
	if ($c->stash('representation') eq "html"){
	    my $scheme = ($config->get('use_https'))?'https':$c->stash('scheme');
	    
	    my $redirect_to = $scheme."://".$c->stash('servername').$c->stash('url');
	    
	    my $dispatch_url = $scheme."://".$c->stash('servername').$c->stash('path_prefix')."/".$config->get('login_loc')."?l=".$c->stash('lang').";redirect_to=".uri_escape($redirect_to);
	    
	    $logger->debug("force_login URLs: $redirect_to - ".$c->stash('url')." - ".$dispatch_url);
	    
	    if ($do_dispatch){
		$c->stash('dispatch_url',$dispatch_url);
	    }
	}
	else {
	    if ($do_dispatch){
		$c->stash('default_runmode','show_warning');
		$c->stash('warning_message',$msg->maketext("Zugriff verweigert."));
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
    if (0 == 1 && $session->is_expired){
	if ($c->stash('representation') eq "html"){

	    my $scheme = ($config->get('use_https'))?'https':$c->stash('scheme');
	    
	    my $dispatch_url = $scheme."://".$c->stash('servername').$c->stash('path_prefix')."/".$config->get('logout_loc').".html?l=".$c->stash('lang').";expired=1";
	    
	    $logger->debug("Session expired. Force logout: ".$c->stash('url')." - ".$dispatch_url);
	    
	    $c->stash('dispatch_url',$dispatch_url);
	}
	else {
	    $c->stash('default_runmode','show_warning');
	    $c->stash('warning_message',$msg->maketext("Sitzung abgelaufen."));
	}
    }
    

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden
    
    my $method          = ($r->param('_method'))?escape_html($r->param('_method')):'';
    my $confirm         = ($r->param('confirm'))?escape_html($r->param('confirm')):0;
    
    if ($method eq "DELETE" || $r->method eq "DELETE"){
	$logger->debug("Deletion shortcut");
	
	if ($confirm){
	    $c->routes->continue("#confirm_delete_record")
		#$c->prerun_mode('confirm_delete_record');
	}
	else {
	    $c->routes->continue("#delete_record")	       
		#               $c->prerun_mode('delete_record');
	}
    }
    
    # Wenn dispatch_url, dann Runmode dispatch_to_representation mit externem Redirect
    if ($c->stash('dispatch_url')){
	$logger->debug("Dispatching to representation ".$c->stash('dispatch_url'));
	$c->res->code(303);
	$c->redirect_to($c->stash('dispatch_url'));
    }
    

    # Wenn default_runmode gesetzt, dann ausschliesslich in diesen wechseln
    if ($c->stash('default_runmode')){
	if (OpenBib::Mojo::Controller->can($c->stash('default_runmode'))){
	    $c->run_modes(
		$c->stash('default_runmode')  => $c->stash('default_runmode'),
		);
	}
	else {
	    $logger->error("Invalid default runmode ".$c->stash('default_runmode'));
	}
    }        
    
    $logger->debug("Existing _before_dispatch");        
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for _before_dispatch is ".timestr($timeall));
    }
}

sub _before_routes($c) {
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r            = $c->req;
    my $path         = $r->url->path;

    return if ($path !~m{^/portal/});

    $logger->debug("Mojo - Entering _before_routes");
    $logger->debug("Mojo - View: ".$c->param('view'));
    $logger->debug("Mojo - Path: ".$r->url->path);
    $logger->debug("Mojo - Route: ".$c->match);
    $logger->debug("Mojo - Format: ".$c->stash('format'));
    
    return;
}

sub process_uri($c) {

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view       = $c->stash('view');

    # Shared Args
    my $r          = $c->stash('r');
    my $config     = $c->stash('config');
    my $servername = $c->stash('servername');

    $logger->debug("Object Type ".ref $c);
    
    my $path_prefix          = $config->get('base_loc');
    my $complete_path_prefix = "$path_prefix/$view";
    
    # Letztes Pfad-Element bestimmen
    my $uri      = $r->url->base;
    my $path     = $r->url->path;
    my $scheme   = $r->url->scheme || 'http';
    my $args_ref = $r->url->query;

    my $forwarded_proto = $r->headers->header('X-Forwarded-Proto');

    $logger->debug("X-Forwarded-Proto: $forwarded_proto") if (defined $forwarded_proto);

    if (defined $forwarded_proto && $forwarded_proto=~/^https/){
	$scheme = "https";
    }

    # use-https overrides everything
    $scheme = ($config->get('use_https'))?'https':$scheme;
    
    my ($location_uri,$last_uri_element) = $path =~m/^(.+?)\/([^\/]+)$/;
 
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
    $logger->debug("Path Prefix: $path_prefix");
    $logger->debug("Location_uri: $location_uri");
    

    my $id;

    if ($last_uri_element){
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
	my $args = join('&',@$args_ref);
        $location.="?$args";
    }

    $c->stash('location',$location);
    $c->stash('path_prefix',$path_prefix);
    $c->stash('path',$path);
    $c->stash('scheme',$scheme);

    my $url = $r->url->base;
    
    $c->stash('url',$url);
}

sub set_content_type_from_uri {
    my $c    = shift;
    my $uri  = shift || $c->stash('path');

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $c->stash('config');

    my $suffixes = join '|', keys %{$config->{content_type_map_rev}};

    my ($representation) = $uri =~m/^.*?\/[^\/]*?\.($suffixes)$/;

    # Korrektur des ausgehandelten Typs bei direkter Auswahl einer bestimmten Repraesentation
    if (defined $representation && $config->{content_type_map_rev}{$representation}){
	$logger->debug("Setting type from URI $uri. Got Representation $representation and content_type ".$config->{content_type_map_rev}{$representation});

        $c->stash('content_type',$config->{content_type_map_rev}{$representation});
        $c->stash('representation',$representation);
    }
    
    return;
}

sub negotiate_type($c) {

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $c->stash('r');
    my $config         = $c->stash('config');

    
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
            $c->stash('content_type',$content_type);
            $c->stash('representation',$config->{content_type_map}->{$content_type});
        }
        $logger->debug("content_type: ".$c->stash('content_type')." - representation: ".$c->stash('representation')) if (defined $c->stash('content_type') && defined $c->stash('represenation'));
    }
    elsif (@accepted_types){
        #if ($logger->is_debug){
        #    $logger->debug("Accept: $accept - Types: ".YAML::Dump(\@accepted_types));
        #}
    
        foreach my $information_type (@accepted_types){
            if ($config->{content_type_map}{$information_type}){
                $logger->debug("Negotiated Type: $information_type - Suffix: ".$config->{content_type_map}->{$information_type});
                $c->stash('content_type',$information_type);
                $c->stash('representation',$config->{content_type_map}->{$information_type});
                last;
            }
        }

        if ($logger->is_debug){
            $logger->debug("content_type: ".$c->stash('content_type')) if ($c->stash('content_type'));
            $logger->debug("representation: ".$c->stash('representation')) if ($c->stash('representation'));
        }
    }

    # mobile-Repraesentation ist obsolet. Daher keine Analyse mehr

    # Default, wenn bisher nicht besetzt
    if (!$c->stash('content_type') && !$c->stash('representation') ){
        $logger->debug("Default Type: text/html - Suffix: html");
        $c->stash('content_type','text/html');
        $c->stash('representation','html');
    }

    return;
}

sub negotiate_language($c) {

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $c->stash('r');
    my $config         = $c->stash('config');
    
    my $lang           = $r->headers->header('Accept-Language') || '';
    my @accepted_languages  = map { ($_)=$_=~/^(..)/} map { (split ";", $_)[0] } split /\*s,\*s/, $lang;
    
    #if ($logger->is_debug){
    #    $logger->debug("Accept-Language: $lang - Languages: ".YAML::Dump(\@accepted_languages));
    #}
    
    foreach my $language (@{$config->{lang}}){
        if (any { $_ eq $language } @accepted_languages) {
            $logger->debug("Negotiated Language: $language");
            $c->stash('lang',$language);
            last;
        }
    }

    if (!$c->stash('lang')){
        $logger->debug("Default Language: de");
        $c->stash('lang','de');
    }

    return;
}

sub negotiate_content($c) {

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view       = $c->stash('view');

    # Shared Args
    my $r       = $c->stash('r');
    my $config  = $c->stash('config');
    my $session = $c->stash('session');
    
    if ($logger->is_debug){
	$logger->debug("r-Method: ".$r->method);
    }
    
    if (!$c->stash('disable_content_negotiation')){
        $logger->debug("Doing content negotiation");

        # Wird keine konkrete Reprasentation angesprochen, dann
        # - Typ verhandeln
        # - Sprache verhandeln
        if ($r->method eq "GET"){
            if (!$c->stash('representation') && !$c->stash('content_type')){

                $logger->debug("No specific representation given - negotiating content and language");

                $logger->debug("Path: ".$c->stash('path'));
                
                &negotiate_type($c);
                
                # Zusaetzlich auch Sprache verhandeln
                my $args="";
                if (!$r->param('l')){
                    if ($session->{lang}){
                        $logger->debug("Sprache definiert durch Session: ".$session->{lang});
                        $c->stash('lang',&cleanup_lang($c,$session->{lang}));
                    }
		    elsif ($c->session('lang')){
                        $logger->debug("Sprache definiert durch Cookie: ".$session->{lang});
                        $c->stash('lang',$c->session('lang'));
		    }
                    else {
                        &negotiate_language($c);
                    }

		    # language nun in stash lang
		    my $existing_args = $r->url->query->merge(l => $c->stash('lang'));
		    $logger->debug("Args with added language: ".$existing_args->to_string);
		    $args = "?".$existing_args->to_string;
                }
                else {
                    $args="?".$r->url->query;
                }

                my $path = "";

                $c->stash('path',$c->stash('path').".".$c->stash('representation'));

                my $dispatch_url = $c->stash('scheme')."://".$c->stash('servername').$c->stash('path').$args;

                $c->stash('dispatch_url',$dispatch_url);
                
                $logger->debug("Negotiating type -> Dispatching to $dispatch_url");

                return;
            }

            # Wenn eine konkrete Repraesentation angesprochen wird, jedoch ohne Sprach-Stasheter,
            # dann muss dieser verhandelt werden.
            if (!$r->param('l') ){
                $logger->debug("Specific representation given, but without language - negotiating");
                
                if ($session->{lang}){
                    $logger->debug("Sprache definiert durch Cookie: ".$session->{lang});
                    $c->stash('lang',&cleanup_lang($c,$session->{lang}));
                }
                else {
                    &negotiate_language($c);
                }
                
		# language nun in stash lang
		my $existing_args = $r->url->query->merge(l => $c->stash('lang'));
		$logger->debug("Args with added language: ".$existing_args->to_string);
		my $args = "?".$existing_args->to_string;

                my $dispatch_url = $c->stash('scheme')."://".$c->stash('servername').$c->stash('path').$args;
            
                $logger->debug("Negotiated language -> Dispatching to $dispatch_url");

                $c->stash('dispatch_url',$dispatch_url);

                return ;
            }
        }
        # CUD-operations always use the resource-URI, so no redirect neccessary
        elsif ($r->method eq "POST" || $r->method eq "PUT" || $r->method eq "DELETE"){
            &negotiate_type($c);
            &negotiate_language($c);
        }
        else {
            $logger->debug("No additional negotiation necessary");
            $logger->debug("Current URL is ".$c->stash('path')." with args ".$r->url->query);
        }
    }
    else {
	# Respektiere und verarbeite ggf. mitgegebene Repraesentation fuer API-Zugriff
	my $content_type = $r->headers->header('Content-Type') || '';
	
	if ($config->{content_type_map}{$content_type}){
            $c->stash('content_type',$content_type);
            $c->stash('representation',$config->{content_type_map}->{$content_type});
        }
    }

    if ($logger->is_debug && defined $c->stash('representation')){
	$logger->debug("Leaving with representation ".$c->stash('representation'));
    }
    else {
	$logger->debug("Leaving without representation");
    }
    
    return;
}

sub alter_negotiated_language($c) {
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r       = $c->stash('r');
    my $session = $c->stash('session');
    my $config  = $c->stash('config');

    # Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Stasheter 'l'
    if ($r->param('l')){
        $logger->debug("Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Parameter: ".$r->param('l'));
        $c->stash('lang',&cleanup_lang($c,$r->param('l')));
        
	$c->session({'lang' => $c->stash('lang')}) ;
    }
    # alterantiv Korrektur der ausgehandelten Sprache wenn durch cookie festgelegt
    elsif ($session->{lang}){
        $logger->debug("Korrektur der ausgehandelten Sprache durch Cookie: ".$session->{lang});
        $c->stash('lang',&cleanup_lang($c,$session->{lang}));
    }

    return;
}

sub cleanup_lang {
    my $c = shift;
    my $lang = shift;
    
    my $config = $c->stash('config');

    my $is_valid_ref = {};
    
    foreach my $lang (@{$config->{lang}}){
	$is_valid_ref->{$lang} = 1;
    }

    return (defined $is_valid_ref->{$lang} && $is_valid_ref->{$lang})?$lang:'de';
}

sub personalize_uri($c) {

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r        = $c->stash('r');
    my $args_ref = $c->stash('dispatch_args');

    if (defined $args_ref && $logger->is_debug){
	$logger->debug("Using dispatch args :".YAML::Dump($args_ref));
    }
    else {
	$logger->debug("No dispatch args available");
    }
    
    # Personalisierte URIs
    if ($args_ref->{'users_loc'}){
        my $dispatch_url = ""; #$c->param('scheme')."://".$c->param('servername');   
        
        my $user           = $c->stash('user');
        my $config         = $c->stash('config');
        my $path_prefix    = $c->stash('path_prefix');
        my $path           = $c->stash('path');
        my $representation = $c->stash('representation');
        
        # Eine Weiterleitung haengt vom angemeldeten Nutzer ab
        # und gilt immer nur fuer Repraesentationen.
        if ($user->{ID} && $representation){
            my $loc = $args_ref->{'users_loc'};
            $logger->debug("Replacing $path_prefix/$loc with $path_prefix/users/$user->{ID}/$loc");
            my $old_loc = "$path_prefix/$loc";
            my $new_loc = "$path_prefix/users/id/$user->{ID}/$loc";
            $path=~s{^$old_loc}{$new_loc};

            $c->stash('path',$path);
            
            $dispatch_url .=$path;
            
            if ($c->to_cgi_querystring()){
                $dispatch_url.="?".$c->to_cgi_querystring();
            }

            $logger->debug("Dispatching to $dispatch_url");
            $c->stash('dispatch_url',$dispatch_url);

            return;            
        }
        else {
            if (defined $user->{ID} && defined $representation){
                $logger->debug("No Dispatch: User: $user->{ID} / Representation:$representation:");
            }   
        }   
    }
    elsif ($args_ref->{'admin_loc'}){
        my $dispatch_url = ""; #$c->stash('scheme')."://".$c->stash('servername');   
        
        my $user           = $c->stash('user');
        my $config         = $c->stash('config');
        my $path_prefix    = $c->stash('path_prefix');
        my $path           = $c->stash('path');
        my $representation = $c->stash('representation');
        
        # Eine Weiterleitung haengt vom angemeldeten Nutzer ab
        # und gilt immer nur fuer Repraesentationen.
        if ($user->is_admin && $representation){
            my $loc = $c->stash('admin_loc');
            $logger->debug("Replacing $path_prefix/$loc with $path_prefix/$config->{admin_loc}/$loc");
            my $old_loc = "$path_prefix/$loc";
            my $new_loc = "$path_prefix/$config->{admin_loc}/$loc";
            $path=~s{^$old_loc}{$new_loc};

            $c->stash('path',$path);
            
            $dispatch_url .=$path;
            
            if ($c->to_cgi_querystring()){
                $dispatch_url.="?".$c->to_cgi_querystring();
            }

            $logger->debug("Dispatching to $dispatch_url");
            $c->stash('dispatch_url',$dispatch_url);

            return;            
        }
        else {
            $logger->debug("No Dispatch: User: $user->{ID} / Representation:$representation:");
        }   
    }
    
    return;
}

sub check_http_basic_authentication($c) {
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view       = $c->stash('view');

    # Shared Args
    my $r       = $c->stash('r');
    my $config  = $c->stash('config');
    my $user    = $c->stash('user');
    my $session = $c->stash('session');

#    if ($logger->is_debug){
#        $logger->debug("User Pre: ".YAML::Dump($user));
#    }
    
    # Shortcut fuer HTTP Basic Authentication anhand lokaler Datenbank
    # Wenn beim Aufruf ein Username und ein Passwort uebergeben wird, dann
    # wird der Nutzer damit authentifiziert und die Session automatisch authorisiert
    
    # Es interessiert nicht der per se in der Konfiguration portal.mojo definierte Authentifizierungstyp,
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
            $c->stash('basic_auth_failure',1);
        }

        #if ($logger->is_debug){
        #    $logger->debug("User post: ".YAML::Dump($user));
        #}
        
        # User zurueckchreiben
        $c->stash('user',$user);
        
    }
}

1;
