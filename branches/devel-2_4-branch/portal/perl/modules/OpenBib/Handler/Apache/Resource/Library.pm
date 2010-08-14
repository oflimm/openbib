#####################################################################
#
#  OpenBib::Handler::Apache::Resource::Library.pm
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

package OpenBib::Handler::Apache::Resource::Library;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Apache2::Reload;
use Apache2::Request;
use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use DBI;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';

    my $config = OpenBib::Config->instance;

    my $query       = Apache2::Request->new($r);

    my $session     = OpenBib::Session->instance({ apreq => $r });

    my $user        = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $useragent   = $r->subprocess_env('HTTP_USER_AGENT');
  
    my $stylesheet  = OpenBib::Common::Util::get_css_by_browsertype($r);
    
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $uri  = $r->parsed_uri;
    my $path = $uri->path;

    # Basisipfad entfernen
    my $basepath = $config->{base_loc}."/$view/".$config->{handler}{resource_library_loc}{name};
    $path=~s/$basepath//;
    
    $logger->debug("Path: $path without basepath $basepath");

    # Service-Parameter aus URI bestimmen
    my $id;
    my $representation;

    if ($path=~m/^\/([^\/]+?)\/([^\/]*)/){
        $id = $1;
        $representation = $2;
    }
    elsif ($path=~m/^\/([^\/]+)/){
        $id = $1;
        $representation = '';
    }
    else {
        return Apache2::Const::OK;
    }


    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    $logger->debug("Type: library - Key: $id - Representation: $representation");

    if ( $id ){ # Valide Informationen etc.
        $logger->debug("Path: $path - Key: $id");

        my $libinfo_ref = $config->get_libinfo($id);


        my $ttdata = {
            representation => $representation,
            libinfo        => $libinfo_ref,
            
            config         => $config,
            dbinfo         => $dbinfotable,
            
            user           => $user,
            msg            => $msg,

        };

        
        my $templatename = "tt_resource_library_tname";

        OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

    }

    return Apache2::Const::OK;
}

1;
