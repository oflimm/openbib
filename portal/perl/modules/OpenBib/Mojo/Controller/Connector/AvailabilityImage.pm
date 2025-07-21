####################################################################
#
#  OpenBib::Mojo::Controller::Connector::AvailabilityImage
#
#  Dieses File ist (C) 2008-2025 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Connector::AvailabilityImage;

use strict;
use warnings;
no warnings 'redefine';

use Business::ISBN;
use Benchmark;
use DBI;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use Mojo::UserAgent;
use Template;
use XML::LibXML;
use YAML::Syck;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $type           = $self->param('type');

    # Shared Args    
    my $msg            = $self->stash('msg');

    if ($type eq "gbs"){
	return $self->process_gbs;
    }
    elsif ($type eq "bibsonomy"){
	return $self->process_bibsonomy;
    }
    elsif ($type eq "ebooks"){
	return $self->process_ebooks;
    }
    elsif ($type eq "ol"){
	return $self->process_ol;
    }
    elsif ($type eq "wikipedia"){
	return $self->process_wikipedia;
    }
    else {
	return $self->print_warning($msg->maketext("Unbekannter Typ"));
    }
}

sub process_gbs {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->param('id');
    
    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $client_ip      = $self->stash('remote_ip');
    
    my $isbn = $self->id2isbnX($id);

    if ($logger->is_debug){
        $logger->debug("ISBN von ID $id: ".YAML::Dump($isbn));
    }

    my $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/no_img.png";
    
    if ($isbn->{isbn13}){
        my $ua       = Mojo::UserAgent->new;
	$ua->transactor->name($useragent); # Passthrough Clients UA
	$ua->connect_timeout(10);

        my $header_ref = {'X-Forwarded-For' => $client_ip};
	
        my $url      ="http://books.google.com/books?jscmd=viewapi&bibkeys=ISBN$isbn->{isbn13}";
        #        my $url      = "http://books.google.com/books?vid=ISBN$isbn->{isbn13}";

        my $response = $ua->get($url => $header_ref)->result;
        
        if ( $response->is_error() ) {
            $logger->info("ISBN $isbn->{isbn13} NOT found in Google BookSearch");
            $logger->debug("Error-Code:".$response->code());
            $logger->debug("Fehlermeldung:".$response->message());
        }
        else {
            $logger->info("ISBN $isbn->{isbn13} found in Google BookSearch");
            $logger->debug($response->body);
            
            my ($json_result) = $response->body =~/^var _GBSBookInfo = (.+);$/;
            
            my $gbs_result = {};
            
            eval {
                $gbs_result = decode_json($json_result);
            };
            
            if ($logger->is_debug){
                $logger->debug("GBS".YAML::Dump($gbs_result));
            }
            
            my $type = $gbs_result->{"ISBN$isbn->{isbn13}"}{preview} || $gbs_result->{"ISBN$isbn->{isbn10}"}{preview} || '';
            
            if ($type eq "noview"){
                $logger->debug("GBS: noview");
                $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/no_img.png";
            }
            elsif ($type eq "partial"){
                $logger->debug("GBS: partial");
                $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/gbs-partial.png";
            }
            elsif ($type eq "full"){
                $logger->debug("GBS: full");
                $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/gbs-full.png";
            }
            else {
                $logger->debug("GBS: other");
                $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/no_img.png";
            }
        }
    }

    $self->redirect($redirect_url);

    return;
}

sub process_bibsonomy {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->param('id');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $client_ip      = $self->stash('remote_ip');

    my $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/no_img.png";
    
    my $ua       = Mojo::UserAgent->new;
    $ua->transactor->name($useragent); # Passthrough Clients UA
    $ua->connect_timeout(10);
    
    my $header_ref = {'X-Forwarded-For' => $client_ip};

    my $url      ="http://www.bibsonomy.org/swrc/bibtex/$id";

    my $response = $ua->get($url => $header_ref)->result;

    if ( $response->is_error() ) {
        $logger->info("Bibkey $id NOT found in BibSonomy");
        $logger->debug("Error-Code:".$response->code());
        $logger->debug("Fehlermeldung:".$response->message());
    }
    else {
        $logger->info("Bibkey $id found in BibSonomy");
        $logger->debug($response->body);
        
        my $content = $response->body;
        if ($content=~/rdf:Description/){
            $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/bibsonomy_available.png";
        }
    }

    $self->redirect($redirect_url);

    return;
}

sub process_ebooks {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->param('id');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $client_ip      = $self->stash('remote_ip');

    my $isbn = $self->id2isbnX($id);

    my $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/no_img.png";
    
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
            $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/usb_ebook.png";
        }
    }

    $self->redirect($redirect_url);

    return;
}

