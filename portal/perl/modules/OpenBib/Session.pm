#####################################################################
#
#  OpenBib::Session
#
#  Dieses File ist (C) 2006-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Session;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use CGI::Cookie;
use Cache::Memcached::Fast;
use Date::Manip;
use DBIx::Class::ResultClass::HashRefInflator;
use Benchmark ':hireswallclock';
use Digest::MD5;
use Encode qw(decode_utf8 encode_utf8);
use HTTP::BrowserDetect;
use JSON::XS qw(encode_json decode_json);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Config::File;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Schema::DBI;
use OpenBib::Schema::System;
use OpenBib::Schema::System::Singleton;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::SearchQuery;
use OpenBib::Statistics;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $sessionID   = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;

    my $view        = exists $arg_ref->{view}
        ? $arg_ref->{view}                  : undef;

    my $config     = exists $arg_ref->{config}
        ? $arg_ref->{config}                : OpenBib::Config->new;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $self->{_config} = $config;
    
    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Reuse des memc-Handles von config
    if ($config->{memc}){
	$self->{memc} = $config->{memc};
    }
    
    $self->{servername} = $config->{servername};
    $self->{view}       = $view;
    $self->{_is_new_session} = 0;

    # Setzen der Defaults
    
    $logger->debug("Entering Session->new");

    if ($config->{benchmark}) {
		$btime=new Benchmark;
		$timeall=timediff($btime,$atime);
		$logger->info("Total time for stage 0 is ".timestr($timeall));
    }

    if (!defined $sessionID || !$sessionID){
        $self->_init_new_session();
	if ($config->{benchmark}) {
	    $btime=new Benchmark;
	    $timeall=timediff($btime,$atime);
	    $logger->info("Total time for stage 0a is ".timestr($timeall));
	}
	
        $logger->debug("Generation of new SessionID $self->{ID} successful");
    }
    else {
        $self->{ID}        = $sessionID;
        
        $logger->debug("Examining if SessionID $self->{ID} is valid");
        if (!$self->is_valid()){
            $logger->debug("SessionID is NOT valid");

	    if ($config->{benchmark}) {
		$btime=new Benchmark;
		$timeall=timediff($btime,$atime);
		$logger->info("Total time for stage 0b2 is ".timestr($timeall));
	    }
            
            # Wenn uebergebene SessionID nicht ok, dann neue generieren
            $self->_init_new_session();
            $logger->debug("Generation of new SessionID $self->{ID} successful");
        }
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 1 is ".timestr($timeall));
    }

    if ($self->{ID} && !$self->{sid}){
        my $search_sid = $self->get_schema->resultset('Sessioninfo')->single(
            {
                sessionid => $self->{ID},
            }
        );
        
        if ($search_sid){
            $self->{sid} = $search_sid->id;
        }
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 2 is ".timestr($timeall));
    }
    
    #$logger->debug("Session-Object created: ".YAML::Dump($self));

    return $self;
}

sub get_config {
    my $self = shift;

    return $self->{_config};
}

sub _init_new_session {
    my ($self,$r) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = $self->get_config;

    my $sessionID="";

    my $havenewsessionID=0;

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    while ($havenewsessionID == 0) {
        my $gmtime = localtime(time);
        my $md5digest=Digest::MD5->new();
    
        $md5digest->add($gmtime . rand('1024'). $$);
    
        $sessionID=$md5digest->hexdigest;

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time for stage 1 is ".timestr($timeall));
        }

        my $anzahl=$self->get_schema->resultset('Sessioninfo')->search_rs({ sessionid => $sessionID })->count;

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Total time for stage 2 is ".timestr($timeall));
        }

        # Wenn wir nichts gefunden haben, dann ist alles ok.
        if ($anzahl == 0 ) {
            $havenewsessionID=1;

	    my $createtime = Date::Manip::ParseDate("now");
            my $expiretime = Date::Manip::DateCalc($createtime,$config->{default_session_expiration});

	    $createtime = Date::Manip::UnixDate($createtime,"%Y-%m-%d %H:%M:%S");
	    $expiretime = Date::Manip::UnixDate($expiretime,"%Y-%m-%d %H:%M:%S");

            my $queryoptions = OpenBib::QueryOptions->get_session_defaults;

            my $new_session = $self->get_schema->resultset('Sessioninfo')->create(
                {
                    sessionid    => $sessionID,
                    createtime   => $createtime,
                    expiretime   => $expiretime,
                    queryoptions => encode_json($queryoptions),
                    viewname     => $self->{view},
                    searchform   => 'simple',
                }
            );

            if ($config->{benchmark}) {
                $btime=new Benchmark;
                $timeall=timediff($btime,$atime);
                $logger->info("Total time for stage 2a is ".timestr($timeall));
            }

            $self->{ID}  = $sessionID;
            $self->{sid} = $new_session->id;
        }
    }

    if ($logger->is_debug){
        $logger->debug("Request Object: ".YAML::Dump($r));
    }
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 3 is ".timestr($timeall));
    }

    $self->{_is_new_session} = 1;
    

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time for stage 4 is ".timestr($timeall));
    }

    # BEGIN View (Institutssicht)
    #
    ####################################################################
    # Wenn ein View aufgerufen wird, muss fuer die aktuelle Session
    # die Datenbankauswahl vorausgewaehlt und das Profil geaendert werden.
    ####################################################################
  
    if ($self->{view}) {
        # 1. Gibt es diesen View?
        if ($config->view_exists($self->{view})) {
            # 2. Datenbankauswahl setzen, aber nur, wenn der Benutzer selbst noch
            #    keine Auswahl getroffen hat
      

            # Wenn noch keine Datenbank ausgewaehlt wurde, dann setze die
            # Auswahl auf die zum View gehoerenden Datenbanken
            if ($self->get_number_of_dbchoice == 0) {
                my @viewdbs=$config->get_dbs_of_view($self->{view});

                $self->set_dbchoice(\@viewdbs);
            }
        }
        # Wenn es den View nicht gibt, dann wird gestartet wie ohne view
        else {
            $self->{view}="";
        }
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time is ".timestr($timeall));
    }

    return $sessionID;
}

sub is_valid {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    # Spezielle SessionID -1 ist erlaubt
    if (defined $self->{ID} && $self->{ID} eq "-1") {
        return 1;
    }

    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my $anzahl = $self->get_schema->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} },{ result_class => 'DBIx::Class::ResultClass::HashRefInflator' })->count;
    
    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Total time for validity check is ".timestr($timeall));
    }
    
    if ($anzahl == 1) {
        return 1;
    }

    return 0;
}

sub is_expired {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my ($atime,$btime,$timeall)=(0,0,0);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $sessioninfo = $self->get_schema->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} });

    my $is_expired = 0;
    
    if ($sessioninfo){	
	my $expiretstamp = $sessioninfo->first->get_column('expiretime');
	
	if ($expiretstamp){
	    my $current_time    = Date::Manip::ParseDate("now");
	    my $expiration_time = Date::Manip::ParseDate($expiretstamp);

	    my $createtime = Date::Manip::UnixDate($current_time,"%Y-%m-%d %H:%M:%S");
	    
	}
    }
    
    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Total time for validity check is ".timestr($timeall));
    }
    
    return $is_expired;
}

