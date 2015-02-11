#####################################################################
#
#  OpenBib::Record.pm
#
#  Basisklasse
#
#  Dieses File ist (C) 2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Record;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Reload;
use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use SOAP::Lite;
use Storable;
use YAML ();

use OpenBib::Config;
use OpenBib::Schema::Catalog;
use OpenBib::Schema::Enrichment::Singleton;

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    eval {
        # UTF8: {'pg_enable_utf8'    => 1}
        $self->{schema} = OpenBib::Schema::Catalog->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},{'pg_enable_utf8'    => 1, pg_server_prepare => 0 }) or $logger->error_die($DBI::errstr);
    };
    
    if ($@){
        $logger->fatal("Unable to connect schema to database $self->{database}: DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}");
    }

    return;

}

sub connectEnrichmentDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    if ($self->{'enrichmntdbsingleton'}){
        eval {        
            #            $self->{enrich_schema} = OpenBib::Schema::Enrichment::Singleton->connect("DBI:Pg:dbname=$self->{systemdbname};host=$self->{systemdbhost};port=$self->{systemdbport}", $self->{systemdbuser}, $self->{systemdbpasswd}) or $logger->error_die($DBI::errstr);
            $self->{enrich_schema} = OpenBib::Schema::Enrichment::Singleton->connect("DBI:Pg:dbname=$self->{systemdbname};host=$self->{systemdbhost};port=$self->{systemdbport}", $self->{systemdbuser}, $self->{systemdbpasswd},{'pg_enable_utf8'    => 1, pg_server_prepare => 0}) or $logger->error_die($DBI::errstr);
            
        };
        
        if ($@){
            $logger->fatal("Unable to connect to database $self->{enrichmntdbname}");
        }
    }
    else {
        eval {
            # UTF8: {'pg_enable_utf8'    => 1}
            $self->{enrich_schema} = OpenBib::Schema::Enrichment->connect("DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd},{'pg_enable_utf8'    => 1, pg_server_prepare => 0 }) or $logger->error_die($DBI::errstr);
            # $self->{enrich_schema} = OpenBib::Schema::Enrichment->connect("DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $config->{enrichmntdbname}: DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}");
        }

    }
    
    return;
}

sub set_generic_attributes {
    my ($self,$arg_ref) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    foreach my $attribute (keys %$arg_ref){
        $self->{generic_attributes}{$attribute} = $arg_ref->{$attribute};     
    }    
    
    return $self;
}

sub get_generic_attributes {
    my ($self) = @_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($logger->is_debug){
        $logger->debug("Got: ".YAML::Dump($self->{generic_attributes}));
    }   
    
    return $self->{generic_attributes};
}

sub get_id {
    my ($self)=@_;

    return (defined $self->{id})?$self->{id}:undef;
}

sub get_database {
    my ($self)=@_;

    return (defined $self->{database})?$self->{database}:undef;
}

sub get_fields {
    my ($self,$msg)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Anreicherung mit Feld-Bezeichnungen
    if (defined $msg){
        foreach my $fieldnumber (keys %{$self->{_fields}}){
            my $effective_fieldnumber = $fieldnumber;
            my $mapping = $config->{'categorymapping'};
            if (defined $mapping->{$self->{database}}{$fieldnumber}){
                $effective_fieldnumber = $fieldnumber."-".$self->{database};
            }
                    
            foreach my $fieldcontent_ref (@{$self->{_fields}->{$fieldnumber}}){
                $fieldcontent_ref->{description} = $msg->maketext($effective_fieldnumber);
            }
        }

        foreach my $item_ref (@{$self->{items}}){            
            foreach my $fieldnumber (keys %{$item_ref}){                
                next if ($fieldnumber eq "id");

                my $effective_fieldnumber = $fieldnumber;
                my $mapping = $config->{'categorymapping'};
                if (defined $mapping->{$self->{database}}{$fieldnumber}){
                    $effective_fieldnumber = $fieldnumber."-".$self->{database};
                }
                
                $item_ref->{$fieldnumber}->{description} = $msg->maketext($effective_fieldnumber);
            }
        }
    }
    
    return (defined $self->{_fields})?$self->{_fields}:{};
}

