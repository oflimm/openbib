####################################################################
#
#  OpenBib::Handler::Apache::Connector::UnAPI.pm
#
#  Dieses File ist (C) 2007-2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::UnAPI;

use strict;
use warnings;
no warnings 'redefine';

use Apache::Constants qw(OK HTTP_NOT_ACCEPTABLE HTTP_NOT_FOUND SERVER_ERROR);
use Apache::Reload;
use Apache::Request ();
use Apache::URI ();
use Benchmark;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::Session;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    my $query  = Apache::Request->instance($r);
    
    my $status=$query->parse;
    
    if ($status){
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $unapiid        = $query->param('id')              || '';
    my $format         = $query->param('format')          || '';

    my $lang = "de"; # TODO: Ausweitung auf andere Sprachen

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    if ($format){

        unless (exists $config->{unAPI_formats}->{$format}){
            return HTTP_NOT_ACCEPTABLE;
        }

        if ($unapiid){
            my ($database,$idn,$record);

            if ($unapiid =~/^(\w+):(\d+)$/){
                $database = $1;
                $idn      = $2;
                
                $logger->debug("Database: $database - ID: $idn");

                $record     = new OpenBib::Record::Title({database=>$database, id=>$idn})->load_full_record
                
            }

            if (!$record->record_exists){
                return HTTP_NOT_FOUND;
            }
            
            my $ttdata={
                record          => $record,

                config          => $config,
                msg             => $msg,
            };
            
            my $templatename = ($format)?"tt_connector_unapi_".$format."_tname":"tt_unapi_formats_tname";
            
            $logger->debug("Using Template $templatename");
            
            my $template = Template->new({ 
                LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                    INCLUDE_PATH   => $config->{tt_include_path},
                    ABSOLUTE       => 1,
                }) ],
                OUTPUT         => $r,    # Output geht direkt an Apache Request
                RECURSION      => 1,
            });
            
            my %format_info = (
                bibtex => 'text/plain',
            );
            
            # Dann Ausgabe des neuen Headers
            if ($format_info{$format}){
                print $r->send_http_header($format_info{$format});
            }
            else {
                print $r->send_http_header('application/xml');
            }
            
            $template->process($config->{$templatename}, $ttdata) || do {
                $r->log_reason($template->error(), $r->filename);
                return SERVER_ERROR;
            };
            
        }
        else {
        }
    }
    else {
        my $ttdata={
            unapiid         => $unapiid,
            config          => $config,
            msg             => $msg,
        };

        my $templatename = $config->{tt_connector_unapi_formats_tname};

        $logger->debug("Using Template $templatename");
        
        my $template = Template->new({ 
            LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                INCLUDE_PATH   => $config->{tt_include_path},
                ABSOLUTE       => 1,
            }) ],
            OUTPUT         => $r,    # Output geht direkt an Apache Request
            RECURSION      => 1,
        });
        
        # Dann Ausgabe des neuen Headers
        print $r->send_http_header("application/xml");
  
        $template->process($templatename, $ttdata) || do {
            $r->log_reason($template->error(), $r->filename);
            return SERVER_ERROR;
        };

        return OK;
    }

    

}

1;
