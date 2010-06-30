####################################################################
#
#  OpenBib::Handler::Apache::Connector::SeeAlso.pm
#
#  Dieses File ist (C) 2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::SeeAlso;

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();   # CGI-Handling (or require)
use Apache2::RequestIO (); # rflush, print
use Apache2::RequestRec ();
use Apache2::URI ();
use APR::URI ();
use URI;

use Benchmark;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;
use SeeAlso::Server;
use SeeAlso::Response;
use SeeAlso::Source;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Enrichment;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    my $uri  = $r->parsed_uri;
    my $path = $uri->path;

    my $query  = Apache2::Request->new($r);

    my $id         = $query->param('id')        || '';
    my $format     = $query->param('format')    || '';
    my $callback   = $query->param('callback')  || '';
    my $lang       = $query->param('lang')      || 'de';

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    # Basisipfad entfernen
    my $basepath = $config->{connector_seealso_loc};
    $path=~s/$basepath//;

    # Service-Parameter aus URI bestimmen
    my $service;
    if ($path=~m/^\/(.+)/){
        $service=$1;
    }

    my $identifier =  new SeeAlso::Identifier($id);

    my @description = ( "ShortName" => "MySimpleServer" );
    my $server = new SeeAlso::Server( description => \@description );

    $logger->debug("SeeAlso: Service - $service Identifier $id - Format $format");
    
    my $services_ref = {
        'isbn2wikipedia' => {
            'description' => 'Articles in Wikipedia referencing given ISBN',
            'query_proc'  => sub {
                my $identifier = shift;

                my $logger = get_logger();

                my $response = SeeAlso::Response->new($identifier);

                my $enrichmnt = new OpenBib::Enrichment;

                my $result_ref = $enrichmnt->get_additional_normdata({isbn => $identifier});

                # Deutsche Wikipedia
                foreach my $content (@{$result_ref->{E4200}}){
                    my $uri = URI->new( "http://de.wikipedia.org/wiki/$content" )->canonical;
                    $response->add($content,"Artikel in deutscher Wikipedia","$uri");
                    $logger->debug("Added $content");
                }

                return $response;
            }
        },
        'isbn2paperc' => {
            'description' => 'Available Title in PaperC for a given ISBN',
            'query_proc'  => sub {
                my $identifier = shift;

                my $logger = get_logger();

                my $response = SeeAlso::Response->new($identifier);

                my $enrichmnt = new OpenBib::Enrichment;

                my $result_ref = $enrichmnt->get_additional_normdata({isbn => $identifier});

                # PaperC
                foreach my $content (@{$result_ref->{E4122}}){
                    my $uri = URI->new( "$content" )->canonical;
                    $response->add($content,"Title in PaperC","$uri");
                    $logger->debug("Added $content");
                }

                return $response;
            }
        },
        'isbn2subjects' => {
            'description' => 'Subjects of a given ISBN',
            'query_proc'  => sub {
                my $identifier = shift;

                my $logger = get_logger();
                
                my $response = SeeAlso::Response->new($identifier);

                my $enrichmnt = new OpenBib::Enrichment;

                my $result_ref = $enrichmnt->get_additional_normdata({isbn => $identifier});
                
                foreach my $content (@{$result_ref->{E4300}}){
                    my $uri = URI->new( "http://de.wikipedia.org/wiki/$content" )->canonical;
                    $response->add($content,"Schlagwort","$uri");
                    $logger->debug("Added $content");
                }

                return $response;
            }
        },
        'issn2tictocs' => {
            'description' => 'TicTocs-Feeds of a given ISSN',
            'query_proc'  => sub {
                my $identifier = shift;

                my $logger = get_logger();
                
                my $response = SeeAlso::Response->new($identifier);

                my $enrichmnt = new OpenBib::Enrichment;

                my $result_ref = $enrichmnt->get_additional_normdata({isbn => $identifier});
                
                foreach my $content (@{$result_ref->{E4115}}){
                    my $uri = URI->new( $content )->canonical;
                    $response->add("Recent Articles","TicTocs RSS-Feed","$uri");
                    $logger->debug("Added $content");
                }

                return $response;
            }
        },
        'thingisbn' => {
            'description' => 'Other manifestations of a work for a given ISBN',
            'query_proc'  => sub {
                my $identifier = shift;

                my $logger = get_logger();
                
                my $response = SeeAlso::Response->new($identifier);

                my $enrichmnt = new OpenBib::Enrichment;

                my $result_ref = $enrichmnt->get_similar_isbns({isbn => $identifier});
                
                foreach my $content (keys %{$result_ref}){
                    my $uri = URI->new( "http://de.wikipedia.org/wiki/$content" )->canonical;
                    $response->add($content,"ISBN","$uri");
                    $logger->debug("Added $content");
                }

                return $response;
            }
        },
        'isbn2kug' => {
            'description' => 'Occurence of a given ISBN in KUG',
            'query_proc'  => sub {
                my $identifier = shift;

                my $logger = get_logger();
                
                my $response = SeeAlso::Response->new($identifier);

                my $enrichmnt = new OpenBib::Enrichment;

                my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

                my $result_ref = $enrichmnt->get_holdings({isbn => $identifier});

                foreach my $content_ref (@{$result_ref}){
                    my $content = $dbinfotable->{dbnames}{$content_ref->{dbname}};
                    my $uri     = URI->new( "http://kug.ub.uni-koeln.de/portal/connector/permalink/$content.wikipedia.org/wiki/$content_ref->{dbname}/$content->{id}/1/kug/index.html" )->canonical;
                    $response->add($content,"Verfuegbarkeit des Titels im KUG","$uri");
                    $logger->debug("Added $content");
                }

                return $response;
            }
        },

    };

    my $current_service_ref = (exists $services_ref->{$service})?$services_ref->{$service}:"";

    if ($current_service_ref){
        $logger->debug("Using service $service");
        my $source = SeeAlso::Source->new($current_service_ref->{query_proc},
        ( "ShortName" => $current_service_ref->{description} )
    );
        
    $r->print($server->query($source, $identifier, $format, $callback));
                                  }
    return Apache2::Const::OK;
}

1;