sub get_profile {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $prevprofile;

    # DBI: "select profile from sessionprofile where sessionid = ?"
    my $sessioninfo = $self->get_schema->resultset('Sessioninfo')->single({ sessionid => $self->{ID} });

    if ($sessioninfo){
        $prevprofile =$sessioninfo->searchprofile;
    }
    
    return $prevprofile;
}

sub get_datacache {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $current_cache;

    # DBI: "select profile from sessionprofile where sessionid = ?"
    my $sessioninfo = $self->get_schema->resultset('Sessioninfo')->single({ sessionid => $self->{ID} });

    if ($sessioninfo){
        $current_cache =$sessioninfo->datacache;
    }

    my $current_ref = {};
    
    eval {
	if ($current_cache){
	    $current_ref = decode_json $current_cache;
	}
    };

    if ($@){
	$logger->error($@);
    }
    
    return $current_ref;
}

sub set_datacache_by_key {
    my ($self,$key,$data_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Zuerst aktuelle Informationen holen ...
    my $current_ref = $self->get_datacache;

    # Reset auf leeren Hashref, wenn andere Datenstruktur im datacache
    unless (ref($current_ref) eq "HASH"){
	$current_ref = {};
    }
    
    # ... dort aktuellen Inhalt via key hinzufuegen
    $current_ref->{$key} = $data_ref;


    # ... und schliesslich wieder zurueckschreiben
    my $sessioninfo = $self->get_schema->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} });

    if ($sessioninfo){
	my $json = "{}"; # Leerer JSON-String als default
	eval {
	    $json = encode_json $current_ref;
	};
	
        $sessioninfo->update({ datacache => $json });
    }

    return;
}

sub set_datacache {
    my ($self,$data_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sessioninfo = $self->get_schema->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} });

    if ($sessioninfo){
	my $json = "{}"; # Leerer JSON-String als default
	eval {
	    $json = encode_json $data_ref;
	};
	
        $sessioninfo->update({ datacache => $json });
    }

    return;
}

sub clear_datacache {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $sessioninfo = $self->get_schema->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} });

    if ($sessioninfo){
        $sessioninfo->update({ datacache => "{}" });
    }

    return;
}

sub get_id {
    my $self = shift;

    return $self->{ID};
}

sub set_profile {
    my ($self,$profileid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sessioninfo = $self->get_schema->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} });

    if ($sessioninfo){
        $sessioninfo->update({ searchprofile => $profileid });
    }

    return;
}

sub get_resultlists_offsets {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    
    my $queryid   = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}            : undef;

    my $hitrange  = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select offset, hits from searchresults where sessionid = ? and queryid = ? and dbname = ? and hitrange = ? order by offset"
    my $history = $self->get_schema->resultset('Searchhistory')->search_rs(
        {
            'sid.sessionid' => $self->{ID},
            'me.queryid'    => $queryid,
            'me.dbname'     => $database,
            'me.hitrange'   => $hitrange,
        },
        {
            order_by => 'me.offset',
            select => [ 'me.offset', 'me.hits' ],
            as     => [ 'thisoffset', 'thishits' ],
            join => 'sid',
        }
    );

    my @offsets=();
    my $lasthits   = 0;
    my $lastoffset = 0;
    foreach my $item ($history->all){
        my $offset = $item->get_column('offset');
        my $hits   = $item->get_column('hits');
        
        push @offsets, {
            offset => $offset,
            hits   => $hits,
            start  => $offset+1,
            end    => $offset+$hits,
            type   => 'cached',
        };
        $lasthits   = $hits;
        $lastoffset = $offset;
    }

    # Eventuell noch mehr Treffer vorhanden?
    if ($lasthits == $hitrange){
        push @offsets, {
            offset => $lastoffset+$lasthits,
            type   => 'getnext',
        };
    }

    if ($logger->is_debug){
        $logger->debug("Offsets:\n".YAML::Dump(\@offsets));
    }
    
    return @offsets;
}

sub get_mask {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI ehemals: "select masktype from sessionmask where sessionid = ?"
    my $form = $self->get_schema->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} })->first->searchform;

    return ($form)?$form:'simple';
}

sub set_mask {
    my ($self,$mask)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI ehemals: "update sessionmask set masktype = ? where sessionid = ?"
    $self->get_schema->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} })->update({ searchform => $mask });

    return;
}

sub set_dbchoice {
    my ($self,$db_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;

    my $sid             =  $self->get_schema->resultset('Sessioninfo')->single({ sessionid => $self->{ID} })->id;
    my $searchprofileid =  $config->get_searchprofile_or_create($db_ref);
    
    # Datenbankverknuepfung zunaechst loeschen
    eval {
        $self->get_schema->resultset('SessionSearchprofile')->search_rs({ sid => $sid })->delete;
    };

    $self->get_schema->resultset('SessionSearchprofile')->create(
        {
            sid             => $sid,
            searchprofileid => $searchprofileid,
        }
    );
    
    return $searchprofileid;
}

sub get_dbchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $dbases = $self->get_schema->resultset('SessionSearchprofile')->search_rs(
        {
            'sid.sessionID' => $self->{ID}
        },
        {
            join   => ['sid','searchprofileid'],
            select => ['searchprofileid.id'],
            as     => ['thissearchprofileid'],
        }
    )->single();

    my @dbchoice = ();
    my $searchprofileid;
    
    if ($dbases){
        $searchprofileid   = $dbases->get_column('thissearchprofileid');

        @dbchoice = reverse $config->get_databases_of_searchprofile($searchprofileid);
            
        if ($logger->is_debug){
            $logger->debug("DB-Choice:\n".YAML::Dump(\@dbchoice));
        }
    }

        
    return {
        id        => $searchprofileid,
        databases => \@dbchoice,
    };
}

sub clear_dbchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Datenbanken zunaechst loeschen
    eval {
        $self->get_schema->resultset('SessionSearchprofile')->search_rs({ 'sid.sessionid' => $self->{ID} }, { join => 'sid' })->delete;
    };

    return;
}

sub get_number_of_dbchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @dbases = $self->get_dbchoice();

    my $numofdbs = scalar @dbases;

    return $numofdbs;
}

sub get_number_of_items_in_resultlist {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(sessionid) as rowcount from searchresults where sessionid = ?"
    my $numofresults = $self->get_schema->resultset('Searchhistory')->search_rs({ 'sid.sessionid' => $self->{ID} }, { join => 'sid' })->count;

    return $numofresults;
}

sub get_number_of_queries {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(queryid) as rowcount from queries where sessionid = ?
    my $numofqueries = $self->get_schema->resultset('Query')->search_rs({ 'sid.sessionid' => $self->{ID} }, { join => 'sid' } )->count;

    $logger->debug("Found $numofqueries queries in Session $self->{ID}");
    
    return $numofqueries;
}

sub get_last_searchquery {
    my ($self,$arg_ref)=@_;

    # Set defaults

    my $sid =   exists $arg_ref->{sid}
        ? $arg_ref->{sid}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $thissid = (defined $sid)?$sid:$self->{sid};

    my ($atime,$btime,$timeall)=(0,0,0);
    
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # DBI: "select queryid from queries where sessionid = ? order by queryid DESC "
    my $searchquery = $self->get_schema->resultset('Query')->search_rs(
        {
            'sid.id' => $thissid,
        },
        {
            select => 'me.queryid',
            as     => 'thisqueryid',
            order_by => [ 'me.queryid DESC' ],
            join => 'sid',
	    rows => 1,
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',            
        }
    )->single;

    if ($searchquery){
        $logger->debug("Found last searchquery with id ".$searchquery->{thisqueryid});
        return OpenBib::SearchQuery->new->load({sid => $thissid, queryid => $searchquery->{thisqueryid} });
    }

    return;
}

