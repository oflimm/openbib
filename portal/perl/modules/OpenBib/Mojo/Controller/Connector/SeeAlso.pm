####################################################################
#
#  OpenBib::Mojo::Controller::Connector::SeeAlso.pm
#
#  Dieses File ist (C) 2009-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Connector::SeeAlso;

use strict;
use warnings;
no warnings 'redefine';

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

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $serviceid      = $self->strip_suffix($self->param('serviceid'));

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

    # CGI Args
    my $id         = $query->stash('id')        || '';
    my $format     = $query->stash('format')    || '';
    my $callback   = $query->stash('callback')  || '';
    my $lang       = $query->stash('lang')      || 'de';

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

                my $result_ref = $enrichmnt->get_enriched_content({isbn => $identifier});

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

                my $result_ref = $enrichmnt->get_enriched_content({isbn => $identifier});
                
                foreach my $content (@{$result_ref->{E4300}}){
                    my $uri = URI->new( "http://de.wikipedia.org/wiki/$content" )->canonical;
                    $response->add($content,"Schlagwort","$uri");
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

                my $dbinfotable = OpenBib::Config::DatabaseInfoTable->new;

                my $result_ref = $enrichmnt->get_holdings({isbn => $identifier});

                foreach my $content_ref (@{$result_ref}){
                    my $content = $dbinfotable->get('dbnames')->{$content_ref->{dbname}};
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
        
        return $self->_output_seealso($id,$server,$source, $identifier, $format, $callback); # TODO print
    }

    return;
}

