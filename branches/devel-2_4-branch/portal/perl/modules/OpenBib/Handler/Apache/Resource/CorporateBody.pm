#####################################################################
#
#  OpenBib::Handler::Apache::Resource::CorporateBody.pm
#
#  Copyright 2009-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Resource::CorporateBody;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Apache2::Reload;
use Apache2::Request;
use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use DBI;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::CorporateBody;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $view=$r->subprocess_env('openbib_view') || $config->{defaultview};
    
    my $uri  = $r->parsed_uri;
    my $path = $uri->path;

    # Basisipfad entfernen
    my $basepath = $config->{base_loc}."/$view/".$config->{handler}{resource_loc}{name};
    $path=~s/$basepath//;
    
    $logger->debug("Path: $path without basepath $basepath");

    # Service-Parameter aus URI bestimmen
    my $id;
    my $database;
    my $representation;

    if ($path=~m/^\/corporatebody\/([^\/]+?)\/([^\/]+?)\/([^\/]*)/){
        $database = $1;
        $id       = $2;
        $representation = $3;
    }
    elsif ($path=~m/^\/corporatebody\/([^\/]+)\/([^\/]+)/){
        $database = $1;
        $id       = $2;
        $representation = '';
    }
    else {
        return Apache2::Const::OK;        
    }


    $logger->debug("Type: corporatebody - Database: $database - Key: $id - Representation: $representation");

    if ($database && $id ){ # Valide Informationen etc.
        $logger->debug("Path: $path - Key: $id - DB: $database - ID: $id");

        #####################################################################
        # Verbindung zur SQL-Datenbank herstellen
        
        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);

        OpenBib::Record::CorporateBody->new({database => $database, id => $id})
              ->load_full_record({dbh => $dbh})->print_to_handler({
                  apachereq          => $r,
                  representation     => $representation
              });
        
        $dbh->disconnect;
    }

    return Apache2::Const::OK;
}

1;
