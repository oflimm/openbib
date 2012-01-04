#####################################################################
#
#  OpenBib::Statistics
#
#  Dieses File ist (C) 2006-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Statistics;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use base qw(Apache::Singleton);

use Encode qw(decode_utf8 encode_utf8);
use Date::Manip qw/ParseDate UnixDate/;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Storable ();

use OpenBib::Config;
use OpenBib::Database::DBI;
use OpenBib::Database::Statistics;

sub new {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $self->connectDB();

    return $self;
}

sub store_relevance {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $tstamp            = exists $arg_ref->{tstamp}
        ? $arg_ref->{tstamp}        : undef;
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id    }        : undef;
    my $isbn              = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn  }        : undef;
    my $dbname            = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}        : undef;
    my $katkey            = exists $arg_ref->{katkey}
        ? $arg_ref->{katkey}        : undef;
    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type  }        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef unless (defined $id && defined $dbname && defined $katkey && defined $type);

    # DBI: insert into relevance values (?,?,?,?,?,?)
    $self->{schema}->resultset('Relevance')->create(
        {
            tstamp => $tstamp,
            id     => $id,
            isbn   => $isbn,
            dbname => $dbname,
            type   => $type,
            katkey => $katkey,
        }
    );

    return;
}

sub store_result {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id           } : undef;

    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type  }        : undef;

    my $subkey            = exists $arg_ref->{subkey}
        ? $arg_ref->{subkey  }      : '';

    my $data_ref          = exists $arg_ref->{data}
        ? $arg_ref->{data  }        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("About to store result");

    return undef unless (defined $id && defined $type && defined $data_ref);

    # DBI: "delete from result_data where id=? and type=?";
    my $where_ref     = {
        id   => $id,
        type => $type,
    };
    
    if ($subkey){
        $where_ref->{subkey}=$subkey;
    }

    eval {
        $self->{schema}->resultset('ResultData')->search($where_ref)->delete_all;
    };

    if ($@){
        $logger->error("Couldn't delete item(s)");
    }

    $logger->debug("Storing:\n".YAML::Dump($data_ref));
    $logger->debug(ref $data_ref);

    if (ref $data_ref eq "ARRAY" && !@$data_ref){
        $logger->debug("Aborting: No Data");
        return;
    }

    my $datastring = encode_json $data_ref;

    # DBI: "insert into result_data values (?,NULL,?,?,?)"
    $self->{schema}->resultset('ResultData')->create(
        {
            id     => $id,
            type   => $type,
            subkey => $subkey,
            data   => $datastring
        }
    );

    return;
}

sub get_result {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id           } : undef;
    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type  }        : undef;
    my $subkey            = exists $arg_ref->{subkey}
        ? $arg_ref->{subkey  }      : '';
    my $hashkey           = exists $arg_ref->{hashkey}
        ? $arg_ref->{hashkey}       : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Getting Result");
    
    return undef unless (defined $id && defined $type);

    # DBI: "select data from result_data where id=? and type=?"
    my $where_ref     = {
        id   => $id,
        type => $type,
    };
    
    if ($subkey){
        $where_ref->{subkey}=$subkey;
    }
    
    my $resultdatas = $self->{schema}->resultset('ResultData')->search($where_ref,{ columns => qw/ data / });

    $logger->debug("Searching data for Id: $id / Type: $type");

    my $data_ref;
    foreach my $resultdata ($resultdatas->all){
        my $datastring = $resultdata->data;

	$logger->debug("Found a Record: $datastring");

        $data_ref     = decode_json $datastring;
    }

    $logger->debug(YAML::Dump($data_ref));

    $logger->debug("Ref: ".(ref $data_ref));

    if (ref $data_ref eq "HASH" && $hashkey){
        $logger->debug("Returning Ref: ".(ref $data_ref));
        return $data_ref->{$hashkey};
    }
    
    return $data_ref;
}

sub result_exists {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id           } : undef;
    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type  }        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return 0 unless (defined $id && defined $type);

    # DBI: "select count(data) as resultcount from result_data where id=? and type=? and length(data) > 300"
    # length WHY? ;-)
    my $where_ref     = {
        id   => $id,
        type => $type,
    };
    
    my $resultcount = $self->{schema}->resultset('ResultData')->search($where_ref)->count;

    $logger->debug("Found: $resultcount");
    
    return $resultcount;
}

