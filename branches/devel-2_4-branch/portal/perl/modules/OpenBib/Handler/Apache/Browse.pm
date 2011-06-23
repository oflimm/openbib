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
    ## Database: Name der verwendeten SQL-Datenbank
  
    my $database=($query->param('db'))?$query->param('db'):'inst001';
  
    #####################################################################
    ## Sortierung der Titellisten
  
    my $sorttype  = ($query->param('srt'))?$query->param('srt'):"author";
    my $sortorder = ($query->param('srto'))?$query->param('srto'):"up";

    my $benchmark=0;

    #####################################################################
    # Variablen in <FORM>, die den Such-Flu"s steuern
    #####################################################################
  
    #####################################################################
    ## Initialsearch:
  
    my $generalsearch     = $query->param('generalsearch')     || '';
    my $swtindex          = decode_utf8($query->param('swtindex'))          || '';
    my $swtindexall       = $query->param('swtindexall')       || '';

    my $searchtitofcnt    = decode_utf8($query->param('searchtitofcnt'))    || '';

    my $browsecat         = $query->param('browsecat')         || '';
    my $browsecontent     = $query->param('browsecontent')     || '';
    my @category          = ($query->param('category'))?$query->param('category'):();

    my $olws              = $query->param('olws')              || 0;
    my $olws_action       = $query->param('olws_action')       || '';
    my $collection        = $query->param('collection')        || '';

    my $queryid           = $query->param('queryid')           || '';
    my $format            = $query->param('format')            || 'full';

    my $no_log            = $query->param('no_log')            || '';

    # Sub-Template ID
    my $stid              = $query->param('stid')              || '';

    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########
  
    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen
  
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);

    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        $dbh->disconnect();

        return Apache2::Const::OK;
    }

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
                            SOAP::Data->name(category   => $browsecat)->type('string'),
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
                    browsecat     => $browsecat,
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

    
    #####################################################################
    ## Schlagwortindex
  
    if ($swtindex ne "") {
    
        OpenBib::Search::Util::print_index_by_swt({
            swt              => $swtindex,
            dbh              => $dbh,
            database         => $database,
            apachereq        => $r,
            stylesheet       => $stylesheet,
            view             => $view,
            msg              => $msg,
        });
        return Apache2::Const::OK;
    }

    #######################################################################
    # Nachdem initial per SQL nach den Usereingaben eine Treffermenge 
    # gefunden wurde, geht es nun exklusiv in der SQL-DB weiter

    if ($generalsearch) { 
        if ($generalsearch=~/^supertit/) {
            my $recordlist = new OpenBib::RecordList::Title();

            my $supertitidn = $query->param("$generalsearch");
            my $hits        = 0;

            # Zuerst Gesamtzahl bestimmen
            my $reqstring="select count(distinct targetid) as conncount from conn where sourceid=? and sourcetype=1 and targettype=1";
            my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($supertitidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

            my $res=$request->fetchrow_hashref;
            $hits = $res->{conncount};

            my $limits="";
            if ($hitrange > 0){
                $limits="limit $offset,$hitrange";
            }

            # Bestimmung der Titel
            $reqstring="select distinct targetid from conn where sourceid=? and sourcetype=1 and targettype=1 $limits";
            $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($supertitidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

            while (my $res=$request->fetchrow_hashref) {
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{targetid}}));
            }

            $request->finish();
            
            $recordlist->print_to_handler({
                database         => $database,
                sortorder        => $sortorder,
                sorttype         => $sorttype,
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                hits             => $hits,
                offset           => $offset,
                hitrange         => $hitrange,
                msg              => $msg,
            });

            return Apache2::Const::OK;
        }

        if ($generalsearch=~/^subtit/) {
            my $recordlist = new OpenBib::RecordList::Title();

            my $subtitidn=$query->param("$generalsearch");
            my $hits        = 0;

            my $reqstring="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=1";
            my $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($subtitidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);
            
            my $res=$request->fetchrow_hashref;
            $hits = $res->{conncount};

            my $limits="";
            if ($hitrange > 0){
                $limits="limit $offset,$hitrange";
            }
            
            # Bestimmung der Titel
            $reqstring="select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=1 $limits";
            $request=$dbh->prepare($reqstring) or $logger->error($DBI::errstr);
            $request->execute($subtitidn) or $logger->error("Request: $reqstring - ".$DBI::errstr);

            my @titidns=();
            
            while (my $res=$request->fetchrow_hashref) {
                $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{sourceid}}));
            }

            $request->finish();

            $recordlist->print_to_handler({
                database         => $database,
                sortorder        => $sortorder,
                sorttype         => $sorttype,
                apachereq        => $r,
                stylesheet       => $stylesheet,
                view             => $view,
                hits             => $hits,
                offset           => $offset,
                hitrange         => $hitrange,
                msg              => $msg,
            });

            return Apache2::Const::OK;
        }
    }
  

    #######################################################################
    # Titel zu einem gegebenen Kategorie-Inhalt
    # Voraussetzung: Diese Kategorie muss String-Invertiert sein (convert.yml)
    #                Ausnahme: Anreicherung enrich

    # Jetzt ueber Suchmaschine in Search.pm
    #     if ($searchtitofcnt) {
