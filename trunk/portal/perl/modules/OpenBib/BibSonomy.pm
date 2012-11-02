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
use OpenBib::Enrichment;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;

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
    my $search = exists $arg_ref->{search}
        ? $arg_ref->{search}     : undef;

    my $bibkey = exists $arg_ref->{bibkey}
        ? $arg_ref->{bibkey}     : undef;

    my $tag    = exists $arg_ref->{tag}
        ? $arg_ref->{tag}        : undef;

    my $user   = exists $arg_ref->{user}
        ? $arg_ref->{user}       : undef;

    my $type   = exists $arg_ref->{type}
        ? $arg_ref->{type}       : undef;

    my $start  = exists $arg_ref->{start}
        ? $arg_ref->{start}      : undef;

    my $end    = exists $arg_ref->{end}
        ? $arg_ref->{end}        : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my %valid_type = (
        #OpenBib      => #Bibsonomy
        'publication' => 'bibtex',
        'bookmark'    => 'bookmark',
    );

    if (defined $user && $user eq "self"){
        $user = $self->{api_user};
    }
    
    my $url='http://www.bibsonomy.org/api/posts?';

    # Type prefix?
    if (defined $bibkey){
        if ($bibkey =~/^bm_(.+)$/){
            $bibkey=$1;
            $type="bookmark";
        }
        elsif ($bibkey =~/^bt_(.+)$/){
            $bibkey=$1;
            $type="publication";
        }
    }

    if (defined $type && defined $valid_type{$type}){
        $url.='resourcetype='.$valid_type{$type};
    }
    else {
        $url.='resourcetype=bibtex';
    }

    if (defined $search){
        $url.='&search='.$search;
    }

    if (defined $bibkey) { # && $bibkey=~/^1[0-9a-f]{32}$/){
#        substr($bibkey,0,1)=""; # Remove leading 1
        $url.="&resource=$bibkey";
    }

    if (defined $user){
        $url.="&user=$user";
    }

    if (defined $tag){
        $url.="&tags=$tag";
    }

    if ($start && $end){
        $url.="&start=$start&end=$end";
    }

    my $search_count = 0;
    
    $logger->debug("Request: $url");

    my $response = $self->{client}->get($url)->decoded_content(charset => 'utf-8');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    unless ($root->findvalue('/bibsonomy/@stat') eq "ok"){
        return new OpenBib::RecordList::Title;
    }

    my $next = $root->findvalue('/bibsonomy/posts/@next');

    $logger->debug("Next: $next");
    
    if ($root->findvalue('/bibsonomy/posts/@next')){
        $next = $root->findvalue('/bibsonomy/posts/@next');
    }

    if ($root->findvalue('/bibsonomy/posts/@end')){
        $search_count = $root->findvalue('/bibsonomy/posts/@end');     
    }

    my $recordlist = new OpenBib::RecordList::Title({
        generic_attributes => {
            hits   => $search_count,
            next   => $next,
        }
    });

    foreach my $post_node ($root->findnodes('/bibsonomy/posts/post')) {
        my $generic_attributes_ref = {} ;
        
        my $recordtype = ($post_node->findvalue('bibtex/@interhash'))?'publication':'bookmark';

        my $id;
        
        if ($recordtype eq "publication"){
            $id = "bt_".$post_node->findvalue('bibtex/@interhash');
            $generic_attributes_ref->{bibkey}    = "1".$post_node->findvalue('bibtex/@interhash');
            $generic_attributes_ref->{interhash} = $post_node->findvalue('bibtex/@interhash');
            $generic_attributes_ref->{intrahash} = $post_node->findvalue('bibtex/@intrahash');
        }
        else {
            $id = "bm_".$post_node->findvalue('bookmark/@interhash');
            $generic_attributes_ref->{bibkey}    = "1".$post_node->findvalue('bookmark/@interhash');
            $generic_attributes_ref->{interhash} = $post_node->findvalue('bookmark/@interhash');
            $generic_attributes_ref->{intrahash} = $post_node->findvalue('bookmark/@intrahash');
        }

        $generic_attributes_ref->{xmldata}   = $post_node->toString();
        $generic_attributes_ref->{user}      = $post_node->findvalue('user/@name');
        $generic_attributes_ref->{desc}      = $post_node->findvalue('@description');
        $generic_attributes_ref->{subjects}      = [];

        foreach my $tag_node ($post_node->findnodes('tag')){
            push @{$generic_attributes_ref->{subjects}}, $tag_node->getAttribute('name');
        }

        $logger->debug("Creating title record with generic attributes ".YAML::Dump($generic_attributes_ref));
        
        my $record = new OpenBib::Record::Title({ database => 'bibsonomy', id => $id, generic_attributes => $generic_attributes_ref });

        my $mult = 1;
        foreach my $subject (@{$generic_attributes_ref->{subjects}}){
            $record->set_field({field => 'T0710', subfield => '', mult => $mult++, content => $subject });
        }
        
        if ($recordtype eq "publication"){
            if ($post_node->findvalue('bibtex/@author')){
                my $author = $post_node->findvalue('bibtex/@author');
                my $mult = 1;
                if ($author=~/\s+and\s+/){
                    foreach my $singleauthor (split('\s+and\s+',$author)){
                        $record->set_field({field => 'T0100', subfield => '', mult => $mult++, content => $singleauthor});
                    }
                }
                else {
                    $record->set_field({field => 'T0100', subfield => '', mult => 1, content => $author});
                }
            }
            
            if ($post_node->findvalue('bibtex/@editor')){
                $record->set_field({field => 'T0101', subfield => '', mult => 1, content => $post_node->findvalue('bibtex/@editor')});
            }
            
            if ($post_node->findvalue('bibtex/@title')){
                $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $post_node->findvalue('bibtex/@title')});
            }

            $record->set_field({field => 'T0800', subfield => '', mult => 1, content => 'publication'});
            
            if ($post_node->findvalue('bibtex/@journal')){
                my $journal = $post_node->findvalue('bibtex/@journal');

                # Erweiterungen um volume, pages etc.

                #             $singlepost_ref->{record}->{pages}     = $post_node->findvalue('bibtex/@pages');
                #             $singlepost_ref->{record}->{volume}    = $post_node->findvalue('bibtex/@volume');
                #             $singlepost_ref->{record}->{number}    = $post_node->findvalue('bibtex/@number');
                
                $record->set_field({field => 'T0590', subfield => '', mult => 1, content => $journal});
            }
            
            if ($post_node->findvalue('bibtex/@address')){
                $record->set_field({field => 'T0410', subfield => '', mult => 1, content => $post_node->findvalue('bibtex/@address')});
            }
            
            if ($post_node->findvalue('bibtex/@publisher')){
                $record->set_field({field => 'T0412', subfield => '', mult => 1, content => $post_node->findvalue('bibtex/@publisher')});
            }
            
            if ($post_node->findvalue('bibtex/@bibtexAbstract')){
                $record->set_field({field => 'T0750', subfield => '', mult => 1, content => $post_node->findvalue('bibtex/@bibtexAbstract')});
            }
            
            if ($post_node->findvalue('bibtex/@year')){
                $record->set_field({field => 'T0425', subfield => '', mult => 1, content => $post_node->findvalue('bibtex/@year')});
            }
            
            if ($post_node->findvalue('bibtex/@edition')){
                $record->set_field({field => 'T0403', subfield => '', mult => 1, content => $post_node->findvalue('bibtex/@edition')});
            }
            
            if ($post_node->findvalue('bibtex/@url')){
                $record->set_field({field => 'T0662', subfield => '', mult => 1, content => $post_node->findvalue('bibtex/@url')});
            }
            
            if ($post_node->findvalue('bibtex/@misc')){
                my $misc = $post_node->findvalue('bibtex/@misc');

                if ($misc =~/isbn = \{([^}]+)\}/){
                    $record->set_field({field => 'T0540', subfield => '', mult => 1, content => $1 });
                }
            }

            if ($post_node->findvalue('bibtex/@series')){
                $record->set_field({field => 'T0451', subfield => '', mult => 1, content => $post_node->findvalue('bibtex/@series')});
            }