sub log_event {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $sid          = exists $arg_ref->{sid}
        ? $arg_ref->{sid}                : undef;

    my $tstamp       = exists $arg_ref->{tstamp}
        ? $arg_ref->{tstamp}             : undef;

    my $type         = exists $arg_ref->{type}
        ? $arg_ref->{type}               : undef;
    
    my $content      = exists $arg_ref->{content}
        ? $arg_ref->{content}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Moegliche Event-Typen
    #
    # Recherchen:
    #   1 => Recherche-Anfrage bei Virtueller Recherche
    #  10 => Eineltrefferanzeige (Titel)
    #  11 => Verfasser-Normdatenanzeige
    #  12 => Koerperschafts-Normdatenanzeige
    #  13 => Notations-Normdatenanzeige
    #  14 => Schlagwort-Normdatenanzeige
    #  20 => Rechercheart (einfach=1,komplex=2,...)
    #  21 => Recherche-Backend (sql,xapian,z3950)
    #  22 => Recherche-Einstieg ueber Connector (1=DigiBib)
    #
    # Allgemeine Informationen
    # 100 => View
    # 101 => Browser
    # 102 => IP des Klienten
    # Redirects 
    # 500 => TOC / hbz-Server
    # 501 => TOC / ImageWaere-Server
    # 502 => USB ebook Vollzugriff
    # 503 => Nationallizenzen Vollzugriff
    # 510 => BibSonomy
    # 520 => Wikipedia / Personen
    # 521 => Wikipedia / ISBN
    # 522 => Wikipedia / Artikel
    # 530 => EZB
    # 531 => DBIS
    # 532 => Kartenkatalog Philfak
    # 533 => MedPilot
    # 540 => HBZ-Monofernleihe
    # 541 => HBZ-Dokumentenlieferung
    # 550 => WebOPAC

    # DBI: "insert into eventlog values (?,?,?,?)"
    $self->{schema}->resultset('Eventlog')->create(
        {
            sid     => $sid,
            tstamp  => $tstamp,
            type    => $type,
            content => $content,
        }
    );

    return;
}

sub get_number_of_event {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $from       = exists $arg_ref->{from}
        ? $arg_ref->{from}               : undef;

    my $to       = exists $arg_ref->{to}
        ? $arg_ref->{to}                 : undef;
    
    my $type         = exists $arg_ref->{type}
        ? $arg_ref->{type}               : undef;
    
    my $content      = exists $arg_ref->{content}
        ? $arg_ref->{content}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(tstamp) as rowcount, min(tstamp) as sincetstamp from eventlog"
    my $where_ref     = {};
    
    if ($type){
        $where_ref->{type} = $type,
    } 

    if ($from){
        push @{$where_ref->{tstamp}}, { '>' => $from }; 
    } 

    if ($to){
        push @{$where_ref->{tstamp}}, { '<' => $to } ; 
    } 

    if ($content){
        my $op = "=";
        if ($content =~m/\%$/){
	    $op = "like";
        }

        $where_ref->{content}= { $op => $content }; 
    } 

    $logger->debug(YAML::Dump($where_ref));

    my $count = $self->{schema}->resultset('Eventlog')->search($where_ref)->get_column('tstamp')->count;
    my $since = $self->{schema}->resultset('Eventlog')->search($where_ref)->get_column('tstamp')->min;

    $logger->debug("Got results: Number $count since $since");

    return {
        number => $count,
        since  => $since,
    }
}

sub get_tstamp_range_of_events {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $format     = exists $arg_ref->{format}
        ? $arg_ref->{format}              : '%Y-%M-%d %h:%m:%s';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select min(tstamp) as min_tstamp, max(tstamp) as max_tstamp from eventlog";
    my $eventlog_tstamp = $self->{schema}->resultset('Eventlog')->get_column('tstamp');
    
    my $min_tstamp = ParseDate($eventlog_tstamp->min);
    my $max_tstamp = ParseDate($eventlog_tstamp->max);

    return {
        min  => UnixDate($min_tstamp, $format),
        max  => UnixDate($max_tstamp, $format),
    }
}

sub get_number_of_queries_by_category {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $from       = exists $arg_ref->{from}
        ? $arg_ref->{from}               : undef;

    my $to       = exists $arg_ref->{to}
        ? $arg_ref->{to}                 : undef;

    my $tstamp       = exists $arg_ref->{tstamp}
        ? $arg_ref->{tstamp}             : undef;

    my $category     = exists $arg_ref->{category}
        ? $arg_ref->{category}           : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    return 0 if (!$category);

    # DBI: "select count(tstamp) as rowcount from querycategory";
    my $where_ref = {
        $category => 1,
    };

    if ($from){
        push @{$where_ref->{tstamp}}, { '>' => $from }; 
    } 

    if ($to){
        push @{$where_ref->{tstamp}}, { '<' => $to } ; 
    } 

    my $count = $self->{schema}->resultset('Querycategory')->search($where_ref)->get_column('tstamp')->count;

    return {
	 number => $count,
    };
}

