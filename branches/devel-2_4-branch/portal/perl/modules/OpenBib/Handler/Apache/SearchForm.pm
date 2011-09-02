#####################################################################
#
#  OpenBib::Handler::Apache::SearchForm
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

package OpenBib::Handler::Apache::SearchForm;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Storable ();
use Template;
use YAML;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use Apache2::Cookie;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::Statistics;
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
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $type           = $self->strip_suffix($self->param('type'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my @databases  = ($query->param('db'))?$query->param('db'):();
    my $queryid     = $query->param('queryid') || '';

    
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $statistics  = new OpenBib::Statistics();

    if ($type eq "recent"){
        $type = $session->get_mask();
    }    
    else {
        $session->set_mask($type);
    }

    $logger->debug("Got Type: $type");
    
    my $fieldchoice_ref = $config->{default_fieldchoice};
  
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
        $fieldchoice_ref = $user->get_fieldchoice();
    
        $spelling_suggestion_ref = $user->get_spelling_suggestion();
        $livesearch_ref          = $user->get_livesearch();

        foreach my $profile_ref ($user->get_all_profiles()){
            my @profiledbs = $user->get_profiledbs_of_profileid($profile_ref->{profilid});
            $userprofile_ref->{$profile_ref->{profilid}} = {
                name      => $profile_ref->{profilename},
                databases => \@profiledbs,
            };
        }
    }    

    my $searchquery = OpenBib::SearchQuery->instance;

    if ($queryid) {
        $searchquery->load({sessionID => $session->{ID}, queryid => $queryid});
    }
    else {
        $searchquery->set_from_apache_request($r);
    }
    
    my $viewdesc      = $config->get_viewdesc_from_viewname($view);

    # Erzeugung der database-Input Tags fuer die suche
    my $dbinputtags = "";
    my $dbchoice_ref = [];
    foreach my $dbname ($session->get_dbchoice()){
        push @$dbchoice_ref, $dbname;
    }

    my $alldbs     = $config->get_number_of_dbs($config->get_profilename_of_view($view));
    my $alldbcount = $config->get_number_of_titles({ profile => $config->get_profilename_of_view($view)});

    my @queries    = $session->get_all_searchqueries();

    my $anzahl     = $#queries;
    
    # Ausgewaehlte Datenbanken bestimmen
    my $checkeddb_ref = {};
    foreach my $dbname ($session->get_dbchoice()){
        $checkeddb_ref->{$dbname}=1;
    }
    
    my $maxcolumn = 1;
    my @catdb     = $config->get_infomatrix_of_active_databases({session => $session, checkeddb_ref => $checkeddb_ref, maxcolumn => $maxcolumn, view => $view});
    my $colspan   = $maxcolumn*3;
    
    # TT-Data erzeugen
    my $ttdata={
        viewdesc      => $viewdesc,
        alldbs        => $alldbs,
        alldbcount    => $alldbcount,
        userprofile   => $userprofile_ref,
        dbchoice      => $dbchoice_ref,
        dbinfo        => $dbinfotable,
        prevprofile   => $prevprofile,

        fieldchoice         => $fieldchoice_ref,
        spelling_suggestion => $spelling_suggestion_ref,
        livesearch          => $livesearch_ref,
        
        searchquery   => $searchquery->get_searchquery,
        qopts         => $queryoptions->get_options,

        anzahl        => $anzahl,
        queries       => \@queries,

        catdb         => \@catdb,
        maxcolumn     => $maxcolumn,
        colspan       => $colspan,
        
        statistics    => $statistics,
    };

    my $templatename = ($type)?"tt_searchform_".$type."_tname":"tt_searchform_tname";
    
    $self->print_page($config->{$templatename},$ttdata);

    return Apache2::Const::OK;
}

1;
