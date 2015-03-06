#####################################################################
#
#  OpenBib::Handler::PSGI
#
#  Dieses File ist (C) 2010-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);
use List::MoreUtils qw(none any);
use Benchmark ':hireswallclock';
use Encode qw(decode_utf8 encode_utf8);
use HTTP::Negotiate;
use HTTP::BrowserDetect;
use JSON::XS;
use Template;
use URI::Escape;
use XML::RSS;
use Text::CSV_XS;
use YAML ();

use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Config::LocationInfoTable;
use OpenBib::Common::Util;
use OpenBib::Container;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Template::Provider;
use OpenBib::User;

use Scalar::Util;

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

    my $config       = OpenBib::Config->new;

    $self->param('config',$config);
    
    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    if (!defined $r){
        $logger->error("No Request");
    }
    
    my $sessionID     = $r->cookies->{sessionID} || '';

    my $session      = OpenBib::Session->new({ sessionID => $sessionID , view => $view });
    $self->param('session',$session);

    $logger->debug("Got sessionID $sessionID and effecitve sessionID is $session->{ID}");

    # Neuer Cookie?, dann senden
    if ($sessionID ne $session->{ID}){
        $self->set_cookie('sessionID',$session->{ID}) ;
    }
    
    # Neue Session, dann loggen
    $session->log_new_session_once($r);

    my $user         = OpenBib::User->new({sessionID => $session->{ID}});
    $self->param('user',$user);

    $logger->debug("User: ".YAML::Dump($user));
    
    my $dbinfo       = OpenBib::Config::DatabaseInfoTable->new;
    $self->param('dbinfo',$dbinfo);

    my $locinfo      = OpenBib::Config::LocationInfoTable->new;
    $self->param('locinfo',$locinfo);

    my $useragent    = $r->user_agent;
    $self->param('useragent',$useragent);
    
    my $browser      = HTTP::BrowserDetect->new($useragent);
    $self->param('browser',$browser);
    
    my $queryoptions = OpenBib::QueryOptions->new({ query => $r, session => $session });
    $self->param('qopts',$queryoptions);
    $self->param('servername',$r->get_server_name);

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

    if (defined $user->{ID}){
        $logger->debug("This request after initialization: User? $user->{ID}");
    }

    if (defined $session->{ID}){
        $logger->debug("This request after initialization: SessionID: $session->{ID}");
    }
    else {
        $logger->error("No SessionID after initialization");
    }

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
   my $user         = $self->param('user');
   
   $logger->debug("User: ".YAML::Dump($user));
   
   {
       # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
       # zu verwenden
       
       my $method          = $r->param('_method') || '';
       my $confirm         = $r->param('confirm') || 0;
       
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

   # Cookie-Header ausgeben
   $self->finalize_cookies;
   
   $logger->debug("Exit cgiapp_prerun");
}

