#####################################################################
#
#  OpenBib::Handler::Apache::Resource.pm
#
#  Copyright 2009 Oliver Flimm <flimm@openbib.org>
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

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request;
use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $uri  = $r->parsed_uri;
    my $path = $uri->path;

    my $query  = Apache2::Request->new($r);

    # Basisipfad entfernen
    my $basepath = $config->{resource_loc};
    $path=~s/$basepath//;

    # Service-Parameter aus URI bestimmen
    my $key;
    my $type;
    my $format;

    if ($path=~m/^\/(\w+)\/(.+)\/(.*)/){
        $type   = $1;
        $key    = $2;
        $format = $3;
    }
    elsif ($path=~m/^\/(\w+)\/(.+)/){
        $type   = $1;
        $key    = $2;
        $format = $3;
    }

    my $is_bibtype_ref = {
        'bib'            => 1,
        'person'         => 1,
        'corporatebody'  => 1,
        'subject'        => 1,
        'classification' => 1,
    };
    
    my ($database,$id)=("","");

    if (!$format){
        $format = "rdf";
    }
    
    my $callback   = $query->param('callback')  || '';
    my $lang       = $query->param('lang')      || 'de';
    my $stid       = $query->param('stid')      || '';

    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    $logger->debug("Type: $type - Format: $format");

    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;
    
    # TT-Data erzeugen
    
    my $ttdata= {
        dbinfo      => $dbinfotable,
        callback    => $callback,
        lang        => $lang,
        format      => $format,
        
        config      => $config,
    };
    
    #####################################################################
        
    my $content_type_map_ref = {
        'rdf'   => "application/rdf+xml",
        'rdfn3' => "text/rdf+n3",
    };
    
    if ($is_bibtype_ref->{$type} ){
        ($database,$id) = split(":",$key);
    
        $logger->debug("Path: $path - Key: $key - DB: $database - ID: $id");
        
        if (!$database){
            return Apache2::Const::OK;
        }

        #####################################################################
        # Verbindung zur SQL-Datenbank herstellen
        
        my $dbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                or $logger->error_die($DBI::errstr);
        

        $ttdata->{database} = $database;
        $ttdata->{id}       = $id;
        
        if ($type eq "bib") {
            my $record = OpenBib::Record::Title->new({database => $database, id => $id})
                ->load_full_record({dbh => $dbh});
            
            $ttdata->{record} = $record;
            
        }
        elsif ($type eq "person"){
            my $record = OpenBib::Record::Person->new({database => $database, id => $id})
                ->load_full_record({dbh => $dbh});
            
            $ttdata->{record} = $record;

            my $recordlist = new OpenBib::RecordList::Title();

            # Bestimmung der Titel
            my $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=2 ") or $logger->error($DBI::errstr);
            $request->execute($id);
            
            while (my $res=$request->fetchrow_hashref){
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{sourceid}}));
            }
            $request->finish();

            $ttdata->{title_records} = $recordlist;

        }
        elsif ($type eq "corporatebody"){
            my $record = OpenBib::Record::CorporateBody->new({database => $database, id => $id})
                ->load_full_record({dbh => $dbh});
            
            $ttdata->{record} = $record;
        }
        elsif ($type eq "subject"){
            my $record = OpenBib::Record::Subject->new({database => $database, id => $id})
                ->load_full_record({dbh => $dbh});
            
            $ttdata->{record} = $record;

            my $recordlist = new OpenBib::RecordList::Title();

            # Bestimmung der Titel
            my $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=4 ") or $logger->error($DBI::errstr);
            $request->execute($id);
            
            while (my $res=$request->fetchrow_hashref){
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{sourceid}}));
            }
            $request->finish();

            $ttdata->{title_records} = $recordlist;

        }
        elsif ($type eq "classification"){
            my $record = OpenBib::Record::Classification->new({database => $database, id => $id})
                ->load_full_record({dbh => $dbh});
            
            $ttdata->{record} = $record;
        }
        
        
        $dbh->disconnect;
    }
    elsif ($type eq "library"){
        $ttdata->{id}       = $key;
    }

    $stid=~s/[^0-9]//g;
    
    my $templatename = ($stid)?"tt_resource_".$type."_".$stid."_tname":"tt_resource_".$type."_tname";
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $database,
        templatename => $templatename,
    });
    
    $logger->debug("Using database specific Template $templatename");
    
    my $template = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        OUTPUT         => $r,    # Output geht direkt an Apache Request
        RECURSION      => 1,
    });
    
    # Dann Ausgabe des neuen Headers
    my $content_type = (exists $content_type_map_ref->{$format})?$content_type_map_ref->{$format}:"text/html";
    
    $r->content_type($content_type);
    
    $template->process($config->{$templatename}, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
    };
    
    return Apache2::Const::OK;
}

1;