#             $singlepost_ref->{record}->{entrytype} = $post_node->findvalue('bibtex/@entrytype');
            
        }
        else {
            if ($post_node->findvalue('bookmark/@url')){
                $record->set_field({field => 'T0662', subfield => '', mult => 1, content => $post_node->findvalue('bookmark/@url')});
            }

            if ($post_node->findvalue('bookmark/@title')){
                $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $post_node->findvalue('bookmark/@title')});
            }

            $record->set_field({field => 'T0800', subfield => '', mult => 1, content => 'bookmark'});
        }

        if ($generic_attributes_ref->{user}){
            $record->set_field({field => 'T4200', subfield => '', mult => 1, content => $generic_attributes_ref->{user} });
        }

        
        $logger->debug($post_node->toString());

        my $enrichment = new OpenBib::Enrichment;
        
        # Anreicherung mit 'gleichen' (=gleicher bibkey) Titeln aus lokalen Katalogen
        {
            my $same_recordlist = new OpenBib::RecordList::Title();
            
            # DBI: "select distinct id,dbname from all_isbn where isbn=? and dbname != ? and id != ?";
            my $same_titles = $enrichment->{schema}->resultset('AllTitleByBibkey')->search_rs(
                {
                    bibkey    => $generic_attributes_ref->{bibkey},
                },
                {                        
                    group_by => ['titleid','dbname','bibkey','tstamp'],
                }
            );

            $logger->debug("Checking bibkey ".$generic_attributes_ref->{bibkey});
            foreach my $item ($same_titles->all) {
                my $id         = $item->titleid;
                my $database   = $item->dbname;

                $logger->debug("Found same item id=$id db=$database");
                $same_recordlist->add(new OpenBib::Record::Title({ id => $id, database => $database}));
            }
            
            $record->set_same_records($same_recordlist);
        }

        $record->set_circulation([]);
        $record->set_holding([]);
        $recordlist->add($record);
    }
    
    return $recordlist;
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
    
    if (defined $bibkey){ # && $bibkey=~/^1[0-9a-f]{32}$/){
#        substr($bibkey,0,1)=""; # Remove leading 1
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
        ? $arg_ref->{type}       : 'publication';

    my $visibility = exists $arg_ref->{visibility}
        ? $arg_ref->{visibility} : 'public';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my %valid_type = (
        #OpenBib      => #Bibsonomy
        'publication' => 'bibtex',
        'bookmark'    => 'bookmark',
    );

    my $recordlist = $self->get_posts({ user => 'self', bibkey => $bibkey});

    if ($recordlist->get_size > 0){
        my @records = $recordlist->get_records;
        my $record = $records[0];
        
        my $postxml = $record->get_generic_attributes->{xmldata};

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
        my $url = "http://www.bibsonomy.org/api/users/".$self->{api_user}."/posts/".$record->get_generic_attributes->{intrahash};
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
    $post->setAttribute('description',"OpenBib Recherche-Portal");

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
(default: 'publication')kann bestimmt werden, ob sich die Liste auf
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
