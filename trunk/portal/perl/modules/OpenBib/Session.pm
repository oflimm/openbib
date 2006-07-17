#####################################################################
#
#  OpenBib::Session
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $sessionID   = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $self = { };

    bless ($self, $class);

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    $self->{dbh}       = $dbh;

    # Setzen der Defaults

    if (!defined $sessionID){
        $sessionID = $self->_init_new_session();
    }
    else {
        if (!$self->is_valid($sessionID)){
            $sessionID = undef;
        }
    }
    
    $self->{ID}        = $sessionID;

    $logger->debug("Session-Object created: ".YAML::Dump($self));
    return $self;
}

sub _init_new_session {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sessionID="";

    my $havenewsessionID=0;
    
    while ($havenewsessionID == 0) {
        my $gmtime = localtime(time);
        my $md5digest=Digest::MD5->new();
    
        $md5digest->add($gmtime . rand('1024'). $$);
    
        $sessionID=$md5digest->hexdigest;
    
        # Nachschauen, ob es diese ID schon gibt
        my $idnresult=$self->{dbh}->prepare("select count(sessionid) from session where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

        my @idn=$idnresult->fetchrow_array();
        my $anzahl=$idn[0];
    
        # Wenn wir nichts gefunden haben, dann ist alles ok.
        if ($anzahl == 0 ) {
            $havenewsessionID=1;
      
            my $createtime = POSIX::strftime('%Y-%m-%d% %H:%M:%S', localtime());


            my $queryoptions_ref={
                hitrange  => undef,
                offset    => undef,
                maxhits   => undef,
                l         => undef,
                profil    => undef,
                autoplus  => undef,
            };

            # Eintrag in die Datenbank
            $idnresult=$self->{dbh}->prepare("insert into session (sessionid,createtime,queryoptions) values (?,?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$createtime,YAML::Dump($queryoptions_ref)) or $logger->error($DBI::errstr);

            
            my $request=$self->{dbh}->prepare("insert into sessionmask values (?,?)");
            $request->execute($sessionID,'simple');
            $request->finish();
        }
        $idnresult->finish();
    }
    return $sessionID;
}

sub is_valid {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (defined $self->{ID} && $self->{ID} eq "-1") {
        return 1;
    }

    my $idnresult=$self->{dbh}->prepare("select count(sessionid) from session where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    my @idn=$idnresult->fetchrow_array();
    my $anzahl=$idn[0];

    $idnresult->finish();

    if ($anzahl == 1) {
        return 1;
    }

    return 0;
}

sub load_queryoptions {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("select queryoptions from session where sessionid = ?") or $logger->error($DBI::errstr);

    $request->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    my $res=$request->fetchrow_hashref();

    $logger->debug($res->{queryoptions});
    my $queryoptions_ref = YAML::Load($res->{queryoptions});

    $request->finish();

    return $queryoptions_ref;
}

sub dump_queryoptions {
    my ($self,$sessionID,$queryoptions_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$self->{dbh}->prepare("update session set queryoptions=? where sessionid = ?") or $logger->error($DBI::errstr);

    $request->execute(YAML::Dump($queryoptions_ref),$self->{ID}) or $logger->error($DBI::errstr);

    $request->finish();

    return;
}

sub merge_queryoptions {
    my ($self,$options1_ref,$options2_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Eintragungen in options1_ref werden, wenn sie in options2_ref
    # gesetzt sind, von diesen ueberschrieben
    
    foreach my $key (keys %$options1_ref){
        if (exists $options2_ref->{$key}){
            $options1_ref->{$key}=$options2_ref->{$key};
        }
    }
}

sub get_queryoptions {
    my ($self,$query) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Hinweis: Bisher wuerde statt $query direkt das Request-Objekt $r
    # uebergeben und an dieser Stelle wieder ein $query-Objekt via
    # Apache::Request daraus erzeugt. Bei Requests, die via POST
    # sowohl mit dem enctype multipart/form-data wie auch
    # multipart/form-data abgesetzt wurden, lassen sich keine
    # Parameter ala sessionID extrahieren.  Das ist ein grosses
    # Problem. Andere Informationen lassen sich ueber das $r
    # aber sehr wohl extrahieren, z.B. der Useragent.

    if (!defined $self->{ID}){
      $logger->fatal("No SessionID");
      return {};
    }	

    # Queryoptions zur Session einladen (default: alles undef)
    my $queryoptions_ref = $self->load_queryoptions();

    my $default_queryoptions_ref={
        hitrange  => 20,
        offset    => 1,
        maxhits   => 500,
        l         => 'de',
        profil    => '',
        autoplus  => '',
    };

    my $altered=0;
    # Abgleich mit uebergebenen Parametern
    # Uebergebene Parameter 'ueberschreiben'und gehen vor
    foreach my $option (keys %$default_queryoptions_ref){
        if (defined $query->param($option)){
            $queryoptions_ref->{$option}=$query->param($option);
	    $logger->debug("Option $option received via HTTP");
	    $altered=1;
        }
    }

    # Abgleich mit Default-Werten:
    # Verbliebene "undefined"-Werte werden mit Standard-Werten belegt
    foreach my $option (keys %$queryoptions_ref){
        if (!defined $queryoptions_ref->{$option}){
            $queryoptions_ref->{$option}=$default_queryoptions_ref->{$option};
	    $logger->debug("Option $option got default value");
	    $altered=1;
        }
    }

    if ($altered){
      $self->dump_queryoptions($queryoptions_ref);
      $logger->debug("Options changed and dumped to DB");
    }

    return $queryoptions_ref;
}

sub get_viewname {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Assoziierten View zur Session aus Datenbank holen
    my $idnresult=$self->{dbh}->prepare("select viewname from sessionview where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
  
    my $result=$idnresult->fetchrow_hashref();
  
    # Entweder wurde ein 'echter' View gefunden oder es wird
    # kein spezieller View verwendet (view='')
    my $view = decode_utf8($result->{'viewname'}) || '';

    $idnresult->finish();

    return $view;
}

sub get_profile {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select profile from sessionprofile where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $result=$idnresult->fetchrow_hashref();
  
    my $prevprofile="";
  
    if (defined($result->{'profile'})) {
        $prevprofile = decode_utf8($result->{'profile'});
    }

    $idnresult->finish();

    return $prevprofile;
}

sub get_mask {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select masktype from sessionmask where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $result=$idnresult->fetchrow_hashref();
    my $setmask = decode_utf8($result->{'masktype'});
    
    $idnresult->finish();
    return $setmask;
}

sub set_mask {
    my ($self,$mask)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("update sessionmask set masktype = ? where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$mask) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}



sub set_view {
    my ($self,$view)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("insert into sessionview values (?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$view) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub set_dbchoice {
    my ($self,$dbname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("insert into dbchoice (sessionid,dbname) values (?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID},$dbname) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub get_dbchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select dbname from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);

    my @dbchoice=();
    while (my $res=$idnresult->fetchrow_hashref){
        push @dbchoice, decode_utf8($res->{'dbname'});

    }
    $idnresult->finish();

    return @dbchoice;
}

sub clear_dbchoice {
    my ($self)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("delete from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub get_number_of_dbchoice {
    my ($self,$dbname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $idnresult=$self->{dbh}->prepare("select count(dbname) as rowcount from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($self->{ID}) or $logger->error($DBI::errstr);
    my $res = $idnresult->fetchrow_hashref();
    my $numofdbs = $res->{rowcount};
    $idnresult->finish();

    return $numofdbs;
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

        push @nresultset, "$resdatabase:$katkey";
    }

    my $resultsetstring=join("|",@nresultset);

    my $sessionresult=$self->{dbh}->prepare("update session set lastresultset = ? where sessionid = ?") or $logger->error($DBI::errstr);
    $sessionresult->execute($resultsetstring,$self->{ID}) or $logger->error($DBI::errstr);
    $sessionresult->finish();

    return;
}

sub DESTROY {
    my $self = shift;
    $self->{dbh}->disconnect();

    return;
}

1;
