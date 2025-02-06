#####################################################################
#
#  OpenBib::Mojo::Controller::SearchForms
#
#  Dieses File ist (C) 2001-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::SearchForms;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Storable ();
use Template;
use YAML::Syck;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')                      || '';
    my $type           = $self->strip_suffix($self->param('type')) || 'simple';

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
    my @databases  = ($r->param('db'))?$r->param('db'):();
    my $queryid     = $r->param('queryid') || '';

    
    my $statistics  = new OpenBib::Statistics();

    # Save Type in Session
    $session->set_mask($type);

    $logger->debug("Set type to session: $type");
    
    my $searchfields_ref = $config->{default_searchfields};
  
    my $spelling_suggestion_ref = {
        as_you_type => 0,
        resultlist  => 0,
    };

    my $livesearch_ref = {
        freesearch => 0,
        person     => 0,
        subject    => 0,
        exact      => 1,
    };

    # Wurde bereits ein Profil bei einer vorangegangenen Suche ausgewaehlt?
    my $prevprofile=$session->get_profile();

    my $userprofile_ref = {};

    if ($user->{ID}) {
        $searchfields_ref = $user->get_searchfields();
    
        $spelling_suggestion_ref = $user->get_spelling_suggestion();
        $livesearch_ref          = $user->get_livesearch();

        foreach my $profile_ref ($user->get_all_profiles()){
            my @profiledbs = $user->get_profiledbs_of_usersearchprofileid($profile_ref->{profileid});
            $userprofile_ref->{$profile_ref->{searchprofileid}} = {
                name      => $profile_ref->{profilename},
                databases => \@profiledbs,
            };
        }
    }    

    my $searchquery = OpenBib::SearchQuery->new({r => $r, view => $view, session => $session});

    if ($queryid) {
        $searchquery->load({sid => $session->{sid}, queryid => $queryid});
    }
    
    my $viewdesc      = $config->get_viewdesc_from_viewname($view);

    # Erzeugung der database-Input Tags fuer die suche
    my $dbinputtags = "";
    my $dbchoice_ref = $session->get_dbchoice();

    my $alldbs     = $config->get_number_of_dbs($config->get_profilename_of_view($view));
    my $alldbcount = $config->get_number_of_titles({ profile => $config->get_profilename_of_view($view)});

    $logger->debug("Mark 2");

#    my @queries    = $session->get_all_searchqueries();

    $logger->debug("Mark 3");


#    my $anzahl     = $#queries;
    
    # Ausgewaehlte Datenbanken bestimmen
    my $checkeddb_ref = {};
    foreach my $dbname ($session->get_dbchoice()){
        $checkeddb_ref->{$dbname}=1;
    }

    my $maxcolumn = 1;
    my @catdb     = $config->get_infomatrix_of_active_databases({session => $session, checkeddb_ref => $checkeddb_ref, maxcolumn => $maxcolumn, view => $view});
    my $colspan   = $maxcolumn*3;

    $logger->debug("Mark 4");
    # TT-Data erzeugen
    my $ttdata={
        viewdesc      => $viewdesc,
        alldbs        => $alldbs,
        alldbcount    => $alldbcount,
        userprofile   => $userprofile_ref,
        dbchoice      => $dbchoice_ref,
        prevprofile   => $prevprofile,

        available_searchfields => $searchfields_ref,
        spelling_suggestion    => $spelling_suggestion_ref,
        livesearch             => $livesearch_ref,
        
        searchquery   => $searchquery,
        qopts         => $queryoptions->get_options,

        catdb         => \@catdb,
        maxcolumn     => $maxcolumn,
        colspan       => $colspan,
        
        statistics    => $statistics,
    };

    my $templatename = "tt_searchforms_record_".$type."_tname";

    return $self->print_page($config->{$templatename},$ttdata);
}

sub show_session {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Shared Args
    my $session        = $self->stash('session');

    my $type = $session->get_mask();

    $logger->debug("Got Type: $type");
    
    $self->stash('type',$type);

    return $self->show;
}

1;
