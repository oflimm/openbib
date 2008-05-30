#####################################################################
#
#  OpenBib::Session
#
#  Dieses File ist (C) 2006-2007 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use YAML;

use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Database::DBI;
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

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $self = { };

    bless ($self, $class);

    $self->{servername} = $config->{servername};

    # Setzen der Defaults

    if (!defined $sessionID){
        $self->{ID} = $self->_init_new_session();
        $logger->debug("Generation of new SessionID $self->{ID} successful");
    }
    else {
        $self->{ID}        = $sessionID;
        $logger->debug("Examining if SessionID $self->{ID} is valid");
        if (!$self->is_valid()){
            $self->{ID} = undef;
            $logger->debug("SessionID is NOT valid");
        }
    }
    


    $logger->debug("Session-Object created: ".YAML::Dump($self));
    return $self;
}

sub _new_instance {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $sessionID   = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $self = { };

    bless ($self, $class);

    $self->{servername} = $config->{servername};

    # Setzen der Defaults

    if (!defined $sessionID){
        $self->{ID} = $self->_init_new_session();
        $logger->debug("Generation of new SessionID $self->{ID} successful");
    }
    else {
        $self->{ID}        = $sessionID;
        $logger->debug("Examining if SessionID $self->{ID} is valid");
        if (!$self->is_valid()){
            $self->{ID} = undef;
            $logger->debug("SessionID is NOT valid");
        }
    }
    


    $logger->debug("Session-Object created: ".YAML::Dump($self));
    return $self;
}

