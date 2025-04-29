#####################################################################
#
#  OpenBib::Catalog::Backend::BibSonomy.pm
#
#  Objektorientiertes Interface zu BibSonomy
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

package OpenBib::Catalog::Backend::BibSonomy;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::API::HTTP::BibSonomy;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use Mojo::Base -strict, -signatures;

use base qw(OpenBib::Catalog);

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $api_key  = exists $arg_ref->{api_key}
        ? $arg_ref->{api_key}       : undef;

    my $api_user = exists $arg_ref->{api_user}
        ? $arg_ref->{api_user}      : undef;

    my $database        = exists $arg_ref->{database}
        ? $arg_ref->{database}                : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;
    
    my $self = { };

    bless ($self, $class);

    $self->{api_user} = (defined $api_user)?$api_user:(defined $config->{bibsonomy_api_user})?$config->{bibsonomy_api_user}:undef;
    $self->{api_key}  = (defined $api_key )?$api_key :(defined $config->{bibsonomy_api_key} )?$config->{bibsonomy_api_key} :undef;

    $self->{database}  = $database if ($database);
    $self->{args}      = $arg_ref;

    return $self;
}

sub get_client {
    my $self = shift;

    if (defined $self->{client}){
        return $self->{client};
    }

    $self->connectClient;

    return $self->{client};
}

sub load_full_title_record_p {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id = exists $arg_ref->{id}
        ? $arg_ref->{id}     : '';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $promise = Mojo::Promise->new;
    
    # Retrieve information

    $logger->debug("Loading Record with id $id");
    
    my $recordlist = OpenBib::API::HTTP::BibSonomy->new()->get_posts({ start => 0, end => 20 , bibkey => $id});

    # Record is fully qualified, so get first record in recordlist
    
    my @records = $recordlist->get_records;
    my $record = $records[0];
    
    if ($logger->is_debug){
        $logger->debug("Adding Record with ".YAML::Dump($record->get_fields));
    }
    
    return $promise->resolve($record);
}

sub load_brief_title_record_p {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $id                = exists $arg_ref->{id}
        ? $arg_ref->{id}                :
            (exists $self->{id})?$self->{id}:undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    return $self->load_full_title_record_p($arg_ref);
}

sub get_subjects {
    my ($self,$arg_ref) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->new;

        # Set defaults
    my $bibkey   = exists $arg_ref->{bibkey}
        ? $arg_ref->{bibkey}     : undef;
    
    my $tags = exists $arg_ref->{subjects}
        ? $arg_ref->{subjects}       : undef;

    # Zuerst Dubletten entfernen, um unnoetige Anfragen auszuschliessen:

    # Dubletten entfernen
    my %seen_tags = ();

    my $url;

    $logger->debug("Args: subjects -> $tags / bibkey -> $bibkey");
    
    my @tags = split('\s+',$tags);

    if ($logger->is_debug){
        $logger->debug("Tags to lookup ".YAML::Dump(\@tags));
    }
    
    if (defined $bibkey && $bibkey=~/^[1-3][0-9a-f]{32}$/){
#        substr($bibkey,0,1)=""; # Remove leading 1

        my $recordlist = OpenBib::API::HTTP::BibSonomy->new()->get_posts({ start => 0, end => 20 , bibkey => $bibkey});
        
        # Record is fully qualified, so get first record in recordlist
        
        my @records = $recordlist->get_records;

        if ($recordlist->get_size > 0){
            my $record = $records[0];
            
            foreach my $tag_ref (@{$record->get_field({ field => 'T0710'})}){
                $logger->debug("Found tag in corresponding BibSonomy publication: ".$tag_ref->{content});
                push @tags, $tag_ref->{content};
            }
        }
    }
    
    my @unique_tags = grep { ! $seen_tags{lc($_)} ++ } @tags;

    @tags = ();
    if (@unique_tags) {
        if ($logger->is_debug){
            $logger->debug("Unique Tags: ".join(';',@unique_tags));
        }

        my $tag_count = 0;
        foreach my $tag (@unique_tags){
            next unless ($tag =~m/^[\p{Alphabetic}]+$/);

            # Due to slow response times for tag lookups we limit to 8 tags
            
            last if ($tag_count > 8);

            substr($bibkey,0,1)=""; # Remove leading 1
            $url="https://www.bibsonomy.org/api/tags/$tag";

            $logger->debug("Tag-Request: $url");
            
            my $response = $self->get_client->get($url)->content;
        
            $logger->debug("Response: $response");
            
            my $parser = XML::LibXML->new();
            my $tree   = $parser->parse_string($response);
            my $root   = $tree->getDocumentElement;
            
            if ($root->findvalue('/bibsonomy/@stat') eq "ok"){
                foreach my $tag_node ($root->findnodes('/bibsonomy/tag')) {
                    my $singletag_ref = {} ;
                    
                    $singletag_ref->{name}        = $tag_node->findvalue('@name');
                    $singletag_ref->{href}        = $tag_node->findvalue('@href');
                    $singletag_ref->{usercount}   = $tag_node->findvalue('@usercount');
                    $singletag_ref->{globalcount} = $tag_node->findvalue('@globalcount');
                    
                    push @tags, $singletag_ref;
                }
            }
            $tag_count++;
        }
    }

    if ($logger->is_debug){
        $logger->debug('Bibsonomy Tags: '.join(';',@tags));
    }
    return \@tags;
}

sub connectClient {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    $self->{client}  = LWP::UserAgent->new;            # HTTP client

    $logger->debug("Authenticating with credentials $self->{api_user}/$self->{api_key}");
    
    $self->{client}->credentials(                      # HTTP authentication
        'www.bibsonomy.org:443',
        'BibSonomyWebService',
        $self->{api_user} => $self->{api_key}
    );

    return;
}

sub DESTROY {
    my $self = shift;

    return;
}

1;
__END__

=head1 NAME

OpenBib::Catalog::Backend::BibSonomy - Objektorientiertes Interface zum BibSonomy API

=head1 DESCRIPTION

Mit diesem Objekt kann auf das XML-API von Dummy zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::Catalog::Backend::Dummy;

 my $catalog = OpenBib::Catalog::Backend->new({ database => "openlibrary" });

oder alternativ ueber die Catalog-Factory, wenn die Datenbank ueber 'System' in der Administration
sowie einer entsprechenden Regel in OpenBib::Catalog::Factory dem Backend zugeordnet ist.

 my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => "openlibrary" });

 my $classifications_ref = $catalog->get_classifications;

 my $record = new OpenBib::Record::Title({ database => 'openlibrary', id => '0815' })->load_full_record;

=head1 METHODS

=over 4

=item new({ database => database })

Erzeugung des Dummy Objektes. Der Parameter database muss immer uebergeben werden. Zusaetzlich
koennen beliebige weitere Parameter entgegengenommen werden und im Objekt selbst gespeichert werden.

=item get_classifications

Liefert eine Listenreferenz der vorhandenen Klassifikationen zurück.
Zusätzlich werden für eine Wolkenanzeige die entsprechenden
Klasseninformationen hinzugefügt.

=item load_full_record ({ database => $database, id => $id })

Liefert einen Titel-Record zurueck.

=back

=head1 EXPORT

Es werden keine Funktionen exportiert. Alle Funktionen muessen
vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
Verzicht auf den Exporter weniger Speicherverbrauch und mehr
Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

Oliver Flimm <flimm@openbib.org>

=cut
