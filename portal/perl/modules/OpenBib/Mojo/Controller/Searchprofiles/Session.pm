#####################################################################
#
#  OpenBib::Mojo::Controller::Searchprofiles::Session
#
#  Dieses File ist (C) 2001-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Searchprofiles::Session;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');    
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');    
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI Args
    my @databases = ($r->param('db'))?$r->param('db'):();
    my $singleidn = $r->param('singleidn') || '';
    my $action    = ($r->param('action'))?$r->param('action'):'';
    my $do_choose = $r->param('do_choose') || '';
    my $verf      = $r->param('verf')      || '';
    my $hst       = $r->param('hst')       || '';
    my $swt       = $r->param('swt')       || '';
    my $kor       = $r->param('kor')       || '';
    my $sign      = $r->param('sign')      || '';
    my $isbn      = $r->param('isbn')      || '';
    my $issn      = $r->param('issn')      || '';
    my $notation  = $r->param('notation')  || '';
    my $ejahr     = $r->param('ejahr')     || '';
    my $queryid   = $r->param('queryid')   || '';
    my $maxcolumn = $r->param('maxcolumn') || $config->{databasechoice_maxcolumn};
  
    my %checkeddb;

    my $profile = $config->get_profilename_of_view($view);

    my $idnresult="";
  
    # Ausgewaehlte Datenbanken bestimmen
    my $checkeddb_ref = {};
    foreach my $dbname (@{$session->get_dbchoice()->{databases}}){
        $checkeddb_ref->{$dbname}=1;
    }

    if ($logger->is_debug){
        $logger->debug("Ausgewaehlte Datenbanken".YAML::Dump($checkeddb_ref));
    }
    
    my @catdb     = $config->get_infomatrix_of_active_databases({session => $session, checkeddb_ref => $checkeddb_ref, view => $view });
    
    # TT-Data erzeugen
    my $colspan=$maxcolumn*3;
    
    my $ttdata={
        profile    => $profile,
        maxcolumn  => $maxcolumn,
        colspan    => $colspan,
        catdb      => \@catdb,
    };
    
    return $self->print_page($config->{tt_searchprofiles_session_tname},$ttdata);
}

sub update_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $lang            = $self->stash('lang');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI Args
    my @databases = ($r->param('db'))?$r->param('db'):();
  
    # Wenn es eine neue Auswahl gibt, dann wird diese eingetragen
    my $profileid = $session->set_dbchoice(\@databases);
    
    # Neue Datenbankauswahl ist voreingestellt
    $session->set_profile($profileid);

    my $new_location = "$path_prefix/$config->{searchforms_loc}/session.html?l=$lang";

    # TODO GET?
    $self->res->headers->content_type('text/html');
    $self->redirect($new_location);

    return;
}

1;
