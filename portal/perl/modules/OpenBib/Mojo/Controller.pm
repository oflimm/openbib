#####################################################################
#
#  OpenBib::Mojo::Controller
#
#  Dieses File ist (C) 2010-2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

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

use Mojo::Base 'Mojolicious::Controller', -signatures, -async_await;

sub set_paging {
    my $self = shift;

    my $r            = $self->stash('r');
    my $queryoptions = $self->stash('qopts');
    my $config       = $self->stash('config');
    
    my $page = $r->param('page') || 1;

    my $num    = $queryoptions->get_option('num') || $config->{queryoptions}{num}{value};
    my $offset = $page*$num-$num;

    $self->stash('num',$num);
    $self->stash('offset',$offset);
    $self->stash('page',$page);

    return;
}



sub personalize_uri {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r = $self->stash('r');
    
    # Personalisierte URIs
    if ($self->stash('users_loc')){
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



sub is_authenticated {
    my $self   = shift;
    my $role   = shift || '';
    my $userid = shift || '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $r              = $self->stash('r');
    my $path_prefix    = $self->stash('path_prefix');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $path           = $self->stash('path');
    my $servername     = $self->stash('servername');
    my $msg            = $self->stash('msg');

    $logger->debug("Args: Role: $role UserID: $userid");
    $logger->debug("Session-UserID: ".$user->{ID}) if (defined $user->{ID});
    
#     if (! $user->{ID} && $self->stash('represenation') eq "html"){
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
    my $returnurl = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->stash('config');
    
    my $ttdata = {
        err_nr    => $warningnr,
        err_msg   => $warning,
	returnurl => $returnurl,
    };

    $ttdata = $self->add_default_ttdata($ttdata);
    
    return $self->print_page($config->{tt_error_tname},$ttdata);
}

sub print_info {
    my $self = shift;
    my $info   = shift;
    my $infonr = shift || 1;
    my $returnurl = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->stash('config');

    my $ttdata = {
        info_msg  => $info,
        info_nr   => $infonr,
	returnurl => $returnurl,
    };

    return $self->print_page($config->{tt_info_message_tname},$ttdata);
}

sub print_json {
    my $self      = shift;
    my $json_ref  = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');

    # Dann Ausgabe des neuen Headers
    $self->res->headers->content_type('application/json');

    #if ($logger->is_debug()){
    #    $logger->debug(YAML::Dump($json_ref))
    #}

    return encode_json($json_ref);
}

sub print_page {
    my ($self,$templatename,$ttdata)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->stash('view')           || '';
    
    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $servername     = $self->stash('servername');
    my $path_prefix    = $self->stash('path_prefix');
    my $path           = $self->stash('path');
    my $representation = $self->stash('representation') || 'html';
    my $status         = $self->stash('status') || 200;
    my $content_type   = $self->stash('content_type') || $ttdata->{'content_type'} || $config->{'content_type_map_rev'}{$representation} || 'text/html';
    my $location       = $self->stash('location');
    my $url            = $self->stash('url');

    $logger->debug("Entering print_page with template $templatename and representation $representation");

    $logger->debug("Config: ".(ref $config));

    if (!$config->view_is_active($view)){
	$logger->error("View $view doesn't exist");	
	$self->res->code(404); # Not found
        return;
    }
    
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
    
    # Location- und Content-Location-Header setzen    
   # $self->header_type('header');
    $self->res->code($status) if ($status);
    $self->res->headers->content_type($content_type) if ($content_type);
    $self->header_add('Content-Location' => $location) if ($location);


    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time until stage 2 is ".timestr($timeall));
    }

    my $content = "";

    $ttdata->{representation} = $representation;
    
    eval {
        my $template = Template->new({ 
            LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                INCLUDE_PATH   => $config->{tt_include_path},
                ABSOLUTE       => 1,
                STAT_TTL => 120,  # two minutes
		COMPILE_DIR => '/tmp/ttc',
            }) ],
            STAT_TTL => 120,  # two minutes
	    COMPILE_DIR => '/tmp/ttc',
            OUTPUT         => \$content,    # Output geht in Scalar-Ref
            RECURSION      => 1,
        });
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time until stage 1 is ".timestr($timeall));
        }
        
        $template->process($templatename, $ttdata) || do {
            $logger->fatal($template->error()." url: $url");
            return "Fehler";
        };
    };

    if ($@){
        $logger->fatal($@." url: $url");
    }
    
    $self->render(text => $content);

    $logger->debug("Template processed with content $content");
}