sub cgiapp_get_query {
	my $self = shift;

	# Include OpenBib::Request instead of CGI.pm and related modules
#	require OpenBib::Request;

	# Get the query object
#	my $r = OpenBib::Request->new();

	return $self->param('r');
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
                if (!$r->param('l')){
                    if ($session->{lang}){
                        $logger->debug("Sprache definiert durch Cookie: ".$session->{lang});
                        $self->param('lang',$session->{lang});
                    }
                    else {
                        $self->negotiate_language;
                    }
                    
                    $args="?l=".$self->param('lang');
                    if ($r->args()){
                        $args="$args;".$r->args();
                    }
                }
                else {
                    $args="?".$r->args();
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
            if (!$r->param('l') ){
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
                
                $args=$args.";".$r->args() if ($r->args());

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
            $logger->debug("Current URL is ".$self->param('path')." with args ".$r->args());
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
    if ($r->param('l')){
        $logger->debug("Korrektur der ausgehandelten Sprache bei direkter Auswahl via CGI-Parameter: ".$r->param('l'));
        $self->param('lang',$r->param('l'));
        
        # Setzen als Cookie
        $self->set_cookie('lang',$self->param('lang'));
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
    my $uri    = $r->request_uri;
    my $path   = $r->path;
    my $scheme = $r->scheme || 'http';
    my $args   = $r->args;

    my $forwarded_proto = $r->header('X-Forwarded-Proto');

    $logger->debug("X-Forwarded-Proto: $forwarded_proto") if (defined $forwarded_proto);

    if (defined $forwarded_proto && $forwarded_proto=~/^https/){
	$scheme = "https";
    }

    my ($location_uri,$last_uri_element) = $path =~m/^(.+?)\/([^\/]+)$/;
    
    $logger->debug("Full Internal Path: $path - Last URI Element: $last_uri_element - Args: ".$r->args);
    
    if (! $config->strip_view_from_uri($view)){
        $path_prefix = $complete_path_prefix;
    }
    else {
        $path =~s/^(\/[^\/]+)\/[^\/]+(\/.+)$/$1$2/;
    }

    my $suffixes = join '|', keys %{$config->{content_type_map_rev}};
    my $regexp = "^(.+?)\.($suffixes)\$";
    
    $logger->debug("Suffixes: $suffixes");
    $logger->debug("Scheme: $scheme");
    
#    my ($id) = $last_uri_element =~m/^(.+?)\.($suffixes)$/;
    my ($id) = $last_uri_element =~m/^(.+?)\.($suffixes)$/;

    $logger->debug("ID: $id") if ($id);
    
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

    my $url = $r->request_uri;
    
    $self->param('url',$url);
}

sub personalize_uri {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r = $self->param('r');
    
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
            
            if ($r->args()){
                $dispatch_url.="?".$r->args();
            }

            $logger->debug("Dispatching to $dispatch_url");
            $self->param('dispatch_url',$dispatch_url);

            return;            
        }
        else {
            if (defined $user->{ID} && defined $representation){
                $logger->debug("No Dispatch: User: $user->{ID} / Representation:$representation:");
            }   
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
            
            if ($r->args()){
                $dispatch_url.="?".$r->args();
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

    if (defined $representation){
        $logger->debug("Setting type from URI $uri. Got Represenation $representation");
    }
    
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
    my $config         = OpenBib::Config->new;    

    
    my $content_type = $r->header('Content-Type') || '';
    my $accept       = $r->header('Accept') || '';
    my @accepted_types = ();

    foreach my $item (split '\s*,\s*', $accept){
        $item=~s/;.+$//;
        push @accepted_types, $item;
    }

    if ($content_type){
        if ($logger->is_debug){
            $logger->debug("Content-Type: |$content_type|");
            $logger->debug(YAML::Dump($config->{content_type_map}));
        }
        
        if ($config->{content_type_map}{$content_type}){
            $self->param('content_type',$content_type);
            $self->param('representation',$config->{content_type_map}->{$content_type});
        }
        $logger->debug("content_type: ".$self->param('content_type')." - representation: ".$self->param('representation'));
    }
    elsif (@accepted_types){
        if ($logger->is_debug){
            $logger->debug("Accept: $accept - Types: ".YAML::Dump(\@accepted_types));
        }
    
        foreach my $information_type (@accepted_types){
            if ($config->{content_type_map}{$information_type}){
                $logger->debug("Negotiated Type: $information_type - Suffix: ".$config->{content_type_map}->{$information_type});
                $self->param('content_type',$information_type);
                $self->param('representation',$config->{content_type_map}->{$information_type});
                last;
            }
        }

        if ($logger->is_debug){
            $logger->debug("content_type: ".$self->param('content_type')) if ($self->param('content_type'));
            $logger->debug("representation: ".$self->param('representation')) if ($self->param('representation'));
        }
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
    
    my $lang         = $r->header('Accept-Language') || '';
    my @accepted_languages  = map { ($_)=$_=~/^(..)/} map { (split ";", $_)[0] } split /\*s,\*s/, $lang;
    
    if ($logger->is_debug){
        $logger->debug("Accept-Language: $lang - Languages: ".YAML::Dump(\@accepted_languages));
    }
    
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
    $logger->debug("Session-UserID: ".$user->{ID}) if (defined $user->{ID});
    
#     if (! $user->{ID} && $self->param('represenation') eq "html"){
#         # Aufruf-URL
#         my $return_uri  = uri_escape($r->parsed_uri->path);
        
#         # Return-URL in der Session abspeichern
        
#         return $self->redirect("$path_prefix/$config->{login_loc}?redirect_to=$return_uri",303);
#     }

    if ($role eq "admin" && $user->is_admin){
        return 1;
    }
    elsif ($role eq "user" && ( $user->is_admin || $user->{ID} eq $userid )){
        return 1;
    }
    else {
      $logger->debug("User authenticated as $user->{ID}, but doesn't match required userid $userid") if (defined $user->{ID} && $userid);
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

    return $self->print_page($config->{tt_error_tname},$ttdata);
}

sub print_info {
    my $self = shift;
    my $info   = shift;
    my $infonr = shift || 1;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->param('config');

    my $ttdata = {
        info_msg => $info,
        info_nr  => $infonr,
    };

    retunr $self->print_page($config->{tt_info_message_tname},$ttdata);
}

sub print_json {
    my $self      = shift;
    my $json_ref  = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');

    # Dann Ausgabe des neuen Headers
    $self->header_add('Content-Type' => 'application/json');

    if ($logger->is_debug()){
        $logger->debug(YAML::Dump($json_ref))
    }

    return encoder_json($json_ref);
}

sub print_page {
    my ($self,$templatename,$ttdata)=@_;

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
    my $representation = $self->param('representation') || 'html';
    my $status         = $self->param('status') || 200;
    my $content_type   = $self->param('content_type') || $ttdata->{'content_type'} || $config->{'content_type_map_rev'}{$representation} || 'text/html';
    my $location       = $self->param('location');
    my $url            = $self->param('url');

    $logger->debug("Entering print_page with template $templatename");
    
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

    my $content = "";

    my $template = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
	    ABSOLUTE       => 1,
            STAT_TTL => 60,  # one minute
        }) ],
        COMPILE_EXT => '.ttc',
        COMPILE_DIR => '/tmp/ttc',
        STAT_TTL => 60,  # one minute
        OUTPUT         => \$content,    # Output geht in Scalar-Ref
        RECURSION      => 1,
    });

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time until stage 1 is ".timestr($timeall));
    }

    $template->process($templatename, $ttdata) || do {
        $logger->fatal($template->error());
        return;
    };

    # Location- und Content-Location-Header setzen    
    $self->header_type('header');
    $self->header_add('Status' => $status) if ($status);
    $self->header_add('Content-Type' => $content_type) if ($content_type);
    $self->header_add('Content-Location' => $location) if ($location);


    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time until stage 2 is ".timestr($timeall));
    }

    $logger->debug("Template-Output: ".$content);

    # PSGI-Spezifikation erwartet UTF8 bytestream
    $content = encode_utf8($content);

    return \$content;
}

