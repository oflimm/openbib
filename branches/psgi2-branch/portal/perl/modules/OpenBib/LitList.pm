#####################################################################
#
#  OpenBib::LitList
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::LitList;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Encode qw(decode_utf8 encode_utf8);
use Log::Log4perl qw(get_logger :levels);
use YAML::Syck;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Schema::DBI;
use OpenBib::Record::Title;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $id           = exists $arg_ref->{id}
        ? $arg_ref->{id}             : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    if (defined $id){
        $self->{id}       = $id;
    }

    $self->{_litlist}     = [];
    $self->{_properties}  = {};
    $self->{_size}        = 0;

    return $self;
}

sub load {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Schema::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$self->{id});

    return;
}

#sub add_litlist {
sub store {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $title               = exists $arg_ref->{title}
        ? $arg_ref->{title}               : 'Literaturliste';
    my $type                = exists $arg_ref->{type}
        ? $arg_ref->{type}                : 1;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Schema::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    #return if (!$titleid || !$dbname || !$loginname || !$tags);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    
    my $request=$dbh->prepare("insert into litlists (userid,title,type) values (?,?,?)") or $logger->error($DBI::errstr);
    $request->execute($self->{id},$title,$type) or $logger->error($DBI::errstr);

    return;
}

sub update {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $title               = exists $arg_ref->{title}
        ? $arg_ref->{title}               : 'Literaturliste';
    my $type                = exists $arg_ref->{type}
        ? $arg_ref->{type}                : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Schema::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$self->{id} || !$title || !$type);

    # Ratings sind Zahlen und Reviews, Titel sowie Nicknames bestehen nur aus Text
    $title    =~s/[^-+\p{Alphabetic}0-9\/:. '()"\?!]//g;
    
    my $request=$dbh->prepare("update litlists set title=?, type=? where id=?") or $logger->error($DBI::errstr);
    $request->execute($title,$type,$self->{id}) or $logger->error($DBI::errstr);

    return;
}

#sub add_litlistentry {
sub add_record {
    my ($self,$record)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Schema::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$record->{id} || !$record->{database} || !$self->{id} );

    my $request=$dbh->prepare("delete from litlistitems where litlistid=? and titleid=? and dbname=?") or $logger->error($DBI::errstr);
    $request->execute($self->{id},$record->{id},$record->{database}) or $logger->error($DBI::errstr);

    $request=$dbh->prepare("insert into litlistitems (litlistid,titleid,dbname) values (?,?,?)") or $logger->error($DBI::errstr);
    $request->execute($self->{id},$record->{id},$record->{database}) or $logger->error($DBI::errstr);

    return;
}

#sub del_litlistentry {
sub del_record {
    my ($self,$record)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Schema::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$self->{id} || !$record->{id} || !$record->{database});

    my $request=$dbh->prepare("delete from litlistitems where litlistid=? and titleid=? and dbname=?") or $logger->error($DBI::errstr);
    $request->execute($self->{id},$record->{id},$record->{database}) or $logger->error($DBI::errstr);

    return;
}

#sub get_litlistentries {
sub _get_records {
    my ($self)=@_;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Schema::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return if (!defined $dbh);

    return if (!$self->{id});

    my $request=$dbh->prepare("select titleid,dbname,tstamp from litlistitems where litlistid=?") or $logger->error($DBI::errstr);
    $request->execute($self->{id}) or $logger->error($DBI::errstr);

    while (my $result=$request->fetchrow_hashref){
      my $titelidn  = decode_utf8($result->{titleid});
      my $database  = decode_utf8($result->{dbname});
      my $tstamp    = decode_utf8($result->{tstamp});
      
      my $dbh
	= DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
	    or $logger->error_die($DBI::errstr);
	
      push @{$self->{_litlist}}, {            
#				  id        => $titelidn,
				  record => OpenBib::Record::Title->new({id => $titelidn, database => $database})->load_brief_record,
				  tstamp    => $tstamp,

#				  id        => $titelidn,
#				  title     => OpenBib::Search::Util::get_tit_listitem_by_idn({
#                    titleid            => $titelidn,
#                    dbh               => $dbh,
#                    database          => $database,
#											    }),
				
				 };
      $dbh->disconnect();
    }
    
    return $self->{_litlist};
}

#sub get_number_of_litlistentries {
sub size {
    my ($self,$arg_ref)=@_;
    
    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Schema::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return undef if (!defined $dbh);

    return if (!$self->{id});

    my $request=$dbh->prepare("select count(litlistid) as numofentries from litlistitems where litlistid=?") or $logger->error($DBI::errstr);
    $request->execute($self->{id}) or $logger->error($DBI::errstr);

    my $result=$request->fetchrow_hashref;

    return $result->{numofentries};
}

sub load_properties {
    my ($self,$arg_ref)=@_;

    # Set defaults
    my $litlistid           = exists $arg_ref->{litlistid}
        ? $arg_ref->{litlistid}           : undef;

    # Log4perl logger erzeugen
  
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Schema::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error($DBI::errstr);

    return {} if (!defined $dbh);

    return {} if (!$self->{id});

    my $request=$dbh->prepare("select * from litlists where id = ?") or $logger->error($DBI::errstr);
    $request->execute($self->{id}) or $logger->error($DBI::errstr);

    my $result=$request->fetchrow_hashref;

    $self->{title}  = decode_utf8($result->{title});
    $self->{type}   = $result->{type};
    $self->{tstamp} = $result->{tstamp};
    $self->{userid} = $result->{userid};
    $self->{_size}  = $self->size;

    return;
}

sub size {
    my ($self)=@_;

    return $self->{_size};
}

1;
=head1 NAME

OpenBib::LitList - Objekt einer Literaturliste

=head1 DESCRIPTION

Dieses Objekt wird derzeit noch nicht verwendet. In ihm sollen alle
Literaturlisten-spezifischen Methoden zusammengefasst werden, die sich
derzeit z.B. noch in OpenBib::User befinden.

=head1 SYNOPSIS

 use OpenBib::LitList;

=head1 METHODS


=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