sub get_all_searchqueries {
    my ($self,$arg_ref)=@_;

    # Set defaults

    my $sid =   exists $arg_ref->{sid}
        ? $arg_ref->{sid}         : undef;

    my $num =   exists $arg_ref->{num}
        ? $arg_ref->{num}         : 10;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $thissid = (defined $sid)?$sid:$self->{sid};

    my ($atime,$btime,$timeall)=(0,0,0);
    
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # DBI: "select queryid from queries where sessionid = ? order by queryid DESC "
    my $searchqueries = $self->get_schema->resultset('Query')->search_rs(
        {
            'sid.id' => $thissid,
        },
        {
            select       => 'me.queryid',
            as           => 'thisqueryid',
            order_by     => [ 'me.queryid DESC' ],
            join         => 'sid',
	    rows         => $num,
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    my @queries=();

    foreach my $item ($searchqueries->all){
        $logger->debug("Found Searchquery with id ".$item->{thisqueryid});
        my $searchquery = OpenBib::SearchQuery->new->load({sid => $thissid, queryid => $item->{thisqueryid} });
        push @queries, $searchquery;
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Total time is ".timestr($timeall));
    }

    return @queries;
}

sub get_number_of_items_in_collection {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(*) as rowcount from treffer where sessionid = ?"
    my $count = $self->get_schema->resultset('SessionCartitem')->search_rs({ 'sid.sessionid' => $self->{ID} }, { join => 'sid' } )->count;

    return $count;
}

sub get_items_in_collection {
    my ($self,$arg_ref)=@_;

    my $queryoptions        = exists $arg_ref->{queryoptions}
        ? $arg_ref->{queryoptions}        : new OpenBib::QueryOptions;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    my $sorttype          = $queryoptions->get_option('srt');
    my $sortorder         = $queryoptions->get_option('srto');

    # Wenn srto in srt enthalten, dann aufteilen
    if ($sorttype =~m/^([^_]+)_([^_]+)$/){
        $sorttype=$1;
        $sortorder=$2;
        $logger->debug("srt Option split: srt = $1, srto = $2");
    }
    
    # Pagination parameters
    my $page              = ($queryoptions->get_option('page'))?$queryoptions->get_option('page'):1;
    my $num               = ($queryoptions->get_option('num'))?$queryoptions->get_option('num'):20;

    my $offset = $page*$num-$num;
    
    my $recordlist = new OpenBib::RecordList::Title();
    
    return $recordlist if (!defined $self->get_schema);

    # DBI: "select dbname,singleidn from treffer where sessionid = ? order by dbname"
    my $items = $self->get_schema->resultset('SessionCartitem')->search_rs(
        {
            'sid.sessionid' => $self->{ID},
        },
        {
            select => [ 'cartitemid.dbname', 'cartitemid.titleid', 'cartitemid.titlecache', 'cartitemid.id', 'cartitemid.tstamp', 'cartitemid.comment' ],
            as     => [ 'thisdbname', 'thistitleid', 'thistitlecache', 'thislistid','thiststamp','thiscomment' ],
            join   => ['sid','cartitemid'],

	    order_by => ["cartitemid.tstamp $sortorder"],

	    offset => $offset,
	    rows   => $num,
	    
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',                        
        }
    );

    foreach my $item ($items->all){
        my $database   = $item->{thisdbname};
        my $titleid    = $item->{thistitleid};
        my $titlecache = $item->{thistitlecache};
        my $listid     = $item->{thislistid};
        my $tstamp     = $item->{thiststamp};
        my $comment    = $item->{thiscomment};

	if ($logger->is_debug()){
	    $logger->debug("Found Cartitem - DB: $database / ID: $titleid / Cache:$titlecache");
	}

        my $record;	
	my $record_exists = 0;

	# Record fuer die Anzeige aus Performance-Gruenden immer aus Titlecache
        if ($titlecache){
            eval {
  	      $record = OpenBib::Record::Title->new({ date => $tstamp, listid => $listid, comment => $comment, config => $config })->from_json($titlecache);
              # $record->set_status('from_cache',1);

              $record_exists = $record->record_exists;
	      $logger->debug("Trying titlecache $titlecache : Records Exists? $record_exists");
            };

	    if ($@){
		$logger->error($@);
	    }
        }

	# Titelcache nicht vorhanden oder Verarbeitung fehlgeschlagen, dann Titel per DB/ID referenziert. Laden aus der DB
	
        if (!$record_exists && $titleid && $database){
            eval {
		$record = OpenBib::Record::Title->new({id =>$titleid, database => $database, date => $tstamp, listid => $listid, comment => $comment, config => $config })->load_full_record;
		$record_exists = $record->record_exists;
		
		$logger->debug("Trying DB: $database / ID: $titleid : Records Exists? $record_exists");
	    };

	    if ($@){
		$logger->error($@);
	    }
        }

        # Weder in DB vorhanden, noch gecached? Dann leerer Record
        if (!$record_exists && $titleid && $database){
	    $record = OpenBib::Record::Title->new({id => $titleid, database => $database, date => $tstamp, listid => $listid, comment => $comment, config => $config });
	    $logger->debug("Record with DB: $database / ID: $titleid is empty");
        }
        elsif (!$record_exists) {
	    $record = OpenBib::Record::Title->new({ date => $tstamp, listid => $listid, comment => $comment, config => $config });
	    $logger->debug("Record without DB / ID is empty");
        }

        $recordlist->add($record);
    }

    return $recordlist;
}

sub get_single_item_in_collection {
    my ($self,$listid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $cartitem = $self->get_schema->resultset('SessionCartitem')->search_rs(
        {
            'cartitemid.id' => $listid,
            'sid.sessionid'       => $self->{ID},
        },
        {
            select => [ 'cartitemid.dbname', 'cartitemid.titleid', 'cartitemid.titlecache'],
            as     => [ 'thisdbname', 'thistitleid', 'thistitlecache' ],
            join   => ['sid','cartitemid'],
        }
    )->single;

    if ($cartitem){
        my $database   = $cartitem->get_column('thisdbname');
        my $titleid    = $cartitem->get_column('thistitleid');
        my $titlecache = $cartitem->get_column('thistitlecache');
        
        my $record = new OpenBib::Record::Title({ database => $database, id => $titleid, listid => $listid});
        
        return $record;
    }
    
    return;
}

sub add_item_to_collection {
    my ($self,$arg_ref)=@_;

    my $dbname       = exists $arg_ref->{dbname}
        ? $arg_ref->{dbname}               : undef;
    
    my $titleid      = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}              : undef;
    
    my $comment      = exists $arg_ref->{comment}
        ? $arg_ref->{comment}              : '';
    
    my $record       = exists $arg_ref->{record}
        ? $arg_ref->{record}               : undef;
        
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $new_title;
    
    if ($dbname && $titleid){
	$logger->debug("Adding by dbname/titleid: $dbname/$titleid");
        # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
        
        # DBI: "select count(userid) as rowcount from collection where userid = ? and dbname = ? and titleid = ?"
        my $have_title = $self->get_schema->resultset('SessionCartitem')->search_rs(
            {
                'sid.id'             => $self->{sid},
                'cartitemid.dbname'  => $dbname,
                'cartitemid.titleid' => $titleid,
            },
            {
                join => ['sid','cartitemid'],
            }
        )->count;
        
        if (!$have_title) {
            my $cached_title = new OpenBib::Record::Title({ database => $dbname , id => $titleid});
            my $record_json = $cached_title->load_full_record->to_json;
            
            $logger->debug("Adding Title to Collection: $cached_title");
            
            # DBI "insert into treffer values (?,?,?,?)"
            $new_title = $self->get_schema->resultset('Cartitem')->create(
                {
                    dbname     => $dbname,
                    titleid    => $titleid,
                    titlecache => $record_json,
                    comment    => $comment,
                    tstamp     => \'NOW()',
                }
            );

            $self->get_schema->resultset('SessionCartitem')->create(
                {
                    sid              => $self->{sid},
                    cartitemid => $new_title->id,
                }
            );
        }
        else {
            $logger->debug("Collection item exists");
        }
    }
    elsif ($record){
	$logger->debug("Adding by json-encoded record");

        # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
        
        my $record_json = encode_json $record;
        
        # DBI: "select count(userid) as rowcount from collection where userid = ? and dbname = ? and titleid = ?"
        my $have_title = $self->get_schema->resultset('SessionCartitem')->search_rs(
            {
                'sid.id'                => $self->{sid},
                'cartitemid.titlecache' => $record_json,
            },
            {
                join => ['sid','cartitemid'],
            }
        )->count;
        
        if (!$have_title) {
            $logger->debug("Adding Title to Collection: $record_json");
            
            # DBI "insert into treffer values (?,?,?,?)"
            $new_title = $self->get_schema->resultset('Cartitem')->create(
                {
                    titleid    => 0,
                    dbname     => '',
                    titlecache => $record_json,
                    comment    => $comment,
                    tstamp     => \'NOW()',
                }
            );

            $self->get_schema->resultset('SessionCartitem')->create(
                {
                    sid        => $self->{sid},
                    cartitemid => $new_title->id,
                }
            );
         }
    }

    if ($new_title){
        return $new_title->id;
    }

    return;
}

# Aktualisiert werden kann nur der Kommentar!
sub update_item_in_collection {
    my ($self,$arg_ref)=@_;

    my $itemid         = exists $arg_ref->{id}
        ? $arg_ref->{id}                    : undef;

    my $comment      = exists $arg_ref->{comment}
        ? $arg_ref->{comment}              : '';
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    if ($itemid){
        # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
        
        # DBI: "select count(userid) as rowcount from collection where userid = ? and dbname = ? and titleid = ?"
        my $title = $self->get_schema->resultset('Cartitem')->search_rs(
            {
                'session_cartitemids.sessionid'  => $self->{ID},
                'me.id'                                => $itemid,
            },
            {
                join => ['session_cartitemids'],
            }
        );
        
        if ($title) {
            $title->update(
                {
                    comment    => $comment,
                    tstamp     => \'NOW()',
                }
            );
        }
    }

    return ;
}

sub delete_item_from_collection {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $itemid        = exists $arg_ref->{id}
        ? $arg_ref->{id}                 : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (!$itemid){
        return;
    }

    $logger->debug("Deleting item $itemid");

    eval {
        # DBI: "delete from treffer where sessionid = ? and dbname = ? and singleidn = ?"
        my $item = $self->get_schema->resultset('Cartitem')->search_rs(
            {
                'session_cartitems.sid' => $self->{sid},
                'me.id'                       => $itemid
            },
            {
                join => ['session_cartitems']
            }
        )->single;

        if ($item){
            $item->session_cartitems->delete;
            $item->delete;
        }
        else {
            $logger->debug("Can't delete Item $itemid: ".$@);
        }
    };

    if ($@){
        $logger->error($@);
    }
    
    return;
}

sub updatelastresultset {
    my ($self,$resultset_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @resultset=@$resultset_ref;

    my @nresultset=();

    foreach my $outidx_ref (@resultset) {
        my %outidx=%$outidx_ref;

        # Eintraege merken fuer Lastresultset
        my $katkey      = (exists $outidx{id})?$outidx{id}:"";
        my $resdatabase = (exists $outidx{database})?$outidx{database}:"";

	$logger->debug("Katkey: $katkey - Database: $resdatabase");

        push @nresultset, {
            database => $resdatabase,
            id       => $katkey,
        };
    }

    my $resultsetstring=encode_json(\@nresultset); #

    # DBI: "update session set lastresultset = ? where sessionid = ?"
    $self->get_schema->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} })->update({ lastresultset => $resultsetstring });

    return;
}

