####################################################################
#
#  OpenBib::Handler::Apache::Connector::AvailabilityImage
#
#  Dieses File ist (C) 2008-2011 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

package OpenBib::Handler::Apache::Connector::AvailabilityImage;

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Const -compile => qw(:common REDIRECT);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use APR::Table;

use Business::ISBN;
use Benchmark;
use DBI;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use Template;
use XML::LibXML;
use YAML;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('process_gbs');
    $self->run_modes(
        'gbs'        => 'process_gbs',
        'bibsonomy'  => 'process_bibsonomy',
        'ebook'      => 'process_ebook',
        'ol'         => 'process_ol',
        'wikipedia'  => 'process_wikipedia',
        'paperc'     => 'process_paperc',
        'unifloh'    => 'process_unifloh',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub process_gbs {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));
    
    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    my $client_ip="";
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $isbn = $self->id2isbnX($id);

    $logger->debug("ISBN von ID $id: ".YAML::Dump($isbn));

    my $redirect_url = "/images/openbib/no_img.png";
    
    if ($isbn->{isbn13}){
        my $ua       = LWP::UserAgent->new();
        $ua->agent($useragent);
        $ua->default_header('X-Forwarded-For' => $client_ip) if ($client_ip);
        my $url      ="http://books.google.com/books?jscmd=viewapi&bibkeys=ISBN$isbn->{isbn13}";
        #        my $url      = "http://books.google.com/books?vid=ISBN$isbn->{isbn13}";
        my $request  = HTTP::Request->new('GET', $url);
        my $response = $ua->request($request);
        
        if ( $response->is_error() ) {
            $logger->info("ISBN $isbn->{isbn13} NOT found in Google BookSearch");
            $logger->debug("Error-Code:".$response->code());
            $logger->debug("Fehlermeldung:".$response->message());
        }
        else {
            $logger->info("ISBN $isbn->{isbn13} found in Google BookSearch");
            $logger->debug($response->content());
            
            my ($json_result) = $response->content() =~/^var _GBSBookInfo = (.+);$/;
            
            my $gbs_result = {};
            
            eval {
                $gbs_result = decode_json($json_result);
            };
            
            $logger->debug("GBS".YAML::Dump($gbs_result));
            
            my $type = $gbs_result->{"ISBN$isbn->{isbn13}"}{preview} || $gbs_result->{"ISBN$isbn->{isbn10}"}{preview} || '';
            
            if ($type eq "noview"){
                $logger->debug("GBS: noview");
                $redirect_url = "/images/openbib/no_img.png";
            }
            elsif ($type eq "partial"){
                $logger->debug("GBS: partial");
                $redirect_url = "/images/openbib/gbs-partial.png";
            }
            elsif ($type eq "full"){
                $logger->debug("GBS: full");
                $redirect_url = "/images/openbib/gbs-full.png";
            }
            else {
                $logger->debug("GBS: other");
                $redirect_url = "/images/openbib/no_img.png";
            }
        }
    }

#    $self->header_type('redirect');
#    $self->header_props(-url => $redirect_url);

    $self->query->headers_out->add(Location => $redirect_url);
    $self->query->status(Apache2::Const::REDIRECT);

    return '';
}