sub process_ol {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->param('id');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $client_ip      = $self->stash('remote_ip');

    my $isbn = $self->id2isbnX($id);

    my $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/no_img.png";
    
    my $ua       = Mojo::UserAgent->new;
    $ua->transactor->name($useragent); # Passthrough Clients UA
    $ua->connect_timeout(10);
    
    my $header_ref = {'X-Forwarded-For' => $client_ip};

    my $url      ="http://openlibrary.org/api/things?query=\{\"type\":\"/type/edition\", \"isbn_10\":\"$isbn->{isbn10}\"\}";

    my $response = $ua->get($url => $header_ref)->result;
    
    if ( $response->is_error() ) {
        $logger->info("ISBN $id / $isbn->{isbn10} NOT found in OpenLibrary");
        $logger->debug("Error-Code:".$response->code());
        $logger->debug("Fehlermeldung:".$response->message());
    }
    else {
        $logger->info("ISBN $id / $isbn->{isbn10} found in OpenLibrary");
        $logger->debug($response->content());
        
        my $json_result = $response->body;
        
        my $ol_result = {};
        
        eval {
            $ol_result = decode_json($json_result);
        };
        
        if ($logger->is_debug){
            $logger->debug("OL".YAML::Dump($ol_result));
        }
        
        my $status  = $ol_result->{status} || '';
        my $ids_ref = $ol_result->{result} || ();
        
        
        if ($logger->is_debug){
            $logger->debug("Lookup ID ".YAML::Dump($ids_ref));
        }
        
        my $url      ="http://openlibrary.org/api/get?key=$ids_ref->[0]";
        
        $logger->debug("URI: $url");

	my $response = $ua->get($url => $header_ref)->result;
        
        if ( $response->is_error() ) {
            $logger->info("Document-Data NOT found in OpenLibrary");
            $logger->debug("Error-Code:".$response->code());
            $logger->debug("Fehlermeldung:".$response->message());
        }
        else {
            my $json_result = $response->body;
            
            eval {
                $ol_result = decode_json($json_result);
            };
            
            if ($logger->is_debug){
                $logger->debug("OL OBJ Data".YAML::Dump($ol_result));
            }
        }
        $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/no_img.png";
    }

    $self->redirect($redirect_url);

    return;
}

sub process_wikipedia {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->param('id');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $client_ip      = $self->stash('remote_ip');

    # CGI Args
    my $lang           = $r->param('lang') || 'de';

    my $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."/images/openbib/no_img.png";

    my $ua       = Mojo::UserAgent->new;
    $ua->transactor->name($useragent); # Passthrough Clients UA
    $ua->connect_timeout(10);
    
    my $header_ref = {'X-Forwarded-For' => $client_ip};

    my $url      ="https://${lang}.wikipedia.org/w/api.php?action=query&format=json&titles=$id";

    $logger->debug("Querying Wikipedia with $url");
    
    my $response = $ua->get($url => $header_ref)->result;
        
    if ( $response->is_error() ) {
        $logger->info("Error querying Wikipedia");
        $logger->debug("Error-Code:".$response->code());
        $logger->debug("Fehlermeldung:".$response->message());
    }
    else {
        $logger->debug($response->body);
        
        my $content = $response->body;
        
        my $content_ref = decode_json($content);

	if ($logger->is_debug){
	    $logger->debug("Result: ".YAML::Dump($content_ref));
	}
	
        if (defined $content_ref->{'query'}{'pages'}{'-1'}{'title'}){
            $redirect_url = $self->stash('scheme')."://".$self->stash('servername')."$config->{wikipedia_img}";

	    $logger->debug("Setting redirect url to $redirect_url");
        }
    }

    return $self->redirect($redirect_url);
}

sub id2isbnX {
    my ($self,$id) = @_;

    my $normalizer     = $self->stash('normalizer');
    
    my $isbn13="";
    my $isbn10="";
        
    # Ist es eine ISBN? Dann Normierung auf ISBN10/13
    my $isbnXX     = Business::ISBN->new($id);
    
    if (defined $isbnXX && $isbnXX->is_valid){
        $isbn13 = $isbnXX->as_isbn13->as_string;
        $isbn10 = $isbnXX->as_isbn10->as_string;
        
        $isbn13 = $normalizer->normalize({
            field => 'T0540',
            content  => $isbn13,
        });
        
        $isbn10 = $normalizer->normalize({
            field => 'T0540',
            content  => $isbn10,
        });
    }

    return {
        isbn13 => $isbn13,
        isbn10 => $isbn10,
    };        
}
    
1;
