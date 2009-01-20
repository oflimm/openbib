#####################################################################
#
#  OpenBib::Record::Classification.pm
#
#  Notation/Systematik
#
#  Dieses File ist (C) 2007-2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Record::Classification;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Reload;
use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;
use Storable;
use YAML ();

use OpenBib::Search::Util;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $id        = exists $arg_ref->{id}
        ? $arg_ref->{id}             : undef;

    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}       : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    if (defined $database){
        $self->{database} = $database;
    }

    if (defined $id){
        $self->{id}       = $id;
    }

    $logger->debug("Classification-Record-Object created: ".YAML::Dump($self));
    return $self;
}

sub load_full_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $normset_ref={};

    $normset_ref->{id      } = $id;
    $normset_ref->{database} = $self->{database};

    my ($atime,$btime,$timeall);
    
    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    my $local_dbh = 0;
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
        $local_dbh = 1;
    }

    my $sqlrequest;

    $sqlrequest="select category,content,indicator from notation where id = ?";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($id);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "N".sprintf "%04d",$res->{category };
        my $indicator =        decode_utf8($res->{indicator});
        my $content   =        decode_utf8($res->{content  });
        
        push @{$normset_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # Ausgabe der Anzahl verk"upfter Titel
    my $titcount = $self->get_number_of_titles;
    
    push @{$normset_ref->{N5000}}, {
        content => $titcount,
    };

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    $request->finish();

    $dbh->disconnect() if ($local_dbh);
    
    $self->{normset}=$normset_ref;

    return $self;
}

sub load_name {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my ($atime,$btime,$timeall);
    
    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    my $local_dbh = 0;
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
        $local_dbh = 1;
    }
    
    my $sqlrequest;

    $sqlrequest="select content from notation where id = ? and category=0001";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($id);
    
    my $res=$request->fetchrow_hashref;
  
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }
    
    my $notation="Unbekannt";
    
    if ($res->{content}) {
        $notation = decode_utf8($res->{content});
    }

    $request->finish();

    $dbh->disconnect() if ($local_dbh);
    
    $self->{name}=$notation;

    return $self;
}

sub get_number_of_titles {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;
    
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my $local_dbh = 0;
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
        $local_dbh = 1;
    }
    
    my $sqlrequest;

    # Ausgabe der Anzahl verk"upfter Titel
    $sqlrequest="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=5";
    my $request=$dbh->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($id);
    my $res=$request->fetchrow_hashref;
    
    return $res->{conncount},
}

sub to_rawdata {
    my ($self) = @_;

    return $self->{normset};
}

sub name_as_string {
    my $self=shift;
    
    return $self->{name};
}

1;
