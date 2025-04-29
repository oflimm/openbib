#####################################################################
#
#  OpenBib::API::HTTP::BibSonomy.pm
#
#  Objektorientiertes Interface zum BibSonomy API
#
#  Dieses File ist (C) 2008-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::API::HTTP::BibSonomy;

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
use Mojo::Base -strict, -signatures;

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

    my $config = OpenBib::Config->new;
    
    my $self = { };

    bless ($self, $class);
    
    $self->{api_user} = (defined $api_user)?$api_user:(defined $config->{bibsonomy_api_user})?$config->{bibsonomy_api_user}:undef;
    $self->{api_key}  = (defined $api_key )?$api_key :(defined $config->{bibsonomy_api_key} )?$config->{bibsonomy_api_key} :undef;

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

    my $url='https://www.bibsonomy.org/api/posts?';

    # Type prefix?
    if (defined $bibkey){
        $logger->debug("Bibkey: $bibkey");
    
        if ($bibkey =~/^bm_(.+?)_([a-z0-9]+)$/){
            $user=$1;
            $bibkey=$2;
            $type="bookmark";
        }
        elsif ($bibkey =~/^bt_(.+?)_([a-z0-9]+)$/){
            $user=$1;
            $bibkey=$2;
            $type="publication";
        }
    }
    else {
        $logger->debug("Kein Bibkey");
    }

    $logger->debug("Effektiver Bibkey: $bibkey") if (defined $bibkey);
    $logger->debug("Effektiver User: $user") if (defined $user);
    
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

    my $response = $self->get_client->get($url)->decoded_content(charset => 'utf-8');

    $logger->debug("Response: $response");
    
    my $parser = XML::LibXML->new();
    my $tree   = $parser->parse_string($response);
    my $root   = $tree->getDocumentElement;

    unless ($root->findvalue('/bibsonomy/@stat') eq "ok"){
        return new OpenBib::RecordList::Title;
    }

    my $next = 0;

    if ($root->findvalue('/bibsonomy/posts/@next')){
        $next = $root->findvalue('/bibsonomy/posts/@next');
    }

    $logger->debug("Next: $next");
    

    if ($root->findvalue('/bibsonomy/posts/@end')){
        $end = $root->findvalue('/bibsonomy/posts/@end');     
    }

    $logger->debug("End: $end");
        
    ($search_count) = $next =~m/end=(\d+)/;

    $search_count = $end unless ($next);
    
    my $recordlist = new OpenBib::RecordList::Title({
        generic_attributes => {
            hits   => $search_count,
            next   => $next,
        }
    });

    # ISBNs zu gleichen Bibkeys merken und anreichern, um mehr Titel im
    # eigenen Bestand ausfindig machen zu koennen

    my $bibkey_isbn_ref = {};

    foreach my $post_node ($root->findnodes('/bibsonomy/posts/post')) {
        my $generic_attributes_ref = {} ;
        
        my $recordtype = ($post_node->findvalue('bibtex/@interhash'))?'publication':'bookmark';
        $generic_attributes_ref->{user}      = $post_node->findvalue('user/@name');

        my $id;
        
        if ($recordtype eq "publication"){
            $id = "bt_".$generic_attributes_ref->{user}."_".$post_node->findvalue('bibtex/@interhash');
            $generic_attributes_ref->{bibkey}    = "1".$post_node->findvalue('bibtex/@interhash');
            $generic_attributes_ref->{interhash} = $post_node->findvalue('bibtex/@interhash');
            $generic_attributes_ref->{intrahash} = $post_node->findvalue('bibtex/@intrahash');
        }
        else {
            $id = "bm_".$generic_attributes_ref->{user}."_".$post_node->findvalue('bookmark/@interhash');
            $generic_attributes_ref->{bibkey}    = "1".$post_node->findvalue('bookmark/@interhash');
            $generic_attributes_ref->{interhash} = $post_node->findvalue('bookmark/@interhash');
            $generic_attributes_ref->{intrahash} = $post_node->findvalue('bookmark/@intrahash');
        }

        $generic_attributes_ref->{xmldata}   = $post_node->toString();
        $generic_attributes_ref->{desc}      = $post_node->findvalue('@description');
        $generic_attributes_ref->{subjects}      = [];


        foreach my $tag_node ($post_node->findnodes('tag')){
            push @{$generic_attributes_ref->{subjects}}, $tag_node->getAttribute('name');
        }

        if ($logger->is_debug){
            $logger->debug("Creating title record with generic attributes ".YAML::Dump($generic_attributes_ref));
        }
        
        my $record = new OpenBib::Record::Title({ database => 'bibsonomy', id => $id, generic_attributes => $generic_attributes_ref });

        $record->set_field({field => 'T5050', subfield => '', mult => 1, content => $generic_attributes_ref->{bibkey}});

        my $mult = 1;
        foreach my $subject (@{$generic_attributes_ref->{subjects}}){
            $record->set_field({field => 'T0710', subfield => '', mult => $mult++, content => $self->conv($subject) });
        }
        
        if ($recordtype eq "publication"){
            if ($post_node->findvalue('bibtex/@author')){
                my $author = $post_node->findvalue('bibtex/@author');
                my $mult = 1;
                if ($author=~/\s+and\s+/){
                    foreach my $singleauthor (split('\s+and\s+',$author)){
                        $record->set_field({field => 'T0100', subfield => '', mult => $mult++, content => $self->conv($singleauthor)});
                    }
                }
                else {
                    $record->set_field({field => 'T0100', subfield => '', mult => 1, content => $self->conv($author)});
                }
            }
            
            if ($post_node->findvalue('bibtex/@editor')){
                $record->set_field({field => 'T0101', subfield => '', mult => 1, content => $self->conv($post_node->findvalue('bibtex/@editor'))});
            }
            
            if ($post_node->findvalue('bibtex/@title')){
                $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $self->conv($post_node->findvalue('bibtex/@title'))});
            }

            $record->set_field({field => 'T0800', subfield => '', mult => 1, content => 'publication'});
            
            if ($post_node->findvalue('bibtex/@journal')){
                my $journal = $post_node->findvalue('bibtex/@journal');

                # Erweiterungen um volume, pages etc.

                #             $singlepost_ref->{record}->{pages}     = $post_node->findvalue('bibtex/@pages');
                #             $singlepost_ref->{record}->{volume}    = $post_node->findvalue('bibtex/@volume');
                #             $singlepost_ref->{record}->{number}    = $post_node->findvalue('bibtex/@number');
                
                $record->set_field({field => 'T0590', subfield => '', mult => 1, content => $self->conv($journal)});
            }
            
            if ($post_node->findvalue('bibtex/@address')){
                $record->set_field({field => 'T0410', subfield => '', mult => 1, content => $self->conv($post_node->findvalue('bibtex/@address'))});
            }
            
            if ($post_node->findvalue('bibtex/@publisher')){
                $record->set_field({field => 'T0412', subfield => '', mult => 1, content => $self->conv($post_node->findvalue('bibtex/@publisher'))});
            }
            
            if ($post_node->findvalue('bibtex/@bibtexAbstract')){
                $record->set_field({field => 'T0750', subfield => '', mult => 1, content => $self->conv($post_node->findvalue('bibtex/@bibtexAbstract'))});
            }
            
            if ($post_node->findvalue('bibtex/@year')){
                $record->set_field({field => 'T0425', subfield => '', mult => 1, content => $self->conv($post_node->findvalue('bibtex/@year'))});
            }
            
            if ($post_node->findvalue('bibtex/@edition')){
                $record->set_field({field => 'T0403', subfield => '', mult => 1, content => $self->conv($post_node->findvalue('bibtex/@edition'))});
            }
            
            if ($post_node->findvalue('bibtex/@url')){
                $record->set_field({field => 'T0662', subfield => '', mult => 1, content => $self->conv($post_node->findvalue('bibtex/@url'))});
            }
            
            if ($post_node->findvalue('bibtex/@misc')){
                my $misc = $post_node->findvalue('bibtex/@misc');

                if ($misc =~/isbn = \{([^}]+)\}/){
                    my $isbn = $1;
                    $bibkey_isbn_ref->{$generic_attributes_ref->{bibkey}} = $isbn;
                    $record->set_field({field => 'T0540', subfield => '', mult => 1, content => $self->conv($isbn) });
                }
            }

            if ($post_node->findvalue('bibtex/@series')){
                $record->set_field({field => 'T0451', subfield => '', mult => 1, content => $self->conv($post_node->findvalue('bibtex/@series'))});
            }

