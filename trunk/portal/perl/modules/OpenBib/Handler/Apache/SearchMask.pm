#####################################################################
#
#  OpenBib::Handler::Apache::SearchMask
#
#  Dieses File ist (C) 2001-2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::SearchMask;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Storable ();
use Template;
use YAML;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $query  = Apache::Request->instance($r);

    my $statistics  = new OpenBib::Statistics();

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $user      = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $useragent=$r->subprocess_env('HTTP_USER_AGENT');
  
    my $stylesheet = OpenBib::Common::Util::get_css_by_browsertype($r);
  
    my @databases = ($query->param('database'))?$query->param('database'):();
    my $singleidn = $query->param('singleidn') || '';
    my $setmask   = $query->param('setmask') || '';
    my $action    = ($query->param('action'))?$query->param('action'):'';

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return OK;
    }

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    my $showfs        = "1";
    my $showhst       = "1";
    my $showverf      = "1";
    my $showkor       = "1";
    my $showswt       = "1";
    my $shownotation  = "1";
    my $showisbn      = "1";
    my $showissn      = "1";
    my $showsign      = "1";
    my $showmart      = "0";
    my $showhststring = "1";
    my $showinhalt    = "1";
    my $showgtquelle  = "1";
    my $showejahr     = "1";
  
    my $userprofiles  = "";

    my $spelling_suggestion_ref = {
        as_you_type => 0,
        resultlist  => 0,
    };
    
    # Wurde bereits ein Profil bei einer vorangegangenen Suche ausgewaehlt?
    my $prevprofile=$session->get_profile();

    my $userprofile_ref = {};

    if ($user->{ID}) {
        my $fieldchoice_ref = $user->get_fieldchoice();
    
        $showfs        = $fieldchoice_ref->{'fs'};
        $showhst       = $fieldchoice_ref->{'hst'};
        $showverf      = $fieldchoice_ref->{'verf'};
        $showkor       = $fieldchoice_ref->{'kor'};
        $showswt       = $fieldchoice_ref->{'swt'};
        $shownotation  = $fieldchoice_ref->{'notation'};
        $showisbn      = $fieldchoice_ref->{'isbn'};
        $showissn      = $fieldchoice_ref->{'issn'};
        $showsign      = $fieldchoice_ref->{'sign'};
        $showmart      = $fieldchoice_ref->{'mart'};
        $showhststring = $fieldchoice_ref->{'hststring'};
        $showinhalt    = $fieldchoice_ref->{'inhalt'};
        $showgtquelle  = $fieldchoice_ref->{'gtquelle'};
        $showejahr     = $fieldchoice_ref->{'ejahr'};

        $spelling_suggestion_ref = $user->get_spelling_suggestion();

        foreach my $profile_ref ($user->get_all_profiles()){
            my @profiledbs = $user->get_profiledbs_of_profileid($profile_ref->{profilid});
            $userprofile_ref->{$profile_ref->{profilid}} = {
                name      => $profile_ref->{profilename},
                databases => \@profiledbs,
            };

            my $profselected="";
            if ($prevprofile eq "user$profile_ref->{profilid}") {
                $profselected="selected=\"selected\"";
            }

            $userprofiles.="<option value=\"user$profile_ref->{profilid}\" $profselected>- $profile_ref->{profilename}</option>";
        }

        if ($userprofiles){
            $userprofiles="<option value=\"\">Gespeicherte Katalogprofile:</option><option value=\"\">&nbsp;</option>".$userprofiles."<option value=\"\">&nbsp;</option>";
        }
    
    }

    my $queryid     = $query->param('queryid') || '';
    
    my $searchquery = OpenBib::SearchQuery->instance;

    if ($queryid) {
        $searchquery->load({sessionID => $session->{ID}, queryid => $queryid});
    }
    else {
        $searchquery->set_from_apache_request($r);
    }
    
    my $viewdesc      = $config->get_viewdesc_from_viewname($view);

    if ($setmask) {
        $session->set_mask($setmask);
    }
    else {
        $setmask = $session->get_mask();
    }

    # Wenn Datenbanken uebergeben wurden, dann werden diese eingetragen
    if ($#databases >= 0) {
        $session->clear_dbchoice();

        foreach my $thisdb (@databases) {
            $session->set_dbchoice($thisdb);
        }
    }

    # Erzeugung der database-Input Tags fuer die suche
    my $dbinputtags = "";
    my $dbchoice_ref = [];
    foreach my $dbname ($session->get_dbchoice()){
        push @$dbchoice_ref, $dbname;
    }

    my $alldbs     = $config->get_number_of_dbs($config->get_viewinfo($view)->{profilename});
    my $alldbcount = $config->get_number_of_titles($config->get_viewinfo($view)->{profilename});

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
        view          => $view,
        stylesheet    => $stylesheet,
        viewdesc      => $viewdesc,
        sessionID     => $session->{ID},
        alldbs        => $alldbs,
        alldbcount    => $alldbcount,
        userprofile   => $userprofile_ref,
        dbchoice      => $dbchoice_ref,
        prevprofile   => $prevprofile,
        showfs        => $showfs,
        showhst       => $showhst,
        showverf      => $showverf,
        showkor       => $showkor,
        showswt       => $showswt,
        shownotation  => $shownotation,
        showisbn      => $showisbn,
        showissn      => $showissn,
        showsign      => $showsign,
        showmart      => $showmart,
        showhststring => $showhststring,
        showinhalt    => $showinhalt,
        showgtquelle  => $showgtquelle,
        showejahr     => $showejahr,

        spelling_suggestion => $spelling_suggestion_ref,
        
        searchquery   => $searchquery->get_searchquery,
        qopts         => $queryoptions->get_options,

        iso2utf      => sub {
            my $string=shift;
            $string=Encode::encode("iso-8859-1",$string);
            return $string;
        },

        anzahl        => $anzahl,
        queries       => \@queries,
        useragent     => $useragent,

        catdb         => \@catdb,
        maxcolumn     => $maxcolumn,
        colspan       => $colspan,
        
        statistics    => $statistics,
        config        => $config,
        user          => $user,
        msg           => $msg,
    };

    my $templatename = ($setmask)?"tt_searchmask_".$setmask."_tname":"tt_searchmask_tname";
    
    OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

    return OK;
}

1;
