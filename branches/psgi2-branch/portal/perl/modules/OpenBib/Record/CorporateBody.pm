#####################################################################
#
#  OpenBib::Record::CorporateBody.pm
#
#  Koerperschaft
#
#  Dieses File ist (C) 2007-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Record::CorporateBody;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode 'decode_utf8';
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

    $logger->debug("Creating CorporateBody-Record-Object");

    if (defined $database){
        $self->{database} = $database;

        if ($logger->is_debug){
            $logger->debug("CorporateBody schema:".YAML::Dump($schema));
        }
        
        if (defined $schema){
            $logger->debug("Setting CorporateBody schema");
            $self->{schema} = $schema;
        }
        else {
            $logger->debug("Connecting to CorporateBody schema");
            $self->connectDB();
        }

        $logger->debug("Setting CorporateBody database: $database");
    }

    if (defined $id){
        $self->{id}       = $id;
        $logger->debug("Setting CorporateBody id: $id");
    }

    $logger->debug("CorporateBody-Record-Object created");

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

    # DBI "select category,content,indicator from corporatebody where id = ?";
    my $corporatebody_fields = $self->{schema}->resultset('Corporatebody')->search(
        {
            'me.id' => $id,
        },
        {
            select => ['corporatebody_fields.field','corporatebody_fields.mult','corporatebody_fields.subfield','corporatebody_fields.content'],
            as     => ['thisfield','thismult','thissubfield','thiscontent'],
            join   => ['corporatebody_fields'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    foreach my $item ($corporatebody_fields->all){
        my $field    = "C".sprintf "%04d",$item->{'thisfield'};
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
	$logger->info("Benoetigte Zeit fuer Corporatebodyenbestimmung ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    # Ausgabe der Anzahl verkuepfter Titel
    my $titcount = $self->get_number_of_titles;
    
    push @{$fields_ref->{C5000}}, {
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

    # DBI: "select content from corporatebody where id = ? and category=0001";
    my $corporatebody_fields = $self->{schema}->resultset('Corporatebody')->search(
        {
            'me.id'                 => $id,
            'corporatebody_fields.field'   => '0800',
        },
        {
            select => ['corporatebody_fields.content'],
            as     => ['thiscontent'],
            join   => ['corporatebody_fields'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    )->first;

    my $main_entry="Unbekannt";

    if ($corporatebody_fields){
        $main_entry = $corporatebody_fields->{'thiscontent'};
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

sub save_record {
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

    if ($id){
        my $record_exists = $self->{schema}->resultset('Corporatebody')->search(
            {
                'me.id' => $id,
            },
        )->count;

        # Wenn noch nicht da, dann eintragen,
        if (!$record_exists){

            $logger->debug("Record doesn't exist. Creating.");
            
            my $fields_ref = $self->{_fields};
            
            # Primaeren Normdatensatz erstellen und schreiben

            my $create_ref = {
                id => $id,
            };
            my $create_tstamp = "1970-01-01 12:00:00";
            
            if (defined $fields_ref->{'0002'} && defined $fields_ref->{'0002'}[0]) {
                $create_tstamp = $fields_ref->{'0002'}[0]{content};
                if ($create_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
                    $create_tstamp=$3."-".$2."-".$1." 12:00:00";
                }
                $create_ref->{tstamp_create} = $create_tstamp;
            }
        
            my $update_tstamp = "1970-01-01 12:00:00";
        
            if (exists $fields_ref->{'0003'} && exists $fields_ref->{'0003'}[0]) {
                $update_tstamp = $fields_ref->{'0003'}[0]{content};
                if ($update_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
                    $update_tstamp=$3."-".$2."-".$1." 12:00:00";
                }
                $create_ref->{tstamp_update} = $update_tstamp;
            }

            $self->{schema}->resultset('Corporatebody')->create($create_ref);
        }

        my $record = $self->{schema}->resultset('Corporatebody')->single(
            {
                'me.id' => $id,
            },
        );

        $record->corporatebody_fields->delete;
        
        # Ausgabe der Anzahl verkuepfter Titel
        my $titcount = $self->get_number_of_titles;
        
        push @{$self->{fields}{C5000}}, {
            content => $titcount,
        };

        $logger->debug("Populating new fields.");

        my $fields_ref = $self->get_fields;

        my $corporatebody_fields_ref = [];

        foreach my $field (keys %$fields_ref){
            foreach my $content_ref (@{$fields_ref->{$field}}){
                $content_ref->{corporatebodyid}    = $id;
                $content_ref->{field} = $field;
                push @$corporatebody_fields_ref, $content_ref;
            }
        }
        
        $record->corporatebody_fields->populate($corporatebody_fields_ref);
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Benoetigte Zeit ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }

    }
    # sonst komplett neu anlegen inkl. ID
    else {
        # Derzeit koennen keine Titel ohne bereits festgelegte ID aufgenommen werden.
        # Hierzu wird zukuenftig eine Kombination aus Trigger und Sequenztabelle noetig, mit der zusaetzlichen Problematik,
        # dass die Titel-ID als Textfeld definiert ist. Hier koennen nur Numerische IDs darin verwendet werden, da sonst kein
        # Hochzaehlen moeglich ist.
    }

    $logger->debug("Record with ID $id saved to database $self->{database}");
    return $self;
}

sub delete_record {
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

    # DBI "select category,content,indicator from corporatebody where id = ?";
    my $corporatebody = $self->{schema}->resultset('Corporatebody')->search(
        {
            'me.id' => $id,
        },
    );

    $corporatebody->corporatebody_fields->delete;
    $corporatebody->title_people->delete;

    $logger->debug("Deleted title $self->{id} in database $self->{database}");
    
    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer Corporatebodybestimmung ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

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

    # DBI: "select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=3";
    my $titlecount = $self->{schema}->resultset('Corporatebody')->search(
        {
            'me.id'                 => $id,
        },
        {
            join   => ['title_corporatebodies'],
            columns  => [ qw/title_corporatebodies.titleid/ ], # columns/group_by -> versch. titleid 
            group_by => [ qw/title_corporatebodies.titleid/ ], # via group_by und nicht via distinct (Performance)

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
