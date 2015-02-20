#####################################################################
#
#  OpenBib::Record::Subject.pm
#
#  Schlagworte
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

package OpenBib::Record::Subject;

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

    $logger->debug("Creating Subject-Record-Object");

    if (defined $database){
        $self->{database} = $database;

        if ($logger->is_debug){
            $logger->debug("Subject schema:".YAML::Dump($schema));
        }
        
        if (defined $schema){
            $logger->debug("Setting Subject schema");
            $self->{schema} = $schema;
        }
        else {
            $logger->debug("Connecting to Subject schema");
            $self->connectDB();
        }
        $logger->debug("Setting subject database: $database");
    }

    if (defined $id){
        $self->{id}       = $id;
        $logger->debug("Setting subject id: $id");
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

    # DBI "select category,content,indicator from subject where id = ?";
    my $subject_fields = $self->{schema}->resultset('Subject')->search(
        {
            'me.id' => $id,
        },
        {
            select => ['subject_fields.field','subject_fields.mult','subject_fields.subfield','subject_fields.content'],
            as     => ['thisfield','thismult','thissubfield','thiscontent'],
            join   => ['subject_fields'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    foreach my $item ($subject_fields->all){
        my $field    = "S".sprintf "%04d",$item->{'thisfield'};
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
	$logger->info("Benoetigte Zeit fuer Subjectenbestimmung ist ".timestr($timeall));
	undef $atime;
	undef $btime;
	undef $timeall;
    }

    if ($config->{benchmark}) {
	$atime=new Benchmark;
    }

    # Ausgabe der Anzahl verkuepfter Titel
    my $titcount = $self->get_number_of_titles;
    
    push @{$fields_ref->{S5000}}, {
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

    # DBI: "select content from subject where id = ? and category=0001";
    my $subject_fields = $self->{schema}->resultset('SubjectField')->search(
        {
            'subjectid.id' => $id,
            'me.field'     => '0800',
        },
        {
            order_by => ['me.mult ASC'],
            select => ['me.content'],
            as     => ['thiscontent'],
            join   => ['subjectid'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    my $main_entry  = "Unbekannt";
    
    my @mainentries = ();
    foreach my $item ($subject_fields->all){
        push @mainentries, $item->{'thiscontent'};
    }

    if (@mainentries){
        $main_entry = join (' / ',@mainentries);
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
        my $record_exists = $self->{schema}->resultset('Subject')->search(
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

            $self->{schema}->resultset('Subject')->create($create_ref);
        }

        my $record = $self->{schema}->resultset('Subject')->single(
            {
                'me.id' => $id,
            },
        );

        $record->subject_fields->delete;
        
        # Ausgabe der Anzahl verkuepfter Titel
        my $titcount = $self->get_number_of_titles;
        
        push @{$self->{fields}{S5000}}, {
            content => $titcount,
        };

        $logger->debug("Populating new fields.");

        my $fields_ref = $self->get_fields;

        my $subject_fields_ref = [];

        foreach my $field (keys %$fields_ref){
            foreach my $content_ref (@{$fields_ref->{$field}}){
                $content_ref->{subjectid}    = $id;
                $content_ref->{field} = $field;
                push @$subject_fields_ref, $content_ref;
            }
        }
        
        $record->subject_fields->populate($subject_fields_ref);
        
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

    # DBI "select category,content,indicator from subject where id = ?";
    my $subject = $self->{schema}->resultset('Subject')->search(
        {
            'me.id' => $id,
        },
    );

    $subject->subject_fields->delete;
    $subject->title_people->delete;

    $logger->debug("Deleted title $self->{id} in database $self->{database}");
    
    if ($config->{benchmark}) {
	$btime=new Benchmark;
	$timeall=timediff($btime,$atime);
	$logger->info("Benoetigte Zeit fuer Subjectbestimmung ist ".timestr($timeall));
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

    # DBI: "select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=4";
    my $titlecount = $self->{schema}->resultset('Subject')->search(
        {
            'me.id'                 => $id,
        },
        {
            join   => ['title_subjects'],
            columns  => [ qw/title_subjects.titleid/ ], # columns/group_by -> versch. titleid 
            group_by => [ qw/title_subjects.titleid/ ], # via group_by und nicht via distinct (Performance)

        }
    )->count;

    return $titlecount;
}

sub to_rawdata {
    my ($self) = @_;

    return $self->{_fields};
}

# unnoetiges Prototype, da sonst unnoetige Warning
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
