####################################################################
#
#  OpenBib::Handler::Apache::Connector::AvailabilityImage
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
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

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::SubRequest ();
use APR::Table;

use Business::ISBN;
use Benchmark;
use DBI;
use JSON;
use Log::Log4perl qw(get_logger :levels);
use LWP::UserAgent;
use Template;
use YAML;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $query  = Apache2::Request->new($r);
    
    my $status=$query->parse;
    
    if ($status){
        $logger->error("Cannot parse Arguments");
    }

    my $useragent=$r->subprocess_env('HTTP_USER_AGENT') || 'Mozilla/5.0';
    my $client_ip="";
    if ($r->headers_in->get('X-Forwarded-For') =~ /([^,\s]+)$/) {
        $client_ip=$1;
    }

    my $action         = $query->param('action')          || 'lookup';
    my $isbn           = $query->param('isbn')            || '';
    my $bibkey         = $query->param('bibkey')          || '';
    my $target         = $query->param('target')          || 'gbs';
    
    if ($action eq "lookup"){

        my $isbn13="";
        
        if ($isbn){
            # Normierung auf ISBN13
            my $isbnXX     = Business::ISBN->new($isbn);
            
            if (defined $isbnXX && $isbnXX->is_valid){
                $isbn13 = $isbnXX->as_isbn13->as_string;
            }
            else {
                $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");
                return Apache2::Const::OK;
            }
            
            $isbn13 = OpenBib::Common::Util::grundform({
                category => '0540',
                content  => $isbn,
            });
        }
        
        if ($target eq "gbs" && $isbn13){
            my $ua       = LWP::UserAgent->new();
            $ua->agent($useragent);
            $ua->default_header('X-Forwarded-For' => $client_ip) if ($client_ip);
            my $url      ="http://books.google.com/books?jscmd=viewapi&bibkeys=ISBN$isbn13";
            #        my $url      = "http://books.google.com/books?vid=ISBN$isbn13";
            my $request  = HTTP::Request->new('GET', $url);
            my $response = $ua->request($request);
            
            if ( $response->is_error() ) {
                $logger->info("ISBN $isbn13 NOT found in Google BookSearch");
                $logger->debug("Error-Code:".$response->code());
                $logger->debug("Fehlermeldung:".$response->message());

                $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");                
                return Apache2::Const::OK;                
            }
            else {
                $logger->info("ISBN $isbn13 found in Google BookSearch");
                $logger->debug($response->content());
                
                my ($json_result) = $response->content() =~/^var _GBSBookInfo = (.+);$/;
                
                my $json = new JSON;
                my $gbs_result = {};
                
                eval {
                    $gbs_result = $json->jsonToObj($json_result);
                };
                
                $logger->debug("GBS".YAML::Dump($gbs_result));
                
                my $type = $gbs_result->{"ISBN$isbn13"}{preview} || '';
                
                if ($type eq "noview"){
                    #$r->internal_redirect("/images/openbib/no_img.png");
                    $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");
                    #$r->internal_redirect("http://$config->{servername}/images/openbib/gbs-noview.png");
                    return Apache2::Const::OK;
                }
                elsif ($type eq "partial"){
                    $r->internal_redirect("http://$config->{servername}/images/openbib/gbs-partial.png");
                    return Apache2::Const::OK;
                }
                elsif ($type eq "full"){
                    $r->internal_redirect("http://$config->{servername}/images/openbib/gbs-full.png");
                    return Apache2::Const::OK;
                }
                else {
                    #$r->internal_redirect("/images/openbib/no_img.png");
                    $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");
                    #$r->internal_redirect("http://$config->{servername}/images/openbib/gbs.png");
                    return Apache2::Const::OK;
                }
            }
        }
        elsif ($target eq "bibsonomy" && $bibkey){
            my $ua       = LWP::UserAgent->new();
            $ua->agent($useragent);
            $ua->default_header('X-Forwarded-For' => $client_ip) if ($client_ip);
            my $url      ="http://www.bibsonomy.org/swrc/bibtex/$bibkey";

            my $request  = HTTP::Request->new('GET', $url);
            my $response = $ua->request($request);
            
            if ( $response->is_error() ) {
                $logger->info("Bibkey $bibkey NOT found in BibSonomy");
                $logger->debug("Error-Code:".$response->code());
                $logger->debug("Fehlermeldung:".$response->message());

                $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");                
                return Apache2::Const::OK;                
            }
            else {
                $logger->info("Bibkey $bibkey found in BibSonomy");
                $logger->debug($response->content());
                
                my $content = $response->content();
                if ($content=~/rdf:Description/){                    
                    $r->internal_redirect("http://$config->{servername}/images/openbib/bibsonomy_available.png");
                    return Apache2::Const::OK;
                }
            }
        }
        elsif ($target eq "ebook"){
            # Verbindung zur SQL-Datenbank herstellen
            my $enrichdbh
                = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                    or $logger->error_die($DBI::errstr);

            my $sql_request = "select count(isbn) as ebcount from normdata where isbn=? and origin=20 and category=4120";
            my $request=$enrichdbh->prepare($sql_request);
            $request->execute($isbn13);
            my $result =$request->fetchrow_hashref;

            if ($result->{ebcount} > 0){
                $logger->info("ISBN $isbn13 found for USB Ebooks");
                $r->internal_redirect("http://$config->{servername}/images/openbib/usb_ebook.png");
                return Apache2::Const::OK;
            }
            
        }
        if ($target eq "ol" && $isbn){
            my $ua       = LWP::UserAgent->new();
            $ua->agent($useragent);
            $ua->default_header('X-Forwarded-For' => $client_ip) if ($client_ip);
            my $url      ="http://openlibrary.org/api/things?query=\{\"type\":\"/type/edition\", \"isbn_10\":\"$isbn\"\}";

            my $request  = HTTP::Request->new('GET', $url);
            my $response = $ua->request($request);
            
            if ( $response->is_error() ) {
                $logger->info("ISBN $isbn NOT found in OpenLibrary");
                $logger->debug("Error-Code:".$response->code());
                $logger->debug("Fehlermeldung:".$response->message());

                $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");                
                return Apache2::Const::OK;                
            }
            else {
                $logger->info("ISBN $isbn found in OpenLibrary");
                $logger->debug($response->content());
                
                my ($json_result) = $response->content();
                
                my $json = new JSON;
                my $ol_result = {};
                
                eval {
                    $ol_result = $json->jsonToObj($json_result);
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

                   $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");                
                   return Apache2::Const::OK;                
                }
                else {
                    my ($json_result) = $response->content();

                    eval {
                        $ol_result = $json->jsonToObj($json_result);
                    };
                
                    $logger->debug("OL OBJ Data".YAML::Dump($ol_result));
                }

                $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");
                return Apache2::Const::OK;
            }
        }
    }
    
    $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");
    
    return Apache2::Const::OK;
}

1;