sub get_ranking_of_event {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $from       = exists $arg_ref->{from}
        ? $arg_ref->{from}               : undef;

    my $to       = exists $arg_ref->{to}
        ? $arg_ref->{to}                 : undef;

    my $tstamp       = exists $arg_ref->{tstamp}
        ? $arg_ref->{tstamp}             : undef;

    my $type         = exists $arg_ref->{type}
        ? $arg_ref->{type}               : undef;

    my $limit        = exists $arg_ref->{limit}
        ? $arg_ref->{limit}              : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(content) as rowcount, content from eventlog" XXX "group by content order by rowcount DESC"
    my $where_ref     = {};

    my $attribute_ref = {
        group_by => 'content',
        select => [{ count => 'content'},'content'],
        as     => ['thiscount','thiscontent'],
    };
    
    if ($from){
        push @{$where_ref->{tstamp}}, { '>' => $from }; 
    } 

    if ($to){
        push @{$where_ref->{tstamp}}, { '<' => $to } ; 
    } 

    if ($to){
        $where_ref->{type} = $type;
    } 
    
    if ($limit){
        $attribute_ref->{rows} = $limit;
    }

    $logger->debug(YAML::Dump($where_ref)." - ".YAML::Dump($attribute_ref));

    my @ranking=();

    my $contentrankings = $self->{schema}->resultset('Eventlog')->search($where_ref,$attribute_ref);

    foreach my $contentranking ($contentrankings->all){
        my $count      = $contentranking->get_column('thiscount');
        my $content    = $contentranking->get_column('thiscontent');

        push @ranking, {
                        content   => $content,
                        number    => $count,
                       };
    }

    my @sortedranking = sort {$b->{number} cmp $a->{number}} @ranking;

    $logger->debug(YAML::Dump(\@sortedranking));

    return @sortedranking;
}

