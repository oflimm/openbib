#####################################################################
#
#  OpenBib::Session
#
#  Dieses File ist (C) 2006-2011 Oliver Flimm <flimm@openbib.org>
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

use base qw(Apache::Singleton);

use Apache2::Cookie;
use Digest::MD5;
use Encode 'decode_utf8';
use JSON::XS qw(encode_json decode_json);
use Log::Log4perl qw(get_logger :levels);
use Storable;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Database::DBI;
use OpenBib::Database::Session;
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

    my $r           = exists $arg_ref->{apreq}
        ? $arg_ref->{apreq}                 : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $self = { };

    bless ($self, $class);

    $self->connectDB();
    $self->connectMemcached();

    $self->{servername} = $config->{servername};
    $self->{view}       = $view;

    $logger->debug("Entering Session->new");
    
    # Setzen der Defaults
    if ($r){
        my $cookiejar = Apache2::Cookie::Jar->new($r);
        $sessionID = ($cookiejar->cookies("sessionID"))?$cookiejar->cookies("sessionID")->value:undef;
        
        $logger->debug("Got SessionID-Cookie: $sessionID");
    }   
    
    if (!defined $sessionID || !$sessionID){
        $self->_init_new_session($r);
        $logger->debug("Generation of new SessionID $self->{ID} successful");
    }
    else {
        $self->{ID}        = $sessionID;
        $logger->debug("Examining if SessionID $self->{ID} is valid");
        if (!$self->is_valid()){
            $logger->debug("SessionID is NOT valid");
            
            # Wenn uebergebene SessionID nicht ok, dann neue generieren
            $self->_init_new_session($r);
            $logger->debug("Generation of new SessionID $self->{ID} successful");
        }
    }

    # Neuer Cookie?, dann senden
    if ($sessionID ne $self->{ID}){
        
        $sessionID = $self->{ID};
        
        $logger->debug("Creating new Cookie with SessionID $self->{ID}");
        
        my $cookie = Apache2::Cookie->new($r,
                                          -name    => "sessionID",
                                          -value   => $self->{ID},
                                          -expires => '+24h',
                                          -path    => '/',
                                      );
        
        $r->err_headers_out->set('Set-Cookie', $cookie);
    }
    
    $logger->debug("Session-Object created: ".YAML::Dump($self));
    return $self;
}

sub _new_instance {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $sessionID   = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;

    my $view        = exists $arg_ref->{view}
        ? $arg_ref->{view}                  : undef;

    my $r           = exists $arg_ref->{apreq}
        ? $arg_ref->{apreq}             : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
                                # 
    my $self = { };

    bless ($self, $class);

    $self->connectDB();
    $self->connectMemcached();

    $self->{servername} = $config->{servername};
    $self->{view}       = $view;
    
    # Setzen der Defaults

    $logger->debug("Entering Session->instance");
    
    if ($r){
        my $cookiejar = Apache2::Cookie::Jar->new($r);
        $sessionID = ($cookiejar->cookies("sessionID"))?$cookiejar->cookies("sessionID")->value:undef;
        
        $logger->debug("Got SessionID-Cookie: $sessionID");
    }   

    if (!defined $sessionID || !$sessionID){
        $self->_init_new_session($r);
        $logger->debug("Generation of new SessionID $self->{ID} successful");
    }
    else {
        $self->{ID}        = $sessionID;
        
        $logger->debug("Examining if SessionID $self->{ID} is valid");
        if (!$self->is_valid()){
            $logger->debug("SessionID is NOT valid");
            
            # Wenn uebergebene SessionID nicht ok, dann neue generieren
            $self->_init_new_session($r);
            $logger->debug("Generation of new SessionID $self->{ID} successful");
        }
    }

    # Neuer Cookie?, dann senden
    if ($r && $sessionID ne $self->{ID}){
        
        $sessionID = $self->{ID};

        $logger->debug("Creating new Cookie with SessionID $self->{ID}");
        
        my $cookie = Apache2::Cookie->new($r,
                                          -name    => "sessionID",
                                          -value   => $self->{ID},
                                          -expires => '+24h',
                                          -path    => '/',
                                      );
        
        $r->err_headers_out->set('Set-Cookie', $cookie);
    }
    
    $logger->debug("Session-Object created: ".YAML::Dump($self));
    return $self;
}