sub _init_new_session {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $sessionID="";

    my $havenewsessionID=0;
    
    while ($havenewsessionID == 0) {
        my $gmtime = localtime(time);
        my $md5digest=Digest::MD5->new();
    
        $md5digest->add($gmtime . rand('1024'). $$);
    
        $sessionID=$md5digest->hexdigest;
    
        # Nachschauen, ob es diese ID schon gibt
        my $idnresult=$dbh->prepare("select count(sessionid) from session where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

        my @idn=$idnresult->fetchrow_array();
        my $anzahl=$idn[0];
    
        # Wenn wir nichts gefunden haben, dann ist alles ok.
        if ($anzahl == 0 ) {
            $havenewsessionID=1;
      
            my $createtime = POSIX::strftime('%Y-%m-%d% %H:%M:%S', localtime());

            my $queryoptions = OpenBib::QueryOptions->get_default_options;

            # Eintrag in die Datenbank
            $idnresult=$dbh->prepare("insert into session (sessionid,createtime,queryoptions) values (?,?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$createtime,YAML::Dump($queryoptions)) or $logger->error($DBI::errstr);

            
            my $request=$dbh->prepare("insert into sessionmask values (?,?)");
            $request->execute($sessionID,'simple');
            $request->finish();
        }
        $idnresult->finish();
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
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    # Spezielle SessionID -1 ist erlaubt
    if (defined $self->{ID} && $self->{ID} eq "-1") {
        return 1;
    }

    my $idnresult=$dbh->prepare("select count(sessionid) from session where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    my @idn=$idnresult->fetchrow_array();
    my $anzahl=$idn[0];

    $idnresult->finish();

    if ($anzahl == 1) {
        return 1;
    }

    return 0;
}

sub get_viewname {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    $logger->debug("Self: ".YAML::Dump($self));

    # Assoziierten View zur Session aus Datenbank holen
    my $idnresult=$dbh->prepare("select viewname from sessionview where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    my $result=$idnresult->fetchrow_hashref();
  
    # Entweder wurde ein 'echter' View gefunden oder es wird
    # kein spezieller View verwendet (view='')
    my $view = decode_utf8($result->{'viewname'}) || '';

    $idnresult->finish();

    $logger->debug("Got view: $view");

    return $view;
}

sub get_profile {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select profile from sessionprofile where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $result=$idnresult->fetchrow_hashref();
  
    my $prevprofile="";
  
    if (defined($result->{'profile'})) {
        $prevprofile = decode_utf8($result->{'profile'});
    }

    $idnresult->finish();

    return $prevprofile;
}

sub set_profile {
    my ($self,$profile)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("delete from sessionprofile where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    $idnresult=$dbh->prepare("insert into sessionprofile values (?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$profile) or $logger->error($DBI::errstr);
    $idnresult->finish();

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

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select offset, hits from searchresults where sessionid = ? and queryid = ? and dbname = ? and hitrange = ? order by offset") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$queryid,$database,$hitrange) or $logger->error($DBI::errstr);

    my @offsets=();
    my $lasthits   = 0;
    my $lastoffset = 0;
    while (my $result=$idnresult->fetchrow_hashref){
        my $offset = $result->{offset};
        my $hits   = $result->{hits};
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
            
    $idnresult->finish();

    $logger->debug("Offsets:\n".YAML::Dump(\@offsets));
    return @offsets;
}

sub get_mask {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select masktype from sessionmask where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $result=$idnresult->fetchrow_hashref();
    my $setmask = decode_utf8($result->{'masktype'});
    
    $idnresult->finish();
    return ($setmask)?$setmask:'simple';
}

sub set_mask {
    my ($self,$mask)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("update sessionmask set masktype = ? where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($mask,$self->{ID}) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}



sub set_view {
    my ($self,$view)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    $logger->debug("Setting view $view for session $self->{ID}");
    my $idnresult=$dbh->prepare("delete from sessionview where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    $idnresult=$dbh->prepare("insert into sessionview values (?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$view) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub set_dbchoice {
    my ($self,$dbname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("insert into dbchoice (sessionid,dbname) values (?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$dbname) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub get_dbchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select dbname from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    my @dbchoice=();
    while (my $res=$idnresult->fetchrow_hashref){
        push @dbchoice, decode_utf8($res->{'dbname'});

    }
    $idnresult->finish();

    $logger->debug("DB-Choice:\n".YAML::Dump(\@dbchoice));
    return reverse @dbchoice;
}

sub clear_dbchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("delete from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub get_number_of_dbchoice {
    my ($self,$dbname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select count(dbname) as rowcount from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofdbs = $res->{rowcount};
    $idnresult->finish();

    return $numofdbs;
}

sub get_number_of_items_in_resultlist {
    my ($self,$dbname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select count(sessionid) as rowcount from searchresults where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofitems = $res->{rowcount};
    $idnresult->finish();

    return $numofitems;
}

sub get_items_in_resultlist_per_db {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    
    my $queryid   = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}            : undef;

    my $offset    = exists $arg_ref->{offset}
        ? $arg_ref->{offset}             : undef;

    my $hitrange  = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}           : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my @resultlist=();

    my $sqlrequest="select searchresult from searchresults where sessionid = ? and dbname = ? and queryid = ?";
    my @sqlargs=($self->{ID},$database,$queryid);

    if (defined $offset){
        $sqlrequest.=" and offset = ?";
        push @sqlargs, $offset;
    }
    else {
        $sqlrequest.=" order by ASC";
    }
    
    $logger->debug("SQL-Request: $sqlrequest / $self->{ID} - $database - $queryid - $offset - $hitrange");
    my $idnresult=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $idnresult->execute(@sqlargs) or $logger->error($DBI::errstr);
    while (my $res = $idnresult->fetchrow_hashref()){
        push @resultlist, $res->{searchresult};
    }
    $idnresult->finish();

    $logger->debug(\@resultlist);
    
    return @resultlist;
}

sub get_all_items_in_resultlist {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $queryid   = exists $arg_ref->{queryid}
        ? $arg_ref->{queryid}            : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select searchresult,dbname from searchresults where sessionid = ? and queryid = ? and offset=0") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$queryid) or $logger->error($DBI::errstr);
    
    my $searchresult_ref={};
    while (my $res=$idnresult->fetchrow_hashref){
        $searchresult_ref->{$res->{dbname}}=$res->{searchresult};
    }
    
    my @resultlist=();

    # Sortieren von Searchresults gemaess Ordnung der DBnames in ihren OrgUnits
    foreach my $dbname ($config->get_active_databases()){
        if (exists $searchresult_ref->{$dbname}){
            push @resultlist, {
                dbname       => $dbname,
                searchresult => Storable::thaw(pack "H*",$searchresult_ref->{$dbname}),
            };
        }
    }

    $idnresult->finish();

    return @resultlist;
}

sub get_max_queryid {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select max(queryid) as maxid from queries where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $maxid = decode_utf8($res->{maxid});
    $idnresult->finish();

    return $maxid;
}

sub get_all_searchqueries {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $offset    = exists $arg_ref->{offset}
        ? $arg_ref->{offset}            : undef;

    my $sessionid = exists $arg_ref->{sessionid}
        ? $arg_ref->{sessionid}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    # Ausgabe der vorhandenen queries
    my $sql_request="select * from queries where sessionid = ?";

    if (defined $offset){
        $sql_request="select distinct searchresults.queryid as queryid,queries.query as query,queries.hits as hits, queries.dbases as dbases from searchresults,queries where searchresults.sessionid = ? and searchresults.queryid=queries.queryid and searchresults.offset=$offset order by queryid desc";
    }

    my $thissessionid = (defined $sessionid)?$sessionid:$self->{ID};
    my $idnresult=$dbh->prepare($sql_request) or $logger->error($DBI::errstr);
    $idnresult->execute($thissessionid) or $logger->error($DBI::errstr);
    my $anzahl=$idnresult->rows();

    my @queries=();

    while (my $result=$idnresult->fetchrow_hashref()) {
        my $dbases = decode_utf8($result->{'dbases'});
        $dbases=~s/\|\|/ ; /g;

        push @queries, {
            id          => decode_utf8($result->{queryid}),
            searchquery => Storable::thaw(pack "H*",$result->{query}),
            hits        => decode_utf8($result->{hits}),
            dbases      => $dbases,            
        };
    }

    $idnresult->finish();

    return @queries;
}

sub get_number_of_items_in_collection {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select count(*) as rowcount from treffer where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofitems = $res->{rowcount};
    $idnresult->finish();

    return $numofitems;
}

sub get_items_in_collection {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select dbname,singleidn from treffer where sessionid = ? order by dbname") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    my $recordlist = new OpenBib::RecordList::Title();

    return $recordlist if (!defined $dbh);

    while(my $result = $idnresult->fetchrow_hashref){
        my $database  = decode_utf8($result->{'dbname'});
        my $singleidn = decode_utf8($result->{'singleidn'});

        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $singleidn}));
    }
    
    $idnresult->finish();
    
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

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    if (!$database || !$id){
        return;
    }
    
    my $idnresult=$dbh->prepare("select count(*) as rowcount from treffer where sessionid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$database,$id) or $logger->error($DBI::errstr);
    my $res    = $idnresult->fetchrow_hashref;
    my $anzahl = $res->{rowcount};
    $idnresult->finish();
    
    if ($anzahl == 0) {
        my $idnresult=$dbh->prepare("insert into treffer values (?,?,?)") or $logger->error($DBI::errstr);
        $idnresult->execute($self->{ID},$database,$id) or $logger->error($DBI::errstr);
        $idnresult->finish();
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

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    if (!$database || !$id){
        return;
    }
    
    my $idnresult=$dbh->prepare("delete from treffer where sessionid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$database,$id) or $logger->error($DBI::errstr);
    
    return;
}

sub updatelastresultset {
    my ($self,$resultset_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my @resultset=@$resultset_ref;

    my @nresultset=();

    foreach my $outidx_ref (@resultset) {
        my %outidx=%$outidx_ref;

        # Eintraege merken fuer Lastresultset
        my $katkey      = (exists $outidx{id})?$outidx{id}:"";
        my $resdatabase = (exists $outidx{database})?$outidx{database}:"";

	$logger->debug("Katkey: $katkey - Database: $resdatabase");

        push @nresultset, "$resdatabase:$katkey";
    }

    my $resultsetstring=join("|",@nresultset);

    my $sessionresult=$dbh->prepare("update session set lastresultset = ? where sessionid = ?") or $logger->error($DBI::errstr);
    $sessionresult->execute($resultsetstring,$self->{ID}) or $logger->error($DBI::errstr);
    $sessionresult->finish();

    return;
}

sub clear_data {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult;

    my $view = $self->get_viewname();
    $logger->debug("Viewname: $view");

    # Zuerst Statistikdaten in Statistik-Datenbank uebertragen,
    my $statistics=new OpenBib::Statistics;

    # Alle Events in Statistics-DB uebertragen
    $idnresult=$dbh->prepare("select * from eventlog where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    while (my $result=$idnresult->fetchrow_hashref){
        my $tstamp        = $result->{tstamp};
        my $type          = $result->{type};
        my $content       = $result->{content};
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
    $idnresult=$dbh->prepare("select tstamp,content from eventlog where sessionid = ? and type=10") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    
    my ($wkday,$month,$day,$time,$year) = split(/\s+/, localtime);
    
    my %seen_title=();

    while (my $result=$idnresult->fetchrow_hashref){
        my $tstamp        = $result->{tstamp};
        my $content_ref   = Storable::thaw(pack "H*", $result->{content});

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
    
    # dann Sessiondaten loeschen
    $idnresult=$dbh->prepare("delete from treffer where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    $idnresult=$dbh->prepare("delete from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    $idnresult=$dbh->prepare("delete from queries where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    $idnresult=$dbh->prepare("delete from searchresults where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    $idnresult=$dbh->prepare("delete from sessionview where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    $idnresult=$dbh->prepare("delete from sessionmask where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    $idnresult=$dbh->prepare("delete from sessionprofile where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    $idnresult=$dbh->prepare("delete from session where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    $idnresult->finish();

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

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $contentstring = $content;

    if ($serialize){
        $contentstring=unpack "H*", Storable::freeze($content);
    }
    
    # Moegliche Event-Typen
    #
    # Recherchen:
    #   1 => Recherche-Anfrage bei Virtueller Recherche
    #  10 => Eineltrefferanzeige
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
    #
    # 800 => Aufruf Literaturliste
    # 801 => Aufruf RSS-Feeds
    
    my $log_only_unique_ref = {
			     10 => 1,
			    };

    my $request;
    if (exists $log_only_unique_ref->{$type}){
      $request=$dbh->prepare("delete from eventlog where sessionid=? and type=? and content=?") or $logger->error($DBI::errstr);
      $request->execute($self->{ID},$type,$contentstring) or $logger->error($DBI::errstr);
    }

    $request=$dbh->prepare("insert into eventlog values (?,NOW(),?,?)") or $logger->error($DBI::errstr);
    $request->execute($self->{ID},$type,$contentstring) or $logger->error($DBI::errstr);
    $request->finish;

    return;
}

sub set_returnurl {
    my ($self,$returnurl)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("update session set returnurl=? where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($returnurl, $self->{ID}) or $logger->error($DBI::errstr);
    $idnresult->finish();

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

    my $config = OpenBib::Config->instance;

    my $searchquery = OpenBib::SearchQuery->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $queryid            = 0;
    my $queryalreadyexists = 0;

    my $dbasesstring=join("||",sort @{$databases_ref});
    
    my $thisquerystring=unpack "H*", Storable::freeze($searchquery->get_searchquery);
    my $idnresult=$dbh->prepare("select count(*) as rowcount from queries where query = ? and sessionid = ? and dbases = ? and hitrange = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($thisquerystring,$self->{ID},$dbasesstring,$hitrange) or $logger->error($DBI::errstr);
    my $res  = $idnresult->fetchrow_hashref;
    my $rows = $res->{rowcount};
        
    # Neuer Query
    if ($rows <= 0) {
        # Abspeichern des Queries bis auf die Gesamttrefferzahl
        $idnresult=$dbh->prepare("insert into queries (queryid,sessionid,query,hitrange,dbases) values (NULL,?,?,?,?)") or $logger->error($DBI::errstr);
        $idnresult->execute($self->{ID},$thisquerystring,$hitrange,$dbasesstring) or $logger->error($DBI::errstr);
    }
    # Query existiert schon
    else {
        $queryalreadyexists=1;
    }
        
    $idnresult=$dbh->prepare("select queryid from queries where query = ? and sessionid = ? and dbases = ? and hitrange = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($thisquerystring,$self->{ID},$dbasesstring,$hitrange) or $logger->error($DBI::errstr);
    
    while (my @idnres=$idnresult->fetchrow) {
        $queryid = decode_utf8($idnres[0]);
    }
    
    $idnresult->finish();

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

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("update queries set hits = ? where queryid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($hits,$queryid) or $logger->error($DBI::errstr);
    $idnresult->finish;

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

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("insert into searchresults values (?,?,0,?,?,?,?)") or $logger->error($DBI::errstr);
    
    foreach my $db (keys %{$results_ref}) {
        my $res=$results_ref->{$db};
        
        my $storableres=unpack "H*",Storable::freeze($res);
        
        $logger->debug("YAML-Dumped: ".YAML::Dump($res));
        my $num=$dbhits_ref->{$db};
        $idnresult->execute($self->{ID},$db,$hitrange,$storableres,$num,$queryid) or $logger->error($DBI::errstr);
    }
    $idnresult->finish();

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

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("delete from searchresults where sessionid = ? and queryid = ? and dbname = ? and offset = ? and hitrange = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$queryid,$database,$offset,$hitrange) or $logger->error($DBI::errstr);
    
    $idnresult=$dbh->prepare("insert into searchresults values (?,?,?,?,?,?,?)") or $logger->error($DBI::errstr);
    my $storableres=unpack "H*",Storable::freeze($recordlist->to_list);
    
    $logger->debug("YAML-Dumped: ".YAML::Dump($recordlist->to_list));
    my $num=$recordlist->get_size();
    $idnresult->execute($self->{ID},$database,$offset,$hitrange,$storableres,$num,$queryid) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub get_returnurl {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;    

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select returnurl from session where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $returnurl = $res->{returnurl};
    $idnresult->finish();

    return $returnurl;
}

sub get_db_histogram_of_query {
    my ($self,$queryid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->instance;    
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select dbname,sum(hits) as hitcount from searchresults where sessionid = ? and queryid = ? group by dbname order by hitcount desc") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$queryid) or $logger->error($DBI::errstr);
        
    my $hitcount=0;
    my @resultdbs=();
    
    while (my $res=$idnresult->fetchrow_hashref) {
        push @resultdbs, {
            trefferdb     => decode_utf8($res->{dbname}),
            trefferdbdesc => $dbinfotable->{dbnames}{decode_utf8($res->{dbname})},
            trefferzahl   => decode_utf8($res->{hitcount}),
        };
        
        $hitcount+=$res->{hitcount};
    }
    
    $idnresult->finish();

    # Rueckgabe: 
    return (\@resultdbs,$hitcount);
}

sub get_lastresultset {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    # Bestimmen des vorigen und naechsten Treffer einer
    # vorausgegangenen Kurztitelliste
    my $sessionresult=$dbh->prepare("select lastresultset from session where sessionid = ?") or $logger->error($DBI::errstr);
    $sessionresult->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    my $result=$sessionresult->fetchrow_hashref();
    my $lastresultstring="";
  
    if ($result->{'lastresultset'}) {
        $lastresultstring = decode_utf8($result->{'lastresultset'});
    }
  
    $sessionresult->finish();

    return $lastresultstring;
}

sub set_user {
    my ($self,$user)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("update session set benutzernr = ? where sessionID = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($user,$self->{ID}) or $logger->error($DBI::errstr);

    return;
}

sub logout_user {
    my ($self,$user)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("delete from session where benutzernr = ? and sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($user,$self->{ID}) or $logger->error($DBI::errstr);

    return;
}

sub is_authenticated_as {
    my ($self,$user)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select count(*) as rowcount from session where benutzernr = ? and sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($user,$self->{ID}) or $logger->error($DBI::errstr);
    my $res=$idnresult->fetchrow_hashref;

    my $rows=$res->{rowcount};

    # Authorized as    : 1
    # not Authorized as: 0
    return ($rows <= 0)?0:1;
}

sub get_info_of_all_active_sessions {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select * from session order by createtime") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);

    my @sessions=();

    while (my $result=$idnresult->fetchrow_hashref()) {
        my $singlesessionid = decode_utf8($result->{'sessionid'});
        my $createtime      = decode_utf8($result->{'createtime'});
        my $benutzernr      = decode_utf8($result->{'benutzernr'});

        my $idnresult2=$dbh->prepare("select count(*) as rowcount from queries where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult2->execute($singlesessionid) or $logger->error($DBI::errstr);

        my $res2=$idnresult2->fetchrow_hashref;
        my $numqueries=$res2->{rowcount};

        if (!$benutzernr) {
            $benutzernr="Anonym";
        }

        push @sessions, {
            singlesessionid => $singlesessionid,
            createtime      => $createtime,
            benutzernr      => $benutzernr,
            numqueries      => $numqueries,
        };
    }

    return @sessions;
}

sub get_info {
    my ($self,$sessionid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $singlesessionid=(defined $sessionid)?$sessionid:$self->{ID};
    my $idnresult=$dbh->prepare("select * from session where sessionID = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($singlesessionid) or $logger->error($DBI::errstr);
    
    my $result=$idnresult->fetchrow_hashref();
    my $createtime = decode_utf8($result->{'createtime'});
    my $benutzernr = decode_utf8($result->{'benutzernr'});

    return ($benutzernr,$createtime);
}


1;
