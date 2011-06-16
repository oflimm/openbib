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

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'CGI::Application';

sub cgiapp_init() {       # overrides
   my $self = shift;

   # Log4perl logger erzeugen
   my $logger = get_logger();

   $logger->debug("Entering cgiapp_init");
   
   my $r          = $self->param('r');

   my $config     = OpenBib::Config->instance;

   my $view       = $self->param('view') || $config->get('defaultview');
   
   my $session    = OpenBib::Session->instance({ apreq => $r , view => $view });
   my $user       = OpenBib::User->instance({sessionID => $session->{ID}});

   my $useragent  = $r->subprocess_env('HTTP_USER_AGENT');
   my $stylesheet = OpenBib::Common::Util::get_css_by_browsertype($r);

   my $queryoptions = OpenBib::QueryOptions->instance($self->query());

   my $path_prefix = $config->get('base_loc');

   if (! $config->strip_view_from_uri($view)){
       $path_prefix = "$path_prefix/$view";
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
   $self->param('path_prefix',$path_prefix);

   $logger->debug("Exit cgiapp_init");
   #   $self->query->charset('UTF-8');  # cause CGI.pm to send a UTF-8 Content-Type header
}

sub negotiate_contenttype {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    
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
    foreach my $information_resource_type (keys %{$self->param('config')->{content_type_map}}){            
        if (any { $_ eq $information_resource_type } @accept_types) {            
            return {
                content_type => $information_resource_type,
                suffix       => $self->param('config')->{content_type_map}->{$information_resource_type},
            };
        }                                                
    }
    
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
    
    my $negotiated_type_ref = $self->negotiate_contenttype;

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


1;
