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
use OpenBib::Schema::Statistics::Singleton;

sub new {
    my ($class,$arg_ref) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $self->connectDB($arg_ref);

    return $self;
}

sub _new_instance {
    my ($class,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $self->connectDB($arg_ref);

    return $self;
}

sub store_titleusage {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $tstamp            = exists $arg_ref->{tstamp}
        ? $arg_ref->{tstamp}        : undef;
    my $origin            = exists $arg_ref->{origin}
        ? $arg_ref->{origin}        : 1;
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id    }        : undef;
    my $isbn              = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn  }        : undef;
    my $dbname            = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}        : undef;
    my $sid               = exists $arg_ref->{sid}
        ? $arg_ref->{sid}           : undef;
    my $viewname          = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return undef unless (defined $id && defined $dbname && defined $sid  && defined $origin);

    my $parsed_tstamp = new Date::Manip::Date;
    $parsed_tstamp->parse($tstamp);
    
    # DBI: insert into relevance values (?,?,?,?,?,?)
    $self->{schema}->resultset('Titleusage')->create(
        {
            tstamp       => $tstamp,
            tstamp_year  => $parsed_tstamp->printf("%Y"),
            tstamp_month => $parsed_tstamp->printf("%m"),
            tstamp_day   => $parsed_tstamp->printf("%d"),
            id           => $id,
            isbn         => $isbn,
            dbname       => $dbname,
            sid          => $sid,
            viewname     => $viewname,
            origin       => $origin,
        }
    );

    return;
}

sub cache_data {
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
        $self->{schema}->resultset('Datacache')->search($where_ref)->delete;
    };

    if ($@){
        $logger->error("Couldn't delete item(s)");
    }

    if ($logger->is_debug){
        $logger->debug("Storing:\n".YAML::Dump($data_ref));
        $logger->debug(ref $data_ref);
    }
    
    if (ref $data_ref eq "ARRAY" && !@$data_ref){
        $logger->debug("Aborting: No Data");
        return;
    }

    my $datastring = encode_json $data_ref;

    # DBI: "insert into result_data values (?,NULL,?,?,?)"
    $self->{schema}->resultset('Datacache')->create(
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
    
    my $resultdatas = $self->{schema}->resultset('Datacache')->search($where_ref,{ columns => qw/ data / });

    $logger->debug("Searching data for Id: $id / Type: $type");

    my $data_ref;
    foreach my $resultdata ($resultdatas->all){
        my $datastring = encode_utf8($resultdata->data);

	$logger->debug("Found a Record: $datastring");

        $data_ref     = decode_json $datastring;
    }

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($data_ref));        
        $logger->debug("Ref: ".(ref $data_ref));
    }
    
    if (ref $data_ref eq "HASH" && $hashkey){
        if ($logger->is_debug){
            $logger->debug("Returning Ref: ".(ref $data_ref));
        }
        
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
    
    my $resultcount = $self->{schema}->resultset('Datacache')->search($where_ref)->count;

    $logger->debug("Found: $resultcount");
    
    return $resultcount;
}

