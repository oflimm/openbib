#####################################################################
#
#  OpenBib::Search::Z3950::USBK
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Z3950::USBK;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Reload;
use Apache::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Net::Z3950;
use SOAP::Lite;
use Storable;
use YAML ();

use OpenBib::Search::Z3950::USBK::Config;
use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config %z39config);

*config    = \%OpenBib::Config::config;
*z39config = \%OpenBib::Search::Z3950::USBK::Config;

if ($OpenBib::Config::config{benchmark}){
    use Benchmark ':hireswallclock';
}

sub new {
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $mgr = new Net::Z3950::Manager();
    
    $mgr->option(databaseName          => $z39config{databaseName});
    $mgr->option(user                  => $z39config{user});
    $mgr->option(password              => $z39config{password});
    $mgr->option(groupid               => $z39config{groupid});
    $mgr->option(preferredRecordSyntax => $z39config{preferredRecordSyntax});

    my $conn = $mgr->connect($z39config{hostname}, $z39config{port}) or $logger->error_die($!);
    $conn->option(querytype => $z39config{querytype});

}

sub search {
    my ()=@_;

}

sub get_resultlist {
    my ()=@_;
}

sub get_singletitle {
    my ()=@_;
}

1;