sub _init_new_session {
    my ($self,$r) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    my $sessionID="";

    my $havenewsessionID=0;
    
    while ($havenewsessionID == 0) {
        my $gmtime = localtime(time);
        my $md5digest=Digest::MD5->new();
    
        $md5digest->add($gmtime . rand('1024'). $$);
    
        $sessionID=$md5digest->hexdigest;

        my $anzahl=$self->{schema}->resultset('Sessioninfo')->search_rs({ sessionid => $sessionID })->count;
    
        # Wenn wir nichts gefunden haben, dann ist alles ok.
        if ($anzahl == 0 ) {
            $havenewsessionID=1;
      
            my $createtime = POSIX::strftime('%Y-%m-%d% %H:%M:%S', localtime());

            my $queryoptions = OpenBib::QueryOptions->get_default_options;

            $self->{schema}->resultset('Sessioninfo')->create({
                sessionid    => $sessionID,
                createtime   => $createtime,
                queryoptions => encode_json($queryoptions),
                searchform   => 'simple',
            });

            $self->{ID} = $sessionID;
        }
    }

    $logger->debug("Request Object: ".YAML::Dump($r));

    my $useragent=$r->pnotes('useragent') || '';

    # Loggen des Brower-Types
    $self->log_event({
        type      => 101,
        content   => $useragent,
    });

    # Wenn der Request ueber einen Proxy kommt, dann urspruengliche
    # Client-IP setzen
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $r->connection->remote_ip($1);
    }
    
    # Loggen der Client-IP
    $self->log_event({
        type      => 102,
        content   => $r->connection->remote_ip,
    });
    
    if ($self->{view}) {
        # Loggen der View-Auswahl
        $self->log_event({
            type      => 100,
            content   => $self->{view},
        });
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

    return $sessionID;
}

sub is_valid {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{sessiondbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    # Spezielle SessionID -1 ist erlaubt
    if (defined $self->{ID} && $self->{ID} eq "-1") {
        return 1;
    }

    my $anzahl = $self->{schema}->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} })->count;

    if ($anzahl == 1) {
        return 1;
    }

    return 0;
}

sub get_profile {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select profile from sessionprofile where sessionid = ?"
    my $prevprofile = $self->{schema}->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} })->single->searchprofile;

    return $prevprofile;
}

sub set_profile {
    my ($self,$profile)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{schema}->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} })->update({ searchprofile => $profile });

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
    my $history = $self->{schema}->resultset('Searchhistory')->search_rs(
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

    $logger->debug("Offsets:\n".YAML::Dump(\@offsets));
    return @offsets;
}

sub get_mask {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI ehemals: "select masktype from sessionmask where sessionid = ?"
    my $form = $self->{schema}->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} })->first->searchform;

    return ($form)?$form:'simple';
}

sub set_mask {
    my ($self,$mask)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI ehemals: "update sessionmask set masktype = ? where sessionid = ?"
    $self->{schema}->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} })->update({ searchform => $mask });

    return;
}

sub set_dbchoice {
    my ($self,$db_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sid =  $self->{schema}->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} })->single->id;

    # Datenbanken zunaechst loeschen
    eval {
        $self->{schema}->resultset('Dbchoice')->search_rs({ sid => $sid })->delete;
    };

    if (@$db_ref){
        my $this_db_ref = [];
        foreach my $dbname (@$db_ref){
            push @$this_db_ref, {
                sid    => $sid,
                dbname => $dbname,
            };
        }

        # Dann die zugehoerigen Datenbanken eintragen
        $self->{schema}->resultset('Dbchoice')->populate($this_db_ref);
    }

    return;
}

sub get_dbchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $dbases = $self->{schema}->resultset('Dbchoice')->search_rs({ 'sid.sessionID' => $self->{ID}}, { join => 'sid' } );

    my @dbchoice=();
    foreach my $item ($dbases->all){
        push @dbchoice, $item->dbname;

    }

    $logger->debug("DB-Choice:\n".YAML::Dump(\@dbchoice));
    return reverse @dbchoice;
}

