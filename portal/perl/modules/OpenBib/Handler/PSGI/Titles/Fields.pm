#####################################################################
#
#  OpenBib::Handler::PSGI::Titles::Fields.pm
#
#  Register ueber Titelfeld
#
#  Copyright 1997-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Titles::Fields;

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
use OpenBib::Conv::Config;
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

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'            => 'show_collection',
        'show_record'                => 'show_record',
        'dispatch_to_representation' => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');

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

    my $catalog = new OpenBib::Catalog({ database => $database });

    my $fields = $catalog->get_schema->resultset('TitleField')->search_rs(
        undef,
        {
            select => [{ 'distinct' => 'field'}],
            as     => ['thisfield'],
            sort_by => ['field'],
            group_by => ['field','titleid','mult','subfield','content'],
        }
    );

    my $fields_ref = {};
    
    foreach my $field_ref ($fields->all){
        my $thisfield = sprintf "%04d",$field_ref->get_column('thisfield');
        $fields_ref->{$thisfield} = 1;
    }
    
    # TT-Data erzeugen
    my $ttdata={
        database => $database,
        fields => $fields_ref,
    };
    
    return $self->print_page($config->{tt_titles_fields_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $field          = $self->strip_suffix($self->param('fieldid'));

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

    my $start             = $query->param('start')             || '';

    # Sub-Template ID
    my $stid              = $query->param('stid')              || '';

    unless ($config->database_defined_in_view({ database => $database, view => $view })){
	return $self->print_warning($msg->maketext("Zugriff auf Katalog $database verweigert.")) if (!$user->is_admin);	    
    }
        
    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen

    return unless ($database && $field);

    my $subfield = "";
    
    if ($field =~m/:/){
	($field,$subfield) = $field =~m/^([^:]+):(.)$/
    }

    $logger->debug("Index for field '$field' and subfield '$subfield'");
	    
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
    my $dataschema    = $dbinfotable->{dbinfo}{schema}{$database};
    
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

    # Welche Kategorien sind mit Nordaten verknuepft, so dass dort die Ansetzungsform bestimmt werden muss
    
    my $conn_field_ref = {};

    if ($dataschema eq "mab2"){
	$conn_field_ref = {    
	    '0014' => 'holding',
		'0016' => 'holding',
		'0100' => 'person',
		'0101' => 'person',
		'0102' => 'person',
		'0103' => 'person',
		'4308' => 'person',
		'0200' => 'corporatebody',
		'0201' => 'corporatebody',
		'4307' => 'corporatebody',
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
		'4306' => 'subject',
	};
    }
    elsif ($dataschema eq "marc21"){
	$conn_field_ref = {    
	    '0014' => 'holding',
		'0016' => 'holding',
		# '0100' => 'person',
		# '0700' => 'person',
		# '0110' => 'corporatebody',
		# '0111' => 'corporatebody',
		# '0710' => 'corporatebody',
		# '0082' => 'classification',
		# '0084' => 'classification',		
		# '0710' => 'subject',
		# '0600' => 'subject',
		# '0610' => 'subject',
		# '0648' => 'subject',
		# '0650' => 'subject',
		# '0651' => 'subject',
		# '0655' => 'subject',
		# '0688' => 'subject',
		# '0689' => 'subject',
	};
    }

    my $contents;

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
                fieldcontent => 'person_fields.content',
                select => 'person_fields.content',
                join => ['personid', { 'personid' => 'person_fields' }],
            },
            'corporatebody'  => {
                resultset => 'TitleCorporatebody',
                field => 'corporatebody_fields.field',
                fieldcontent => 'corporatebody_fields.content',
                select => 'corporatebody_fields.content',
                join => ['corporatebodyid', { 'corporatebodyid' => 'corporatebody_fields' }],
            },
            'subject'        => {
                resultset => 'TitleSubject',
                field => 'subject_fields.field',
                fieldcontent => 'subject_fields.content',
                select => 'subject_fields.content',
                join => ['subjectid', { 'subjectid' => 'subject_fields' }],
            },
            'classification' => {
                resultset => 'TitleClassification',
                field => 'classification_fields.field',
                fieldcontent => 'classification_fields.content',
                select => 'classification_fields.content',
                join => ['classificationid', { 'classificationid' => 'classification_fields' }],
            },
            'holding' => {
                resultset => 'HoldingField',
                field => 'field',
                select => 'content',
            },
        );
        
        # DBI: "select distinct norm.content as content from $normtable as norm, conn where conn.field=? and conn.sourcetype=1 and conn.targettype=? and conn.targetid=norm.id and norm.field=1 order by content $limits ";
        $logger->debug("Type $table -> $table_type{$table}{resultset}");

	if ($table eq "holding"){
	    $contents = $schema->resultset($table_type{$table}{resultset})->search_rs(
		{
		    $table_type{$table}{field} => $field,
		},
		{
		    select   => [$table_type{$table}{select}],
		    group_by => $table_type{$table}{select},
		    as       => ['thiscontent'],
		}
		);
	    
	    $hits = $contents->count;
	    
	    $contents = $schema->resultset($table_type{$table}{resultset})->search_rs(
		{
		    $table_type{$table}{field} => $field,
		},
		{
		    select   => [$table_type{$table}{select}],
		    group_by => $table_type{$table}{select},
		    order_by => [ { -asc => $table_type{$table}{select} } ],
		    as       => ['thiscontent'],
		    rows => $hitrange,
		    offset => $offset,
		}
		);            
	}
	else {

	    my $where_ref = {
		$table_type{$table}{field} => 800, # Ansetzungsform		
		    'me.field'   => $field,
	    };
	    
	    if ($start){
		$start = decode_utf8($start);
		$where_ref->{$table_type{$table}{fieldcontent}} = { -ilike => "$start\%" };
	    }

	    $contents = $schema->resultset($table_type{$table}{resultset})->search_rs(
		$where_ref,
		{
		    select   => [$table_type{$table}{select}],
		    group_by => $table_type{$table}{select},
		    as       => ['thiscontent'],
		    join     => $table_type{$table}{join},
		}
		);
	    
	    $hits = $contents->count;
	    
	    $contents = $schema->resultset($table_type{$table}{resultset})->search_rs(
		$where_ref,
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
    }
    # Sonst direkt in den Titelfeldern
    else {
        $logger->debug("Searching title field directly with hitrange $hitrange / offset $offset");

	my $where_ref = {
                'field'   => $field,
	};

	if ($subfield){
	    $where_ref->{'subfield'} = $subfield;
	}

        $contents = $schema->resultset('TitleField')->search_rs(
	    $where_ref,
            {
                select   => ['content'],
                as       => ['thiscontent'],
                group_by => ['content'],
            }
        );
        
        $hits = $contents->count;

	if ($start){
	    $start = decode_utf8($start);
	    $where_ref->{content} = { -ilike => "$start\%" };
	}
	
        $contents = $schema->resultset('TitleField')->search_rs(
            $where_ref,
            {
                select   => ['content'],
                as       => ['thiscontent'],
                order_by => ['content'],
                group_by => ['content'],#,'mult','subfield'],
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
	subfield   => $subfield,
        browselist => $browselist_ref,
        hits       => $hits,
        nav        => $nav,
    };
    
    return $self->print_page($config->{"tt_titles_fields_record_tname"},$ttdata);
}

sub get_searchprefix {
    my ($self) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config   = $self->param('config');
    my $database = $self->param('database');
    my $field    = $self->strip_suffix($self->param('fieldid'));

    $logger->debug("Getting searchprefix for field $field in database $database");
    #my $searchprefix = (defined $config->{searchfield}{"t$field"}{prefix})? $config->{searchfield}{"t$field"}{prefix}:undef;
    my $searchprefix = (defined $config->{searchfield}{"t$field"} && $config->{searchfield}{"t$field"}{type} eq "string")? $config->{searchfield}{"t$field"}{prefix}:undef;
    $logger->debug("Got searchprefix $searchprefix");

    return $searchprefix;
}

1;
