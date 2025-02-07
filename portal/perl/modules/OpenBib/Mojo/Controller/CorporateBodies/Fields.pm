#####################################################################
#
#  OpenBib::Mojo::Controller::Titles::Fields.pm
#
#  Register ueber Titelfeld
#
#  Copyright 1997-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::CorporateBodies::Fields;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Data::Pageset;
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Schema::Catalog;
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

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $type           = $self->param('type');
    my $field          = $self->strip_suffix($self->param('field'));

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
    #####################################################################
    ## Hitrange: Anzahl gleichzeitig ausgegebener Treffer (Blaettern)
    ##          >0  - gibt die maximale Zahl an
    ##          <=0 - gibt immer alle Treffer aus
  
    my $hitrange=($r->param('num'))?$r->param('num'):20;
    ($hitrange)=$hitrange=~/^(-?\d+)$/; # hitrange muss numerisch sein (SQL-Injection)

    my $page=($r->param('page'))?$r->param('page'):1;
    ($page)=$page=~/^(-?\d+)$/; # page muss numerisch sein (SQL-Injection)

    #####################################################################
    ## Offset: Maximale Anzahl ausgegebener Treffer bei Anfangs-Suche
    ##          >0  - hitrange Treffer werden ab dieser Nr. ausgegeben 
  
    my $offset=$page*$hitrange-$hitrange;
  
    #####################################################################
    ## Initialsearch:
  
    my $browsecontent     = $r->param('browsecontent')     || '';

    my $olws              = $r->param('olws')              || 0;
    my $olws_action       = $r->param('olws_action')       || '';
    my $collection        = $r->param('collection')        || '';

    my $no_log            = $r->param('no_log')            || '';

    # Sub-Template ID
    my $stid              = $r->param('stid')              || '';

    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen

    return unless ($database && $field);

    my $schema;

    eval {
        # UTF8: {'pg_enable_utf8'    => 1}
        $schema = OpenBib::Schema::Catalog->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},$config->{dboptions}) or $logger->error_die($DBI::errstr);
    };
    
    if ($@){
        $logger->fatal("Unable to connect schema to database $database: DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}");
        next;
    }

    my $circinfotable = OpenBib::Config::CirculationInfoTable->new;
    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->new;

    #####################################################################
    ## Eigentliche Suche (default)

    # Suche ueber OLWS (urn:/Viewer)
    
    if ($olws){
        if (defined $circinfotable->get($database) && defined $circinfotable->get($database)->{circcheckurl}){
	    my $poolname=$dbinfotable->get('sigel')->{
	      $dbinfotable->get('dbases')->{$database}};
            
            if ($olws_action eq "browse"){

                $logger->debug("Endpoint: ".$circinfotable->get($database)->{circcheckurl});
                my $soapresult;
                eval {
                    my $soap = SOAP::Lite
                        -> uri("urn:/Viewer")
                            -> proxy($circinfotable->get($database)->{circcheckurl});

                    my $result = $soap->browse(
                        SOAP::Data->name(parameter  =>\SOAP::Data->value(
                            SOAP::Data->name(collection => $collection)->type('string'),
                            SOAP::Data->name(category   => $field)->type('string'),
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

                if ($logger->is_debug){
                    $logger->debug("OLWS".YAML::Dump($soapresult));
                }

                # TT-Data erzeugen
                my $ttdata={
                    database    => $database,
                    poolname    => $poolname,
                    qopts       => $queryoptions->get_options,
                    result      => $soapresult,

                    collection    => $collection,
                    browsecontent => $browsecontent,
                    browsecat     => $field,
                };

                $stid=~s/[^0-9]//g;
                my $templatename = ($stid)?"tt_indexes_olws_".$stid."_tname":"tt_indexes_olws_tname";

                return $self->print_page($config->{$templatename},$ttdata);
            }
            
            my $soap = SOAP::Lite
                -> uri("urn:/Viewer")
                    -> proxy($circinfotable->get($database)->{circcheckurl});

        }
    }

    #######################################################################
    # Browsen ueber alle Inhalte von Kategorien
    # Voraussetzung: Diese Kategorie muss String-Invertiert sein (Config.pm)

    my $browselist_ref = [];
    my $hits           = 0;
    
    my $conn_field_ref = {
        '0100' => 'person',
        '0101' => 'person',
        '0102' => 'person',
        '0103' => 'person',
        '0200' => 'corporatebody',
        '0201' => 'corporatebody',
        '0700' => 'classification',
        '0710' => 'subject',
        '0902' => 'subject',
        '0902' => 'subject',
        '0907' => 'subject',
        '0912' => 'subject',
        '0917' => 'subject',
        '0922' => 'subject',
        '0927' => 'subject',
        '0932' => 'subject',
        '0937' => 'subject',
        '0942' => 'subject',
        '0947' => 'subject',
    };

    my $contents;

    # Browsen in Titelnormdaten vie verknuepfter anderer Normdaten 
    if ($type eq "title"){
        # Bestimmung der Titel
        my $table= "";

        if (defined $conn_field_ref->{$field}){
            $table = $conn_field_ref->{$field};
        }

        # Wenn verknuepfte Normdatei
        if ($table){
            $logger->debug("Searching title field via connected normdata");

            my %table_type = (
                'person'         => {
                    resultset => 'TitlePerson',
                    field => 'person_fields.field',
                    select => 'person_fields.content',
                    join => ['personid', { 'personid' => 'person_fields' }],
                },
                'corporatebody'  => {
                    resultset => 'TitleCorporatebody',
                    field => 'corporatebody_fields.field',
                    select => 'corporatebody_fields.content',
                    join => ['corporatebodyid', { 'corporatebodyid' => 'corporatebody_fields' }],
                },
                'subject'        => {
                    resultset => 'TitleSubject',
                    field => 'subject_fields.field',
                    select => 'subject_fields.content',
                    join => ['subjectid', { 'subjectid' => 'subject_fields' }],
                },
                'classification' => {
                    resultset => 'TitleClassification',
                    field => 'classification_fields.field',
                    select => 'classification_fields.content',
                    join => ['classificationid', { 'classificationid' => 'classification_fields' }],
                },
                'holding' => {
                    resultset => 'TitleHolding',
                    field => 'holding_fields.field',
                    select => 'holding_fields.content',
                    join => ['holdingid', { 'holdingid' => 'holding_fields' }],
                },
            );

            # DBI: "select distinct norm.content as content from $normtable as norm, conn where conn.field=? and conn.sourcetype=1 and conn.targettype=? and conn.targetid=norm.id and norm.field=1 order by content $limits ";
            $logger->debug("Type $table -> $table_type{$table}{resultset}");
            $contents = $schema->resultset($table_type{$table}{resultset})->search_rs(
                {
                    $table_type{$table}{field} => 800, # Ansetzungsform
                    'me.field' => $field
                },
                {
                    select   => [$table_type{$table}{select}],
                    group_by => $table_type{$table}{select},
                    as       => ['thiscontent'],
                    join     => $table_type{$table}{join},
                }
            );

            $hits = $contents->count;

            $contents = $schema->resultset($table_type{$table}{resultset})->search_rs(
                {
                    $table_type{$table}{field} => 800, # Ansetzungsform
                    'me.field' => $field
                },
                {
                    select   => [$table_type{$table}{select}],
                    group_by => $table_type{$table}{select},
                    order_by => [ { -asc => $table_type{$table}{select} } ],
                    as       => ['thiscontent'],
                    join     => $table_type{$table}{join},
                    rows => $hitrange,
                    offset => $offset,
                }
            );            

        }
        # Sonst direkt in den Titelfeldern
        else {
            $logger->debug("Searching title field directly with hitrange $hitrange / offset $offset");
            
            $contents = $schema->resultset('TitleField')->search_rs(
                {
                    'field'   => $field,
                },
                {
                    select   => ['content'],
                    as       => ['thiscontent'],
                    group_by => ['content'],
                }
            );

            $hits = $contents->count;
            
            $contents = $schema->resultset('TitleField')->search_rs(
                            {
                    'field'   => $field,
                },
                {
                    select   => ['content'],
                    as       => ['thiscontent'],
                    group_by => ['content'],
                    rows     => $hitrange,
                    offset   => $offset,
                }
            );

        }
    }
    # Browsen direkt in entsprechenden Normdaten
    else {
        $logger->debug("Searching $type field");
        my %table_type = (
            'title'         => {
                resultset => 'TitleField',
            },
            'person'         => {
                resultset => 'PersonField',
            },
            'corporatebody'  => {
                resultset => 'CorporatebodyField',
            },
            'subject'        => {
                resultset => 'SubjectField',
            },
            'classification' => {
                resultset => 'ClassificationField',
            },
            'holding' => {
                resultset => 'HoldingField',
            },
        );

        $logger->debug("Type $type -> $table_type{$type}{resultset}");
        # DBI: "select distinct content from $type where field=? order by content $limits 
        $contents = $schema->resultset($table_type{$type}{resultset})->search_rs(
            {
                'field'   => $field,
            },
            {
                select   => ['content'],
                as       => ['thiscontent'],
                group_by => ['content'],
            }
        );

        $hits = $contents->count;

        $contents = $schema->resultset($table_type{$type}{resultset})->search_rs(
            {
                'field'   => $field,
            },
            {
                select   => ['content'],
                as       => ['thiscontent'],
                order_by => [ { -asc => 'content' } ],
                group_by => ['content'],
                rows     => $hitrange,
                offset   => $offset,
            }
        );


    }

    foreach my $item ($contents->all){
        push @$browselist_ref, $item->get_column('thiscontent');
    }
    
    # Bestimmung der Titelzahl
    # DBI: "select count(distinct content) as rowcount from tit where field=?") or $logger->error($DBI::errstr);
    

    my $nav = Data::Pageset->new({
            'total_entries'    => $hits,
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
        });

    # TT-Data erzeugen
    my $ttdata={
        database   => $database,
        field      => $field,
        qopts      => $queryoptions->get_options,
        browselist => $browselist_ref,
        hits       => $hits,
        nav        => $nav,
    };
    
    return $self->print_page($config->{"tt_indexes_".$type."_tname"},$ttdata);
}

1;