sub clear_dbchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Datenbanken zunaechst loeschen
    eval {
        $self->{schema}->resultset('Dbchoice')->search_rs({ 'sid.sessionid' => $self->{ID} }, { join => 'sid' })->delete;
    };

    return;
}

sub get_number_of_dbchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(dbname) as rowcount from dbchoice where sessionid = ?"
    my $numofdbs = $self->{schema}->resultset('Dbchoice')->search_rs({ 'sid.sessionid' => $self->{ID} }, { join => 'sid' } )->count;

    return $numofdbs;
}

sub get_number_of_items_in_resultlist {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(sessionid) as rowcount from searchresults where sessionid = ?"
    my $numofresults = $self->{schema}->resultset('Searchhistory')->search_rs({ 'sid.sessionid' => $self->{ID} }, { join => 'sid' })->count;

    return $numofresults;
}

sub get_number_of_queries {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(queryid) as rowcount from queries where sessionid = ?
    my $numofqueries = $self->{schema}->resultset('Query')->search_rs({ 'sid.sessionid' => $self->{ID} }, { join => 'sid' } )->count;

    $logger->debug("Found $numofqueries queries in Session $self->{ID}");
    
    return $numofqueries;
}

sub get_all_searchqueries {
    my ($self,$arg_ref)=@_;

    # Set defaults

    my $sessionid = exists $arg_ref->{sessionid}
        ? $arg_ref->{sessionid}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $thissessionid = (defined $sessionid)?$sessionid:$self->{ID};

    # DBI: "select queryid from queries where sessionid = ? order by queryid DESC "
    my $searchqueries = $self->{schema}->resultset('Query')->search_rs(
        {
            'sid.sessionid' => $thissessionid,
        },
        {
            select => 'me.queryid',
            as     => 'thisqueryid',
            order_by => [ 'me.queryid DESC' ],
            join => 'sid'
        }
    );

    my @queries=();

    foreach my $item ($searchqueries->all){
        my $searchquery = OpenBib::SearchQuery->new->load({sessionID => $self->{ID}, queryid => $item->get_column('thisqueryid') });
        push @queries, $searchquery;
    }

    return @queries;
}

sub get_number_of_items_in_collection {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(*) as rowcount from treffer where sessionid = ?"
    my $count = $self->{schema}->resultset('Collection')->search_rs({ 'sid.sessionid' => $self->{ID} }, { join => 'sid' } )->count;

    return $count;
}

sub get_items_in_collection {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $recordlist = new OpenBib::RecordList::Title();
    
    return $recordlist if (!defined $self->{schema});

    # DBI: "select dbname,singleidn from treffer where sessionid = ? order by dbname"
    my $items = $self->{schema}->resultset('Collection')->search_rs(
        {
            'sid.sessionid' => $self->{ID},
        },
        {
            select => [ 'me.dbname', 'me.titleid' ],
            as     => [ 'thisdbname', 'thistitleid' ],
            join   => 'sid'
        }
    );

    foreach my $item ($items->all){
        my $database = $item->get_column('thisdbname');
        my $titleid  = $item->get_column('thistitleid');

        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $titleid}));
    }

    return $recordlist;
}

sub set_item_in_collection {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;

    my $id        = exists $arg_ref->{id}
        ? $arg_ref->{id}                 : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (!$database || !$id){
        return;
    }

    my $count = $self->{schema}->resultset('Collection')->search_rs({ 'sid.sessionid' => $self->{ID}, 'me.dbname' => $database, 'me.titleid' => $id },{ join => 'sid' })->count;
    
    if ($count == 0) {
        my $record        = new OpenBib::Record::Title({ database => $database , id => $id});
        my $cached_title  = $record->load_full_record->to_json;

        $logger->debug("Adding Title to Collection: $cached_title");

        # DBI: "insert into treffer values (?,?,?,?)"
        $self->{schema}->resultset('Collection')->create( { dbname => $database, titleid => $id, titlecache => $cached_title });
    }

    return;
}

