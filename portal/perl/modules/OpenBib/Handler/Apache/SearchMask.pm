#####################################################################
#
#  OpenBib::Handler::Apache::SearchMask
#
#  Dieses File ist (C) 2001-2007 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();

    my $query=Apache::Request->instance($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = new OpenBib::Session({
        sessionID => $query->param('sessionID'),
    });

    my $user      = new OpenBib::User({sessionID => $session->{ID}});
    
    my $useragent=$r->subprocess_env('HTTP_USER_AGENT');
  
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    my @databases = ($query->param('database'))?$query->param('database'):();
    my $singleidn = $query->param('singleidn') || '';
    my $setmask   = $query->param('setmask') || '';
    my $action    = ($query->param('action'))?$query->param('action'):'';

    my $queryoptions_ref
        = $session->get_queryoptions($query);

    $logger->debug(YAML::Dump($queryoptions_ref));
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
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

    # Wurde bereits ein Profil bei einer vorangegangenen Suche ausgewaehlt?
    my $prevprofile=$session->get_profile();

    my $userprofile_ref = {};

    if ($user->{ID}) {
        my $targetresult=$user->{dbh}->prepare("select * from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
        $targetresult->execute($user->{ID}) or $logger->error($DBI::errstr);
    
        my $result=$targetresult->fetchrow_hashref();
    
        $showfs        = decode_utf8($result->{'fs'});
        $showhst       = decode_utf8($result->{'hst'});
        $showverf      = decode_utf8($result->{'verf'});
        $showkor       = decode_utf8($result->{'kor'});
        $showswt       = decode_utf8($result->{'swt'});
        $shownotation  = decode_utf8($result->{'notation'});
        $showisbn      = decode_utf8($result->{'isbn'});
        $showissn      = decode_utf8($result->{'issn'});
        $showsign      = decode_utf8($result->{'sign'});
        $showmart      = decode_utf8($result->{'mart'});
        $showhststring = decode_utf8($result->{'hststring'});
        $showinhalt    = decode_utf8($result->{'inhalt'});
        $showgtquelle  = decode_utf8($result->{'gtquelle'});
        $showejahr     = decode_utf8($result->{'ejahr'});

        $targetresult->finish();

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
    
        $targetresult=$user->{dbh}->prepare("select * from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
        $targetresult->execute($user->{ID}) or $logger->error($DBI::errstr);
    
        $result=$targetresult->fetchrow_hashref();
    
        $targetresult->finish();
    }
  
    my $searchquery_ref
        = OpenBib::Common::Util::get_searchquery($r);
    
    my $queryid       = $query->param('queryid') || '';
  
    my $viewdesc      = $config->get_viewdesc_from_viewname($view);

    if ($setmask) {
        $session->set_mask($setmask);
    }
    else {
        $setmask = $session->get_mask();
    }

    my $hits;
    if ($queryid ne "") {
        my $idnresult=$session->{dbh}->prepare("select query,hits from queries where queryid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($queryid) or $logger->error($DBI::errstr);
    
        my $result=$idnresult->fetchrow_hashref();
        $searchquery_ref = Storable::thaw(pack "H*",$result->{'query'});
        $logger->debug(YAML::Dump($searchquery_ref));
        $hits            = decode_utf8($result->{'hits'});
#        $query=~s/"/&quot;/g;

        $idnresult->finish();
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

    my $alldbs     = $config->get_number_of_dbs();
    my $alldbcount = $config->get_number_of_titles();

    # Ausgabe der vorhandenen queries
    my $idnresult=$session->{dbh}->prepare("select * from queries where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($session->{ID}) or $logger->error($DBI::errstr);
    my $anzahl=$idnresult->rows();

    my @queries=();

    while (my $result=$idnresult->fetchrow_hashref()) {
        push @queries, {
            id          => decode_utf8($result->{queryid}),
            searchquery => Storable::thaw(pack "H*",$result->{query}),
            hits        => decode_utf8($result->{hits}),
        };
    }

    $idnresult->finish();

    # Ausgewaehlte Datenbanken bestimmen
    my $checkeddb_ref = {};
    foreach my $dbname ($session->get_dbchoice()){
        $checkeddb_ref->{$dbname}=1;
    }
    
    my $maxcolumn = 1;
    my @catdb     = $config->get_infomatrix_of_active_databases({session => $session, checkeddb_ref => $checkeddb_ref, maxcolumn => $maxcolumn});
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

        searchquery   => $searchquery_ref,
        qopts         => $queryoptions_ref,

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
        
        config        => $config,
        msg           => $msg,
    };

    my $templatename = ($setmask)?"tt_searchmask_".$setmask."_tname":"tt_searchmask_tname";
    
    OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

    return OK;
}

1;
