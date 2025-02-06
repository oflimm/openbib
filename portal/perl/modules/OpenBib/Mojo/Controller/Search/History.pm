####################################################################
#
#  OpenBib::Mojo::Controller::Search::History.pm
#
#  Dieses File ist (C) 2003-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Search::History;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

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
use OpenBib::Session;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
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
    my $sorttype     = ($r->param('srt'))?$r->param('srt'):"person";
    my $sortall      = ($r->param('sortall'))?$r->param('sortall'):'0';
    my $sortorder    = ($r->param('srto'))?$r->param('srto'):'asc';
    my $queryid      = $r->param('queryid')      || '';
    my $offset       = (defined $r->param('offset'))?$r->param('offset'):0;
    ($offset)=$offset=~/^(-?\d+)$/; # offset muss numerisch sein (SQL-Injection)
    my $hitrange     = $r->param('num')          || 50;
    ($hitrange)=$hitrange=~/^(-?\d+)$/; # hitrange muss numerisch sein (SQL-Injection)

    my $database     = $r->param('db')     || '';

    my @queryids     = ();
    my @querystrings = ();
    my @queryhits    = ();
    
    my @queries      = $session->get_all_searchqueries;
    
#    my ($resultdbs_ref,$hitcount)=$session->get_db_histogram_of_query(@{$thisquery_ref}{id}) ;
    
    # TT-Data erzeugen
    my $ttdata={
        queryid    => $queryid,

        qopts      => $queryoptions->get_options,
        queryoptions => $queryoptions,
        
#        hitcount   => $hitcount,
#        resultdbs  => $resultdbs_ref,
        queries    => \@queries,
    };
    
    return $self->print_page($config->{tt_search_history_tname},$ttdata);
}

1;