sub clear_item_in_collection {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;

    my $id        = exists $arg_ref->{id}
        ? $arg_ref->{id}                 : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (!$database || !$id){
        return;
    }

    $logger->debug("Deleting item $database - $id");

    eval {
        # DBI: "delete from treffer where sessionid = ? and dbname = ? and singleidn = ?"
        $self->{schema}->resultset('Collection')->search_rs({ 'sid.sessionid' => $self->{ID}, 'me.dbname' => $database, 'me.titleid' => $id },{ join => 'sid' })->delete;
    };

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
    $self->{schema}->resultset('Sessioninfo')->search_rs({ sessionid => $self->{ID} })->update({ lastresultset => $resultsetstring });

    return;
}

sub save_eventlog_to_statisticsdb {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Zuerst Statistikdaten in Statistik-Datenbank uebertragen,
    my $statistics=new OpenBib::Statistics;

    my $view = "";

    eval {
        $view = $self->{schema}->resultset('Eventlog')->search_rs(
            {
                'sid.sessionid' => $self->{ID},
                'me.type' => 100,
            },
            {
                select => 'me.content',
                as     => 'thisview',
                join => 'sid'
            }
        )->single->get_column('thisview');
    };
    
    # Alle Events in Statistics-DB uebertragen
    # DBI: "select * from eventlog where sessionid = ?"
    my $events = $self->{schema}->resultset('Eventlog')->search_rs({ 'sid.sessionid' => $self->{ID} },{ join => 'sid' });

    foreach my $event ($events->all){
        my $tstamp        = $event->tstamp;
        my $type          = $event->type;
        my $content       = $event->content;
        my $id            = $self->{servername}.":".$self->{ID};

        $statistics->log_event({
            sessionID => $id,
            tstamp    => $tstamp,
            type      => $type,
            content   => $content,
        });

	if ($type == 1){
	  my $searchquery_ref = Storable::thaw(pack "H*", $content);
	  
	  $logger->debug(YAML::Dump($searchquery_ref));
	  $statistics->log_query({
				  tstamp          => $tstamp,
				  view            => $view,
				  searchquery_ref => $searchquery_ref,
	  });
	}
    }
    
    # Relevanz-Daten vom Typ 2 (Einzeltrefferaufruf)
    # DBI: "select tstamp,content from eventlog where sessionid = ? and type=10"
    my $records = $self->{schema}->resultset('Eventlog')->search_rs(
        {
            'sid.sessionid' => $self->{ID},
            'me.type' => 10,
        },
        {
            select => [ 'me.tstamp', 'me.content' ],
            as     => [ 'thiststamp' ,'thisview' ],
            join => 'sid'
        }
    );

    my ($wkday,$month,$day,$time,$year) = split(/\s+/, localtime);
    
    my %seen_title=();

    foreach my $item ($records->all){
        my $tstamp        = $item->get_column('thiststamp');
        my $content_ref   = Storable::thaw(pack "H*", $item->get_column('content'));

        my $id            = $self->{servername}.":".$self->{ID};
        my $isbn          = $content_ref->{isbn};
        my $dbname        = $content_ref->{database};
        my $katkey        = $content_ref->{id};

	next if (exists $seen_title{"$dbname:$katkey"});

        $statistics->store_relevance({
            tstamp => $tstamp,
            id     => $id,
            isbn   => $isbn,
            dbname => $dbname,
            katkey => $katkey,
            type   => 2,
        });

	$seen_title{"$dbname:$katkey"}=1;
    }

    return;
}

