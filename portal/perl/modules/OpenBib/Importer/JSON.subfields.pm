#####################################################################
#
#  OpenBib::Importer::JSON.pm
#
#  Basis-Klasse fuer JSON-Importe
#
#  Dieses File ist (C) 2014-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Importer::JSON;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Digest::MD5 qw(md5_hex);
use Encode qw/decode_utf8/;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use YAML ();
use Business::ISBN;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Container;
use OpenBib::Index::Document;

my %char_replacements = (
    
    # Zeichenersetzungen
    "\n"     => "<br\/>",
    "\r"     => "\\r",
    ""     => "",
#    "\x{00}" => "",
#    "\x{80}" => "",
#    "\x{87}" => "",
);

my $chars_to_replace = join '|',
    keys %char_replacements;

$chars_to_replace = qr/$chars_to_replace/;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $database  = exists $arg_ref->{database}
        ? $arg_ref->{database}       : undef;

    my $storage   = exists $arg_ref->{storage}
        ? $arg_ref->{storage}        : {};
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->new;
    
    my $conv_config = OpenBib::Conv::Config->instance({dbname => $database}); 

    my $self = { };

    bless ($self, $class);

    $logger->debug("Creating Importer-Object");

    if (defined $database){
        $self->{database} = $database;
        $logger->debug("Setting database: $database");
    }

    if (defined $conv_config){
        $self->{conv_config}       = $conv_config;
    }

    # Storage
    if (defined $storage){
        $self->{storage}       = $storage;
        $logger->debug("Setting storage");
    }
    
    # Serials
    $self->{'serialid'} = 1;

    $self->set_defaults;

    return $self;
}

# Common processing method for persons, corporate bodies, classifications and subjects
# titles implement their own much more complex method

sub process {
    my ($self,$arg_ref) = @_;

    my $json      = exists $arg_ref->{json}
        ? $arg_ref->{json}           : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self unless (defined $json);

    my $database    = $self->{database};

    $logger->debug("Processing JSON: $json");

    # Cleanup
    $self->{_columns}                = [];
    $self->{_columns_fields}         = [];
    
    my $inverted_ref  = $self->{conv_config}{$self->{'inverted_authority'}};
    my $blacklist_ref = $self->{conv_config}{$self->{'blacklist_authority'}};
    
    my $record_ref;

    my $import_hash = "";

    if ($json){
        $import_hash = md5_hex($json);
        
        eval {
            $record_ref = decode_json $json;
        };
        
        if ($@){
            $logger->error("Skipping record: $@");
            return;
        }
    }

    $logger->debug("JSON decoded");
    
    my $id            = $self->cleanup_content($record_ref->{id});
    my $fields_ref    = $record_ref->{fields};

    $self->{id}       = $id;
    
    # Primaeren Normdatensatz erstellen und schreiben
            
    my $create_tstamp = "1970-01-01 12:00:00";
    
    if (defined $fields_ref->{'0002'} && defined $fields_ref->{'0002'}[0]) {
        $create_tstamp = $fields_ref->{'0002'}[0]{content};
        if ($create_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
            $create_tstamp=$3."-".$2."-".$1." 12:00:00";
        }
    }
    
    my $update_tstamp = "1970-01-01 12:00:00";
    
    if (defined $fields_ref->{'0003'} && defined $fields_ref->{'0003'}[0]) {
        $update_tstamp = $fields_ref->{'0003'}[0]{content};
        if ($update_tstamp=~/^(\d\d)\.(\d\d)\.(\d\d\d\d)/) {
            $update_tstamp=$3."-".$2."-".$1." 12:00:00";
        }            
    }

    push @{$self->{_columns}}, [$id,$create_tstamp,$update_tstamp,$import_hash];
    
    # Ansetzungsformen fuer Kurztitelliste merken
    
    my $mainentry;
    
    if (defined $fields_ref->{'0800'} && defined $fields_ref->{'0800'}[0] ) {
        $mainentry = $fields_ref->{'0800'}[0]{content};
    }
    
    if ($mainentry) {
        $self->process_mainentry({ id => $id, mainentry => $mainentry, field => $fields_ref});
    }
    
    foreach my $field (keys %{$fields_ref}) {
        next if ($field eq "id" || defined $blacklist_ref->{$field} );
        foreach my $item_ref (@{$fields_ref->{$field}}) {
            if (defined $inverted_ref->{$field}->{index}) {
                foreach my $searchfield (keys %{$inverted_ref->{$field}->{index}}) {
                    my $weight = $inverted_ref->{$field}->{index}{$searchfield};
                    
                    my $hash_ref = {};
                    if (defined $self->{storage}{$self->{'indexed_authority'}}{$id}) {
                        $hash_ref = $self->{storage}{$self->{'indexed_authority'}}{$id};
                    }
                    push @{$hash_ref->{$searchfield}{$weight}}, ["$self->{'field_prefix'}$field",$item_ref->{content}];
                    
                    $self->{storage}{$self->{'indexed_authority'}}{$id} = $hash_ref;
                }
            }
            
            if ($id && $field && defined $item_ref->{content} && length($item_ref->{content}) > 0) {
                $item_ref->{content} = $self->cleanup_content($item_ref->{content});
                # Abhaengige Feldspezifische Saetze erstellen und schreiben
                push @{$self->{_columns_fields}}, [$self->{serialid},$id,$field,$item_ref->{mult},$item_ref->{subfield},$item_ref->{content}];
                #push @{$self->{_columns_fields}}, ['',$id,$field,$item_ref->{mult},$item_ref->{subfield},$item_ref->{content}];
                $self->{serialid}++;
            }
        }
    }
    
    return $self;
}

sub process_mainentry {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id         = exists $arg_ref->{id}
        ? $arg_ref->{id}              : undef;

    my $mainentry  = exists $arg_ref->{mainentry}
        ? $arg_ref->{mainentry}       : undef;

    my $fields_ref = exists $arg_ref->{fields}
        ? $arg_ref->{fields}          : {};
    

    $self->{storage}{$self->{'listitemdata_authority'}}{$id}=$mainentry;

    return;
}

sub get_id {
    my $self = shift;

    return (defined $self->{id})?$self->{id}:'';
}

sub get_columns {
    my $self = shift;

    return $self->{_columns};
}

sub get_columns_fields {
    my $self = shift;

    return $self->{_columns_fields};
}

sub get_fields {
}

sub add_fields {
}

sub set_record {
}

sub get_record {
}

sub get_storage {
    my $self = shift;
    return $self->{storage};
}

sub cleanup_content {
    my ($self,$content) = @_;
    
    return '' unless (defined $content);
    
    # Make PostgreSQL Happy    
    $content =~ s/\\/\\\\/g;
    $content =~ s/($chars_to_replace)/$char_replacements{$1}/g;
    
    return $content;
}

sub set_defaults {
    my $self=shift;

    # Stub: Setting defaults for field_prefix etc.

    return $self;
}

1;