sub create_session {
    my ($self,$arg_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Set defaults
    my $sessionid    = exists $arg_ref->{sessionid}
        ? $arg_ref->{sessionid}         : undef;

    my $createtime         = exists $arg_ref->{createtime}
        ? $arg_ref->{createtime}               : undef;

    my $viewname           = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}                 : undef;

    my $parsed_tstamp = new Date::Manip::Date;
    $parsed_tstamp->parse($createtime);

    my $new_session = $self->{schema}->resultset('Sessioninfo')->create({
        sessionid  => $sessionid,
        createtime => $createtime,
        createtime_year  => $parsed_tstamp->printf("%Y"),
        createtime_month => $parsed_tstamp->printf("%m"),
        createtime_day   => $parsed_tstamp->printf("%d"),
        viewname         => $viewname,
    });

    if ($new_session){
        return $new_session->id;
    }
    
    return;
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

    my $serialize    = exists $arg_ref->{serialize}
        ? $arg_ref->{serialize}          : undef;

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

    my $parsed_tstamp = new Date::Manip::Date;
    $parsed_tstamp->parse($tstamp);

    my $resultset = "Eventlog";
    
    if ($serialize){
        # Backslashes Escapen fuer PostgreSQL!!!
        $content=~s/\\/\\\\/g;        
        
        $resultset = "Eventlogjson";
    }
    
    $self->{schema}->resultset($resultset)->create(
        {
            sid          => $sid,
            tstamp       => $tstamp,
            tstamp_year  => $parsed_tstamp->printf("%Y"),
            tstamp_month => $parsed_tstamp->printf("%m"),
            tstamp_day   => $parsed_tstamp->printf("%d"),
            type         => $type,
            content      => $content,
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

    my $year       = exists $arg_ref->{year}
        ? $arg_ref->{year}               : undef;

    my $month      = exists $arg_ref->{month}
        ? $arg_ref->{month}               : undef;

    my $type         = exists $arg_ref->{type}
        ? $arg_ref->{type}               : undef;
    
    my $content      = exists $arg_ref->{content}
        ? $arg_ref->{content}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # DBI: "select count(tstamp) as rowcount, min(tstamp) as sincetstamp from eventlog"
    my $where_ref     = {};
    
    if ($type){
        $where_ref->{type} = $type,
    } 

    if ($year){
        push @{$where_ref->{tstamp_year}}, { '=' => $year }; 
    } 
    
    if ($month){
        push @{$where_ref->{tstamp_month}}, { '=' => $month } ; 
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

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($where_ref));
    }

    if (exists $config->{eventlogjson_type}{$type}){
        my $count = $self->{schema}->resultset('Eventlogjson')->search_rs($where_ref)->count;
        
        $logger->debug("Since when?");
        
        my $since = $self->{schema}->resultset('Eventlogjson')->search_rs($where_ref)->get_column('tstamp')->min;
        
        #    my $since = "ultimo";
        $logger->debug("Got results: Number $count since $since");
        
        return {
            number => $count,
            since  => $since,
        };
    }
    else {            
        my $count = $self->{schema}->resultset('Eventlog')->search_rs($where_ref)->count;
        
        $logger->debug("Since when?");
        
        my $since = $self->{schema}->resultset('Eventlog')->search_rs($where_ref)->get_column('tstamp')->min;
        
        #    my $since = "ultimo";
        $logger->debug("Got results: Number $count since $since");
        
        return {
            number => $count,
            since  => $since,
        };
    }
}

sub get_tstamp_range_of_events {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $format     = exists $arg_ref->{format}
        ? $arg_ref->{format}              : '%Y-%M-%d %h:%m:%s';

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Shortcut fuer Jahr
    if ($format == '%Y'){
        my $eventlog_tstamp = $self->{schema}->resultset('Eventlog')->get_column('tstamp_year');
        
        my $min_tstamp = $eventlog_tstamp->min;
        my $max_tstamp = $eventlog_tstamp->max;
        
        return {
            min  => $min_tstamp,
            max  => $max_tstamp,
        };
    }
    else {
        # DBI: "select min(tstamp) as min_tstamp, max(tstamp) as max_tstamp from eventlog";
        my $eventlog_tstamp = $self->{schema}->resultset('Eventlog')->get_column('tstamp');
        
        my $min_tstamp = ParseDate($eventlog_tstamp->min);
        my $max_tstamp = ParseDate($eventlog_tstamp->max);
        
        return {
            min  => UnixDate($min_tstamp, $format),
            max  => UnixDate($max_tstamp, $format),
        };
    }
}

sub get_number_of_queries_by_category {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $from       = exists $arg_ref->{from}
        ? $arg_ref->{from}               : undef;

    my $to       = exists $arg_ref->{to}
        ? $arg_ref->{to}                 : undef;

    my $year       = exists $arg_ref->{year}
        ? $arg_ref->{year}               : undef;

    my $month      = exists $arg_ref->{month}
        ? $arg_ref->{month}               : undef;

    my $category     = exists $arg_ref->{category}
        ? $arg_ref->{category}           : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    return 0 if (!$category);

    # DBI: "select count(tstamp) as rowcount from querycategory";
    my $where_ref = {
        $category => 1,
    };

    if ($year){
        push @{$where_ref->{tstamp_year}}, { '=' => $year }; 
    } 

    if ($month){
        push @{$where_ref->{tstamp_month}}, { '=' => $month } ; 
    } 

    if ($from){
        push @{$where_ref->{tstamp}}, { '>' => $from }; 
    } 

    if ($to){
        push @{$where_ref->{tstamp}}, { '<' => $to } ; 
    } 

    my $count = $self->{schema}->resultset('Searchfield')->search($where_ref)->count;

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

    my $year       = exists $arg_ref->{year}
        ? $arg_ref->{year}               : undef;

    my $month      = exists $arg_ref->{month}
        ? $arg_ref->{month}               : undef;

    my $type         = exists $arg_ref->{type}
        ? $arg_ref->{type}               : undef;

    my $limit        = exists $arg_ref->{limit}
        ? $arg_ref->{limit}              : '';

    my $sortorder    = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}          : 'up';

    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(content) as rowcount, content from eventlog" XXX "group by content order by rowcount DESC"
    my $where_ref     = {};

    my $attribute_ref = {
        group_by => 'content',
        select => [{ count => 'content'},'content'],
        as     => ['thiscount','thiscontent'],
    };

    if ($year){
        push @{$where_ref->{tstamp_year}}, { '=' => $year }; 
    } 

    if ($month){
        push @{$where_ref->{tstamp_month}}, { '=' => $month } ; 
    } 
    
    if ($from){
        push @{$where_ref->{tstamp}}, { '>' => $from }; 
    } 

    if ($to){
        push @{$where_ref->{tstamp}}, { '<' => $to } ; 
    } 

    if ($type){
        $where_ref->{type} = $type;
    } 
    
    if ($limit){
        $attribute_ref->{rows} = $limit;
    }
    
    if ($logger->is_debug){
        $logger->debug(YAML::Dump($where_ref)." - ".YAML::Dump($attribute_ref));
    }   

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

    
    my @sortedranking = ();

    if ($sortorder eq "up"){
        @sortedranking = sort {$b->{number} cmp $a->{number}} @ranking;
    }
    else {
        @sortedranking = sort {$a->{number} cmp $b->{number}} @ranking;
    }
    
    if ($logger->is_debug){
        $logger->debug(YAML::Dump(\@sortedranking));
    }

    return @sortedranking;
}

