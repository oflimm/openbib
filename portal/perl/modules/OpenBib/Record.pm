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
use OpenBib::Schema::Enrichment;

sub connectDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    if ($config->{dbimodule} eq "Pg"){
        eval {
            # UTF8: {'pg_enable_utf8'    => 1}
            $self->{schema} = OpenBib::Schema::Catalog->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},{'pg_enable_utf8'    => 1 }) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $self->{database}: DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}");
        }
    }
    elsif ($config->{dbimodule} eq "mysql"){
        eval {
            # UTF8: {'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}
            $self->{schema} = OpenBib::Schema::Catalog->connect("DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $self->{database}: DBI:$config->{dbimodule}:dbname=$self->{database};host=$config->{dbhost};port=$config->{dbport}");
        }
    }

    return;

}

sub connectEnrichmentDB {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    if ($config->{dbimodule} eq "Pg"){
        eval {
            # UTF8: {'pg_enable_utf8'    => 1}
            $self->{enrich_schema} = OpenBib::Schema::Enrichment->connect("DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd},{'pg_enable_utf8'    => 1}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}, $config->{enrichmntdbuser}");
        }
    }
    elsif ($config->{dbimodule} eq "mysql"){
        eval {
            # UTF8: {'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}
            $self->{enrich_schema} = OpenBib::Schema::Enrichment->connect("DBI:$config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd},{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or $logger->error_die($DBI::errstr);
        };
        
        if ($@){
            $logger->fatal("Unable to connect schema to database $config->{enrichmntdbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}, $config->{enrichmntdbuser}");
        }
    }
    
    return;
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
        push @{$self->{_normset}{$field}}, {
            id         => $id,
            content    => $content,
            supplement => $supplement,
        };
    }
    else {
        push @{$self->{_normdata}{$field}}, {
            mult      => $mult,
            subfield  => $subfield,
            content   => $content,
        };
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
#                 $contentnorm = OpenBib::Common::Util::grundform({
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