sub save_eventlog_to_statisticsdb {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Saving Evenlog of Session $self->{ID}");
    
    # Zuerst Statistikdaten in Statistik-Datenbank uebertragen,
    my $statistics = OpenBib::Statistics->instance;

    my $view = $self->{view};

    my $useragent = "";

    eval {
        $useragent = $self->get_schema->resultset('Eventlog')->search_rs(
            {
                'sid.sessionid' => $self->{ID},
                'me.type' => 101,
            },
            {
                select => 'me.content',
                as     => 'thisua',
                join => 'sid'
            }
        )->single->get_column('thisua');
    };

    # Ignore robots
    my $browser = HTTP::BrowserDetect->new($useragent);

    if ($browser->robot()){
       $logger->info("Not saving session ".$self->{ID}." to statisticsdb with useragent $useragent");
       return;
    }

    # Rudimentaere Session-Informationen uebertragen
    my $sessioninfo = $self->get_schema->resultset('Sessioninfo')->search_rs(
        {
            sessionid => $self->{ID},
        }
    )->single;

    $logger->debug("Create new session in statistics db");

    my $new_sid = $statistics->create_session({
        sessionid  => $self->{ID},
        createtime => $sessioninfo->createtime,
        viewname   => $view,
    });
    
    $logger->debug("Copy default events from active session to new session in statistics db");

    # Alle skalaren Events in Statistics-DB uebertragen
    foreach my $event ($sessioninfo->eventlogs->all){
        my $tstamp        = $event->tstamp;
        my $type          = $event->type;
        my $content       = $event->content;

        # Nutzer-IP's - falls aufgezeichnet - anonymisieren, indem letztes Octet auf Null gesetzt wird.
        if ($type == 102){
            $content =~s/\d+$/0/;
        }
        
        $statistics->log_event({
            sid       => $new_sid,
            tstamp    => $tstamp,
            type      => $type,
            content   => $content,
        });
    }

    $logger->debug("Copy json events from active session to new session in statistics db");

    # Alle Events im JSON-Format in Statistics-DB uebertragen
    foreach my $event ($sessioninfo->eventlogjsons->all){
        my $tstamp        = $event->tstamp;
        my $type          = $event->type;
        my $content       = $event->content;

        $statistics->log_event({
            sid       => $new_sid,
            tstamp    => $tstamp,
            type      => $type,
#            content   => decode_utf8($content),
            content   => $content,
            serialize => 1, # in Eventlogjson
        });
        
	if ($type == 1){
            my $searchquery_ref = {};
  
            # Quotes von Postgresql entfernen
            $content=~s/\\\\/\\/g;

            eval {
                $searchquery_ref = decode_json encode_utf8($content);
            };

            if ($@){
                $logger->error("Error decoding JSON content: $@");
                $logger->error("Query: $content");
            }
            
            $statistics->log_query({
                sid             => $new_sid,
                tstamp          => $tstamp,
                view            => $view,
                searchquery_ref => $searchquery_ref,
            });
	}
    }

    $logger->debug("Write title usage stats from active session to new session in statistics db");

    # Relevanz-Daten vom Typ 2 (Einzeltrefferaufruf)
    # DBI: "select tstamp,content from eventlog where sessionid = ? and type=10"
    my $records = $sessioninfo->eventlogjsons->search_rs(
        {
            'type' => 10,
        },
    );

    my ($wkday,$month,$day,$time,$year) = split(/\s+/, localtime);
    
    my %seen_title=();

    foreach my $item ($records->all){
        my $tstamp        = $item->tstamp;
        my $content       = $item->content;

        $logger->debug("Content: $content");
        
        my $content_ref   = {} ;

        eval {
            $content_ref = decode_json $content;
        };

        if ($@){
            $logger->error("Error decoding JSON content: $@");
        }

        my $isbn          = $content_ref->{isbn};
        my $dbname        = $content_ref->{database};
        my $titleid       = $content_ref->{titleid} || $content_ref->{id};

	next if (exists $seen_title{"$dbname:$titleid"});

        $statistics->store_titleusage({
            tstamp   => $tstamp,
            sid      => $new_sid,
            viewname => $view,
            isbn     => $isbn,
            dbname   => $dbname,
            titleid  => $titleid,
            origin   => 1,
        });

	$seen_title{"$dbname:$titleid"}=1;
    }

    return;
}