sub add_default_ttdata {
    my ($self,$ttdata) = @_; 

    my $r              = $self->param('r');
    my $view           = $self->param('view');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $browser        = $self->param('browser');
    my $servername     = $self->param('servername');
    my $dbinfo         = $self->param('dbinfo');
    my $locinfo        = $self->param('locinfo');
    my $path_prefix    = $self->param('path_prefix');
    my $path           = $self->param('path');
    my $url            = $self->param('url');
    my $location       = $self->param('location');
    my $scheme         = $self->param('scheme');
    my $representation = $self->param('representation') || 'html';
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
    my $authenticator = {};
    
    # Wenn wir authentifiziert sind, dann
    if ($user->{ID}) {
        $username=$user->get_username();
        $authenticator=$session->get_authenticator;
    }

    # Mitgelieferter Username geht vor:
    if ($ttdata->{'username'}){
        $username = $ttdata->{'username'};
    }
    
    if ($representation eq "rss"){
        my $rss = new XML::RSS ( version => '1.0' ) ;
        $ttdata->{'rss'}           = $rss;
    }

    if ($representation eq "csv"){
        my $csv = Text::CSV_XS->new ({
            'binary'       => 1, # potential newlines inside fields
            'always_quote' => 1,
            'eol'          => "\n",
#            'sep_char'    => "\t",
        });
        $ttdata->{'csv'}           = $csv;
    }
    
    # TT-Data anreichern
    $ttdata->{'r'}              = $r;
    $ttdata->{'query'}          = $query;
    $ttdata->{'scheme'}         = $scheme;
    $ttdata->{'view'}           = $view;
    $ttdata->{'dbinfo'}         = $dbinfo;
    $ttdata->{'locinfo'}        = $locinfo;
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
    $ttdata->{'authenticator'}  = $authenticator;
    $ttdata->{'useragent'}      = $useragent;
    $ttdata->{'browser'}      = $browser;
    $ttdata->{'cgiapp'}         = $self;
    $ttdata->{'container'}      = $container;
    
    # Helper functions
    $ttdata->{'to_json'}        = sub {
        my $ref = shift;
        return decode_utf8(encode_json $ref);
    };

    $ttdata->{'from_json'}        = sub {
        my $string = shift;
        my $json_ref = {};
        $string=~s/\\"/"/g;
        my $logger = get_logger();

        eval {
            $json_ref = decode_json encode_utf8($string);
        };
        if ($@){
            $logger->error($@);
        }
            
        return $json_ref;
    };

    $ttdata->{'uri_escape'}     = sub {
        my $string = shift;
        return uri_escape_utf8($string);
    };

    $ttdata->{'uri_unescape'}     = sub {
        my $string = shift;
        return uri_unescape($string);
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

    $ttdata->{'encode_utf8'}    = sub {
        my $string=shift;
        return encode_utf8($string);
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

    if ($logger->is_debug){
        $logger->debug("Args".YAML::Dump($arg_ref));
    }

    my @cgiparams = ();

    my $r            = $self->param('r');

    if ($r->parameters){
        foreach my $param (keys %{$r->parameters}){
            next unless ($r->param($param));
            $logger->debug("Processing $param");
            if (exists $arg_ref->{change}->{$param}){
                push @cgiparams, {
                    param => $param,
                    val   => decode_utf8(uri_unescape($arg_ref->{change}->{$param})),
                };
            }
            elsif (! exists $exclude_ref->{$param}){
                my @values = $r->param($param);
                if (@values){
                    foreach my $value (@values){
                        push @cgiparams, {
                            param => $param,
                            val   => decode_utf8(uri_unescape($value)),
                        };
                    }
                }
                else {
                    push @cgiparams, {
                        param => $param,
                        val => decode_utf8(uri_unescape($r->param($param))),
                    };
                }
            }
        }
    }

    if ($logger->is_debug){
        $logger->debug("Got cgiparams ".YAML::Dump(\@cgiparams));
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
        push @cgiparams, "$arg_ref->{param}=".uri_escape_utf8($arg_ref->{val});
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
    
    if ($logger->is_debug){
        $logger->debug("Args".YAML::Dump($arg_ref));
    }

    my @cgiparams = ();

    foreach my $arg_ref ($self->to_cgi_params($arg_ref)){
        push @cgiparams, "<input type=\"hidden\" name=\"$arg_ref->{param}\" value=\"".decode_utf8(uri_unescape($arg_ref->{val}))."\" />";
    }   

    return join("\n",@cgiparams);
}

# Kudos to Stas Bekman: mod_per2 Users's Guide

sub read_json_input {
    my $self = shift;
    
    my $r  = $self->param('r');
        
    return $r->content;
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
            elsif ($type eq "bool"){
                $input_params_ref->{$param} = $query->param($param)  || $default;
            }
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

    $self->redirect($self->param('dispatch_url'),'303');
    
    return;
}

sub redirect {
    my ($self,$url,$status) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $status = $status || '302'; # Found

    if (!$url){
        $logger->error("Trying to redirect without url...");
        return;
    }

#    $self->param('status',$status);
    
    $self->header_type('redirect');
    $self->header_add('Location' => $url);
    $self->header_add('Status' => $status);

    if ($logger->is_debug){
        $logger->debug("Redirect-Headers: ".YAML::Syck::Dump($self->{__HEADER_PROPS}));
    }
    
    return;
}

sub print_authorization_error {
    my $self = shift;

    my $r           = $self->param('r');
    my $path_prefix = $self->param('path_prefix');
    my $config      = $self->param('config');
    my $msg         = $self->param('msg');

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($self->param('representation') eq "html"){
        # Aufruf-URL
        my $return_uri  = uri_escape($r->request_uri);
        
        # Return-URL in der Session abspeichern
        
        $logger->debug("Authorization error: Redirecting to $return_uri");
        
        return $self->redirect("$path_prefix/$config->{login_loc}?redirect_to=$return_uri",303);
    }
    else {
        $logger->debug("Authorization error");
        $self->header_add('Status' => 403); # FORBIDDEN
        return;
    }
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

#    if ($logger->is_debug){
#        $logger->debug("User Pre: ".YAML::Dump($user));
#    }
    
    # Shortcut fuer HTTP Basic Authentication anhand lokaler Datenbank
    # Wenn beim Aufruf ein Username und ein Passwort uebergeben wird, dann
    # wird der Nutzer damit authentifiziert und die Session automatisch authorisiert
    
    # Es interessiert nicht der per so in der PSGI-Konfiguration portal.psgi definierte Authentifizierungstyp,
    # sondern der etwaig mit dem aktuellen Request gesendete Typ!
    my $http_authtype = "";
    
    if (defined $r->header('Authorization')){
        ($http_authtype) = $r->header('Authorization') =~/^(\S+)\s+/; #  $r->ap_auth_type(); 
    }
    
    $logger->debug("HTTP Authtype: $http_authtype");
    
    # Nur wenn konkrete Authentifizierungsinformationen geliefert wurden, wird per shortcut
    # und HTTP Basic Authentication authentifiziert, ansonsten gilt die Cookie based authentication
    if ($http_authtype eq "Basic"){
        
        my ($status, $http_user, $password) = $r->get_basic_auth_credentials;
        
        $logger->debug("get_basic_auth: Status $status");
        
        return $status unless $status == 200; # OK
        
        $logger->debug("Authentication Shortcut for user $http_user : Status $status / Password: $password");
        
        my $userid   = $user->authenticate_self_user({ username => $http_user, password => $password });
        
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
            $self->param('basic_auth_failure',1);
        }

        if ($logger->is_debug){
            $logger->debug("User post: ".YAML::Dump($user));
        }
        
        # User zurueckchreiben
        $self->param('user',$user);
        
    }
}

sub tunnel_through_authenticator {
    my ($self,$method,$authenticatorid) = @_;

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
    
    my $new_location = "$config->{base_loc}/$view/$config->{login_loc}?authenticatorid=$authenticatorid;redirect_to=$return_uri";
    
    return $self->redirect($new_location,303);
}

sub set_cookieXX {
    my ($self,$name,$value)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    if (!($name || $value)){
        $logger->debug("Invalid cookie parameters for cookie: $name / value: $value");
        return;
    }   

    $logger->debug("Adding cookie $name to $value");
    
    my $cookie = CGI::Cookie->new(
        -name    => $name,
        -value   => $value,
        -expires => '+24h',
        -path    => $config->{base_loc},
    );
    
    my $cookie_string = $cookie->as_string();
     
    $self->header_add('Set-Cookie', $cookie_string) if ($cookie_string);
    
    return;
}

sub set_cookie {
    my ($self,$name,$value)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

    if (!($name || $value)){
        $logger->debug("Invalid cookie parameters for cookie: $name / value: $value");
        return;
    }   

    my $cookie_jar_ref = (defined $self->param('cookie_jar'))?$self->param('cookie_jar'):[];

    $logger->debug("Adding cookie $name to $value");
    
    my $cookie = CGI::Cookie->new(
        -name    => $name,
        -value   => $value,
        -expires => '+24h',
        -path    => $config->{base_loc},
    );
    
    push @$cookie_jar_ref, $cookie;
    
    $self->param('cookie_jar',$cookie_jar_ref);
    
    return;
}

sub finalize_cookies {
    my ($self)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = OpenBib::Config->new;

    if (defined $self->param('cookie_jar')){
        $self->header_add('Set-Cookie', $self->param('cookie_jar'));
    }
    
    return;
}

# return a 2 element array modeling the first PSGI redirect values: status code and arrayref of header pairs
sub _send_psgi_headersXX {
	my $self = shift;
	my $q    = $self->query;
	my $type = $self->header_type;

        # Log4perl logger erzeugen
        my $logger = get_logger();

        if ($logger->is_debug){
            $logger->debug("Query-Object: ".ref($q));
            $logger->debug("Type: $type - ".YAML::Dump($self->header_props));
        }
        
    return
        $type eq 'redirect' ? $q->psgi_redirect( $self->header_props )
      : $type eq 'header'   ? $q->psgi_header  ( $self->header_props )
      : $type eq 'none'     ? ''
      : $logger->error( "Invalid header_type '$type'");

}

# Umdefinition von SUPER::run, damit diese Methode um Code-Refs fuer PSGI erweitert wird
# vgl. https://github.com/markstos/CGI--Application/blob/master/lib/CGI/Application.pm#L201

sub run {
    my $self = shift;
    my $q = $self->query();
    
    my $rm_param = $self->mode_param();
    
    my $rm = $self->__get_runmode($rm_param);
    
    # Set get_current_runmode() for access by user later
    $self->{__CURRENT_RUNMODE} = $rm;
    
    # Allow prerun_mode to be changed
    delete($self->{__PRERUN_MODE_LOCKED});
    
    # Call PRE-RUN hook, now that we know the run mode
    # This hook can be used to provide run mode specific behaviors
    # before the run mode actually runs.
    $self->call_hook('prerun', $rm);
    
    # Lock prerun_mode from being changed after cgiapp_prerun()
    $self->{__PRERUN_MODE_LOCKED} = 1;
    
    # If prerun_mode has been set, use it!
    my $prerun_mode = $self->prerun_mode();
    if (length($prerun_mode)) {
        $rm = $prerun_mode;
        $self->{__CURRENT_RUNMODE} = $rm;
    }
    
    # Process run mode!
    my $body = $self->__get_body($rm);
    
    # Support scalar-ref for body return
    $body = $$body if ref $body eq 'SCALAR';
    
    # Call cgiapp_postrun() hook
    $self->call_hook('postrun', \$body);
    
    my $return_value;
    if ($self->{__IS_PSGI}) {
        my ($status, $headers) = $self->send_psgi_headers();
        
        if (ref($body) eq 'GLOB' || (Scalar::Util::blessed($body) && $body->can('getline'))) {
            # body a file handle - return it
            $return_value = [ $status, $headers, $body];
        }
        elsif (ref($body) eq 'CODE') {
            
            # body is a subref, or an explicit callback method is set
            $return_value = $body;
        }
        else {
            
            $return_value = [ $status, $headers, [ $body ]];
        }
    }
    else {
        # Set up HTTP headers non-PSGI responses
        my $headers = $self->_send_headers();
        
        # Build up total output
        $return_value  = $headers.$body;
        print $return_value unless $ENV{CGI_APP_RETURN_ONLY};
    }
    
    # clean up operations
    $self->call_hook('teardown');
    
    return $return_value;
}

sub send_psgi_headers {
    my $self = shift;

    return $self->_send_psgi_headers();
}

sub teardown {
    my $self = shift;

    my $config = OpenBib::Config->new;
    
    $config->disconnectDB;
    
    return;
}

1;
