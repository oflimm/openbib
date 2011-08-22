#####################################################################
#
#  OpenBib::Handler::Apache::Browse.pm
#
#  ehemals Search.pm
#
#  Copyright 1997-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Browse;

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
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::Session;

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
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $category       = $self->strip_suffix($self->param('category'));

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
    #####################################################################
    ## Hitrange: Anzahl gleichzeitig ausgegebener Treffer (Blaettern)
    ##          >0  - gibt die maximale Zahl an
    ##          <=0 - gibt immer alle Treffer aus
  
    my $hitrange=($query->param('num'))?$query->param('num'):-1;
    ($hitrange)=$hitrange=~/^(-?\d+)$/; # hitrange muss numerisch sein (SQL-Injection)
  
    #####################################################################
    ## Offset: Maximale Anzahl ausgegebener Treffer bei Anfangs-Suche
    ##          >0  - hitrange Treffer werden ab dieser Nr. ausgegeben 
  
    my $offset=($query->param('offset'))?$query->param('offset'):0;
    ($offset)=$offset=~/^(-?\d+)$/; # offset muss numerisch sein (SQL-Injection)
  
    #####################################################################
    ## Initialsearch:
  
    my $browsecontent     = $query->param('browsecontent')     || '';

    my $olws              = $query->param('olws')              || 0;
    my $olws_action       = $query->param('olws_action')       || '';
    my $collection        = $query->param('collection')        || '';

    my $no_log            = $query->param('no_log')            || '';

    # Sub-Template ID
    my $stid              = $query->param('stid')              || '';

    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen

    return unless ($database && $category);
    
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);

    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    #####################################################################
    ## Eigentliche Suche (default)

    # Suche ueber OLWS (urn:/Viewer)
    
    if ($olws){
        if (exists $circinfotable->{$database} && exists $circinfotable->{$database}{circcheckurl}){
	    my $poolname=$dbinfotable->{sigel}{
	      $dbinfotable->{dbases}{$database}};
            
            if ($olws_action eq "browse"){

                $logger->debug("Endpoint: ".$circinfotable->{$database}{circcheckurl});
                my $soapresult;
                eval {
                    my $soap = SOAP::Lite
                        -> uri("urn:/Viewer")
                            -> proxy($circinfotable->{$database}{circcheckurl});

                    my $result = $soap->browse(
                        SOAP::Data->name(parameter  =>\SOAP::Data->value(
                            SOAP::Data->name(collection => $collection)->type('string'),
                            SOAP::Data->name(category   => $category)->type('string'),
                            SOAP::Data->name(content    => $browsecontent)->type('string'))));
                    
                    unless ($result->fault) {
                        $soapresult=$result->result;
                    }
                    else {
                        $logger->error("SOAP Viewer Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                    }
                };
                
                if ($@){
                    $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
                }

                $logger->debug("OLWS".YAML::Dump($soapresult));

                # TT-Data erzeugen
                my $ttdata={
                    database    => $database,
                    poolname    => $poolname,
                    qopts       => $queryoptions->get_options,
                    result      => $soapresult,

                    collection    => $collection,
                    browsecontent => $browsecontent,
                    browsecat     => $category,
                };

                $stid=~s/[^0-9]//g;
                my $templatename = ($stid)?"tt_browse_olws_".$stid."_tname":"tt_browse_olws_tname";

                $self->print_page($config->{$templatename},$ttdata);
                return Apache2::Const::OK;
            }
            
            my $soap = SOAP::Lite
                -> uri("urn:/Viewer")
                    -> proxy($circinfotable->{$database}{circcheckurl});

        }
    }

    #######################################################################
    # Browsen ueber alle Inhalte von Kategorien
    # Voraussetzung: Diese Kategorie muss String-Invertiert sein (Config.pm)

    my $browselist_ref = [];
    my $hits           = 0;
    
    my ($type,$thiscategory)=$category=~/^([A-Z])(\d+)/;
    
    $type =
        ($type eq "P")?'person':
            ($type eq "C")?'corporatebody':
                ($type eq "S")?'subject':
                    ($type eq "N")?'classificatio':'title';
    
    my $limits="";
    if ($hitrange > 0){
        $limits="limit $offset,$hitrange";
    }
    
    my $conn_cat_ref = {
        'T0100' => 'person',
        'T0101' => 'person',
        'T0102' => 'person',
        'T0103' => 'person',
        'T0200' => 'corporatebody',
        'T0201' => 'corporatebody',
        'T0700' => 'classificatio',
        'T0710' => 'subject',
        'T0902' => 'subject',
        'T0902' => 'subject',
        'T0907' => 'subject',
        'T0912' => 'subject',
        'T0917' => 'subject',
        'T0922' => 'subject',
        'T0927' => 'subject',
        'T0932' => 'subject',
        'T0937' => 'subject',
        'T0942' => 'subject',
        'T0947' => 'subject',
    };
    
    if ($type eq "title" && exists $conn_cat_ref->{$category}){
        # Bestimmung der Titel
        my $normtable  = $conn_cat_ref->{$category};
        my $targettype =
            ($normtable eq "person")?2:
            ($normtable eq "corporatebody")?3:
            ($normtable eq "subject")?4:
            ($normtable eq "classificatio")?5:1;
        
        my $sqlstring="select distinct norm.content as content from $normtable as norm, conn where conn.category=? and conn.sourcetype=1 and conn.targettype=? and conn.targetid=norm.id and norm.category=1 order by content $limits ";
        my $request=$dbh->prepare($sqlstring) or $logger->error($DBI::errstr);
        $request->execute($thiscategory,$targettype);
        
        $logger->debug("SQL: $sqlstring");
        while (my $res=$request->fetchrow_hashref){
            push @$browselist_ref, decode_utf8($res->{content});
        }
        
        # Bestimmung der Titelzahl
        $request=$dbh->prepare("select count(distinct content) as rowcount from tit where category=?") or $logger->error($DBI::errstr);
        $request->execute($thiscategory);
        
        my $res=$request->fetchrow_hashref;
        $hits=$res->{rowcount};
        
        $request->finish();
    }
    else {
        # Bestimmung der Titel
        my $request=$dbh->prepare("select distinct content from $type where category=? order by content $limits ") or $logger->error($DBI::errstr);
        $request->execute($thiscategory);
        
        while (my $res=$request->fetchrow_hashref){
            push @$browselist_ref, decode_utf8($res->{content});
        }
        
        # Bestimmung der Titelzahl
        $request=$dbh->prepare("select count(distinct content) as rowcount from tit where category=?") or $logger->error($DBI::errstr);
        $request->execute($thiscategory);
        
        my $res=$request->fetchrow_hashref;
        $hits=$res->{rowcount};
        
        $request->finish();
    }
    
    # TT-Data erzeugen
    my $ttdata={
        database   => $database,
        category   => $category,
        qopts      => $queryoptions->get_options,
        browselist => $browselist_ref,
        hits       => $hits,
    };
    $self->print_page($config->{"tt_browse_".$type."_tname"},$ttdata);
    return Apache2::Const::OK;
  
    $dbh->disconnect;
    return Apache2::Const::OK;
}

1;