sub log_query {
    my ($self,$arg_ref)=@_;

    my $tstamp       = exists $arg_ref->{tstamp}
        ? $arg_ref->{tstamp}             : undef;

    # Set defaults
    my $view            = exists $arg_ref->{view}
        ? $arg_ref->{view}               : undef;

    my $searchquery_ref = exists $arg_ref->{searchquery_ref}
        ? $arg_ref->{searchquery_ref}    : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
            or $logger->error($DBI::errstr);

    # Moegliche Queryterm-Typen
    #
    # 01 => fs
    # 02 => hst 
    # 03 => verf
    # 04 => kor
    # 05 => swt
    # 06 => notation
    # 07 => isbn
    # 08 => issn
    # 09 => sign
    # 10 => mart
    # 11 => hststring
    # 12 => gtquelle
    # 13 => ejahr

    my $cat2type_ref = {
			fs        => 1,
			hst       => 2,
			verf      => 3,
			kor       => 4,
			swt       => 5,
			notation  => 6,
			isbn      => 7,
			issn      => 8,
			sign      => 9,
			mart      => 10,
			hststring => 11,
			gtquelle  => 12,
			ejahr     => 13,
		       };

    my $used_category_ref = {
			fs        => 0,
			hst       => 0,
			verf      => 0,
			kor       => 0,
			swt       => 0,
			notation  => 0,
			isbn      => 0,
			issn      => 0,
			sign      => 0,
			mart      => 0,
			hststring => 0,
			gtquelle  => 0,
			ejahr     => 0,
			    };

    my $term_stopword_ref = {
			  'a'     => 1,
			  'als'   => 1,
			  'an'    => 1,
			  'and'   => 1,
			  'auf'   => 1,
			  'aus'   => 1,
			  'bei'   => 1,
			  'das'   => 1,
			  'de'    => 1,
			  'der'   => 1,
			  'des'   => 1,
			  'die'   => 1,
			  'ein'   => 1,
			  'eine'  => 1,
			  'einer' => 1,
			  'für'   => 1,
			  'im'    => 1,
			  'in'    => 1,
			  'la'    => 1,
			  'le'    => 1,
			  'of'    => 1,
			  'the'   => 1,
			  'und'   => 1,
			  'von'   => 1,
			  'zu'    => 1,
			  'zum'   => 1,
			  'zur'   => 1,
			 };

    foreach my $cat (keys %$cat2type_ref){
        my $thiscategory_terms = (defined $searchquery_ref->{$cat}->{val})?$searchquery_ref->{$cat}->{val}:'';

        next if (!$thiscategory_terms);
        
	$thiscategory_terms    =~s/[^\p{Alphabetic}0-9 ]//g;
	$thiscategory_terms    = lc($thiscategory_terms);

	# Genutzte Kategorie merken
	if ($thiscategory_terms){
	  $used_category_ref->{$cat} = 1;
	}

	my $tokenizer = String::Tokenizer->new();
	$tokenizer->tokenize($thiscategory_terms);
	
	my $i = $tokenizer->iterator();
	
	while ($i->hasNextToken()) {
	  my $next = $i->nextToken();
	  next if (!$next);
	  next if ($next=~/^[\p{Alphabetic}0-9]$/);
	  next if (exists $term_stopword_ref->{$next});

          # DBI: "insert into queryterm values (?,?,?,?)"
          $self->{schema}->resultset('Queryterm')->create(
              {
                  tstamp  => $tstamp,
                  view    => $view,
                  type    => $cat2type_ref->{$cat},
                  content => $next,
                  
              }
          );
	}
    }

    # DBI: "insert into querycategory values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
    $self->{schema}->resultset('Querycategory')->create(
              {
                  tstamp    => $tstamp,
                  view      => $view,
                  fs        => $used_category_ref->{fs},
                  hst       => $used_category_ref->{hst},
                  verf      => $used_category_ref->{verf},
                  kor       => $used_category_ref->{kor},
                  swt       => $used_category_ref->{swt},
                  notation  => $used_category_ref->{notation},
                  isbn      => $used_category_ref->{isbn},
                  issn      => $used_category_ref->{issn},
                  sign      => $used_category_ref->{sign},
                  mart      => $used_category_ref->{mart},
                  hststring => $used_category_ref->{hststring},
                  inhalt    => $used_category_ref->{inhalt},
                  gtquelle  => $used_category_ref->{gtquelle},
                  ejahr     => $used_category_ref->{ejahr},
              }
          );

    return;
}