sub clear_data {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{sessiondbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult;

    $self->save_eventlog_to_statisticsdb;
    
    # dann Sessiondaten loeschen
    eval {
        $self->{schema}->resultset('Eventlog')->search_rs({ 'sid.sessionid' => $self->{ID} },{ join => 'sid' })->delete;
        $self->{schema}->resultset('Collection')->search_rs({ 'sid.sessionid' => $self->{ID} },{ join => 'sid' })->delete;
        $self->{schema}->resultset('Dbchoice')->search_rs({ 'sid.sessionid' => $self->{ID} },{ join => 'sid' })->delete;
        $self->{schema}->resultset('Recordhistory')->search_rs({ 'sid.sessionid' => $self->{ID} },{ join => 'sid' })->delete;
        $self->{schema}->resultset('Searchhistory')->search_rs({ 'sid.sessionid' => $self->{ID} },{ join => 'sid' })->delete;
        $self->{schema}->resultset('Sessioninfo')->search_rs({ 'sessionid' => $self->{ID} })->delete;
    };

    
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
        $contentstring=unpack "H*", Storable::freeze($content);
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
    # 102 => IP des Klienten
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
            $self->{schema}->resultset('Eventlog')->search_rs({ 'sid.sessionid' => $self->{ID}, 'me.type' => $type, 'me.content' => $contentstring},{ join => 'sid' })->delete_all;
        };
    }

    
    $logger->debug("Getting sid for SessionID ".$self->{ID});
    my $sid = $self->{schema}->resultset('Sessioninfo')->search_rs({ 'sessionid' => $self->{ID} })->single->id;

    # DBI: "insert into eventlog values (?,NOW(),?,?)"
    $self->{schema}->resultset('Eventlog')->populate([{ sid => $sid, tstamp => \'NOW()', type => $type, content => $contentstring }]);

    return;
}

sub set_returnurl {
    my ($self,$returnurl)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "update session set returnurl=? where sessionid = ?"
    $self->{schema}->resultset('Sessioninfo')->search({ sessionid => $self->{ID} })->update({ returnurl => $returnurl });

    return;
}