sub add_default_ttdata {
    my ($self,$ttdata) = @_; 

    my $r              = $self->stash('r');
    my $view           = $self->stash('view');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $statistics     = $self->stash('statistics');
    my $msg            = $self->stash('msg');
    my $lang           = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $browser        = $self->stash('browser');
    my $servername     = $self->stash('servername');
    my $dbinfo         = $self->stash('dbinfo');
    my $locinfo        = $self->stash('locinfo');
    my $path_prefix    = $self->stash('path_prefix');
    my $path           = $self->stash('path');
    my $url            = $self->stash('url');
    my $location       = $self->stash('location');
    my $scheme         = $self->stash('scheme');
    my $remote_ip      = $self->stash('remote_ip');
    my $representation = $self->stash('representation') || 'html';
    my $content_type   = $self->stash('content_type') || $ttdata->{'content_type'} || $config->{'content_type_map_rev'}{$representation} || 'text/html';
    
    my $query          = $r->params->to_hash;
    my $container      = OpenBib::Container->instance;
    
    # View- und Datenbank-spezifisches Templating
    my $database  = $ttdata->{'database'};
    my $sessionID = $session->{ID};
    
    my $sysprofile= $config->get_profilename_of_view($view);

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
        my $csv = Text::CSV_PP->new ({
            'binary'       => 1, # potential newlines inside fields
            'always_quote' => 1,
	    'sep_char'     => ';',
	    'quote_char'   => '"',
            'eol'          => "\n",
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
    $ttdata->{'statistics'}     = $statistics;
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
    $ttdata->{'browser'}        = $browser;
    $ttdata->{'cgiapp'}         = $self;
    $ttdata->{'container'}      = $container;
    $ttdata->{'remote_ip'}      = $remote_ip;
    
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

    $ttdata->{'escape_html'}     = sub {
        my $string = shift;
        return ($string)?escape_html(decode_utf8(uri_unescape($string))):'';
    };

    $ttdata->{'uri_escape'}     = sub {
        my $string = shift;
        return uri_escape_utf8($string);
    };

    $ttdata->{'uri_unescape'}     = sub {
        my $string = shift;
        return uri_unescape($string);
    };

    $ttdata->{'encode_id'}     = sub {
        my $string = shift;
        return $self->encode_id($string);
    };

    $ttdata->{'decode_id'}     = sub {
        my $string = shift;
        return $self->decode_id($string);
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

    $ttdata->{'snipper'}    = sub {
        my ($arg_ref) = @_;
        return Search::Tools->snipper(%$arg_ref);
    };

    $ttdata->{'create_title_record'}    = sub {
        my ($arg_ref) = @_;
        return OpenBib::Record::Title->new($arg_ref);
    };

    $ttdata->{'create_title_recordlist'}    = sub {
        my ($arg_ref) = @_;
        return OpenBib::RecordList::Title->new($arg_ref);
    };

    foreach my $key (keys %$ttdata){
	$self->stash($key,$ttdata->{$key});
    }

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
#     my $r              = $self->stash('r');
#     my $config         = $self->stash('config');
#     my $session        = $self->stash('session');
#     my $user           = $self->stash('user');
#     my $msg            = $self->stash('msg');
#     my $lang           = $self->stash('lang');
#     my $queryoptions   = $self->stash('qopts');
#     my $stylesheet     = $self->stash('stylesheet');
#     my $useragent      = $self->stash('useragent');
#     my $servername     = $self->stash('servername');
#     my $path_prefix    = $self->stash('path_prefix');
#     my $path           = $self->stash('path');
#     my $representation = $self->stash('representation');
#     my $content_type   = $self->stash('content_type') || $ttdata->{'content_type'} || $config->{'content_type_map_rev'}{$representation} || 'text/html';
    
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

#     my $hitrange          = $r->param('hitrange') || 50;
#     my $sortorder         = $r->param('srto')     || 'up';
#     my $sorttype          = $r->param('srt')      || 'author';
#     my $offset            = $r->param('offset')   || undef;
    
#     my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;
#     my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;

#     my $searchtitofcnt = decode_utf8($r->param('searchtitofcnt'))    || '';

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
#         if (defined $r->param('olws') && $r->param('olws') eq "Viewer"){            
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
#         foreach my $param ($r->param()) {
#             $logger->debug("Adding Param $param with value ".$r->param($param));
#             push @args, $param."=".$r->param($param) if ($param ne "offset" && $param ne "hitrange");
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

    my $config = $self->stash('config');
    
    my $suffixes = join '|', map { '\.'.$_ } keys %{$config->{content_type_map_rev}};

    # Leerzeichen rueckumwandeln
    $element =~s/%20/ /g;
    
    $logger->debug("Element in: $element");
    $logger->debug("Suffixes: $suffixes");
    
    
    if ($element=~/^(.+?)($suffixes)$/){
	$logger->debug("Element out stripped: $element");
	
        return $1;
    }

    $logger->debug("Element out original: $element");
    
    return $element;
}

sub to_cgi_params {
    my ($self,$arg_ref)=@_;
    
    # Set defaults
    my $exclude_array_ref    = exists $arg_ref->{exclude}
    ? $arg_ref->{exclude}        : [];
    
    my $change_ref           = exists $arg_ref->{change}
    ? $arg_ref->{change}         : {};
    
    # my $valid_param_ref     = exists $arg_ref->{valid}
    # ? arg_ref->{valid}           : {};
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = $self->stash('config');
    
    $logger->debug("Modify Query");
    
    my $exclude_ref = {};
    
    foreach my $param (@{$exclude_array_ref}){
        $exclude_ref->{$param} = 1;
    }

    #if ($logger->is_debug){
    #    $logger->debug("Args".YAML::Dump($arg_ref));
    #}

    # # Empty, than set default params
    # unless (keys %$valid_params_ref){
    # 	# Searchquery
    # 	foreach my $field_ref ($config->get('searchfield')){
    # 	    $valid_params_ref->{$field_ref->{prefix}} = 1;
    # 	    $valid_params_ref->{"f\[".$field_ref->{prefix}."\]"} = 1;
    # 	}
    # 	# QueryO
    # }
    
    my @cgiparams = ();

    my $r            = $self->stash('r');

    if ($r->query_params){
        foreach my $param (@{$r->query_params->names}){
	    unless ($param =~m/^[a-z0-9A-Z_[\]]+$/){
	     	$logger->debug("Rejecting param $param - not valid");
	     	next;
	    }
            # unless (defined $valid_params_ref->{$param} && $valid_params_ref->{$param}){
	    # 	$logger->debug("Rejecting param $param - not valid");
	    # 	next;
	    # }
            $logger->debug("Processing $param");
            if (exists $arg_ref->{change}->{$param}){
		my $value = $arg_ref->{change}->{$param};

		if ($param eq "l"){
		    $value = $self->cleanup_lang($value);
		}
		else {
		    $value = escape_html(decode_utf8(uri_unescape($value)));
		    # Anpassung/Ausnahme " fuer Phrasensuche
		    $value =~s/&quot;/"/g;
		}
		
		push @cgiparams, {
			param => $param,
			val   => $value,
		};
	    }
            elsif (! exists $exclude_ref->{$param}){
                my @values = @{$r->every_param($param)};
                if (@values){
                    foreach my $value (@values){

			if ($param eq "l"){
			    $value = $self->cleanup_lang($value);
			}
			else {
			    $value = escape_html(decode_utf8(uri_unescape($value)));
			    # Anpassung/Ausnahme " fuer Phrasensuche
			    $value =~s/&quot;/"/g;
			}
			
                        push @cgiparams, {
                            param => $param,
                            val   => $value,
                        };
                    }
                }
                else {
		    my $value = $r->param($param);		    
		    
		    if ($param eq "l"){
			$value = $self->cleanup_lang($value);
		    }
		    else {
			$value = escape_html(decode_utf8(uri_unescape($value)));
			# Anpassung/Ausnahme " fuer Phrasensuche
			$value =~s/&quot;/"/g;
		    }

                    push @cgiparams, {
                        param => $param,
                        val => $value,
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
        
    return join('&',@cgiparams);
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
    
    #if ($logger->is_debug){
    #    $logger->debug("Args".YAML::Dump($arg_ref));
    #}

    my @cgiparams = ();

    foreach my $arg_ref ($self->to_cgi_params($arg_ref)){
        push @cgiparams, "<input type=\"hidden\" name=\"$arg_ref->{param}\" value=\"".uri_unescape($arg_ref->{val})."\" />";
#        push @cgiparams, "<input type=\"hidden\" name=\"$arg_ref->{param}\" value=\"".uri_escape_utf8($arg_ref->{val})."\" />";
    }   

    return join("\n",@cgiparams);
}

# Kudos to Stas Bekman: mod_per2 Users's Guide

sub read_json_input {
    my $self = shift;
    
    my $r  = $self->stash('r');
        
    return $r->content;
}

sub parse_valid_input {
    my ($self,$method)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r     = $self->stash('r');

    my $valid_input_params_ref = {};

    if ($method){
	$valid_input_params_ref = $self->$method;
    }
    else {
	$valid_input_params_ref = $self->get_input_definition;
    }
    
    my $input_params_ref = {};

    # JSON Processing
    if ($self->stash('representation') eq "json"){
        my $input_data_ref;
        
        eval {
            $input_data_ref = $r->json || $r->body_params->to_hash;
        };
        
        if ($@){
            $logger->error("Couldn't decode JSON POST-data");
            return { error => 1 };
        }

	if ($logger->is_debug){
	    $logger->debug("JSON Input ".YAML::Dump($input_data_ref));
	}

        foreach my $param (keys %$valid_input_params_ref){
            my $type     = $valid_input_params_ref->{$param}{type};
            my $encoding = $valid_input_params_ref->{$param}{encoding};
            my $default  = $valid_input_params_ref->{$param}{default};

	    if ($type eq "mixed_bag"){
		my $param_prefix = $param;
		
                foreach my $jsonparam (keys %$input_data_ref){
                    if ($jsonparam=~/^${param_prefix}_/){

			my $content = $input_data_ref->{$jsonparam} || $default;
			
			push @{$input_params_ref->{mixed_bag}{$jsonparam}}, $content;
                    }
                }
	    }
	    else {
		$input_params_ref->{$param} = $input_data_ref->{$param} || $default;
	    }
        }    

    }
    # CGI Processing
    else {
        $logger->debug("CGI Input");

        foreach my $param (keys %$valid_input_params_ref){
            my $type      = $valid_input_params_ref->{$param}{type};
            my $encoding  = $valid_input_params_ref->{$param}{encoding};
            my $default   = $valid_input_params_ref->{$param}{default};
	    my $no_escape = (defined $valid_input_params_ref->{$param}{no_escape})?$valid_input_params_ref->{$param}{no_escape}:0;
            
	    if ($type eq "scalar"){
		my $value = ($r->param($param))?decode_utf8($r->param($param)):$default;
		unless ($no_escape){
		    $value = escape_html($value);
		}
		
		$input_params_ref->{$param} = $value;
            }
	    elsif ($type eq "integer"){
		$input_params_ref->{$param} = ($r->param($param) >= 0)?$r->param($param):$default;
            }
            elsif ($type eq "bool"){
                $input_params_ref->{$param} = ($r->param($param))?escape_html($r->param($param)):$default;
            }
            # sonst array
            elsif ($type eq "array") {
                if ($r->every_param($param)){
		    if ($no_escape){
			@{$input_params_ref->{$param}} = @{$r->every_param($param)};
		    }
		    else {
			@{$input_params_ref->{$param}} = map { $_=escape_html($_) } @{$r->every_param($param)};
		    }
                }
                else {
                    $input_params_ref->{$param} = $default;
                }
            }
            elsif ($type eq "fields") {
                my $fields_ref = $default;
                foreach my $qparam ($r->param){
                    if ($qparam=~/^fields_([TXPCSNL])(\d+)_([a-z0-9])?_(\d+)$/){
                        my $prefix   = $1;
                        my $field    = $2;
                        my $subfield = $3;
                        my $mult     = $4;

                        my $content  = ($no_escape)?decode_utf8($r->param($qparam)):escape_html(decode_utf8($r->param($qparam)));

                        $logger->debug("Got $field - $prefix - $subfield - $mult - $content");

                        push @{$fields_ref->{$field}}, {
                            subfield => $subfield,
                            mult     => $mult,
                            content  => $content,
                        } if ($content);
                    }
                }
                $input_params_ref->{$param} = $fields_ref;
            }
	    elsif ($type eq "mixed_bag"){
		my $param_prefix = $param;
		
                foreach my $qparam ($r->param){
                    if ($qparam=~/^${param_prefix}_/){

                        my $content  = ($no_escape)?decode_utf8($r->param($qparam)):escape_html(decode_utf8($r->param($qparam)));
			
			push @{$input_params_ref->{mixed_bag}{$qparam}}, $content;
                    }
                }
	    }
            elsif ($type eq "rights") {
                my $rights_ref     = $default;
                my $rights_tmp_ref = {};
                foreach my $qparam ($r->param){
                    if ($qparam=~/^([a-zA-Z0-9_]+)\|(right_[a-z]+)$/){
                        my $scope    = $1;
                        my $right    = $2;
                        
                        my $content  = escape_html(decode_utf8($r->param($qparam)));
                        
                        $logger->debug("Got $scope - $right - $content");
                        
                        $rights_tmp_ref->{$scope}{$right} = $content;
                    }
                }

                # Reorganize
                foreach my $scope (keys %$rights_tmp_ref){
                    my $thisrights_ref = {
                        scope => $scope,
                        right_create => ($rights_tmp_ref->{$scope}{right_create})?1:0,
                        right_read   => ($rights_tmp_ref->{$scope}{right_read})?1:0,
                        right_update => ($rights_tmp_ref->{$scope}{right_update})?1:0,
                        right_delete => ($rights_tmp_ref->{$scope}{right_delete})?1:0,
                    };

                    push @$rights_ref, $thisrights_ref;
                }
                
                
                $input_params_ref->{$param} = $rights_ref;
            }

        }
    }

    if ($logger->is_debug){
	$logger->debug("Input Params: ".YAML::Dump($input_params_ref));
    }
    
    return $input_params_ref;
}

# Common runmodes 
sub dispatch_to_representation {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Dispatching to representation ".$self->stash('dispatch_url'));

    $self->redirect($self->stash('dispatch_url'),'303');
    
    return;
}

sub show_warning {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $message = $self->stash('warning_message');

    return $self->print_warning($message);
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

    $logger->debug("Redirecting to $url with code $status");
    
#    $self->stash('status',$status);

#     if ($url=~/\?/){
#         my ($base,$query) = split("\\?",$url);
#         my @query_args = ();
#         foreach my ($key,$value) (split("[&;]",$query)){
#             push @query_args, $key."=".uri_escape_utf8($value);
#         }
#         $query = join(";",@query_args);
#         $url = $base."?".$query;
#     }

    $self->res->code($status);
    
    return $self->redirect_to($url);
}

sub print_authorization_error {
    my $self = shift;

    my $r           = $self->stash('r');
    my $scheme      = $self->stash('scheme');
    my $servername  = $self->stash('servername');
    my $location    = $self->stash('location');
    my $path        = $self->stash('path');        
    my $url         = $self->stash('url');            
    my $path_prefix = $self->stash('path_prefix');
    my $config      = $self->stash('config');
    my $view        = $self->stash('view');    
    my $msg         = $self->stash('msg');
    my $args        = $self->to_cgi_querystring;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($self->stash('representation') eq "html"){
        # Aufruf-URL
	
	if ($logger->is_debug){
	    $logger->debug("Tunnelling: path $path - url $url");
	    $logger->debug("Tunnelling to path $path");    	
	    $logger->debug("Tunnelling to path $path_prefix");    	
	    $logger->debug("Tunnelling to base location $location");
	}
	
	# Construct redirect_uri
	
	my $redirect_uri = $scheme."://".$servername.$path;
	
	# Args? Append Method
	if ($args){
	    $redirect_uri.="?".$args;
	}
	
	if ($logger->is_debug){
	    $logger->debug("Redirect-URL is $redirect_uri");
	}
    
	$redirect_uri = uri_escape($redirect_uri);
	
        my $login_url   = "$path_prefix/$config->{login_loc}?redirect_to=$redirect_uri";

        my $ttdata = {
            login_url => $login_url,
        };
        
        return $self->print_page($config->{tt_authorization_error_tname},$ttdata);
        
#        return $self->redirect("$path_prefix/$config->{login_loc}?redirect_to=$return_uri",303);
    }
    else {
        $logger->debug("Authorization error");
        $self->res->code(403); # FORBIDDEN
        return;
    }
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

sub authorization_successful {
    my $self   = shift;

    # On Success 1
    return 1;
}

sub check_http_basic_authentication {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r       = $self->stash('r');
    my $config  = $self->stash('config');
    my $user    = $self->stash('user');
    my $session = $self->stash('session');
    my $view    = $self->param('view');

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

sub tunnel_through_authenticator {
    my ($self,$method,$authenticatorid) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $r           = $self->stash('r');    
    my $config      = $self->stash('config');
    my $view        = $self->param('view');    
    my $location    = $self->stash('location');
    my $scheme      = $self->stash('scheme');
    my $servername  = $self->stash('servername');
    my $path        = $self->stash('path');        
    my $url         = $self->stash('url');            
    my $path_prefix = $self->stash('path_prefix');
    my $args        = $self->to_cgi_querystring;

    if ($logger->is_debug){
	$logger->debug("Tunnelling: path $path - url $url");
	$logger->debug("Tunnelling to path $path");    	
	$logger->debug("Tunnelling to path $path_prefix");    	
	$logger->debug("Tunnelling to base location $location");
    }

    # Construct redirect_uri

    my $redirect_uri = $scheme."://".$servername.$path;
    
    # Args? Append Method
    if ($args){
	$redirect_uri.="?";
        if ($method){
            $redirect_uri.="_method=$method";
        }
	$redirect_uri.=";".$args;

    }
    # Else? Set Method    
    elsif ($method) {
        $redirect_uri.="?_method=$method";
    }

    if ($logger->is_debug){
	$logger->debug("Tunnelling to $redirect_uri");
    }
    
    $redirect_uri = uri_escape($redirect_uri);
    
    my $new_location = "$path_prefix/$config->{login_loc}?authenticatorid=$authenticatorid;redirect_to=$redirect_uri";
    
    return $self->redirect($new_location,303);
}

# de/encode_id corresponds to OpenBib::Record::get_encoded_id, so keep encoding/decoding mechanism in these methods synchronized!

sub decode_id {
    my ($self,$id) = @_;

    return uri_unescape($id);
}

sub encode_id {
    my ($self,$id) = @_;

    return uri_escape_utf8($id);
}


sub check_online_media {
    my ($self,$arg_ref)=@_;
    
    # Set defaults
    my $view     = exists $arg_ref->{view}
        ? $arg_ref->{view}        : undef;
    my $isbn     = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r       = $self->stash('r');
    my $config  = $self->stash('config');

    $logger->debug("Checking online availability of isbn $isbn for view $view");
    
    my $searchprofile = $config->get_searchprofile_of_view($view);
    
    my $searchquery = new OpenBib::SearchQuery();

    my $normalizer = $self->stash('normalizer');
    
    $isbn = $normalizer->normalize({ field => 'T0540', content => $isbn });
    
    $searchquery->set_searchfield('isbn',$isbn,'AND');
    $searchquery->set_filter({ field => 'favail', term => 'online'});
    $searchquery->set_searchprofile($searchprofile);
        
    my $queryoptions = new OpenBib::QueryOptions;
    
    $queryoptions->set_option('num',10);
    $queryoptions->set_option('srt','relevance_asc');    
    $queryoptions->set_option('page',1);
    $queryoptions->set_option('facets','none');
    
    my $search_args_ref = {
	view         => $view,
	searchprofile => $searchprofile,
	searchquery  => $searchquery,
	queryoptions => $queryoptions,
    };
    
    my $searcher = OpenBib::Search::Factory->create_searcher($search_args_ref);

    # Recherche starten
    $searcher->search;
    
    $searchquery->set_hits($searcher->get_resultcount);

    my $recordlist = new OpenBib::RecordList::Title;
    
    if ($searcher->have_results) {
	$recordlist = $searcher->get_records();
    }
    
    return $recordlist;
}


sub ip_from_local_network {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config       = $self->stash('config');
    
    my $remote_ip    = $self->stash('remote_ip');
    
    my $ip_from_local_network = 0;

    my $remote_address;
    
    eval {
	$remote_address = NetAddr::IP->new($remote_ip);
    };
    
    if (!$@){
	my $local_networks_ref = $config->get('local_networks') || [];
	
	foreach my $ip (@$local_networks_ref){
	    $logger->debug("Checking remote ip $remote_ip with allowed ip range $ip");
	    
	    my $address_range;
	    
	    eval {
		$address_range = NetAddr::IP->new($ip);
	    };
	    
	    next if (!$address_range);
	    
	    if ($remote_address->within($address_range)){
		$ip_from_local_network = 1;
		$logger->debug("IP $remote_ip considered in local network $ip");
	    }
	}
    }

    return $ip_from_local_network;
}

sub verify_gpg_data {
    my ($self,$data,$verification_token)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $gpg = new Crypt::GPG;

    $gpg->gpgbin('/usr/bin/gpg'); # The GnuPG executable

    if ($logger->is_debug){
	$logger->debug("Verifying data $data with token $verification_token");
    }
    
    $verification_token = decode_base64($verification_token);

    if ($logger->is_debug){
	$logger->debug("Verifying with decoded token $verification_token");
    }
    
    my ($plaintext, $sig) = $gpg->verify($verification_token, $data);

    if ($logger->is_debug){
	$logger->debug("Verification result: $plaintext with validity ".$sig->validity());
    }

    # Return Crypt::GPG::Signature object with methods validity, time, keyid and trusted
    return $sig;
}

sub header_add {
    my ($self,$header,$value) = @_;
    if ($header =~/status/i){
	$self->res->code($value);
    }
    else {
	$self->res->headers->header($header, $value);
    }
    return;
}

sub query2hashref {
    my $self=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $args_ref = {};
    my @param_names = @{$self->req->query_params->names};
    foreach my $param (@param_names){
        $args_ref->{$param} = $self->req->param($param);
    }

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($args_ref));
    }
    
    return $args_ref;
}

1;