sub clear_data {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    # Wenn Statistik-DB aktiviert ist, werden alle Sessiondaten in der Statistik-DB anonymisiert archiviert, sonst effektiv verworfen
    if ($config->{active_statisticsdb}){
        $self->save_eventlog_to_statisticsdb;
    }
	
    # Sessiondaten loeschen
    my $sessioninfo = $self->get_schema->resultset('Sessioninfo')->single({ 'sessionid' => $self->{ID} });
	
    if ($sessioninfo){
	$logger->debug("Trying to clear data for sessionID ".$sessioninfo->sessionid);
	    
	eval {
		$sessioninfo->eventlogs->delete;
		$sessioninfo->eventlogjsons->delete;
		$sessioninfo->queries->delete;
		$sessioninfo->recordhistories->delete;
		$sessioninfo->searchhistories->delete;
		#            $sessioninfo->session_cartitems->cartitemid->delete;
		$sessioninfo->session_cartitems->delete;
		$sessioninfo->session_searchprofiles->delete;
		$sessioninfo->user_sessions->delete;
		$sessioninfo->delete;
	};
	    
	if ($@){
		$logger->fatal("Problem clearing session $self->{ID}: $@");
	}
    }
	
    return;
}

sub log_event {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $type         = exists $arg_ref->{type}
        ? $arg_ref->{type}               : undef;
    
    my $content      = exists $arg_ref->{content}
        ? $arg_ref->{content}            : undef;

    my $serialize = exists $arg_ref->{serialize}
        ? $arg_ref->{serialize}          : 0;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $contentstring = $content;

    if ($serialize){
	eval {
	    $contentstring= JSON::XS->new->utf8->canonical->encode($content);
	};

	if ($@){
	    $logger->error("Canonical Encoding failed: ".YAML::Dump($content));
	}
    }
    
    # Moegliche Event-Typen
    #
    # Recherchen:
    #   1 => Recherche-Anfrage bei Virtueller Recherche
    #  10 => Eineltrefferanzeige
    #  11 => Verfasser-Normdatenanzeige
    #  12 => Koerperschafts-Normdatenanzeige
    #  13 => Notations-Normdatenanzeige
    #  14 => Schlagwort-Normdatenanzeige
    #  20 => Rechercheart (einfach=1,komplex=2, externer Suchschlitz=3)
    #  21 => Recherche-Backend (sql,xapian,z3950)
    #  22 => Recherche-Einstieg ueber Connector (1=DigiBib)
    #
    # Allgemeine Informationen
    # 100 => View
    # 101 => Browser
    # 102 => IP des Klienten (obsolet durch DSGVO)
    # Redirects 
    # 500 => TOC / hbz-Server
    # 501 => TOC / ImageWaere-Server
    # 502 => USB E-Books / Vollzugriff
    # 503 => Nationallizenzen / Vollzugriff
    # 510 => BibSonomy
    # 520 => Wikipedia / Personen
    # 521 => Wikipedia / ISBN
    # 530 => EZB
    # 531 => DBIS
    # 532 => Kartenkatalog Philfak
    # 533 => MedPilot
    # 540 => HBZ-Monofernleihe
    # 541 => HBZ-Dokumentenlieferung
    # 550 => WebOPAC
    # 560 => DFG-Viewer
    #
    # 800 => Aufruf Literaturliste
    # 801 => Aufruf RSS-Feeds
    # 802 => Aufruf PermaLink Titel
    # 803 => Aufruf PermaLink Literaturliste
    # 804 => Aufruf Liste zu Tag
    
    my $log_only_unique_ref = {
			     10 => 1,
			    };
    
    if (exists $log_only_unique_ref->{$type}){        
        # DBI: "delete from eventlog where sessionid=? and type=? and content=?"
        eval {
            $self->get_schema->resultset('Eventlog')->search_rs({ 'sid.sessionid' => $self->{ID}, 'me.type' => $type, 'me.content' => $contentstring},{ join => 'sid' })->delete_all;
        };

	if ($@){
	    $logger->error("Error logging unique event: sessionid/type/content = ".$self->{ID}."/$type/$contentstring");
	}
    }
    
    $logger->debug("Getting sid for SessionID ".$self->{ID});
    my $sid = $self->get_schema->resultset('Sessioninfo')->single({ 'sessionid' => $self->{ID} })->id;

    # DBI: "insert into eventlog values (?,NOW(),?,?)"
    if ($serialize){
        # Backslashes Escapen fuer PostgreSQL!!!
        #$contentstring=~s/\\/\\\\/g;

        $self->get_schema->resultset('Eventlogjson')->populate([{ sid => $sid, tstamp => \'NOW()', type => $type, content => $contentstring }]);
    }
    else {
        $self->get_schema->resultset('Eventlog')->populate([{ sid => $sid, tstamp => \'NOW()', type => $type, content => $contentstring }]);
    }
    
    return;
}

# sub get_queryid {
#     my ($self,$arg_ref)=@_;

#     # Set defaults
#     my $databases_ref      = exists $arg_ref->{databases}
#         ? $arg_ref->{databases}               : undef;
    
#     my $hitrange           = exists $arg_ref->{hitrange}
#         ? $arg_ref->{hitrange}                : undef;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     my $searchquery = OpenBib::SearchQuery->new;

#     my $queryid            = 0;
#     my $queryalreadyexists = 0;

#     # Wenn man databases_ref hier sortiert und in VirtualSearch.pm sortiert, dann koennen anhand von Suchanfrage und Datenbankauswahl auch
#     # bei gleicher aber permutierter Datenbankliste die entsprechende queryid gefunden werden, allerdings kann man dann
#     # diese Liste nicht mehr fuer wiederholte Anfrage (Listentyp) verwenden, da sich dann
#     # durch die Sortierung die Reihenfolge geaendert hat. Daher wird hier nicht mehr sortiert
#     my $dbasesstring=join("||",@{$databases_ref});