#         my $recordlist = new OpenBib::RecordList::Title();

#         my $hits      = 0;

#         my $searchtitofcntnorm = OpenBib::Common::Util::grundform({
#             content  => $searchtitofcnt,
#         });

#         my $limits="";
#         if ($hitrange > 0){
#             $limits="limit $offset,$hitrange";
#         }

#         $logger->debug("Categories ".YAML::Dump(\@category)." ... ".$#category);
#         if ($#category == 0){
#             my $category = $category[0];
#             my ($type,$thiscategory)=$category=~/^([A-Z])(\d+)/;
            
#             $type =
#                 ($type eq "U")?'user':
#                     ($type eq "E")?'enrich':
#                         ($type eq "P")?'aut':
#                             ($type eq "C")?'kor':
#                                 ($type eq "S")?'swt':
#                                     ($type eq "N")?'notation':'tit';
            
#             my $conn_cat_ref = {
#                 'T0100' => 'aut',
#                 'T0101' => 'aut',
#                 'T0102' => 'aut',
#                 'T0103' => 'aut',
#                 'T0200' => 'kor',
#                 'T0201' => 'kor',
#                 'T0700' => 'notation',
#                 'T0710' => 'swt',
#                 'T0902' => 'swt',
#                 'T0902' => 'swt',
#                 'T0907' => 'swt',
#                 'T0912' => 'swt',
#                 'T0917' => 'swt',
#                 'T0922' => 'swt',
#                 'T0927' => 'swt',
#                 'T0932' => 'swt',
#                 'T0937' => 'swt',
#                 'T0942' => 'swt',
#                 'T0947' => 'swt',
#             };
            
#             if ($type eq "tit" && exists $conn_cat_ref->{$category}){
#                 # Bestimmung der Titel
#                 my $normtable  = $conn_cat_ref->{$category};
#                 my $targettype =
#                     ($normtable eq "aut")?2:
#                     ($normtable eq "kor")?3:
#                     ($normtable eq "swt")?4:
#                     ($normtable eq "notation")?5:1;
                
#                 my $sqlstring="select distinct conn.sourceid as sourceid from ".$normtable."_string as norm, conn where conn.category=? and conn.sourcetype=1 and conn.targettype=? and conn.targetid=norm.id and norm.category=1 and norm.content=?";
#                 my $request=$dbh->prepare($sqlstring) or $logger->error($DBI::errstr);
#                 $request->execute($thiscategory,$targettype,$searchtitofcntnorm);
                
#                 $logger->debug("$thiscategory/$targettype/$searchtitofcntnorm");
#                 while (my $res=$request->fetchrow_hashref){
#                     $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{sourceid}}));
#                 }
                
#                 # Bestimmung der Titelzahl
#                 $request=$dbh->prepare("select count(distinct conn.sourceid) as rowcount from ".$normtable."_string as norm, conn where conn.category=? and conn.sourcetype=1 and conn.targettype=? and conn.targetid=norm.id and norm.category=1 and norm.content=?") or $logger->error($DBI::errstr);
#                 $request->execute($thiscategory,$targettype,$searchtitofcntnorm);
                
#                 my $res=$request->fetchrow_hashref;
#                 $hits=$res->{rowcount};
                
#                 $request->finish();
#             }
#             elsif ($type eq "enrich"){
#                 my $enrichdbh
#                     = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
#                         or $logger->error_die($DBI::errstr);
                
#                 my $sqlstring="select distinct ai.id as id from all_isbn as ai, normdata as n where n.category=? and n.content=? and n.isbn=ai.isbn and ai.dbname=? $limits ";
#                 my $request=$enrichdbh->prepare($sqlstring) or $logger->error($DBI::errstr);
#                 $request->execute($thiscategory,$searchtitofcnt,$database);
                
#                 $logger->debug("Enrich: $sqlstring");
#                 $logger->debug("Enrich: $thiscategory/$type/$searchtitofcnt");
#                 while (my $res=$request->fetchrow_hashref){
#                     $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}}));
#                 }
                
#                 # Bestimmung der Titelzahl
#                 $request=$enrichdbh->prepare("select count(distinct ai.id) as rowcount from all_isbn as ai, normdata as n where n.category=? and n.content=? and n.isbn=ai.isbn and ai.dbname=?") or $logger->error($DBI::errstr);
#                 $request->execute($thiscategory,$searchtitofcnt,$database);
                
#                 my $res=$request->fetchrow_hashref;
#                 $hits=$res->{rowcount};
                
#                 $request->finish();
                
