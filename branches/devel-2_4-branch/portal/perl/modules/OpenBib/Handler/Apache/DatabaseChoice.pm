#####################################################################
#
#  OpenBib::Handler::Apache::DatabaseChoice
#
#  Dieses File ist (C) 2001-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::DatabaseChoice;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::SubRequest ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection_negotiate');
    $self->run_modes(
        'show_collection_negotiate'            => 'show_collection_negotiate',
        'show_collection_as_html'              => 'show_collection_as_html',
        'show_collection_as_json'              => 'show_collection_as_json',
        'show_collection_as_rdf'               => 'show_collection_as_rdf',
        'update_collection'                    => 'update_collection',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';

    my $config  = OpenBib::Config->instance;

    my $negotiated_type_ref = $self->negotiate_type;

    my $new_location = "$config->{base_loc}/$view/$config->{databasechoice_loc}.$negotiated_type_ref->{suffix}";

    $self->query->method('GET');
    $self->query->content_type($negotiated_type_ref->{content_type});
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    $logger->debug("Default Information Resource Type: $negotiated_type_ref->{content_type} - URI: $new_location");

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

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';

    my $config  = OpenBib::Config->instance;
    
    my $query   = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });    

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Uebergabe

    my @databases = ($query->param('db'))?$query->param('db'):();
    my $singleidn = $query->param('singleidn') || '';
    my $action    = ($query->param('action'))?$query->param('action'):'';
    my $do_choose = $query->param('do_choose') || '';
    my $verf      = $query->param('verf')      || '';
    my $hst       = $query->param('hst')       || '';
    my $swt       = $query->param('swt')       || '';
    my $kor       = $query->param('kor')       || '';
    my $sign      = $query->param('sign')      || '';
    my $isbn      = $query->param('isbn')      || '';
    my $issn      = $query->param('issn')      || '';
    my $notation  = $query->param('notation')  || '';
    my $ejahr     = $query->param('ejahr')     || '';
    my $queryid   = $query->param('queryid')   || '';
    my $maxcolumn = $query->param('maxcolumn') || $config->{databasechoice_maxcolumn};
  
    my %checkeddb;

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    my $profile = $config->get_viewinfo($view)->profilename;

    my $idnresult="";
  
    # Ausgewaehlte Datenbanken bestimmen
    my $checkeddb_ref = {};
    foreach my $dbname ($session->get_dbchoice()){
        $checkeddb_ref->{$dbname}=1;
    }

    $logger->debug("Ausgewaehlte Datenbanken".YAML::Dump($checkeddb_ref));
    
    my @catdb     = $config->get_infomatrix_of_active_databases({session => $session, checkeddb_ref => $checkeddb_ref, view => $view });
    
    # TT-Data erzeugen
    my $colspan=$maxcolumn*3;
    
    my $ttdata={
        view       => $view,
        profile    => $profile,
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
        maxcolumn  => $maxcolumn,
        colspan    => $colspan,
        catdb      => \@catdb,
        config     => $config,
        user       => $user,
        msg        => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_databasechoice_tname},$ttdata,$r);
    return Apache2::Const::OK;
}

sub update_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';

    my $config  = OpenBib::Config->instance;
    
    my $query   = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });    

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Uebergabe

    my @databases = ($query->param('db'))?$query->param('db'):();
    my $singleidn = $query->param('singleidn') || '';
    my $action    = ($query->param('action'))?$query->param('action'):'';
    my $do_choose = $query->param('do_choose') || '';
    my $verf      = $query->param('verf')      || '';
    my $hst       = $query->param('hst')       || '';
    my $swt       = $query->param('swt')       || '';
    my $kor       = $query->param('kor')       || '';
    my $sign      = $query->param('sign')      || '';
    my $isbn      = $query->param('isbn')      || '';
    my $issn      = $query->param('issn')      || '';
    my $notation  = $query->param('notation')  || '';
    my $ejahr     = $query->param('ejahr')     || '';
    my $queryid   = $query->param('queryid')   || '';
    my $maxcolumn = $query->param('maxcolumn') || $config->{databasechoice_maxcolumn};
  
    my %checkeddb;

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    my $profile = $config->get_viewinfo($view)->profilename;

    my $idnresult="";
  
    # Zuerst die bestehende Auswahl loeschen
    $session->clear_dbchoice();
    
    # Wenn es eine neue Auswahl gibt, dann wird diese eingetragen
    foreach my $database (@databases) {
        $session->set_dbchoice($database);
    }
    
    # Neue Datenbankauswahl ist voreingestellt
    $session->set_profile('dbauswahl');

    my $new_location = "$config->{base_loc}/$view/$config->{searchform_loc}.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
