#####################################################################
#
#  OpenBib::Importer::JSON::Holding.pm
#
#  Exemplare
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

package OpenBib::Importer::JSON::Holding;

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

use base 'OpenBib::Importer::JSON';

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
    $self->{'title_holding_serialid'} = 1;

    $self->set_defaults;

    return $self;
}

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
    $self->{_columns_title_holding}  = [];
    
    my $inverted_ref  = $self->{conv_config}{$self->{'inverted_authority'}};
    
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

    # Primaeren Normdatensatz erstellen und schreiben

    push @{$self->{_columns}}, [$id,$import_hash];
    
    # Titelid bestimmen
    
    my $titleid;
    
    if (defined $fields_ref->{'0004'} && defined $fields_ref->{'0004'}[0] ) {
        $titleid = $fields_ref->{'0004'}[0]{content};
    }
    
    # Verknupefungen
    if ($titleid && $id) {
        push @{$self->{_columns_title_holding}}, [$self->{title_holding_serialid},'',$titleid,$id,''];

        $self->{title_holding_serialid}++;
    }
    
    foreach my $field (keys %{$fields_ref}) {
        next if ($field eq "id");
        
        foreach my $item_ref (@{$fields_ref->{$field}}) {
            next unless (defined $item_ref->{content});
	    my $subfield         = ($item_ref->{subfield})?$item_ref->{subfield}:'';
            if (defined $inverted_ref->{$field}{$subfield}->{index}) {
                foreach my $searchfield (keys %{$inverted_ref->{$field}{$subfield}->{index}}) {
                    my $weight = $inverted_ref->{$field}{$subfield}->{index}{$searchfield};
                    
                    my $hash_ref = {};
                    
                    if ($titleid) {
                        if (defined $self->{storage}{$self->{'indexed_authority'}}{$titleid}) {
                            $hash_ref = $self->{storage}{$self->{'indexed_authority'}}{$titleid};
                        }
                        
                        push @{$hash_ref->{$searchfield}{$weight}}, ["$self->{'field_prefix'}$field",$item_ref->{content}];
                        $self->{storage}{$self->{'indexed_authority'}}{$titleid} = $hash_ref;
                    }
                }
            }
            
            if ($id && $field && $item_ref->{content}) {
                $item_ref->{content} = $self->cleanup_content($item_ref->{content});
                # Abhaengige Feldspezifische Saetze erstellen und schreiben
                push @{$self->{_columns_fields}}, [$self->{serialid},$id,$field,$item_ref->{mult},$item_ref->{subfield},$item_ref->{content}];

                $self->{serialid}++;
            }
        }
    }
    
    # Signatur fuer Kurztitelliste merken
    
    if (exists $fields_ref->{'0014'} && $titleid) {
        my $array_ref= [];
        if (defined $self->{storage}{$self->{'listitemdata_authority'}}{$titleid}) {
            $array_ref = $self->{storage}{$self->{'listitemdata_authority'}}{$titleid};
        }
        push @$array_ref, $fields_ref->{'0014'}[0]{content};
        $self->{storage}{$self->{'listitemdata_authority'}}{$titleid}=$array_ref;
    }
    
    # Bestandsverlauf in Jahreszahlen umwandeln
    if ((defined $fields_ref->{'1204'}) && $titleid) {        
        my $array_ref=[];
        if (defined $self->{storage}{'listitemdata_enriched_years'}{$titleid}) {
            $array_ref = $self->{storage}{'listitemdata_enriched_years'}{$titleid};
        }
        
        foreach my $date (split(";",$self->cleanup_content($fields_ref->{'1204'}[0]{content}))) {
            if ($date =~/^.*?(\d\d\d\d)[^-]+?\s+-\s+.*?(\d\d\d\d)/) {
                my $startyear = $1;
                my $endyear   = $2;
                
                $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                for (my $year=$startyear;$year<=$endyear; $year++) {
                    $logger->debug("Adding year $year");
                    push @$array_ref, $year;
                }
            } elsif ($date =~/^.*?(\d\d\d\d)[^-]+?\s+-/) {
                my $startyear = $1;
                my $endyear   = $self->{'this_year'};
                $logger->debug("Expanding yearstring $date from $startyear to $endyear");
                for (my $year=$startyear;$year<=$endyear;$year++) {
                    $logger->debug("Adding year $year");
                    push @$array_ref, $year;
                }                
            } elsif ($date =~/(\d\d\d\d)/) {
                $logger->debug("Not expanding $date, just adding year $1");
                push @$array_ref, $1;
            }
        }

        $self->{storage}{'listitemdata_enriched_years'}{$titleid}=$array_ref;
    }
    
    return $self;
}

sub get_columns_title_holding {
    my $self = shift;

    return $self->{_columns_title_holding};
}

sub set_defaults {
    my $self=shift;

    $self->{'field_prefix'}           = 'X';
    $self->{'indexed_authority'}      = 'indexed_holding';
    $self->{'listitemdata_authority'} = 'listitemdata_holding';
    $self->{'inverted_authority'}     = 'inverted_holding';
    $self->{'this_year'} = `date +"%Y"`;
    
    return $self;
}

1;
