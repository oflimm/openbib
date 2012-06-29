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

use Apache2::Reload;
use Benchmark ':hireswallclock';
use DBI;
use LWP;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Storable;
use XML::LibXML;
use YAML ();

use OpenBib::Config;
use OpenBib::Record::Title;

sub new {
    my ($class,$arg_ref) = @_;

    # Set defaults
    my $api_key  = exists $arg_ref->{api_key}
        ? $arg_ref->{api_key}       : undef;

    my $api_user = exists $arg_ref->{api_user}
        ? $arg_ref->{api_user}      : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $self = { };

    bless ($self, $class);
    
    $self->{api_user} = (defined $api_user)?$api_user:(defined $config->{bibsonomy_api_user})?$config->{bibsonomy_api_user}:undef;
    $self->{api_key}  = (defined $api_key )?$api_key :(defined $config->{bibsonomy_api_key} )?$config->{bibsonomy_api_key} :undef;

    $self->{client}  = LWP::UserAgent->new;            # HTTP client

    $logger->debug("Authenticating with credentials $self->{api_user}/$self->{api_key}");
    
    $self->{client}->credentials(                      # HTTP authentication
        'www.bibsonomy.org:80',
        'BibSonomyWebService',
        $self->{api_user} => $self->{api_key}
    );

    return $self;
}

sub get_posts {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $bibkey = exists $arg_ref->{bibkey}
        ? $arg_ref->{bibkey}     : undef;

    my $tag    = exists $arg_ref->{tag}
        ? $arg_ref->{tag}        : undef;

    my $user   = exists $arg_ref->{user}
        ? $arg_ref->{user}       : undef;

    my $type   = exists $arg_ref->{type}
        ? $arg_ref->{type}       : 'bibtex';

    my $start  = exists $arg_ref->{start}
        ? $arg_ref->{start}      : undef;

    my $end    = exists $arg_ref->{end}
        ? $arg_ref->{end}        : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my %valid_type = (
        'bibtex'   => 'bibtex',
        'bookmark' => 'bookmark',
    );

    if (defined $user && $user eq "self"){
        $user = $self->{api_user};
    }
    
    my $url;

    my $titles_ref = [];
    
    if (defined $bibkey && $bibkey=~/^1[0-9a-f]{32}$ && !defined $user/){
        substr($bibkey,0,1)=""; # Remove leading 1
        $url='http://www.bibsonomy.org/api/posts?resourcetype=bibtex&resource="'.$bibkey.'"';
    }
    elsif (defined $bibkey && $bibkey=~/^1[0-9a-f]{32}$/ && defined $user){
        substr($bibkey,0,1)=""; # Remove leading 1
        $url="http://www.bibsonomy.org/api/posts?resourcetype=bibtex&resource=$bibkey&user=$user";
    }
    elsif (defined $tag){
        $url='http://www.bibsonomy.org/api/posts?tags='.$tag.'&resourcetype='.$valid_type{$type};
        if ($start && $end){
            $url.="&start=$start&end=$end";
        }
    }
    elsif (!defined $bibkey && defined $user){
        $url='http://www.bibsonomy.org/api/posts?user='.$user.'&resourcetype='.$valid_type{$type};
        if (defined $start && defined $end){
            $url.="&start=$start&end=$end";
        }
    }
    else {
        return $self;
    }

    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'utf-8');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    unless ($root->findvalue('/bibsonomy/@stat') eq "ok"){
        return ();
    }

    my $next_start = "";
    my $next_end   = "";
    if ($root->findvalue('/bibsonomy/posts/@next')){
        my $next = $root->findvalue('/bibsonomy/posts/@next');     
        ($next_start,$next_end) = $next =~/start=(\d+).*?end=(\d+)/; 
    }

    foreach my $post_node ($root->findnodes('/bibsonomy/posts/post')) {

        my $singlepost_ref = {} ;

        $singlepost_ref->{user} = $post_node->findvalue('user/@name');

        $singlepost_ref->{desc} = $post_node->findvalue('@description');

        $singlepost_ref->{tags} = [];
        
        foreach my $tag_node ($post_node->findnodes('tag')){
            push @{$singlepost_ref->{tags}}, $tag_node->getAttribute('name');
        }

        if ($type eq "bibtex"){
            $singlepost_ref->{bibkey}              = "1".$post_node->findvalue('bibtex/@interhash');
            $singlepost_ref->{interhash}           = $post_node->findvalue('bibtex/@interhash');
            $singlepost_ref->{intrahash}           = $post_node->findvalue('bibtex/@intrahash');
            $singlepost_ref->{record}->{author}    = $post_node->findvalue('bibtex/@author');
            $singlepost_ref->{record}->{editor}    = $post_node->findvalue('bibtex/@editor');
            $singlepost_ref->{record}->{title}     = $post_node->findvalue('bibtex/@title');
            $singlepost_ref->{record}->{edition}   = $post_node->findvalue('bibtex/@edition');
            $singlepost_ref->{record}->{address}   = $post_node->findvalue('bibtex/@address');
            $singlepost_ref->{record}->{publisher} = $post_node->findvalue('bibtex/@publisher');
            $singlepost_ref->{record}->{year}      = $post_node->findvalue('bibtex/@year');
            $singlepost_ref->{record}->{href}      = $post_node->findvalue('bibtex/@href');
            $singlepost_ref->{record}->{entrytype} = $post_node->findvalue('bibtex/@entrytype');
            $singlepost_ref->{xmldata}             = $post_node->toString();
        }
        elsif ($type eq "bookmark"){
            $singlepost_ref->{record}->{url}       = $post_node->findvalue('bookmark/@url');
            $singlepost_ref->{record}->{title}     = $post_node->findvalue('bookmark/@title');
        }

        push @{$titles_ref}, $singlepost_ref;
    }

    
    $logger->debug("Response / Posts: ".YAML::Dump($titles_ref));
    
    return {
        recordlist => $titles_ref,
        next       => {
            start => $next_start,
            end   => $next_end,
        },
    };
}

