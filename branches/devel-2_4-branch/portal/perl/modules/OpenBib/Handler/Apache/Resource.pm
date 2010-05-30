#####################################################################
#
#  OpenBib::Handler::Apache::Resource.pm
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

package OpenBib::Handler::Apache::Resource;

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
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
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

    # Datenstrukturen
    ######################################################################
    my $is_bibtype_ref = {
        'title'          => 1,
        'person'         => 1,
        'corporatebody'  => 1,
        'subject'        => 1,
        'classification' => 1,
    };
    
    my $content_type_map_ref = {
        "application/rdf+xml" => "rdf+xml",
        "text/rdf+n3"         => "rdf+n3",
    };

    ######################################################################
    
    # Basisipfad entfernen
    my $basepath = $config->{base_loc}."/$view/".$config->{handler}{resource_loc}{name};
    $path=~s/$basepath//;

    $logger->debug("Path: $path without basepath $basepath");
    
    # Service-Parameter aus URI bestimmen
    my $id;
    my $type; # (title,person,corporatebody,subject,classification,tag,litlist)
    my $database;
    my $representation;

    if ($path=~m/^\/(\w+)\/([^\/]+?)\/([^\/]+?)\/([^\/]*)/){
        $type     = $1;
        $database = $2;
        $id       = $3;
        $representation = $4;
    }
    elsif ($path=~m/^\/(\w+)\/([^\/]+)\/([^\/]+)/){
        $type     = $1;
        $database = $2;
        $id       = $3;
        $representation = '';
    }
    else {
        return Apache2::Const::OK;        
    }

    $logger->debug("Type: $type - Database: $database - Key: $id - Representation: $representation");

    # Content-Weiche, wenn Resource-URI direkt angesprochen wird
    if (!$representation){
        my $accept       = $r->headers_in->{Accept} || '';
        my @accept_types = map { (split ";", $_)[0] } split /\*s,\*s/, $accept;
        
        my $information_resource_found = 0;
        foreach my $information_resource_type (keys %{$content_type_map_ref}){            
            if (any { $_ eq $information_resource_type } @accept_types) {
                $r->content_type($information_resource_type);
                my $new_location = $config->{base_loc}."/$view/".$config->{handler}{resource_loc}{name}."/$type/$database/$id/".$content_type_map_ref->{$information_resource_type};
                $logger->debug("Redirecting HTTP_SEE_OTHER to $new_location");
                $r->headers_out->add("Location" => $new_location);
                $information_resource_found = 1;
                $logger->debug("Information Resource Type: $information_resource_type");
            }                                                
        }

        if (!$information_resource_found){
            my $information_resource_type="text/html";
            $r->content_type($information_resource_type);
            $r->headers_out->add("Location" => $config->{base_loc}."/$view/".$config->{handler}{resource_loc}{name}."/$type/$database/$id/html");
            $logger->debug("Information Resource Type: $information_resource_type");
        }

        $logger->debug("Accept: $accept - Types: ".YAML::Dump(\@accept_types));
        return Apache2::Const::HTTP_SEE_OTHER;
    }
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    $logger->debug("Type: $type - Representation: $representation");
    
    #####################################################################
    
    if ($is_bibtype_ref->{$type} && $database && $id ){ # Valider Typ etc.
        $logger->debug("Path: $path - Key: $id - DB: $database - ID: $id");

        #####################################################################
        # Verbindung zur SQL-Datenbank herstellen
        
        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        
        if ($type eq "title") {
            OpenBib::Record::Title->new({database => $database, id => $id})
                  ->load_full_record({dbh => $dbh})->print_to_handler({
                      apachereq          => $r,
                      representation     => $representation
                  });
        }
        elsif ($type eq "person"){
            OpenBib::Record::Person->new({database => $database, id => $id})
                  ->load_full_record({dbh => $dbh})->print_to_handler({
                      apachereq          => $r,
                      representation     => $representation
                  });            
        }
        elsif ($type eq "corporatebody"){
            OpenBib::Record::CorporateBody->new({database => $database, id => $id})
                  ->load_full_record({dbh => $dbh})->print_to_handler({
                      apachereq          => $r,
                      representation     => $representation
                  });
        }
        elsif ($type eq "subject"){
            OpenBib::Record::Subject->new({database => $database, id => $id})
                  ->load_full_record({dbh => $dbh})->print_to_handler({
                      apachereq          => $r,
                      representation     => $representation
                  });
        }
        elsif ($type eq "classification"){
            OpenBib::Record::Classification->new({database => $database, id => $id})
                  ->load_full_record({dbh => $dbh})->print_to_handler({
                      apachereq          => $r,
                      representation     => $representation
                  });
        }        
        
        $dbh->disconnect;
    }

    return Apache2::Const::OK;
}

1;
