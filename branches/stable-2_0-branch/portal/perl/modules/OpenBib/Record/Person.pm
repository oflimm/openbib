#####################################################################
#
#  OpenBib::Record::Person.pm
#
#  Person
#
#  Dieses File ist (C) 2007 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Record::Person;

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

use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Search::Util;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}       : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $self = { };

    bless ($self, $class);

    $self->{config}         = $config;

    if (defined $database){
        $self->{database} = $database;

        $self->{dbh} = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
    }
    
    $logger->debug("Person-Record-Object created: ".YAML::Dump($self));
    return $self;
}

sub get_full_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                : undef;
    
    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $normset_ref={};

    $self->{id      }        = $id;
    $normset_ref->{id      } = $id;
    $normset_ref->{database} = $self->{database};

    my ($atime,$btime,$timeall);

    if ($self->{config}->{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select category,content,indicator from aut where id = ?";
    my $request=$self->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($id);

    while (my $res=$request->fetchrow_hashref) {
        my $category  = "P".sprintf "%04d",$res->{category };
        my $indicator =        decode_utf8($res->{indicator});
        my $content   =        decode_utf8($res->{content  });
        
        push @{$normset_ref->{$category}}, {
            indicator => $indicator,
            content   => $content,
        };
    }

    if ($self->{config}->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($self->{config}->{benchmark}) {
	$atime=new Benchmark;
    }

    # Ausgabe der Anzahl verkuepfter Titel
    $sqlrequest="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=2";
    $request=$self->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($id);
    my $res=$request->fetchrow_hashref;
    
    push @{$normset_ref->{P5000}}, {
        content => $res->{conncount},
    };

    if ($self->{config}->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    $request->finish();

    $self->{normset}=$normset_ref;

    return $self;
}

sub to_rawdata {
    my ($self) = @_;

    return $self->{normset};
}

sub get_name {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my ($atime,$btime,$timeall);

    if ($self->{config}->{benchmark}) {
	$atime=new Benchmark;
    }

    my $sqlrequest;

    $sqlrequest="select content from aut where id = ? and category=0001";
    my $request=$self->{dbh}->prepare($sqlrequest) or $logger->error($DBI::errstr);
    $request->execute($id);
    
    my $res=$request->fetchrow_hashref;
    
    if ($self->{config}->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer '$sqlrequest' ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    my $ans="Unbekannt";
    if (defined $res->{content}) {
        $ans = decode_utf8($res->{content});
    }

    $request->finish();

    $self->{name}=$ans;

    return $self;
}

sub name_as_string {
    my $self=shift;
    
    return $self->{name};
}

sub DESTROY {
    my $self = shift;

    if (exists $self->{dbh}){
        $self->{dbh}->disconnect();
    }
    
    return;
}

1;