sub get_tags {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $bibkey   = exists $arg_ref->{bibkey}
        ? $arg_ref->{bibkey}     : undef;
    
    my $tags_ref = exists $arg_ref->{tags}
        ? $arg_ref->{tags}       : undef;
        
    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Zuerst Dubletten entfernen, um unnoetige Anfragen auszuschliessen:

    # Dubletten entfernen
    my %seen_tags = ();

    my @unique_tags = grep { ! $seen_tags{lc($_)} ++ } @{$tags_ref};

    my $url;
    
    my @tags = ();
    
    if (defined $bibkey && $bibkey=~/^1[0-9a-f]{32}$/){
        substr($bibkey,0,1)=""; # Remove leading 1
        $url="http://www.bibsonomy.org/api/tags?resourcetype=bibtex&resource=$bibkey";
        $logger->debug("Request: $url");
        
        my $response = $self->{client}->get($url)->content;
        
        $logger->debug("Response: $response");
        
        my $parser = XML::LibXML->new();
        my $tree   = $parser->parse_string($response);
        my $root   = $tree->getDocumentElement;
        
        if ($root->findvalue('/bibsonomy/@stat') eq "ok"){
            foreach my $tag_node ($root->findnodes('/bibsonomy/tags/tag')) {
                my $singletag_ref = {} ;
                
                $singletag_ref->{name}        = $tag_node->findvalue('@name');
                $singletag_ref->{href}        = $tag_node->findvalue('@href');
                $singletag_ref->{usercount}   = $tag_node->findvalue('@usercount');
                $singletag_ref->{globalcount} = $tag_node->findvalue('@globalcount');
                
                push @tags, $singletag_ref;
            }
            
            
            $logger->debug("Response / Posts: ".YAML::Dump(\@tags));
        }
    }
    
    if (@unique_tags) {
        foreach my $tag (@unique_tags){
            substr($bibkey,0,1)=""; # Remove leading 1
            $url="http://www.bibsonomy.org/api/tags/$tag";
            $logger->debug("Request: $url");
            
            my $response = $self->{client}->get($url)->content;
        
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
        }
    }

    # Wiederum Dubletten (Bibkey <> Schlagworte) entfernen
    %seen_tags = ();

    @unique_tags= grep { ! $seen_tags{lc($_->{name})} ++ } @tags;
    
    return @unique_tags;
}