#     my $query_obj_string = $searchquery->to_json;

#     # DBI: "select count(*) as rowcount from queries where query = ? and sessionid = ? and dbases = ? and hitrange = ?"
#     my $rows = $self->get_schema->resultset('Query')->search({ 'sid.sessionid' => $self->{ID}, 'me.query' => $query_obj_string, 'me.dbases' => $dbasesstring, 'me.hitrange' => $hitrange },{ join => 'sid' })->count;

#     my $sid = $self->get_schema->resultset('Sessioninfo')->single({ 'sessionid' => $self->{ID} })->id;

#     # Neuer Query
#     if ($rows <= 0) {
#         # Abspeichern des Queries bis auf die Gesamttrefferzahl
#         # DBI: "insert into queries (queryid,sessionid,query,hitrange,dbases) values (NULL,?,?,?,?)"
        
#         $self->get_schema->resultset('Query')->insert({ queryid => 'NULL', sid => $sid, query => $query_obj_string, hitrange => $hitrange, dbases => $dbasesstring });
#     }
#     # Query existiert schon
#     else {
#         $queryalreadyexists=1;
#     }

#     # DBI: "select queryid from queries where query = ? and sessionid = ? and dbases = ? and hitrange = ?"
#     $queryid = $self->get_schema->resultset('Query')->search({ 'sid.sessionid' => $self->{ID}, 'me.query' => $query_obj_string, 'me.dbases' => $dbasesstring, 'me.hitrange' => $hitrange },{ join => 'sid', select => 'me.queryid', as => 'thisqueryid' })->single->get_column('thisqueryid');

#     return ($queryalreadyexists,$queryid);
# }

sub set_hits_of_query {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $queryid      = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}               : undef;
    
    my $hits         = exists $arg_ref->{hits}
        ? $arg_ref->{hits}                  : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "update queries set hits = ? where queryid = ?"
    $self->get_schema->resultset('Query')->search({ queryid => $queryid })->update({ hits => $hits });

    return;
}

sub set_all_searchresults {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $queryid          = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}               : undef;

    my $results_ref      = exists $arg_ref->{results}
        ? $arg_ref->{results}               : undef;

    my $dbhits_ref       = exists $arg_ref->{dbhits}
        ? $arg_ref->{dbhits}                : undef;

    my $hitrange         = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sid = $self->get_schema->resultset('Sessioninfo')->single({ 'sessionid' => $self->{ID} })->id;

    foreach my $db (keys %{$results_ref}) {
        my $res=$results_ref->{$db};

        my $storableres= ""; #unpack "H*",Storable::freeze($res);

        # DBI: "insert into searchresults values (?,?,0,?,?,?,?)"
        $self->get_schema->resultset('Searchhistory')->insert(
            {
                sid          => $sid,
                dbname       => $db,
                hitrange     => $hitrange,
                searchresult => $storableres,
                hits         => $dbhits_ref->{$db},
                queryid      => $queryid,
                offset       => 0,
            }
        );

        if ($logger->is_debug){
            $logger->debug("YAML-Dumped: ".YAML::Dump($res));
        }
    }

    return;
}

sub set_searchresult {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $queryid          = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}               : undef;

    my $recordlist       = exists $arg_ref->{recordlist}
        ? $arg_ref->{recordlist}            : undef;

    my $database         = exists $arg_ref->{database}
        ? $arg_ref->{database}              : undef;

    my $offset           = exists $arg_ref->{offset}
        ? $arg_ref->{offset}                : undef;
    
    my $hitrange         = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sid = $self->get_schema->resultset('Sessioninfo')->single({ 'sessionid' => $self->{ID} })->id;

    eval {
        # DBI: "delete from searchresults where sessionid = ? and queryid = ? and dbname = ? and offset = ? and hitrange = ?"
        $self->get_schema->resultset('Searchhistory')->search(
            {
                sid          => $sid,
                dbname       => $database,
                hitrange     => $hitrange,
                queryid      => $queryid,
                offset       => $offset,
            }
        )->delte;
    };

    my $storableres=unpack "H*",Storable::freeze($recordlist);
    
    if ($logger->is_debug){
        $logger->debug("YAML-Dumped: ".YAML::Dump($recordlist));
    }
    
    my $num=$recordlist->get_size();

    # DBI: "insert into searchresults values (?,?,?,?,?,?,?)"
    $self->get_schema->resultset('Searchhistory')->insert(
        {
            sid          => $sid,
            dbname       => $database,
            hitrange     => $hitrange,
            searchresult => $storableres,
            hits         => $num,
            queryid      => $queryid,
            offset       => $offset,
        }
    );

    return;
}

sub get_searchresult {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $queryid          = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}               : undef;

    my $database         = exists $arg_ref->{database}
        ? $arg_ref->{database}              : undef;

    my $offset           = exists $arg_ref->{offset}
        ? $arg_ref->{offset}                : undef;
    
    my $hitrange         = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sid = $self->get_schema->resultset('Sessioninfo')->single({ 'sessionid' => $self->{ID} })->id;

    # DBI: "select searchresult from searchresults where sessionid = ? and queryid = ? and dbname = ? and offset = ? and hitrange = ?"
    my $searchresult = $self->get_schema->resultset('Searchhistory')->search(
        {
            sid          => $sid,
            dbname       => $database,
            hitrange     => $hitrange,
            queryid      => $queryid,
            offset       => $offset,
        }
    )->single->searchresult;

    my $recordlist = new OpenBib::RecordList::Title;

    if ($searchresult){
        $logger->debug("Suchergebnis vorhanden: $searchresult");
        $recordlist=Storable::thaw(pack "H*", $searchresult);
    }

    if ($logger->is_debug){
        $logger->debug("Suchergebnis: ".YAML::Dump($recordlist));
    }

    return $recordlist;
}