sub get_queryid {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $databases_ref      = exists $arg_ref->{databases}
        ? $arg_ref->{databases}               : undef;
    
    my $hitrange           = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}                : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $searchquery = OpenBib::SearchQuery->instance;

    my $queryid            = 0;
    my $queryalreadyexists = 0;

    # Wenn man databases_ref hier sortiert und in VirtualSearch.pm sortiert, dann koennen anhand von Suchanfrage und Datenbankauswahl auch
    # bei gleicher aber permutierter Datenbankliste die entsprechende queryid gefunden werden, allerdings kann man dann
    # diese Liste nicht mehr fuer wiederholte Anfrage (Listentyp) verwenden, da sich dann
    # durch die Sortierung die Reihenfolge geaendert hat. Daher wird hier nicht mehr sortiert
    my $dbasesstring=join("||",@{$databases_ref});

    my $query_obj_string = $searchquery->to_json;

    # DBI: "select count(*) as rowcount from queries where query = ? and sessionid = ? and dbases = ? and hitrange = ?"
    my $rows = $self->{schema}->resultset('Query')->search({ 'sid.sessionid' => $self->{ID}, 'me.query' => $query_obj_string, 'me.dbases' => $dbasesstring, 'me.hitrange' => $hitrange },{ join => 'sid' })->count;

    my $sid = $self->{schema}->resultset('Sessioninfo')->search_rs({ 'sessionid' => $self->{ID} })->single->id;

    # Neuer Query
    if ($rows <= 0) {
        # Abspeichern des Queries bis auf die Gesamttrefferzahl
        # DBI: "insert into queries (queryid,sessionid,query,hitrange,dbases) values (NULL,?,?,?,?)"
        
        $self->{schema}->resultset('Query')->insert({ queryid => 'NULL', sid => $sid, query => $query_obj_string, hitrange => $hitrange, dbases => $dbasesstring });
    }
    # Query existiert schon
    else {
        $queryalreadyexists=1;
    }

    # DBI: "select queryid from queries where query = ? and sessionid = ? and dbases = ? and hitrange = ?"
    $queryid = $self->{schema}->resultset('Query')->search({ 'sid.sessionid' => $self->{ID}, 'me.query' => $query_obj_string, 'me.dbases' => $dbasesstring, 'me.hitrange' => $hitrange },{ join => 'sid', select => 'me.queryid', as => 'thisqueryid' })->single->get_column('thisqueryid');

    return ($queryalreadyexists,$queryid);
}

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
    $self->{schema}->resultset('Query')->search({ queryid => $queryid })->update({ hits => $hits });

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

    my $sid = $self->{schema}->resultset('Sessioninfo')->search_rs({ 'sessionid' => $self->{ID} })->single->id;

    foreach my $db (keys %{$results_ref}) {
        my $res=$results_ref->{$db};

        my $storableres= ""; #unpack "H*",Storable::freeze($res);

        # DBI: "insert into searchresults values (?,?,0,?,?,?,?)"
        $self->{schema}->resultset('Searchhistory')->insert(
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

        $logger->debug("YAML-Dumped: ".YAML::Dump($res));
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

    my $sid = $self->{schema}->resultset('Sessioninfo')->search_rs({ 'sessionid' => $self->{ID} })->single->id;

    eval {
        # DBI: "delete from searchresults where sessionid = ? and queryid = ? and dbname = ? and offset = ? and hitrange = ?"
        $self->{schema}->resultset('Searchhistory')->search(
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
    
    $logger->debug("YAML-Dumped: ".YAML::Dump($recordlist));
    my $num=$recordlist->get_size();

    # DBI: "insert into searchresults values (?,?,?,?,?,?,?)"
    $self->{schema}->resultset('Searchhistory')->insert(
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

    my $sid = $self->{schema}->resultset('Sessioninfo')->search_rs({ 'sessionid' => $self->{ID} })->single->id;

    # DBI: "select searchresult from searchresults where sessionid = ? and queryid = ? and dbname = ? and offset = ? and hitrange = ?"
    my $searchresult = $self->{schema}->resultset('Searchhistory')->search(
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

    $logger->debug("Suchergebnis: ".YAML::Dump($recordlist));

    return $recordlist;
}

sub get_returnurl {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select returnurl from session where sessionid = ?"
    my $returnurl = $self->{schema}->resultset('Sessioninfo')->search({ sessionid => $self->{ID} })->single->returnurl;

    return $returnurl;
}

sub get_db_histogram_of_query {
    my ($self,$queryid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $sid = $self->{schema}->resultset('Sessioninfo')->search_rs({ 'sessionid' => $self->{ID} })->single->id;

    # DBI "select dbname,sum(hits) as hitcount from searchresults where sessionid = ? and queryid = ? group by dbname order by hitcount desc"
    my $searchresult = $self->{schema}->resultset('Searchhistory')->search(
        {
            sid          => $sid,
            queryid      => $queryid,
        },
        {
            select => [ 'dbname', { sum => 'hits' }],
            as     => [ 'thisdbname', 'thiscount'],
            group_by => 'dbname',
            order_by => [ 'hitcount desc' ],
        }
    );

    my $hitcount=0;
    my @resultdbs=();

    foreach my $item ($searchresult->all){
        push @resultdbs, {
            trefferdb     => decode_utf8($item->get_column('thisdbname')),
            trefferdbdesc => $dbinfotable->{dbnames}{decode_utf8($item->get_column('thisdbname'))},
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

    # DBI: "select lastresultset from session where sessionid = ?"
    my $lastresultset = $self->{schema}->resultset('Sessioninfo')->search({ sessionid => $self->{ID} })->single->lastresultset;

    return $lastresultset;
}

sub set_user {
    my ($self,$user)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "update session set benutzernr = ? where sessionID = ?"
    $self->{schema}->resultset('Sessioninfo')->search({ sessionid => $self->{ID} })->update({ username => $user });

    return;
}

sub logout_user {
    my ($self,$user)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    eval {
        $self->{schema}->resultset('Sessioninfo')->search({ sessionid => $self->{ID}, username => $user })->delete;
    };

    return;
}

sub is_authenticated_as {
    my ($self,$user)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # DBI: "select count(*) as rowcount from session where benutzernr = ? and sessionid = ?"
    my $count = $self->{schema}->resultset('Sessioninfo')->search({ sessionid => $self->{ID}, username => $user })->count;

    # Authorized as    : 1
    # not Authorized as: 0
    return ($count <= 0)?0:1;
}

sub get_info_of_all_active_sessions {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{sessiondbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare() or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);

    # DBI: "select * from session order by createtime"
    my $sessioninfos = $self->{schema}->resultset('Sessioninfo')->search(undef, { order_by => 'createtype'});
    
    my @sessions=();

    foreach my $item ($sessioninfos->all){
        my $singlesessionid = decode_utf8($item->sessionid);
        my $createtime      = decode_utf8($item->createtime);
        my $username        = decode_utf8($item->username);

        # DBI: "select count(*) as rowcount from queries where sessionid = ?"
        my $numqueries = $self->{schema}->resultset('Query')->search({ 'sid.sessionid' => $singlesessionid }, { join => 'sid' })->count;

        if (!$username) {
            $username="Anonym";
        }

        push @sessions, {
            singlesessionid => $singlesessionid,
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
    my $sessioninfos = $self->{schema}->resultset('Sessioninfo')->search({ sessionid => $singlesessionid })->first;

    my $createtime = decode_utf8($sessioninfos->createtime);
    my $username   = decode_utf8($sessioninfos->username);

    return ($username,$createtime);
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
    my $lastrecords = $self->{schema}->resultset('Eventlog')->search({ 'sid.sessionid' => $self->{ID}, 'me.type' => 10 }, { select => 'me.content', as => 'thiscontent', join => 'sid', order_by => ['tstamp DESC'], limit => "$offset,$hitrange" });

    my $recordlist = new OpenBib::RecordList::Title;

    foreach my $item ($lastrecords->all){
        my $content_ref = Storable::thaw(pack "H*",$item->get_column('thiscontent'));
        $recordlist->add(new OpenBib::Record::Title({database => $content_ref->{database}, id => $content_ref->{id}}));
    }

    $logger->debug($recordlist);
    return $recordlist;
}

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    eval {
        # Verbindung zur SQL-Datenbank herstellen
        $self->{dbh}
            = OpenBib::Database::DBI->connect("DBI:$config->{sessiondbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
    };

    if ($@){
        $logger->fatal("Unable to connect to database $config->{sessiondbname}");
    }
    
    $self->{dbh}->{RaiseError} = 1;

    eval {        
#        $self->{schema} = OpenBib::Database::Session->connect("DBI:$config->{sessiondbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd}) or $logger->error_die($DBI::errstr)
        $self->{schema} = OpenBib::Database::Session->connect("DBI:$config->{sessiondbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error_die($DBI::errstr);

    };

    if ($@){
        $logger->fatal("Unable to connect to database $config->{sessiondbname}");
    }

    return;
}

sub connectMemcached {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Verbindung zu Memchached herstellen
    $self->{memc} = new Cache::Memcached($self->{memcached});

    if (!$self->{memc}->set('isalive',1)){
        $logger->fatal("Unable to connect to memcached");
    }

    return;
}

1;
__END__

=head1 NAME

OpenBib::Session - Apache-Singleton einer Session

=head1 DESCRIPTION

Dieses Apache-Singleton verwaltet eine Session im Portal

=head1 SYNOPSIS

 use OpenBib::Session;

=head1 METHODS

=over 4

=item new({ sessionID => $sessionID })

Erzeugung als herkömmliches Objektes und nicht als
Apache-Singleton. Damit kann auch ausserhalb des Apache mit mod_perl
auf eine gegebene Session in Perl-Skripten zugegriffen werden.

=item instance({ sessionID => $sessionID })

Instanziierung des Apache-Singleton yur SessionID $sessionID. Wird
keine sessionID übergeben, dann wird eine neue erzeugt.

=item instance({ sessionID => $sessionID })

Instanziierung des Apache-Singleton yur SessionID $sessionID. Wird keine sessionID übergeben, dann wird eine neue erzeugt.

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

=item set_returnurl($returnurl)

Speichert den URL $returnurl in der Session, auf den nach einem
erfolgreichen Anmeldevorgang gesprungen wird.

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

=item get_returnurl

Liefert den in der Session abgespeichert Rücksprung-URL.

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