sub change_post {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $bibkey   = exists $arg_ref->{bibkey}
        ? $arg_ref->{bibkey}     : undef;

    my $tags_ref = exists $arg_ref->{tags}
        ? $arg_ref->{tags}        : undef;

    my $type     = exists $arg_ref->{type}
        ? $arg_ref->{type}       : 'bibtex';

    my $visibility = exists $arg_ref->{visibility}
        ? $arg_ref->{visibility} : 'public';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my %valid_type = (
        'bibtex'   => 'bibtex',
        'bookmark' => 'bookmark',
    );

    my $posts_ref = $self->get_posts({ user => 'self', bibkey => $bibkey});

    if (@{$posts_ref->{recordlist}}){
        my $postxml = $posts_ref->{recordlist}[0]{xmldata};

        # Existierende XML-Daten einlesen
        my $xmldata = XML::LibXML->new();
        my $tree       = $xmldata->parse_string($postxml);
        my $postnode   = $tree->getDocumentElement;
    
        $logger->debug($postnode->toString());

        # Daraus geaenderte Daten generieren
        my $newdata = XML::LibXML::Document->new();
        my $root = $newdata->createElement('bibsonomy');
        $newdata->setDocumentElement($root);
        $root->appendChild($postnode);

        $postnode->removeAttribute('postingdate');
    
        # Tags, viewability aktualisieren
    
        # Zuerst loeschen
        foreach my $tag_node ($root->findnodes('/bibsonomy/post/tag')) {
            $postnode->removeChild($tag_node);
        }

        # dann neue Eintragen;
        foreach my $new_tag (@{$tags_ref}){
            my $thistag = $newdata->createElement('tag');
            $thistag->setAttribute('name',$new_tag);
            $postnode->appendChild($thistag);
        }

        # Aendern in BibSonomy
        my $url = "http://www.bibsonomy.org/api/users/".$self->{api_user}."/posts/".$posts_ref->{recordlist}[0]{intrahash};
;

        $logger->debug($url);
        
        my $req = new HTTP::Request 'PUT' => $url;
        $req->content($newdata->toString());

        my $response = $self->{client}->request($req)->decoded_content(charset => 'utf-8');

        $logger->debug("Response: $response");

        my $resultparser = XML::LibXML->new();
        my $rstree   = $resultparser->parse_string($response);
        my $rsroot   = $rstree->getDocumentElement;
        
        if ($root->findvalue('/bibsonomy/@stat') eq "ok"){
            return 1;
        }
        else {
            return 0;
        }
    }
    
    return 0;
}

sub new_post {
    my ($self,$arg_ref) = @_;

    # Set defaults
    my $tags_ref   = exists $arg_ref->{tags}
        ? $arg_ref->{tags}       : undef;

    my $visibility = exists $arg_ref->{visibility}
        ? $arg_ref->{visibility} : 'public';

    my $record     = exists $arg_ref->{record}
        ? $arg_ref->{record  }   : undef;

    my $database   = exists $arg_ref->{database}
        ? $arg_ref->{database}   : undef;

    my $id         = exists $arg_ref->{id}
        ? $arg_ref->{id}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    unless (defined $record){
        $record  = new OpenBib::Record::Title({ database => $database , id => $id})->load_full_record;    
    }
    
    my $postxml = $record->to_bibsonomy_post;

    # Post-XML aus dem Record extrahieren
    my $xmldata    = XML::LibXML->new();    
    my $tree       = $xmldata->parse_string($postxml);
    my $bibsonomy  = $tree->getDocumentElement;
    my $post       = $bibsonomy->firstChild;

    # Request aufbauen
    my $doc = XML::LibXML::Document->new();
    my $root = $doc->createElement('bibsonomy');
    $doc->setDocumentElement($root);
    $root->appendChild($post);

    # Beschreibung
    $post->setAttribute('description',"KUG Recherche-Portal");

    # User
    my $user = $doc->createElement('user');
    $user->setAttribute('name',$self->{api_user});
    $post->appendChild($user);

    # Visibility
    my $vis = $doc->createElement('group');
    $vis->setAttribute('name',$visibility);
    $post->appendChild($vis);

    # Tags
    foreach my $new_tag (@{$tags_ref}){
        my $thistag = $doc->createElement('tag');
        $thistag->setAttribute('name',$new_tag);
        $post->appendChild($thistag);
    }
    
    $logger->debug($doc->toString());

    # Anlegen in BibSonomy
    my $url = "http://www.bibsonomy.org/api/users/".$self->{api_user}."/posts";
;

    $logger->debug($url);
    my $req = new HTTP::Request 'POST' => $url;
    $req->content($doc->toString());

    my $response = $self->{client}->request($req)->decoded_content(charset => 'utf-8');

    $logger->debug("Response: $response");

    my $resultparser = XML::LibXML->new();
    my $rstree   = $resultparser->parse_string($response);
    my $rsroot   = $rstree->getDocumentElement;
    
    if ($root->findvalue('/bibsonomy/@stat') eq "ok"){
        return 1;
    }
    else{
       return 0;
    }
}