sub get_db_histogram_of_query {
    my ($self,$queryid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->new;

    my $sid = $self->get_schema->resultset('Sessioninfo')->single({ 'sessionid' => $self->{ID} })->id;

    # DBI "select dbname,sum(hits) as hitcount from searchresults where sessionid = ? and queryid = ? group by dbname order by hitcount desc"
    my $searchresult = $self->get_schema->resultset('Searchhistory')->search(
        {
            sid          => $sid,
            queryid      => $queryid,
        },
        {
            select => [ 'dbname', { sum => 'hits' }],
            as     => [ 'thisdbname', 'thiscount'],
            group_by => 'dbname',
#            order_by => [ 'thiscount desc' ],
        }
    );

    my $hitcount=0;
    my @resultdbs=();

    foreach my $item ($searchresult->all){
        push @resultdbs, {
            trefferdb     => decode_utf8($item->get_column('thisdbname')),
            trefferdbdesc => $dbinfotable->get('dbnames')->{decode_utf8($item->get_column('thisdbname'))},
            trefferzahl   => decode_utf8($item->get_column('thiscount')),
        };
        $hitcount+=$item->get_column('thiscount');
    }

    # Rueckgabe: 
    return (\@resultdbs,$hitcount);
}

sub get_lastresultset {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Bestimmen des vorigen und naechsten Treffer einer
    # vorausgegangenen Kurztitelliste

    # DBI: select lastresultset from session where sessionid = ?
    my $thissession = $self->get_schema->resultset('Sessioninfo')->single({ sessionid => $self->{ID} });		    
    my $lastresultset = "";

    if ($thissession){
       $lastresultset = $thissession->lastresultset;
    }

    return $lastresultset;
}

sub set_user {
    my ($self,$user)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "update session set benutzernr = ? where sessionID = ?"
    $self->get_schema->resultset('Sessioninfo')->search({ sessionid => $self->{ID} })->update({ username => $user });

    return;
}

sub set_token {
    my ($self,$token)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->get_schema->resultset('Sessioninfo')->search({ sessionid => $self->{ID} })->update({ usertoken => $token });

    return;
}

sub logout_user {
    my ($self,$user)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    eval {
        $self->get_schema->resultset('Sessioninfo')->search({ sessionid => $self->{ID}, username => $user })->delete;
    };

    return;
}

sub is_authenticated_as {
    my ($self,$user)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(*) as rowcount from session where benutzernr = ? and sessionid = ?"
    my $count = $self->get_schema->resultset('Sessioninfo')->search({ sessionid => $self->{ID}, username => $user })->count;

    # Authorized as    : 1
    # not Authorized as: 0
    return ($count <= 0)?0:1;
}

sub get_number_of_all_active_sessions {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select * from session order by createtime"
    return $self->get_schema->resultset('Sessioninfo')->count;
}

sub get_info_of_all_active_sessions {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $offset   = exists $arg_ref->{offset}
        ? $arg_ref->{offset}            : 0;
    my $num      = exists $arg_ref->{num}
        ? $arg_ref->{num}               : 20;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select * from session order by createtime"
    my $sessioninfos = $self->get_schema->resultset('Sessioninfo')->search(
        undef,
        {
            order_by => 'createtime DESC',
            offset   => $offset,
            rows     => $num,
        }
    );
    
    my @sessions=();

    foreach my $item ($sessioninfos->all){
        my $id              = $item->id;
        my $singlesessionid = $item->sessionid;
        my $viewname        = $item->viewname;
        my $createtime      = $item->createtime;
        my $username        = $item->username;
        my $numqueries      = $item->queries->count; #$self->get_schema->resultset('Query')->search({ 'sid.sessionid' => $singlesessionid }, { join => 'sid' })->count;

        if (!$username) {
            $username="Anonym";
        }

        push @sessions, {
            id              => $id,
            viewname        => $viewname,
            sessionid       => $singlesessionid,
            createtime      => $createtime,
            username        => $username,
            numqueries      => $numqueries,
        };
    }

    return @sessions;
}

sub get_info {
    my ($self,$sessionid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $singlesessionid=(defined $sessionid)?$sessionid:$self->{ID};
    
    # DBI: "select * from session where sessionID = ?"
    my $sessioninfos = $self->get_schema->resultset('Sessioninfo')->single({ sessionid => $singlesessionid });

    my $createtime;
    my $username;
    
    if ($sessioninfos){
        $createtime = $sessioninfos->createtime;
        $username   = $sessioninfos->username;
    }
    
    return ($username,$createtime);
}

sub log_new_session_once {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $r                = exists $arg_ref->{r}
        ? $arg_ref->{r}                 : undef;

    my $representation   = exists $arg_ref->{representation}
        ? $arg_ref->{representation}    : undef;

    return unless ($self->{_is_new_session});
    
    # Loggen des Brower-Types
    $self->log_event({
        type      => 101,
        content   => $r->user_agent,
    });
    
    # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
    # Client-IP setzen

    my $remote_ip = $r->remote_host || '';

    my $forwarded_for = $r->header('X-Forwarded-For');
    
    if (defined $forwarded_for && $forwarded_for =~ /([^,\s]+)$/) {
        $remote_ip = $1;
    }
    
    if ($self->{view}) {
        # Loggen der View-Auswahl
        $self->log_event({
            type      => 100,
            content   => $self->{view},
        });
    }

    if ($representation) {
        # Loggen der Repraesentation (json, rss usw.) beim Start
        $self->log_event({
            type      => 24,
            content   => $representation,
        });
    }
    
    $self->{_is_new_session} = 0;
    
    return;
}

sub get_recently_selected_titles {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $offset   = exists $arg_ref->{offset}
        ? $arg_ref->{offset}            : 0;
    my $hitrange = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : 50;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select content from eventlog where sessionid=? and type=10 order by tstamp DESC limit $offset,$hitrange"
    my $lastrecords = $self->get_schema->resultset('Eventlogjson')->search(
        {
            'sid.sessionid' => $self->{ID},
            'me.type' => 10
        },
        {
            select => ['me.content'],
            as => ['thiscontent'],
            join => 'sid',
            order_by => ['me.tstamp DESC'],
            group_by => ['me.content','me.tstamp'],
            limit => "$offset,$hitrange",
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',            
        }
    );

    $logger->debug("Got ".($lastrecords->count)." titles for sid/sessionID ".$self->{sid}."/".$self->{ID});
    
    my $recordlist = new OpenBib::RecordList::Title;

    my $have_item_ref = {};
    foreach my $item ($lastrecords->all){
        my $thiscontent = $item->{thiscontent};
        my $record_ref = {};
		    
	eval {
            $logger->debug("Got ".$item->{thiscontent});
            $record_ref = decode_json $item->{thiscontent};
        };

        next if (defined $have_item_ref->{$record_ref->{database}.$record_ref->{id}});

        if ($@){
            $logger->error("Error decoding JSON $@ ".$item->{thiscontent});
        }
        
	my $record = OpenBib::Record::Title->new->from_hash($record_ref);
        $recordlist->add(OpenBib::Record::Title->new->from_hash($record_ref));

	$have_item_ref->{$record_ref->{database}.$record_ref->{id}} = 1;

    }

    $logger->debug($recordlist);
    return $recordlist;
}

sub get_authenticator {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: select type from user_session,authenticator where user_session.sessionid = ? and user_session.targetid = authenticator.targetid"
    my $authenticator = $self->get_schema->resultset('Authenticatorinfo')->search_rs(
        {
            'sid.sessionid' => $self->{ID},
        },
        {
            join   => ['user_sessions',{ 'user_sessions' => 'sid' }],
        }
            
    )->first;

    return $authenticator;
}

sub get_schema {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Getting Schema $self");
    
    if (defined $self->{schema}){
        $logger->debug("Reusing Schema $self");
        return $self->{schema};
    }

    if (defined $self->{_config}){
        $logger->debug("Reusing Config-Schema ".$self->get_config);
        return $self->get_config->get_schema;        
    }
    
    $logger->debug("Creating new Schema $self");    
    
    $self->connectDB;
    
    return $self->{schema};
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = $self->get_config;
    
    # UTF8: {'pg_enable_utf8'    => 1}
    if ($config->{'systemdbsingleton'}){
        eval {        
            my $schema = OpenBib::Schema::System::Singleton->instance;
            $self->{schema} = $schema->get_schema;
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $config->{systemdbname}");
        }
    }
    else {
        eval {        
            $self->{schema} = OpenBib::Schema::System->connect("DBI:Pg:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd},$config->{systemdboptions}) or $logger->error_die($DBI::errstr);
            
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $config->{systemdbname}");
        }
    }
        
    
    return;
}

sub disconnectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Try disconnecting from System-DB $self");
    
    if (defined $self->{schema}){
        eval {
            $logger->debug("Disconnect from System-DB now $self");
            $self->{schema}->storage->disconnect;
            delete $self->{schema};
        };

        if ($@){
            $logger->error($@);
        }
    }
    
    return;
}

sub DESTROY {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Destroying Session-Object $self");

    if (defined $self->{schema}){
        $self->disconnectDB;
    }

    return;
}

1;
__END__

=head1 NAME

OpenBib::Session - Session-Objekt

=head1 DESCRIPTION

Dieses Objekt verwaltet eine Session im Portal

=head1 SYNOPSIS

 use OpenBib::Session;

=head1 METHODS

=over 4

=item new({ sessionID => $sessionID [, config => $config] })

Erzeugung des Objektes. Um ein bestehendes Config-Objekt wiederzuverwenden, kann
dieses als optionaler Parameter übergeben werden.

=item _init_new_session

Private Methode zur Erzeugung einer neuen Session.

=item is_valid

Liefert einen wahren Wert zurück, wenn die Session existiert.

=item get_viewname

Liefert den in dieser Session verwendeten View $viewname zurück.

=item get_profile

Liefert das in dieser Session verwendeten systemweite Katalog-Profil
$profile zurück.

=item set_profile($profile)

Setzt das systemweite Katalog-Profil $profile für die Session.

=item get_resultlists_offsets({ database => $database, queryid => $queryid, hitrange => $hitrange})

Liefert eine Liste der Offsets einer in der Session
zwischengespeicherten Trefferergebnisliste spezifiziert durch
$database, $queryid und $hitrange zurück.

=item get_mask

Liefert den aktuellen Typ der Recherchemaske (simple, advanced) in der
Session zurück.

=item set_mask($mask)

Setzt den aktuellen Typ der Recherchemaske (simple,advanced) in der
Session auf $mask.

=item set_view($view)

Setzt den aktuellen View (simple,advanced) in der Session auf $view.

=item set_dbchoice($dbname)

Fügt die Datenbank $dbname der aktuellen Datenbankauswahl hinzu.

=item get_dbchoice

Liefert eine umgekehrt alphabetisch sortierte Liste der ausgewählten
Datenbanken zurück.

=item clear_dbchoice

Löscht die aktuelle Datenbankauswahl.

=item get_number_of_dbchoice

Liefert die Anzahl ausgewählter Datenbanken zurück.

=item get_number_of_item_in_resultlist

Liefert die Anzahl der zwischengespeicherten Trefferlisten zurück.

=item get_items_in_resultlist_per_db({ database => $database, queryid => $queryid, offset => $offset, hitrange => $hitrange })

Liefert die zwischengespeicherten Treffer zur Anfrage $queryid in der
Datenbank $database - optional mit Offset $offset - als Liste zurück.

=item get_all_items_in_resultlist({ queryid => $queryid })

Liefert alle zwischengespeicherten Treffer zur Anfrage $queryid als
Liste aufgeschlüsselt als Hashreferenz mit dbname und searchresult
zurück.

=item get_max_queryid

Liefert die maximal vergebene Query-Identifikationsnummer zurück.

=item get_all_searchqueries({ sessionid => $sessionid, offset => $offset })

Liefert eine Liste aller in der Session ausgeführten Suchanfragen als
Hashreferenz mit den Inhalten Query-ID id, Suchanfrage searchquery,
gefundene Treffer hits sowie durchsuchte Datenbanken $dbases zurück.

=item get_number_of_items_in_collection

Liefert die Anzahl der Merklisteneinträge zurück.

=item get_items_in_collection

Liefert ein RecordList::Title-Objekt mit den Einträgen in der
Merkliste zurück.

=item set_item_in_collection({ database => $database, id => $id })

Fügt den Titel mit der Id $id in der Datenbank $database zur Merkliste
hinzu.

=item clear_item_in_collection({ database => $database, id => $id })

Löscht den Titel mit der Id $id in der Datenbank $database aus der
Merkliste.

=item updatelastresultset($resultset_ref)

Aktualisiert die Treffer-Informationen (Datenbank:Id) zur letzten Suchanfrage.

=item save_eventlog_to_statisticsdb

Speichert das Eventlog der aktuellen Session in der
Statistik-Datenbank (ausgelagert von clear_data)

=item clear_data

Daten der aktuellen Session werden aus der Session-Datenbank entfernt
und das Eventlog über save_eventlog_to_statisticsdb in der
Statistik-Datenbank gesichert.

=item log_event({ type => $type, content => $content, serialize => $serialize })

Speichert das Event des Typs $type mit dem Inhalt $content in der
aktuellen Session. Handelt es sich bei $content um eine Referenz einer
komplexen Datenstruktur, dann muss zusätzlich serialize gesetzt werden.

=item get_query_id({ databases => $databases_ref, hitrange => $hitrange})

Liefert zur letzten Suchanfrage über die Datenbanken $databases_ref
mit der Schrittweite $hitrange das Listenpaar mit (Query existiert
schon, zugehörige Query-Id).

=item set_hits_of_query({ queryid => $queryid, hits => $hits})

Setzt für die Suchanfrage mit Query-ID $queryid die Trefferzahl auf $hits.

=item set_all_searchresults({ queryid => $queryid, results => $results_ref, dbhits => $dbhits_ref, hitrange => $hitrange })

Speichert alle Suchergebnisse $results_ref zur Query-ID $queryid mit
den Trefferzahlen $dbhits_ref und der aktuellen Schrittweite $hitrange
in der aktuellen Session.

=item set_searchresult({ queryid => $queryid, recordlist => $recordlist, database => $database, offset => $offset, hitrange => $hitrange })

Speichert das Suchergebnis $recordlist zur Query-ID $queryid in der
Datenbank $database und der aktuellen Schrittweite $hitrange bzw. dem
Offset $offset in der aktuellen Session.

=item get_searchresult({ queryid => $queryid, database => $database, offset => $offset, hitrange => $hitrange })

Liefert das Suchergebnis $recordlist als Objekt
OpenBib::RecordList::Title zur Recherche mit der Query-ID $queryid in
der Datenbank $database und der aktuellen Schrittweite $hitrange
bzw. dem Offset $offset in der aktuellen Session zurück.

=item get_db_histogram_of_query($queryid)

Liefert ein Histogramm der Datenbanken und Trefferzahlen zur
Suchanfrage mit Query-Id $queryid. Das ist ein Wertepaar bestehend aus
einer Liste mit Hashreferenzen (trefferdb, trefferdbdesc, trefferzahl)
und der Gesamttrefferzahl.

=item get_lastresultset

Liefert den letzten Suchergebnisse (Datenbank, Id) als flacher String zurück.

=item set_user($user)

Setzt die Benutzernr auf den Nutzer $user in der aktuelle Session.

=item logout_user($user)

Entfernt die Sessiondaten zu Nutzer $user.

=item is_authenticated_as($user)

Liefert eine wahren Wert zurück, falls sich der Nutzer $user gegenüber
der aktuellen Session authentifiziert hat.

=item get_info_of_all_active_session

Liefert eine Liste aller aktiven Session zurück. Die Liste besteht aus
Hashreferenzen mit den Informationen singlesessionid, createtime,
benutzernr sowie numqueries.

=item get_info($sessionid)

Liefert das Wertepaar Benutzernummer und Zeitpunkt der Sessionerzeugung zurück.

=item get_recently_selected_titles({ hitrange => $hitrange, offset => $offset})

Liefert anhand des Session-Eventlogs eine OpenBib::RecordList::Title aller
aufgerufenen einzeltreffer, optional eingegrenzt ueber $hitrange und $offset.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