#             }
#             else {
#                 # Bestimmung der Titel
#                 my $request=$dbh->prepare("select distinct id from tit_string where category=? and content=? $limits ") or $logger->error($DBI::errstr);
#                 $request->execute($thiscategory,$searchtitofcntnorm);
                
#                 while (my $res=$request->fetchrow_hashref){
#                     $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}}));
#                 }        
                
#                 # Bestimmung der Titelzahl
#                 $request=$dbh->prepare("select count(distinct id) as rowcount from tit_string where category=? and content=?") or $logger->error($DBI::errstr);
#                 $request->execute($thiscategory,$searchtitofcntnorm);
                
#                 my $res=$request->fetchrow_hashref;
#                 $hits=$res->{rowcount};
                
#                 $request->finish();
#             }
#         }
#         elsif ($#category > 0){
#             my @sql_categories = ();
#             my @this_categories = ();

#             foreach my $category (@category){
#                 push @sql_categories, "category=?";
#                 my ($thiscategory)=$category=~/^T(\d+)/;
#                 push @this_categories, $thiscategory;
#             }

#             my $sql_category_string = "( ".join(" or ",@sql_categories)." ) ";
#             my $sql_statement = "select distinct id from tit_string where $sql_category_string and content=? $limits ";

#             $logger->debug($sql_statement. "Args: ".join(" / ",@this_categories)." / ".$searchtitofcntnorm);
            
#             # Bestimmung der Titel
#             my $request=$dbh->prepare($sql_statement) or $logger->error($DBI::errstr);
#             $request->execute(@this_categories,$searchtitofcntnorm);
            
#             while (my $res=$request->fetchrow_hashref){
#                 $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}}));
#             }        
            
#             # Bestimmung der Titelzahl
#             $request=$dbh->prepare("select count(distinct id) as rowcount from tit_string where $sql_category_string and content=?") or $logger->error($DBI::errstr);
#             $request->execute(@this_categories,$searchtitofcntnorm);
            
#             my $res=$request->fetchrow_hashref;
#             $hits=$res->{rowcount};
            
#             $request->finish();
    
#         }
    
#         $recordlist->print_to_handler({
#             database         => $database,
#             sortorder        => $sortorder,
#             sorttype         => $sorttype,
#             apachereq        => $r,
#             stylesheet       => $stylesheet,
#             template         => 'tt_search_showtitlist_of_cnt_tname',
#             view             => $view,
#             hits             => $hits,
#             offset           => $offset,
#             hitrange         => $hitrange,
#             msg              => $msg,
#         });

#         return Apache2::Const::OK;
#     }

    #######################################################################
    # Browsen ueber alle Inhalte von Kategorien
    # Voraussetzung: Diese Kategorie muss String-Invertiert sein (Config.pm)
    if ($browsecat) {
        my $browselist_ref = [];
        my $hits           = 0;

        my ($type,$thiscategory)=$browsecat=~/^([A-Z])(\d+)/;

        $type =
            ($type eq "P")?'aut':
                ($type eq "C")?'kor':
                    ($type eq "S")?'swt':
                        ($type eq "N")?'notation':'tit';
        
        my $limits="";
        if ($hitrange > 0){
            $limits="limit $offset,$hitrange";
        }

        my $conn_cat_ref = {
            'T0100' => 'aut',
            'T0101' => 'aut',
            'T0102' => 'aut',
            'T0103' => 'aut',
            'T0200' => 'kor',
            'T0201' => 'kor',
            'T0700' => 'notation',
            'T0710' => 'swt',
            'T0902' => 'swt',
            'T0902' => 'swt',
            'T0907' => 'swt',
            'T0912' => 'swt',
            'T0917' => 'swt',
            'T0922' => 'swt',
            'T0927' => 'swt',
            'T0932' => 'swt',
            'T0937' => 'swt',
            'T0942' => 'swt',
            'T0947' => 'swt',
        };

        if ($type eq "tit" && exists $conn_cat_ref->{$browsecat}){
            # Bestimmung der Titel
            my $normtable  = $conn_cat_ref->{$browsecat};
            my $targettype =
                ($normtable eq "aut")?2:
                ($normtable eq "kor")?3:
                ($normtable eq "swt")?4:
                ($normtable eq "notation")?5:1;

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
            browsecat  => $browsecat,
            qopts      => $queryoptions->get_options,
            browselist => $browselist_ref,
            hits       => $hits,
        };
        $self->print_page($config->{"tt_browse_".$type."_tname"},$ttdata);
        return Apache2::Const::OK;
    }

    # Falls bis hierhin noch nicht abgearbeitet, dann wirds wohl nichts mehr geben
    OpenBib::Common::Util::print_info($msg->maketext("Es wurde kein Treffer zu Ihrer Suchanfrage in der Datenbank gefunden"),$r,$msg);
    $logger->error("Unerlaubt das Ende erreicht");
  
    $dbh->disconnect;
    return Apache2::Const::OK;
}

1;
