#####################################################################
#
#  OpenBib::Search::Z3950::USBK
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

package OpenBib::Search::Z3950::USBK;

use base 'OpenBib::Search::Z3950';

use strict;
use warnings;
use lib '/usr/lib/perl5';

no warnings 'redefine';
use utf8;

use Apache::Reload;
use Apache::Request ();
use DBI;
use Encode; # 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Encode::MAB2;
use ZOOM;
use SOAP::Lite;
use Storable;
use YAML ();

use OpenBib::Search::Z3950::USBK::Config;
use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config %z39config);

*config    = \%OpenBib::Config::config;
*z39config = \%OpenBib::Search::Z3950::USBK::Config;

if ($OpenBib::Config::config{benchmark}){
    use Benchmark ':hireswallclock';
}

sub new {
    my ($class) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    my $z39config = new OpenBib::Search::Z3950::USBK::Config();
    
    my $conn = new ZOOM::Connection($z39config->{hostname}, $z39config->{port},
                                    databaseName          => $z39config->{databaseName},
                                    user                  => $z39config->{user},
                                    password              => $z39config->{password},
                                    groupid               => $z39config->{groupid},
                                    preferredRecordSyntax => $z39config->{preferredRecordSyntax},
                                    querytype             => $z39config->{querytype},
                                ) or $logger->error_die("Connection Error:".$!);
    $self->{conn} = $conn;

    return $self;
}

sub search {
    my ($self,$searchquery_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  =  new OpenBib::Config();

    my $pqfpath = (-e "$config->{base_dir}/conf/cql/USBK/pqf.properties")?"$config->{base_dir}/conf/cql/USBK/pqf.properties":"$config->{base_dir}/conf/cql/pqf.properties";
    
    $self->{conn}->option(cqlfile => $pqfpath);

    $logger->debug("blabla");
    my @querystrings=();
    
    if ($searchquery_ref->{fs}{val}){
        push @querystrings, "free all \"".$searchquery_ref->{fs}{val}."\"";
    }
    if ($searchquery_ref->{verf}{val}){
        push @querystrings, $searchquery_ref->{verf}{bool}." author all \"".$searchquery_ref->{verf}{val}."\"";
    }
    if ($searchquery_ref->{hst}{val}){
        push @querystrings, $searchquery_ref->{hst}{bool}." title all \"".$searchquery_ref->{hst}{val}."\"";
    }
    if ($searchquery_ref->{swt}{val}){
        push @querystrings, $searchquery_ref->{verf}{bool}." subject all \"".$searchquery_ref->{swt}{val}."\"";
    }
    if ($searchquery_ref->{kor}{val}){
        push @querystrings, $searchquery_ref->{kor}{bool}." corp all \"".$searchquery_ref->{kor}{val}."\"";
    }

    my $querystring  = join(" ",@querystrings);
    $querystring     =~s/^(?:AND|OR|NOT) //;

    $logger->debug("Z39.50 CQL-Query: ".$querystring);
    my $query = new ZOOM::Query::CQL2RPN($querystring, $self->{conn});

    #    my $query = new ZOOM::Query::CQL($querystring);
#    my $querystring = new ZOOM::Query::CQL(lc($searchquery_ref->{fs}{norm}));

    my $resultset = $self->{conn}->search($query) or $logger->error_die("Search Error: ".$self->{conn}->errmsg());

    $self->{rs} = $resultset;

}

sub get_resultlist {
    my ($self,$offset,$hitrange)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $start = $offset+1;
    my $end   = $offset+$hitrange;

    if ($start >= $self->{rs}->size() || $start >= $self->{rs}->size()){
        return ();
    }
    
    # Pre-Cache Results
    $self->{rs}->records($offset, $hitrange, 0);
    
    my @resultlist=();
    foreach my $i ($start..$end) {
        my $rec  = $self->{rs}->record($i-1);

        my $rrec = $rec->raw();

        $logger->debug("Raw Record: ".$rrec);

        
        push @resultlist, $self->to_openbib_list($rrec);
    }

    $logger->debug(YAML::Dump(\@resultlist));

    return @resultlist;
}

sub get_singletitle {
    my ($self,$id)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $resultset = $self->{conn}->search_pqf('@attr 1=1007 '.$id) or $logger->error_die("Search Error: ".$self->{conn}->errmsg());

    $self->{rs} = $resultset;

    $self->{rs}->option(elementSetName => "F");

    my $rec  = $self->{rs}->record(0);
    
    my $rrec = $rec->raw();

    return $self->to_openbib_full($rrec);
}

1;