sub log_query {
    my ($self,$arg_ref)=@_;

    my $sid          = exists $arg_ref->{sid}
        ? $arg_ref->{sid}                : undef;

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

    my $parsed_tstamp = new Date::Manip::Date;
    $parsed_tstamp->parse($tstamp);

    # Moegliche Queryterm-Typen
    #
    # 01 => fressearch
    # 02 => title
    # 03 => person
    # 04 => corporatebody
    # 05 => subject
    # 06 => classification
    # 07 => isbn
    # 08 => issn
    # 09 => mark
    # 10 => mediatype
    # 11 => titlestring
    # 12 => source
    # 13 => year

    my $cat2type_ref = {
			freesearch     => 1,
			title          => 2,
			person         => 3,
			corporatebody  => 4,
			subject        => 5,
			classification => 6,
			isbn           => 7,
			issn           => 8,
			mark           => 9,
			mediatype      => 10,
		        titlestring    => 11,
			source         => 12,
			year           => 13,
                        content        => 14,
		       };

    my $used_category_ref = {
        freesearch     => 'f',
        title          => 'f',
        person         => 'f',
        corporatebody  => 'f',
        subject        => 'f',
        classification => 'f',
        isbn           => 'f',
        issn           => 'f',
        mark           => 'f',
        mediatype      => 'f',
        titlestring    => 'f',
        source         => 'f',
        year           => 'f',
        content        => 'f',
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
	  $used_category_ref->{$cat} = 't';
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
          $self->{schema}->resultset('Searchterm')->create(
              {
                  sid          => $sid,
                  tstamp       => $tstamp,
                  tstamp_year  => $parsed_tstamp->printf("%Y"),
                  tstamp_month => $parsed_tstamp->printf("%m"),
                  tstamp_day   => $parsed_tstamp->printf("%d"),
                  viewname     => $view,
                  type         => $cat2type_ref->{$cat},
                  content      => $next,
                  
              }
          );
	}
    }

    # DBI: "insert into querycategory values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
    $self->{schema}->resultset('Searchfield')->create(
              {
                  sid          => $sid,
                  tstamp       => $tstamp,
                  tstamp_year  => $parsed_tstamp->printf("%Y"),
                  tstamp_month => $parsed_tstamp->printf("%m"),
                  tstamp_day   => $parsed_tstamp->printf("%d"),
                  
                  viewname       => $view,
                  freesearch     => $used_category_ref->{freesearch},
                  title          => $used_category_ref->{title},
                  person         => $used_category_ref->{person},
                  corporatebody  => $used_category_ref->{corporatebody},
                  subject        => $used_category_ref->{subject},
                  classification => $used_category_ref->{classification},
                  isbn           => $used_category_ref->{isbn},
                  issn           => $used_category_ref->{issn},
                  mark           => $used_category_ref->{mark},
                  mediatype      => $used_category_ref->{mediatype},
                  titlestring    => $used_category_ref->{titlestring},
                  content        => $used_category_ref->{content},
                  source         => $used_category_ref->{source},
                  year           => $used_category_ref->{year},
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

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($values_ref));
    }

    return $values_ref;
}

sub connectDB {
    my $self = shift;
    my $arg_ref = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    if (defined $arg_ref->{statisticsdbname} && $arg_ref->{statisticsdbname}){
        $config->{statisticsdbname} = $arg_ref->{statisticsdbname};
    }

    eval {
        # UTF8: {'pg_enable_utf8'    => 1 |
        $self->{schema} = OpenBib::Schema::Statistics::Singleton->connect("DBI:Pg:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd},{'pg_enable_utf8'    => 1 }) or $logger->error_die($DBI::errstr);
    };

    if ($@){
        $logger->fatal("Unable to connect schema to database $config->{statisticsdbname}: DBI:Pg:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}");
    }

    return;

}

sub DESTROY {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (defined $self->{schema}){
        eval {
            $self->{schema}->storage->dbh->disconnect;
        };

        if ($@){
            $logger->error($@);
        }
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

=item store_titleusage({ tstamp => $tstamp, id => $id, dbname => $dbname, isbn => $isbn, $katkey => $katkey, type => $type})

Speichert den Aufruf eines Einzeltreffers als Relevanzinformation in
der Statistik-Datenbank. Die gespeicherten Informationen sind die
Sessionidentifikation $id, der Aufrufzeitpunkt $tstamp, eine etwaige
$isbn, Datenbankname $dbname und $katkey des Titels in dieser Datenbank,
sowie der Aufruftyp $type (1=Einzeltrefferaufruf)

=item cache_data({ id => $id, type => $type, subkey  => $subkey, $data => $data_ref });

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
