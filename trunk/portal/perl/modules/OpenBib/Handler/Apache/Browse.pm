#####################################################################
#
#  OpenBib::Handler::Apache::Browse.pm
#
#  ehemals Search.pm
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
use Data::Pageset;
use POSIX;
use Template;

use OpenBib::Search::Util;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Database::Catalog;
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
  
    my $hitrange=($query->param('num'))?$query->param('num'):20;
    ($hitrange)=$hitrange=~/^(-?\d+)$/; # hitrange muss numerisch sein (SQL-Injection)

    my $page=($query->param('page'))?$query->param('page'):1;
    ($page)=$page=~/^(-?\d+)$/; # page muss numerisch sein (SQL-Injection)

    #####################################################################
    ## Offset: Maximale Anzahl ausgegebener Treffer bei Anfangs-Suche
    ##          >0  - hitrange Treffer werden ab dieser Nr. ausgegeben 
  
    my $offset=$page*$hitrange-$hitrange;
  
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

    my $schema;
    
    if ($config->{dbimodule} eq "Pg"){
        eval {
            # UTF8: {'pg_enable_utf8'    => 1}
            $schema = OpenBib::Database::Catalog->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},{'pg_enable_utf8'    => 1}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $database: DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}");
            next;
        }
    }
    elsif ($config->{dbimodule} eq "mysql"){
        eval {
            # UTF8: {'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}
            $schema = OpenBib::Database::Catalog->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $database: DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}");
            next;
        }
    }

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
    
    my ($type,$thisfield)=$category=~/^([A-Z])(\d+)/;
    
    $type =
        ($type eq "P")?'person':
            ($type eq "C")?'corporatebody':
                ($type eq "S")?'subject':
                    ($type eq "N")?'classification':'title';
    
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

    my $contents;
    
    if ($type eq "title" && exists $conn_cat_ref->{$category}){
        # Bestimmung der Titel
        my $table  = $conn_cat_ref->{$category};
        
        my $regexp_op = ($config->{dbimodule} eq "mysql")?"rlike":
            ($config->{dbimodule} eq "Pg")?"~":"rlike";
        
        if ($table eq "title"){
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

            # DBI: "select distinct norm.content as content from $normtable as norm, conn where conn.category=? and conn.sourcetype=1 and conn.targettype=? and conn.targetid=norm.id and norm.category=1 order by content $limits ";
            $logger->debug("Type $table -> $table_type{$table}{resultset}");
            $contents = $schema->resultset($table_type{$table}{resultset})->search_rs(
                {
                    $table_type{$table}{field} => 1, # Ansetzungsform
                    'me.field' => $thisfield
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
                    $table_type{$table}{field} => 1, # Ansetzungsform
                    'me.field' => $thisfield
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
        else {
            $contents = $schema->resultset('TitleField')->search_rs(
                {
                    'field'   => $thisfield,
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
                    'field'   => $thisfield,
                },
                {
                    select   => ['content'],
                    as       => ['thiscontent'],
                    group_by => ['content'],
                    rows => $hitrange,
                    offset => $offset,
                }
            );

        }
    }
    else {
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
        # DBI: "select distinct content from $type where category=? order by content $limits 
        $contents = $schema->resultset($table_type{$type}{resultset})->search_rs(
            {
                'field'   => $thisfield,
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
                'field'   => $thisfield,
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
    # DBI: "select count(distinct content) as rowcount from tit where category=?") or $logger->error($DBI::errstr);
    

    my $nav = Data::Pageset->new({
            'total_entries'    => $hits,
            'entries_per_page' => $queryoptions->get_option('num'),
            'current_page'     => $queryoptions->get_option('page'),
            'mode'             => 'slide',
        });

    # TT-Data erzeugen
    my $ttdata={
        database   => $database,
        category   => $category,
        qopts      => $queryoptions->get_options,
        browselist => $browselist_ref,
        hits       => $hits,
        nav        => $nav,
    };
    $self->print_page($config->{"tt_browse_".$type."_tname"},$ttdata);
    return Apache2::Const::OK;
}

1;
