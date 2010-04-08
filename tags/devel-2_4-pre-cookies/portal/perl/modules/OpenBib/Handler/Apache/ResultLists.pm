####################################################################
#
#  OpenBib::Handler::Apache::ResultLists.pm
#
#  Dieses File ist (C) 2003-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::ResultLists;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable ();
use Template;
use YAML();

use OpenBib::Common::Stopwords;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::SearchQuery;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

#     my $status=$query->parse;

#     if ($status) {
#         $logger->error("Cannot parse Arguments");
#     }

    my $session    = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $user       = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet = OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Input auslesen
  
    my $sorttype     = ($query->param('sorttype'))?$query->param('sorttype'):"author";
    my $sortall      = ($query->param('sortall'))?$query->param('sortall'):'0';
    my $sortorder    = ($query->param('sortorder'))?$query->param('sortorder'):'up';
    my $autoplus     = $query->param('autoplus')     || '';
    my $combinedbs   = $query->param('combinedbs')   || 0;
    my $queryid      = $query->param('queryid')      || '';
    my $offset       = (defined $query->param('offset'))?$query->param('offset'):0;
    ($offset)=$offset=~/^(-?\d+)$/; # offset muss numerisch sein (SQL-Injection)
    my $hitrange     = $query->param('hitrange')     || 50;
    ($hitrange)=$hitrange=~/^(-?\d+)$/; # hitrange muss numerisch sein (SQL-Injection)

    my $database     = $query->param('database')     || '';
    my $sb           = $query->param('sb')           || 'sql';
    my $action       = $query->param('action')       || '';

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
  
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    # Gibt es bereits Rechercheergebnisse?
    if ($session->get_number_of_items_in_resultlist() <= 0) {

        my $loginname="";
        my $password="";
        
        ($loginname,$password)=$user->get_credentials() if ($user->{ID} && $user->get_targettype_of_session($session->{ID}) ne "self");
        
        # Hash im Loginname ersetzen
        $loginname=~s/#/\%23/;

        # TT-Data erzeugen
        my $ttdata={
            view           => $view,
            stylesheet     => $stylesheet,
            sessionID      => $session->{ID},

            loginname      => $loginname,
            password       => $password,
            
            query          => $query,
            
            qopts          => $queryoptions->get_options,
            database       => $database,
            queryid        => $queryid,
            offset         => $offset,
            hitrange       => $hitrange,
            config         => $config,
            user           => $user,
            msg            => $msg,
        };
        
        OpenBib::Common::Util::print_page($config->{tt_resultlists_empty_tname},$ttdata,$r);

        return Apache2::Const::OK;
    }
    
    # BEGIN Weitere Treffer holen und cachen
    #
    ####################################################################

    if ($action eq "choice"){
        my @queryids     = ();
        my @querystrings = ();
        my @queryhits    = ();
        
        my @queries      = $session->get_all_searchqueries({
            offset => '0',
        });
        
        # Finde den aktuellen Query
        my $thisquery_ref={};
        
        # Wenn keine Queryid angegeben wurde, dann nehme den ersten Eintrag,
        # da dieser der aktuellste ist
        if ($queryid eq "") {
            $thisquery_ref=$queries[0];
        }
        # ansonsten nehmen den ausgewaehlten
        else {
            foreach my $query_ref (@queries) {
                if (@{$query_ref}{id} eq "$queryid") {
                    $thisquery_ref=$query_ref;
                }
            }
        }

        my ($resultdbs_ref,$hitcount)=$session->get_db_histogram_of_query(@{$thisquery_ref}{id}) ;
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            
            
            thisquery  => $thisquery_ref,
            queryid    => $queryid,
            
            qopts      => $queryoptions->get_options,
            hitcount   => $hitcount,
            resultdbs  => $resultdbs_ref,
            queries    => \@queries,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
        OpenBib::Common::Util::print_page($config->{tt_resultlists_choice_tname},$ttdata,$r);
        
        return Apache2::Const::OK;
    }

    ####################################################################
    # ENDE Trefferliste
    #

    OpenBib::Common::Util::print_warning($msg->maketext("Unerlaubte Aktion"),$r,$msg);

    return Apache2::Const::OK;
}

1;
