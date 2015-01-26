#####################################################################
#
#  OpenBib::Record::Classification.pm
#
#  Klassifikation/Notation
#
#  Dieses File ist (C) 2007-2013 Oliver Flimm <flimm@openbib.org>
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

use Benchmark ':hireswallclock';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use YAML ();
use DBIx::Class::ResultClass::HashRefInflator;

use base 'OpenBib::Record';

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $id        = exists $arg_ref->{id}
        ? $arg_ref->{id}             : undef;

    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}       : undef;

    my $schema    = exists $arg_ref->{schema}
        ? $arg_ref->{schema}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $self = { };

    bless ($self, $class);

    $logger->debug("Creating Classification-Record-Object");    

    if (defined $database){
        $self->{database} = $database;

        if ($logger->is_debug){
            $logger->debug("Classification schema:".YAML::Dump($schema));
        }
        
        if (defined $schema){
            $logger->debug("Setting Classification schema");
            $self->{schema} = $schema;
        }
        else {
            $logger->debug("Connecting to Classification schema");
            $self->connectDB();
        }

        $logger->debug("Setting Classification database: $database");    
    }

    if (defined $id){
        $self->{id}       = $id;
        $logger->debug("Setting Classification id: $id");    
    }

    return $self;
}

sub load_full_record {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $fields_ref={};

    $self->{id      }        = $id;
#    $fields_ref->{id      } = $id;
#    $fields_ref->{database} = $self->{database};

    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    # DBI "select category,content,indicator from classification where id = ?";
    my $classification_fields = $self->{schema}->resultset('Classification')->search(
        {
            'me.id' => $id,
        },
        {
            select => ['classification_fields.field','classification_fields.mult','classification_fields.subfield','classification_fields.content'],
            as     => ['thisfield','thismult','thissubfield','thiscontent'],
            join   => ['classification_fields'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    foreach my $item ($classification_fields->all){
        my $field    = "N".sprintf "%04d",$item->{'thisfield'};
        my $subfield =                    $item->{'thissubfield'};
        my $mult     =                    $item->{'thismult'};
        my $content  =                    $item->{'thiscontent'};
        
        push @{$fields_ref->{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };
    }

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer Classificationenbestimmung ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    # Ausgabe der Anzahl verkuepfter Titel
    my $titcount = $self->get_number_of_titles;
    
    push @{$fields_ref->{N5000}}, {
        content => $titcount,
    };

    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($logger->is_debug){
        $logger->debug(YAML::Dump($fields_ref));
    }
    
    $self->{_fields}=$fields_ref;

    return $self;
}

sub load_name {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    $logger->debug("Loading main entry");
    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    # DBI: "select content from classification whree id = ? and category=0001";
    my $classification_fields = $self->{schema}->resultset('Classification')->search(
        {
            'me.id'                         => $id,
            'classification_fields.field'   => '0800',
        },
        {
            select => ['classification_fields.content'],
            as     => ['thiscontent'],
            join   => ['classification_fields'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    )->first;

    my $main_entry="Unbekannt";

    if ($classification_fields){
        $main_entry  =  $classification_fields->{'thiscontent'};
    }
    
    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    $self->{name}=$main_entry;

    return $self;
}

sub get_number_of_titles {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my ($atime,$btime,$timeall);

    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    # DBI: "select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=5";
    my $titlecount = $self->{schema}->resultset('Classification')->search(
        {
            'me.id'                 => $id,
        },
        {
            join   => ['title_classifications'],
            columns  => [ qw/title_classifications.titleid/ ], # columns/group_by -> versch. titleid 
            group_by => [ qw/title_classifications.titleid/ ], # via group_by und nicht via distinct (Performance)
        }
    )->count;

    return $titlecount;
}

sub to_rawdata {
    my ($self) = @_;

    return $self->{_fields};
}

sub to_json ($){
    my ($self)=@_;

    my $json_ref = {
        'id'        => $self->{id},
        'database'  => $self->{database},
        'fields'    => $self->{_fields},
    };

    return encode_json $json_ref;
}

sub name_as_string {
    my $self=shift;
    
    return $self->{name};
}


1;