sub DESTROY {
    my $self = shift;

    return;
}


1;
__END__

=head1 NAME

 OpenBib::BibSonomy - Objekt zur Interaktion mit BibSonomy

=head1 DESCRIPTION

 Mit diesem Objekt kann von OpenBib über das API von BibSonomy auf diesen Web-Dienst zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::BibSonomy;

 my $bibsonomy = new OpenBib::BibSonomy({ api_key => $api_key, api_user => $api_user});

 my @tags = $bibsonomy->get_tags({ bibkey => $bibkey, tags => \@local_tags});

 my $posts_ref = $bibsonomy->get_posts({ tag => encode_utf8($tag) ,start => $start, end => $end , type => $type});

 my $posts_ref = $bibsonomy->get_posts({ user => $bsuser ,start => $start, end => $end , type => $type});

=head1 METHODS

=over 4

=item new({ api_key => $api_key, api_user => $api_user })

Anlegen eines neuen BibSonomy-Objektes. Für den Zugriff über das
BibSonomy-API muss ein API-Key $api_key und ein API-Nutzer $api_user
vorhanden sein. Diese können direkt bei der Objekt-Erzeugung angegeben
werden, ansonsten werden die Standard-Keys bibsonomy_api_key und
-Nutzer bibsonomy_api_user aus OpenBib::Config respektive portal.yml
verwendet.

=item get_posts({ bibkey => $bibkey, tag => $tag, user => $user, type => $type, start => $start, end => $end});

Liefert eine Liste mit Posts aus BibSonomy zu einem Tag $tag, einem
Nutzer $user oder einem Bibkey $bibkey von $start bis $end. Über $type
(default: 'bibtex')kann bestimmt werden, ob sich die Liste auf
bibliographische Informationen bezieht ('bibtex') oder Web-Links
('bookmark').

=item get_tags({ bibkey => $bibkey, tags => $tags_ref })

Liefert auf Basis einer Liste gegebener Tags $tags_ref und/oder eines
Bibkeys $bibkey eine Gesamt-Liste aller diesbezüglich in BibSonomy
vorkommenden Tags zurück. Bei übergebenen Bibkey werden dazu die Tags
des entsprechenden Titels in Bibsonomy - falls existent - bestimmt,
bei übergebener Tag-Liste wird jedes auf Existenz in BibSonomy
überprüft.

=item change_posts({ bibkey => $bibkey, tags => $tags_ref, type => $type, visibility => $visibility})

Ändern der Tags entsprechend $tags_ref sowie der Sichbarkeit
$visibility (public, private) eines eigenen Eintrags mit dem Bibkey
$bibkey in BibSonomy des Typs $type.

=item new_post({ record => $record, tags => $tags_ref, type => $type, visibility => $visibility, database => $database, id => $id})

Erzeuge einen neuen bibliographischen Eintrag in BibSonomy zu einem
gegebenen Satz $record mit Tags $tags_ref und Sichtbarkeit
$visibility. Falls kein $record übergeben wird, kann stattdessen
direkt die Id $id in der gewünschten Datenbank $database angegeben
werden. Ein Bookmark-Eintrag kann derzeit NICHT erzeugt werden.

=back

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