sub get_field {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $field            = exists $arg_ref->{field}
        ? $arg_ref->{field}               : undef;

    my $mult             = exists $arg_ref->{mult}
        ? $arg_ref->{mult}                : undef;

    if (!defined $self->{_fields} && !defined $self->{_fields}->{$field}){
        return;
    }
    
    if (defined $mult && $mult){
        foreach my $field_ref (@{$self->{_fields}->{$field}}){
            if (defined $field_ref->{mult} && $field_ref->{mult} == $mult){
                return $field_ref->{content};
            }
        }
    }
    else {
        return $self->{_fields}->{$field};
    }
}

sub has_field {
    my ($self,$field) = @_;

    return (defined $self->{_fields}->{$field})?1:0;
}

sub set_field {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $field          = exists $arg_ref->{field}
        ? $arg_ref->{field}            : undef;

    my $id             = exists $arg_ref->{id}
        ? $arg_ref->{id}               : undef;
    
    my $mult           = exists $arg_ref->{mult}
        ? $arg_ref->{mult}             : 1;

    my $subfield       = exists $arg_ref->{subfield}
        ? $arg_ref->{subfield}         : undef;

    my $content        = exists $arg_ref->{content}
        ? $arg_ref->{content}          : undef;

    my $supplement     = exists $arg_ref->{supplement}
        ? $arg_ref->{supplement}       : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($id){
        push @{$self->{_fields}{$field}}, {
            id         => $id,
            content    => $content,
            supplement => $supplement,
        };
    }
    else {
        push @{$self->{_fields}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };
    }

    return $self;
}

sub set_fields {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $fields         = exists $arg_ref->{fields}
        ? $arg_ref->{fields}            : undef;

    if ($fields && ref $fields eq "HASH"){
        $self->{_fields} = $fields;
    }

    return $self;
}

# sub have_subfields {
#     my ($self,$content) = @_;

#     # ToDo: Analyse
    
#     return 0;
# }

# sub content_per_subfield {
#     my ($self,$content) = @_;

#     # ToDo: Analyse

#     my @content_per_subfield = ();
    
#     return @content_per_subfield;
# }

# sub to_bulkload_field_string {
#     my $self = shift;
    
#     my $bulkload_string ="";

#     foreach my $field (keys %{$self->{_normset}}){
#         foreach my $item_ref (@{$self->{_normset}{$field}}){
#             $bulkload_string.="$self->{id}$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{content}\n";
#         }
#     }

#     return $bulkload_string;
# }

# sub to_bulkload_normfield_string {
#     my ($self,$conv_config) = @_;

#     # Log4perl logger erzeugen
#     my $logger = get_logger();

#     my $bulkload_string ="";


#     my $type ="";
    
    
#     foreach my $field (keys %{$self->{_normset}}){
#         foreach my $item_ref (@{$self->{_normset}{$field}}){
#             my $contentnorm   = "";

#             if (defined $field && exists $conv_config->{inverted_person}->{$field}){
#                 $contentnorm = OpenBib::Common::Util::normalize({
#                     field => $field,
#                     content  => $content,
#                 });
#         }
        
        
#         if (exists $conv_config->{inverted_person}{$field}->{index}){
#             foreach my $searchfield (keys %{$conv_config->{inverted_person}{$field}->{index}}){
#                 my $weight = $conv_config->{inverted_person}{$field}->{index}{$searchfield};
                
#                 push @{$conv_config->{$type}{data}{$id}{$searchfield}{$weight}}, $contentnormtmp;
#             }
#         }
            
#             $bulkload_string.="$self->{id}$field$item_ref->{mult}$item_ref->{subfield}$item_ref->{content}\n";
#         }
#     }

#     return $bulkload_string;


#     }

1