sub process_bibsonomy {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    my $client_ip="";
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $redirect_url = "/images/openbib/no_img.png";
    
    my $ua       = LWP::UserAgent->new();
    $ua->agent($useragent);
    $ua->default_header('X-Forwarded-For' => $client_ip) if ($client_ip);
    my $url      ="http://www.bibsonomy.org/swrc/bibtex/$id";
    
    my $request  = HTTP::Request->new('GET', $url);
    my $response = $ua->request($request);
    
    if ( $response->is_error() ) {
        $logger->info("Bibkey $id NOT found in BibSonomy");
        $logger->debug("Error-Code:".$response->code());
        $logger->debug("Fehlermeldung:".$response->message());
    }
    else {
        $logger->info("Bibkey $id found in BibSonomy");
        $logger->debug($response->content());
        
        my $content = $response->content();
        if ($content=~/rdf:Description/){
            $redirect_url = "/images/openbib/bibsonomy_available.png";
        }
    }

    $self->query->headers_out->add(Location => $redirect_url);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub process_ebooks {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    my $client_ip="";
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $isbn = $self->id2isbnX($id);

    my $redirect_url = "/images/openbib/no_img.png";
    
    if ($isbn->{isbn13}){
        # Verbindung zur SQL-Datenbank herstellen
        my $enrichdbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $sql_request = "select count(isbn) as ebcount from normdata where isbn=? and origin=20 and category=4120";
        my $request=$enrichdbh->prepare($sql_request);
        $request->execute($isbn->{isbn13});
        my $result =$request->fetchrow_hashref;
        
        if ($result->{ebcount} > 0){
            $logger->info("ISBN $isbn->{isbn13} found for USB Ebooks");
            $redirect_url = "/images/openbib/usb_ebook.png";
        }
    }

    $self->query->headers_out->add(Location => $redirect_url);
    $self->query->status(Apache2::Const::REDIRECT);

    return '';
}

sub process_ol {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    my $client_ip="";
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $isbn = $self->id2isbnX($id);

    my $redirect_url = "/images/openbib/no_img.png";
    
    my $ua       = LWP::UserAgent->new();
    $ua->agent($useragent);
    $ua->default_header('X-Forwarded-For' => $client_ip) if ($client_ip);
    my $url      ="http://openlibrary.org/api/things?query=\{\"type\":\"/type/edition\", \"isbn_10\":\"$isbn->{isbn10}\"\}";
    
    my $request  = HTTP::Request->new('GET', $url);
    my $response = $ua->request($request);
    
    if ( $response->is_error() ) {
        $logger->info("ISBN $id / $isbn->{isbn10} NOT found in OpenLibrary");
        $logger->debug("Error-Code:".$response->code());
        $logger->debug("Fehlermeldung:".$response->message());
    }
    else {
        $logger->info("ISBN $id / $isbn->{isbn10} found in OpenLibrary");
        $logger->debug($response->content());
        
        my ($json_result) = $response->content();
        
        my $ol_result = {};
        
        eval {
            $ol_result = decode_json($json_result);
        };
        
        $logger->debug("OL".YAML::Dump($ol_result));
        
        my $status  = $ol_result->{status} || '';
        my $ids_ref = $ol_result->{result} || ();
        
        
        $logger->debug("Lookup ID ".YAML::Dump($ids_ref));
        my $url      ="http://openlibrary.org/api/get?key=$ids_ref->[0]";
        
        $logger->debug("URI: $url");
        my $request  = HTTP::Request->new('GET', $url);
        my $response = $ua->request($request);
        
        if ( $response->is_error() ) {
            $logger->info("Document-Data NOT found in OpenLibrary");
            $logger->debug("Error-Code:".$response->code());
            $logger->debug("Fehlermeldung:".$response->message());
        }
        else {
            my ($json_result) = $response->content();
            
            eval {
                $ol_result = decode_json($json_result);
            };
            $logger->debug("OL OBJ Data".YAML::Dump($ol_result));
        }
        $redirect_url = "/images/openbib/no_img.png";
    }

    $self->query->headers_out->add(Location => $redirect_url);
    $self->query->status(Apache2::Const::REDIRECT);

    return '';
}

sub process_unifloh {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    my $client_ip="";
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $isbn = $self->id2isbnX($id);

    my $redirect_url = "/images/openbib/no_img.png";
    
    if ($isbn->{isbn13}){
        my $ua       = LWP::UserAgent->new();
        $ua->agent($useragent);
        $ua->default_header('X-Forwarded-For' => $client_ip) if ($client_ip);
        my $url      ="http://www.unifloh.de/apicall?a=4f4ad14a8a543ed4ec90e2a136e5fbcc&uni_tag=koeln&method=getoffers&isbn=$isbn->{isbn13}";
        $logger->debug("Querying Unifloh with $url");
        my $request  = HTTP::Request->new('GET', $url);
        my $response = $ua->request($request);
        
        if ( $response->is_error() ) {
            $logger->info("Error querying Unifloh");
            $logger->debug("Error-Code:".$response->code());
            $logger->debug("Fehlermeldung:".$response->message());
        }
        else {
            $logger->debug($response->content());
            
            my $content = $response->content();
            if ($content=~/<numlocal>(\d+)<\/numlocal>/){
                my $localitems=$1;
                if ($localitems > 0){
                    $redirect_url = "http://www.unifloh.de/template_new/images/logo2.gif";
                }
            }
        }
    }

    $self->query->headers_out->add(Location => $redirect_url);
    $self->query->status(Apache2::Const::REDIRECT);

    return '';
}

sub process_wikipedia {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang') || 'de';
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    my $client_ip="";
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }
    
    my $redirect_url = "/images/openbib/no_img.png";
    
    my $ua       = LWP::UserAgent->new();
    $ua->agent($useragent);
    $ua->default_header('X-Forwarded-For' => $client_ip) if ($client_ip);
    my $url      ="http://${lang}.wikipedia.org/w/api.php?action=query&format=json&titles=$id";
    $logger->debug("Querying Wikipedia with $url");
    my $request  = HTTP::Request->new('GET', $url);
    my $response = $ua->request($request);
    
    if ( $response->is_error() ) {
        $logger->info("Error querying Wikipedia");
        $logger->debug("Error-Code:".$response->code());
        $logger->debug("Fehlermeldung:".$response->message());
    }
    else {
        $logger->debug($response->content());
        
        my $content = $response->content();
        
        my $content_ref = decode_json($content);
        
        if (!$content_ref->{query}{pages}{-1}){
            $redirect_url = "$config->{wikipedia_img}";
        }
    }

    $self->query->headers_out->add(Location => $redirect_url);
    $self->query->status(Apache2::Const::REDIRECT);
    
    return '';
}