sub get_sequencestat_of_event {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $type         = exists $arg_ref->{type}
        ? $arg_ref->{type}               : undef;

    my $subtype      = exists $arg_ref->{subtype}
        ? $arg_ref->{subtype}            : undef;

    my $content      = exists $arg_ref->{content}
        ? $arg_ref->{content}            : undef;

    my $contentop    = exists $arg_ref->{content_op}
        ? $arg_ref->{content_op}         : '=';
    
    my $year         = exists $arg_ref->{year}
        ? $arg_ref->{year}               : undef;

    my $month        = exists $arg_ref->{month}
        ? $arg_ref->{month}              : undef;

    my $day          = exists $arg_ref->{day}
        ? $arg_ref->{day}                : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @x_values = ();
    my @y_values = ();

    my $where_ref = {};
    
    if ($type){
        $where_ref->{type} = $type;
    } 

    if ($content){
        $where_ref->{content} = { $contentop => $content };
    } 
    
    my ($thisday, $thismonth, $thisyear) = (localtime)[3,4,5];
    $thisyear  += 1900;
    $thismonth += 1;

    $year   = $thisyear  if (!$year);
    $month  = $thismonth if (!$month);
    $day    = $thisday   if (!$day);

    my $where_lhsql_ref = []; # Conditions for use of left hand sql functions
    my $attribute_ref   = {};
    
    # Monatsstatistik fuer Jahr $year
    if ($subtype eq 'monthly'){
        # DBI: "select month(tstamp) as x_value, count(tstamp) as y_value from eventlog where $sqlwherestring and year(tstamp) = ? group by month(tstamp)";
        push @$where_lhsql_ref, \[ 'YEAR(tstamp) = ?', [ plain_value => $year ] ]; 
        $attribute_ref = {
            group_by => [ { month => 'tstamp' } ],
            select => [ { month => 'tstamp'}, { count => 'tstamp' } ],
            as     => ['x_value','y_value'],
        };
    }
    # Tagesstatistik fuer Monat $month
    elsif ($subtype eq 'daily'){
        # DBI: "select day(tstamp) as x_value, count(tstamp) as y_value from eventlog where $sqlwherestring and month(tstamp) = ? and YEAR(tstamp) = ? group by day(tstamp)";
        push @$where_lhsql_ref, \[ 'MONTH(tstamp) = ?', [ plain_value => $month ] ]; 
        push @$where_lhsql_ref, \[ 'YEAR(tstamp) = ?', [ plain_value => $year ] ]; # thisyear??
        $attribute_ref = {
            group_by => [ { day => 'tstamp' } ],
            select => [ { day => 'tstamp'}, { count => 'tstamp' } ],
            as     => ['x_value','y_value'],
        };
    }
    # Stundenstatistik fuer Tag $day
    elsif ($subtype eq 'hourly'){
        # DBI: "select hour(tstamp) as x_value, count(tstamp) as y_value from eventlog where $sqlwherestring and DAY(tstamp) = ? and MONTH(tstamp) = ? and YEAR(tstamp) = ? group by hour(tstamp)";
        push @$where_lhsql_ref, \[ 'DAY(tstamp) = ?', [ plain_value => $day ] ]; 
        push @$where_lhsql_ref, \[ 'MONTH(tstamp) = ?', [ plain_value => $month ] ]; 
        push @$where_lhsql_ref, \[ 'YEAR(tstamp) = ?', [ plain_value => $year ] ]; # thisyear??
        $attribute_ref = {
            group_by => [ { hour => 'tstamp' } ],
            select => [ { hour => 'tstamp'}, { count => 'tstamp' } ],
            as     => ['x_value','y_value'],
        };
    }

    my $stats = $self->{schema}->resultset('Eventlog')->search(
        {
            -and => [
                $where_ref,
                $where_lhsql_ref,
            ],
        },
        $attribute_ref,
    );

    foreach my $row ($stats->all){
        push @x_values, $row->get_column('x_value');
        push @y_values, $row->get_column('y_value');
    }

    my $values_ref = { x_values => \@x_values,
		       y_values => \@y_values};

    $logger->debug(YAML::Dump($values_ref));

    return $values_ref;
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    eval {
        # Verbindung zur SQL-Datenbank herstellen
        $self->{dbh}
            = OpenBib::Database::DBI->connect("DBI:$config->{statisticsdbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
            or $logger->error_die($DBI::errstr);
    };

    if ($@){
        $logger->fatal("Unable to connect to database $config->{statisticsdbname}");
    }
    
    $self->{dbh}->{RaiseError} = 1;

    eval {
        # UTF8: {'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}
        $self->{schema} = OpenBib::Database::Statistics->connect("DBI:$config->{statisticsdbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error_die($DBI::errstr);
    };

    if ($@){
        $logger->fatal("Unable to connect schema to database $config->{statisticsdbname}: DBI:$config->{statisticsdbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}");
    }

    return;

}
1;

__END__

=head1 NAME

OpenBib::Statistics - Singleton für den Zugriff auf die Statistik-Datenbank

=head1 DESCRIPTION

Dieser Singleton bietet einen Zugriff auf die Statistik-Datenbank.

=head1 SYNOPSIS

 use OpenBib::Statistics;

=head1 METHODS

=over 4

=item new

Erzeugung als herkömmliches Objektes und nicht als
Apache-Singleton. Damit kann auch ausserhalb des Apache mit mod_perl
auf Statistikdaten in Perl-Skripten zugegriffen werden.

=item store_relevance({ tstamp => $tstamp, id => $id, dbname => $dbname, isbn => $isbn, $katkey => $katkey, type => $type})

Speichert den Aufruf eines Einzeltreffers als Relevanzinformation in
der Statistik-Datenbank. Die gespeicherten Informationen sind die
Sessionidentifikation $id, der Aufrufzeitpunkt $tstamp, eine etwaige
$isbn, Datenbankname $dbname und $katkey des Titels in dieser Datenbank,
sowie der Aufruftyp $type (1=Einzeltrefferaufruf)

=item store_result({ id => $id, type => $type, subkey  => $subkey, $data => $data_ref });

Speichert eine statistische Auswertung oder generell komplexe
Datenstrukturen $data_ref für einen schnellen Lookup in der
Statistik-Datenbank. Spezifiziert werden diese Daten über einen
allgemeinen Typ $type (z.B. 1=meistaufgerufene Titel pro Datenbank,
2=meistgenutzte Kataloge, ..), einem Identifikator $id und den
eigentlichen Nutzdaten $data_ref. Zusätzlich kann optional zur
weiteren Untergliederung auch noch ein subkey vergeben werden.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
