####################################################################
#
#  OpenBib::Connector::AvailabilityImage
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

package OpenBib::Connector::AvailabilityImage;

use strict;
use warnings;
no warnings 'redefine';

use Apache::Constants qw(:common REDIRECT);
use Apache::Reload;
use Apache::Request ();
use Apache::URI ();
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

    my $config = new OpenBib::Config;

    my $query  = Apache::Request->instance($r);
    
    my $status=$query->parse;
    
    if ($status){
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $action         = $query->param('action')          || 'lookup';
    my $isbn           = $query->param('isbn')            || '';
    my $target         = $query->param('target')          || 'gbs';
    
    if ($action eq "lookup"){
        # Normierung auf ISBN13
        my $isbnXX     = Business::ISBN->new($isbn);
        
        if (defined $isbnXX && $isbnXX->is_valid){
            $isbn = $isbnXX->as_isbn13->as_string;
        }
        else {
            $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");
             return OK;
         }
        
        $isbn = OpenBib::Common::Util::grundform({
            category => '0540',
            content  => $isbn,
        });

        if ($target eq "gbs"){
            my $ua       = LWP::UserAgent->new();
            $ua->agent('Mozilla/5.0');
            my $url      ="http://books.google.com/books?jscmd=viewapi&bibkeys=ISBN$isbn";
            #        my $url      = "http://books.google.com/books?vid=ISBN$isbn";
            my $request  = HTTP::Request->new('GET', $url);
            my $response = $ua->request($request);
            
            if ( $response->is_error() ) {
                $logger->info("ISBN $isbn NOT found in Google BookSearch");
                $logger->debug("Error-Code:".$response->code());
                $logger->debug("Fehlermeldung:".$response->message());

                $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");                
                return OK;                
            }
            else {
                $logger->info("ISBN $isbn found in Google BookSearch");
                $logger->debug($response->content());
                
                my ($json_result) = $response->content() =~/^var _GBSBookInfo = (.+);$/;
                
                my $json = new JSON;
                my $gbs_result = {};
                
                eval {
                    $gbs_result = $json->jsonToObj($json_result);
                };
                
                $logger->debug("GBS".YAML::Dump($gbs_result));
                
                my $type = $gbs_result->{"ISBN$isbn"}{preview};
                
                if ($type eq "noview"){
                    $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");
                    #$r->internal_redirect("http://$config->{servername}/images/openbib/gbs-noview.png");
                    return OK;
                }
                elsif ($type eq "partial"){
                    $r->internal_redirect("http://$config->{servername}/images/openbib/gbs-partial.png");
                    $logger->error("http://$config->{servername}/images/openbib/gbs-partial.png");
                    return OK;
                }
                elsif ($type eq "full"){
                    $r->internal_redirect("http://$config->{servername}/images/openbib/gbs-full.png");
                    return OK;
                }
                else {
                    $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");
                    #$r->internal_redirect("http://$config->{servername}/images/openbib/gbs.png");
                    return OK;
                }
            }
        }
    }
    
    $r->internal_redirect("http://$config->{servername}/images/openbib/no_img.png");
    
    return OK;
}

1;