sub process_paperc {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('id'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    my $client_ip="";
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $redirect_url = "http://$config->{servername}/images/openbib/no_img.png";
    
    my $ua       = LWP::UserAgent->new();
    $ua->agent($useragent);
    $ua->default_header('X-Forwarded-For' => $client_ip) if ($client_ip);
    my $url      ="http://paperc.de/search?query=$id&commit=Suchen";
    $logger->debug("Querying PaperC with $url");
    my $request  = HTTP::Request->new('GET', $url);
    my $response = $ua->request($request);
    
    if ( $response->is_error() ) {
        $logger->info("Error querying PaperC");
        $logger->debug("Error-Code:".$response->code());
        $logger->debug("Fehlermeldung:".$response->message());
    }
    else {
        $logger->debug($response->content());
        
        my $content = $response->content();
        if ($content=~/Die Suche nach.+?ergab 1 Treffer/){
            my $uri = "";
            if ($content=~/<a href="(.+?)">Info<\/a>/){
                $uri = $1;
                $logger->debug("Item found in PaperC with URI: $uri");
            }
            
            if ($uri){
                $redirect_url = "http://$config->{servername}/images/openbib/paperc.png";
            }
        }
    }

    $self->query->headers_out->add(Location => $redirect_url);
    $self->query->status(Apache2::Const::REDIRECT);
   
    return '';
}

sub id2isbnX {
    my ($self,$id) = @_;

    my $isbn13="";
    my $isbn10="";
        
    # Ist es eine ISBN? Dann Normierung auf ISBN10/13
    my $isbnXX     = Business::ISBN->new($id);
    
    if (defined $isbnXX && $isbnXX->is_valid){
        $isbn13 = $isbnXX->as_isbn13->as_string;
        $isbn10 = $isbnXX->as_isbn10->as_string;
        
        $isbn13 = OpenBib::Common::Util::grundform({
            category => '0540',
            content  => $isbn13,
        });
        
        $isbn10 = OpenBib::Common::Util::grundform({
            category => '0540',
            content  => $isbn10,
        });
    }

    return {
        isbn13 => $isbn13,
        isbn10 => $isbn10,
    };        
}
    
1;
