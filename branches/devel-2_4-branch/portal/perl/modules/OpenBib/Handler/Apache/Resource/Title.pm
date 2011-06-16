#####################################################################
#
#  OpenBib::Handler::Apache::Resource::Title.pm
#
#  Copyright 2009-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Resource::Title;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Record::Title;
use OpenBib::Template::Utilities;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show' => 'show',
        'negotiate_url'          => 'negotiate_url',
        'show_popular_as_html'   => 'show_popular_as_html',
        'show_popular_as_json'   => 'show_popular_as_json',
        'show_popular_as_rdf'    => 'show_popular_as_rdf',
        'show_popular_as_include'=> 'show_popular_as_include',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_popular {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $database       = $self->param('database')       || '';
    my $representation = $self->param('representation') || 'html';
    
    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');    
    
    # CGI Args

    my $statistics  = new OpenBib::Statistics();
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $utils       = new OpenBib::Template::Utilities;

    my $viewdesc      = $config->get_viewdesc_from_viewname($view);
    my $profile       = $config->get_viewinfo->search({ viewname => $view })->single()->profilename;
    
    # TT-Data erzeugen
    my $ttdata={
        representation=> $representation,
        database      => $database,
        profile       => $profile,
        queryoptions  => $queryoptions,
        view          => $view,
        stylesheet    => $stylesheet,
        viewdesc      => $viewdesc,
        sessionID     => $session->{ID},
	session       => $session,
        useragent     => $useragent,
        config        => $config,
        dbinfo        => $dbinfotable,
        statistics    => $statistics,
        utils         => $utils,
        user          => $user,
        msg           => $msg,
        to_json       => sub {
            my $ref = shift;
            return encode_json $ref;
        },
    };

    my $templatename = "tt_resource_title_popular".(($database)?'_by_database':'')."_tname";
    OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

    return Apache2::Const::OK;
}

sub show {
    my $self = shift;
    my $r    = $self->param('r');

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->param('titleid');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');    

    # Mit Suffix, dann keine Aushandlung des Typs
    
    my $representation = "";
    my $content_type   = "";
    
    my $id             = "";
    if ($titleid=~/^(.+?)(\.html|\.json|\.rdf|\.include)$/){
        $id            = $1;
        ($representation) = $2 =~/^\.(.+?)$/;
        $content_type   = $self->param('config')->{'content_type_map_rev'}{$representation};
    }
    # Sonst Aushandlung
    else {
        $id = $titleid;
        my $negotiated_type_ref = $self->negotiate_type;

        my $new_location = "$self->param('path_prefix')/$config->{resource_title_loc}/$database/$id.$negotiated_type_ref->{suffix}";

        $self->query->method('GET');
        $self->query->content_type($negotiated_type_ref->{content_type});
        $self->query->headers_out->add(Location => $new_location);
        $self->query->status(Apache2::Const::REDIRECT);
        
        $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $new_location");

        return;
    }
    
    if ($database && $id ){ # Valide Informationen etc.
        $logger->debug("Key: $id - DB: $database - ID: $id");
        
        OpenBib::Record::Title->new({database => $database, id => $id})
              ->load_full_record->print_to_handler({
                  apachereq          => $r,
                  representation     => $representation,
                  content_type       => $content_type,
                  view               => $view,
              });
    }

    return Apache2::Const::OK;
}

1;
