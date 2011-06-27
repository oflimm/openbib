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

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $serviceid      = $self->strip_suffix($self->param('serviceid'));

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

    # CGI Args
    my $id         = $query->param('id')        || '';
    my $format     = $query->param('format')    || '';
    my $callback   = $query->param('callback')  || '';
    my $lang       = $query->param('lang')      || 'de';

    my $identifier =  new SeeAlso::Identifier($id);

    my @description = ( "ShortName" => "OpenBib SeeAlso Service" );
    my $server = new SeeAlso::Server( description => \@description );

    $logger->debug("SeeAlso: Serviceid - $serviceid Identifier $id - Format $format");
    
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

    my $current_service_ref = (exists $services_ref->{$serviceid})?$services_ref->{$serviceid}:"";

    if ($current_service_ref){
        $logger->debug("Using service $serviceid");
        my $source = SeeAlso::Source->new($current_service_ref->{query_proc},
        ( "ShortName" => $current_service_ref->{description} )
    );
        
    $r->print($server->query($source, $identifier, $format, $callback));
                                  }
    return Apache2::Const::OK;
}

1;