# Modified Code because Original Code was broken by switching to PSGI. Original code (C) by Jakob Voss
sub _output_seealso {
    my ($self,$id,$server,$source,$identifier,$format,$callback) = @_;
    
    my $http = "";
    
    if (ref($source) eq "CODE") {
        $source = new SeeAlso::Source( $source );
    }
    croak('First parameter must be a SeeAlso::Source object!')
        unless defined $source and UNIVERSAL::isa($source, 'SeeAlso::Source');

    if ( ref($identifier) eq 'CODE' ) {
        $identifier = &$identifier( $id );
    } elsif (not defined $identifier) {
        $identifier = $id;
    }
    $identifier = new SeeAlso::Identifier( $identifier )
        unless UNIVERSAL::isa( $identifier, 'SeeAlso::Identifier' );

    $format = "" unless defined $format;
    $callback = "" unless defined $callback;

    # If everything is ok up to here, we should definitely return some valid stuff
    $format = "seealso" if ( $format eq "debug" && $server->{debug} == -1 ); 
    $format = "debug" if ( $format eq "seealso" && $server->{debug} == 1 ); 

    if ($format eq 'opensearchdescription') {
        $http = $server->openSearchDescription( $source );
        if ($http) {
            $self->header_add('Status' => 200);
            $self->header_add('Content-Type' => 'application/opensearchdescription+xml; charset: utf-8');
            return $http;
        }
    }

    $server->{errors} = (); # clean error list
    my $response;
    my $status = 200;

    if ( not $identifier ) {
        $server->errors( "invalid identifier" );
        $response = SeeAlso::Response->new;
    } elsif ($format eq "seealso" or $format eq "debug" or !$server->{formats}{$format}) {
        eval {
            local $SIG{'__WARN__'} = sub {
                $server->errors(shift);
            };
            $response = $source->query( $identifier );
        };
        if ($@) {
            $server->errors( $@ );
            undef $response;
        } else {
            if (defined $response && !UNIVERSAL::isa($response, 'SeeAlso::Response')) {
                $server->errors( ref($source) . "->query must return a SeeAlso::Response object but it did return '" . ref($response) . "'");
                undef $response;
            }
        }

        $response = SeeAlso::Response->new() unless defined $response;

        if ($callback && !($callback =~ /^[a-zA-Z0-9\._\[\]]+$/)) {
            $server->errors( "Invalid callback name specified" );
            undef $callback;
            $status = 400;
        }
    } else {
        $response = SeeAlso::Response->new( $identifier );
    }


    if ( $format eq "seealso" ) {
        $self->header_add('Status' => $status);
        $self->header_add('Content-Type' => 'text/javascript; charset: utf-8');
        $self->header_add('Expires' => $server->{expires}) if ($server->{expires});
        $http = $response->toJSON($callback);
    }
    elsif ( $format eq "debug") {
        $self->header_add('Status' => $status);
        $self->header_add('Content-Type' => 'text/javascript; charset: utf-8');

        use Class::ISA;
        my %vars = ( Server => $server, Source => $source, Identifier => $identifier, Response => $response );
        foreach my $var (keys %vars) {
            $http .= "$var is a " .
                join(", ", map { $_ . " " . $_->VERSION; }
                Class::ISA::self_and_super_path(ref($vars{$var})))
            . "\n"
        }
        $http .= "\n";
        $http .= "HTTP response status code is $status\n";
        $http .= "\nInternally the following errors occured:\n- "
              . join("\n- ", @{ $server->errors() }) . "\n" if $server->errors();
        $http .= "*/\n";
        $http .= $response->toJSON($callback) . "\n";
    }
    else { # other unAPI formats
        # TODO is this properly logged?
        # TODO: put 'seealso' as format method in the array
        my $f = $server->{formats}{$format};
        if ($f) {
            my $type = $f->{type} . "; charset: utf-8";
            $self->header_add('Status' => $status);
            $self->header_add('Content-Type' => $type);
            
            $http = $f->{method}($identifier); # TODO: what if this fails?!
        }
        else {
            
            if ($response->query() ne "") {
                $status = $response->size ? 300 : 404;
            }

            $self->header_add('Status' => $status);
            $self->header_add('Content-Type' => 'application/xml; charset: utf-8');
            
            $http = '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
            
            if ($server->{xslt}) {
                $http .= "<?xml-stylesheet type=\"text/xsl\" href=\"" . $self->_xmlencode($server->{xslt}) . "\"?>\n";
                $http .= "<?seealso-query-base " . $self->_xmlencode($server->baseURL) . "?>\n";
            }
            if ($server->{clientbase}) {
                $http .= "<?seealso-client-base " . $self->_xmlencode($server->{clientbase}) . "?>\n";
            }
            
            my %formats = %{$server->{formats}};
            
            if ( $server->{description} ) {
                $formats{"opensearchdescription"} = {
                    type=>"application/opensearchdescription+xml",
                    docs=>"http://www.opensearch.org/Specifications/OpenSearch/1.1/Draft_3#OpenSearch_description_document"
                };
            }

            $http = '<?xml version="1.0" encoding="UTF-8"?>' unless defined $http;
            my @xml;
            
            if ($id ne "") {
                push @xml, '<formats id="' . $self->_xmlencode($id) . '">';
            } else {
                push @xml, '<formats>';
            }
            
            foreach my $name (sort({$b cmp $a} keys(%formats))) {
                my $format = $formats{$name};
                my $fstr = "<format name=\"" . $self->_xmlencode($name) . "\" type=\"" . $self->_xmlencode($format->{type}) . "\"";
                $fstr .= " docs=\"" . $self->_xmlencode($format->{docs}) . "\"" if defined $format->{docs};
                push @xml, $fstr . " />";
            }
            
            push @xml, '</formats>';    
            
            $http = $http . join("\n", @xml) . "\n";
        }
    }
    return $http;
}

sub _xmlencode {
    my $self = shift;
    my $data = shift;
    if ($data =~ /[\&\<\>"]/) {
      $data =~ s/\&/\&amp\;/g;
      $data =~ s/\</\&lt\;/g;
      $data =~ s/\>/\&gt\;/g;
      $data =~ s/"/\&quot\;/g;
    }
    return $data;
}

1;
