####################################################################
#
#  OpenBib::Handler::Apache::ResultLists.pm
#
#  Dieses File ist (C) 2003-2010 Oliver Flimm <flimm@openbib.org>
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
    my $sorttype     = ($query->param('srt'))?$query->param('srt'):"author";
    my $sortall      = ($query->param('sortall'))?$query->param('sortall'):'0';
    my $sortorder    = ($query->param('srto'))?$query->param('srto'):'up';
    my $queryid      = $query->param('queryid')      || '';
    my $offset       = (defined $query->param('offset'))?$query->param('offset'):0;
    ($offset)=$offset=~/^(-?\d+)$/; # offset muss numerisch sein (SQL-Injection)
    my $hitrange     = $query->param('num')          || 50;
    ($hitrange)=$hitrange=~/^(-?\d+)$/; # hitrange muss numerisch sein (SQL-Injection)

    my $database     = $query->param('db')     || '';

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    # Gibt es bereits Rechercheergebnisse?
    if ($session->get_number_of_queries() <= 0) {

        my $loginname="";
        my $password="";
        
        ($loginname,$password)=$user->get_credentials() if ($user->{ID} && $user->get_targettype_of_session($session->{ID}) ne "self");
        
        # Hash im Loginname ersetzen
        $loginname=~s/#/\%23/;

        # TT-Data erzeugen
        my $ttdata={
            loginname      => $loginname,
            password       => $password,
            
            query          => $query,
            
            qopts          => $queryoptions->get_options,
            queryoptions   => $queryoptions,
            
            database       => $database,
            queryid        => $queryid,
            offset         => $offset,
            hitrange       => $hitrange,
        };
        
        $self->print_page($config->{tt_resultlists_empty_tname},$ttdata);

        return Apache2::Const::OK;
    }
    
    my @queryids     = ();
    my @querystrings = ();
    my @queryhits    = ();
    
    my @queries      = $session->get_all_searchqueries;
    
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
            if ($query_ref->get_id eq "$queryid") {
                $thisquery_ref=$query_ref;
            }
        }
    }
    
    my ($resultdbs_ref,$hitcount)=$session->get_db_histogram_of_query(@{$thisquery_ref}{id}) ;
    
    # TT-Data erzeugen
    my $ttdata={
        thisquery  => $thisquery_ref,
        queryid    => $queryid,

        dbinfo     => $dbinfotable,
        qopts      => $queryoptions->get_options,
        queryoptions => $queryoptions,
        
        hitcount   => $hitcount,
        resultdbs  => $resultdbs_ref,
        queries    => \@queries,
    };
    $self->print_page($config->{tt_resultlists_choice_tname},$ttdata);
    
    return Apache2::Const::OK;
}

1;
