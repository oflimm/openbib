#####################################################################
#
#  OpenBib::BibSonomy.pm
#
#  Objektorientiertes Interface zum BibSonomy API
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::BibSonomy;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Reload;
use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::Config;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $api_key  = exists $arg_ref->{api_key}
        ? $arg_ref->{api_key}       : undef;

    my $api_user = exists $arg_ref->{api_user}
        ? $arg_ref->{api_user}      : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $self = { };

    bless ($self, $class);
    
    $self->{config}  = $config;

    $api_user = (defined $api_user)?$api_user:(defined $self->{config}->{bibsonomy_api_user})?$self->{config}->{bibsonomy_api_user}:undef;
    $api_key  = (defined $api_key )?$api_key :(defined $self->{config}->{bibsonomy_api_key} )?$self->{config}->{bibsonomy_api_key} :undef;

    $self->{client}  = LWP::UserAgent->new;            # HTTP client

    $logger->debug("Authenticating with credentials $api_user/$api_key");
    
    $self->{client}->credentials(                      # HTTP authentication
        'www.bibsonomy.org:80',
        'BibSonomyWebService',
        $api_user => $api_key
    );

    return $self;
}

sub get_posts {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $isbn  = exists $arg_ref->{isbn}
        ? $arg_ref->{isbn}       : undef;

    my $tag  = exists $arg_ref->{tag}
        ? $arg_ref->{tag}        : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $url;
    
    if (defined $isbn){
        $url='http://www.bibsonomy.org/api/posts?resourcetype=bibtex&search="'.$isbn.'"';
    }
    elsif (defined $tag){
        $url='http://www.bibsonomy.org/api/posts?tags='.$tag.'&resourcetype=bibtex';
    }
    else {
        return $self;
    }

    $logger->debug("Request: $url");
    
    my $response = $self->{client}->get($url)->content;

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    if ($root->findvalue('/bibsonomy/@stat') eq "ok"){
        $self->{posts} = [];
    }
    else {
        return $self;
    }   


    if ($root->findvalue('/bibsonomy/posts/@next')){
        $self->{next} = $root->findvalue('/bibsonomy/posts/@next');
    }

    foreach my $post_node ($root->findnodes('/bibsonomy/posts/post')) {
        my $singlepost_ref = {} ;

        $singlepost_ref->{user} = $post_node->findvalue('user/@name');

        $singlepost_ref->{desc} = $post_node->findvalue('@description');
        
        $singlepost_ref->{tags} = [];
        
        foreach my $tag_node ($post_node->findnodes('tag')){
            push @{$singlepost_ref->{tags}}, $tag_node->getAttribute('name');
        }

        $singlepost_ref->{record}->{T0100}     = $post_node->findvalue('bibtex/@author');
        $singlepost_ref->{record}->{T0331}     = $post_node->findvalue('bibtex/@title');
        $singlepost_ref->{record}->{T0403}     = $post_node->findvalue('bibtex/@edition');
        $singlepost_ref->{record}->{T0410}     = $post_node->findvalue('bibtex/@address');
        $singlepost_ref->{record}->{T0412}     = $post_node->findvalue('bibtex/@publisher');
        $singlepost_ref->{record}->{T0425}     = $post_node->findvalue('bibtex/@year');
        $singlepost_ref->{record}->{T0662}     = $post_node->findvalue('bibtex/@href');
        $singlepost_ref->{record}->{T0800}     = $post_node->findvalue('bibtex/@entrytype');

        push @{$self->{posts}}, $singlepost_ref;
    }

    
    $logger->debug("Response / Posts: ".YAML::Dump($self->{posts}));
    
    return $self;
}

sub get_tags_of_posts {
    my $self     = shift;

    my @tags = ();
    foreach my $singlepost_ref (@{$self->{posts}}){
        push @tags, @{$singlepost_ref->{tags}};
    }

    
    return @tags;
}

sub get_records_of_posts {
    my $self     = shift;

    my @records = ();
    foreach my $singlepost_ref (@{$self->{posts}}){
        push @records, $singlepost_ref->{record};
    }
                                
    return @records;
    
    return;
}

sub DESTROY {
    my $self = shift;

    return;
}


1;