#             $singlepost_ref->{record}->{entrytype} = $post_node->findvalue('bibtex/@entrytype');
            
        }
        else {
            if ($post_node->findvalue('bookmark/@url')){
                $record->set_field({field => 'T0662', subfield => '', mult => 1, content => $post_node->findvalue('bookmark/@url')});
            }

            if ($post_node->findvalue('bookmark/@title')){
                $record->set_field({field => 'T0331', subfield => '', mult => 1, content => $self->conv($post_node->findvalue('bookmark/@title'))});
            }

            $record->set_field({field => 'T0800', subfield => '', mult => 1, content => 'bookmark'});
        }

        if ($generic_attributes_ref->{user}){
            $record->set_field({field => 'T4220', subfield => '', mult => 1, content => $self->conv($generic_attributes_ref->{user}) });
        }

        if ($logger->is_debug){
            $logger->debug(YAML::Dump($record->get_fields()));
            $logger->debug($post_node->toString());
        }
        
        $record->set_circulation([]);
        $record->set_holding([]);
        $recordlist->add($record);
    }


    my $enriched_recordlist = new OpenBib::RecordList::Title({
        generic_attributes => {
            hits   => $search_count,
            next   => $next,
        }
    });

    # Jetzt nachtraegliches Anreichern mit gefundenen ISBNs
    
    foreach my $record ($recordlist->get_records){
        if (!$record->has_field('T0540') && defined $bibkey_isbn_ref->{$record->get_field({ field => 'T5050', mult => 1})}) {
            $record->set_field({field => 'T0540', subfield => '', mult => 1, content => $self->conv($bibkey_isbn_ref->{$record->get_field({ field => 'T5050', mult => 1})}) });
        }
        
        # Vorkommen in anderen Katalogen
        
        # Stage 1: Nach ISBN
        
        my $enrichment = new OpenBib::Enrichment;
        
        my $same_recordlist = new OpenBib::RecordList::Title();
        
        my $isbn   = $record->to_normalized_isbn13;
        my $bibkey = $record->get_field({field => 'T5050', mult => 1});

        my $have_title_ref = {};
        
        if ($isbn){
            
            $logger->debug("Looking for titles with isbn $isbn");
            
            my $same_titles = $enrichment->get_schema->resultset('AllTitleByIsbn')->search_rs(
                {
                    isbn => $isbn,
                },
                {
                    group_by => ['titleid','location','dbname','isbn','tstamp','titlecache'],
                    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                }
            );
            
            if ($logger->is_debug){            
                $logger->debug("Found ".($same_titles->count)." records");
            }
            
            while (my $item = $same_titles->next) {
                my $id         = $item->{titleid};
                my $database   = $item->{dbname};
                my $location    = $item->{location};
                my $titlecache = $item->{titlecache};
                
                next if (defined $have_title_ref->{"$database:$id:$location"});
                
                $same_recordlist->add(new OpenBib::Record::Title({ id => $id, database => $database}));

                $logger->debug("Found with isbn $isbn same item id=$id db=$database");
                
                $have_title_ref->{"$database:$id:$location"} = 1;
            }
        }

        # Stage 2: Ggf. nach BibKey
        
        if (!$same_recordlist->get_size() && $bibkey){
            # Anreicherung mit 'gleichen' (=gleicher bibkey) Titeln aus lokalen Katalogen            
            
            $logger->debug("Looking for titles with bibkey ".$bibkey);
            
            # DBI: "select distinct id,dbname from all_isbn where isbn=? and dbname != ? and id != ?";
            my $same_titles = $enrichment->get_schema->resultset('AllTitleByBibkey')->search_rs(
                {
                    bibkey    => $bibkey,
                },
                {                        
                    group_by => ['titleid','dbname','location','bibkey','tstamp','titlecache'], 
               }
            );

            $logger->debug("Checking bibkey ".$bibkey);

            foreach my $item ($same_titles->all) {
                my $id         = $item->titleid;
                my $database   = $item->dbname;
                my $location   = $item->location;

                next if (defined $have_title_ref->{"$database:$id:$location"});
                
                $logger->debug("Found with bibkey $bibkey same item id=$id db=$database");
                $same_recordlist->add(new OpenBib::Record::Title({ id => $id, database => $database}));

                $have_title_ref->{"$database:$id:$location"} = 1;

            }
            
        }

        $logger->debug("Setting same records");
        
        $record->set_same_records($same_recordlist);

        $logger->debug("Setting same records done");

        $logger->debug("Adding record to enriched recordlist");

        $logger->debug(YAML::Dump($record->get_fields));
        
        $enriched_recordlist->add($record);

        $logger->debug("Adding record to enriched recordlist done");

    }

    return $enriched_recordlist;
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
        $url="https://www.bibsonomy.org/api/tags?resourcetype=bibtex&resource=$bibkey";
        $logger->debug("Request: $url");
        
        my $response = $self->get_client->get($url)->content;
        
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
            
            
            if ($logger->is_debug){
                $logger->debug("Response / Posts: ".YAML::Dump(\@tags));
            }
        }
    }
    
    if (@unique_tags) {
        foreach my $tag (@unique_tags){
            substr($bibkey,0,1)=""; # Remove leading 1
            $url="https://www.bibsonomy.org/api/tags/$tag";
            $logger->debug("Request: $url");
            
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
        my $url = "https://www.bibsonomy.org/api/users/".$self->{api_user}."/posts/".$record->get_generic_attributes->{intrahash};
;

        $logger->debug($url);
        
        my $req = new HTTP::Request 'PUT' => $url;
        $req->content($newdata->toString());

        my $response = $self->get_client->request($req)->decoded_content(charset => 'utf-8');

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
    my $url = "https://www.bibsonomy.org/api/users/".$self->{api_user}."/posts";
;

    $logger->debug($url);
    my $req = new HTTP::Request 'POST' => $url;
    $req->content($doc->toString());

    my $response = $self->get_client->request($req)->decoded_content(charset => 'utf-8');

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

sub conv {
    my ($self,$content) = @_;
    
    $content=~s/\&amp;/&/g;     # zuerst etwaige &amp; auf & normieren 
    $content=~s/\&/&amp;/g;     # dann erst kann umgewandet werden (sonst &amp;amp;) 
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;
    
    return $content;
}

sub get_client {
    my $self = shift;

    if (defined $self->{client}){
        return $self->{client};
    }

    $self->connectClient;

    return $self->{client};
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

 OpenBib::API::HTTP::BibSonomy - Objekt zur Interaktion mit BibSonomy

=head1 DESCRIPTION

 Mit diesem Objekt kann von OpenBib über das API von BibSonomy auf diesen Web-Dienst zugegriffen werden.

=head1 SYNOPSIS

 use OpenBib::API::HTTP::BibSonomy;

 my $bibsonomy = new OpenBib::API::HTTP::BibSonomy({ api_key => $api_key, api_user => $api_user});

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
