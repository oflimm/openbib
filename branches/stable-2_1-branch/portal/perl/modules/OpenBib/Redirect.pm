#####################################################################
#
#  OpenBib::Redirect
#
#  Dieses File ist (C) 2007 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Redirect;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common REDIRECT);
use Apache::Reload;
use Apache::Request ();
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();

    my $uri   = $r->parsed_uri;
    my $path  = $uri->path;
    my $query = $uri->query;

    my $lang = "de"; # TODO: Ausweitung auf andere Sprachen

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    # Basisipfad entfernen
    my $basepath = $config->{redirect_loc};
    $path=~s/$basepath//;

    $logger->debug("Path: $path URI: $uri");

    # Parameter aus URI bestimmen
    #
    # 

    my ($sessionID,$type,$url);
    if ($path=~m/^\/(\w+?)\/(\w+?)\/(.+?)$/){
        ($sessionID,$type,$url)=($1,$2,$3);
    }

    if ($query){
        $url = $url."?".$query;
    }
    
    $logger->debug("SessionID: $sessionID - Type: $type - URL: $url");

    my $session   = new OpenBib::Session({
        sessionID => $sessionID,
    });
    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);

        return OK;
    }

    my $valid_redirection_type_ref = {
        500 => 1, # TOC / hbz-Server
        501 => 1, # TOC / ImageWaere-Server
        502 => 1, # USB E-Book / Vollzugriff
        503 => 1, # Nationallizenzen / Vollzugriff
        510 => 1, # BibSonomy
        520 => 1, # Wikipedia / Personen
        521 => 1, # Wikipedia / ISBN
        530 => 1, # EZB
        531 => 1, # DBIS
        532 => 1, # Kartenkatalog Philfak
        533 => 1, # MedPilot
        534 => 1, # Digitaler Kartenkatalog der Philfak
        540 => 1, # HBZ-Monofernleihe
        541 => 1, # HBZ-Dokumentenlieferung
        550 => 1, # WebOPAC
    };

    if (exists $valid_redirection_type_ref->{$type}){
        $session->log_event({
            type      => $type,
            content   => $url,
        });

        $r->content_type('text/html');
        $r->header_out(Location => $url);
        
        return REDIRECT;
    }
    else {
        OpenBib::Common::Util::print_warning("Typ $type nicht definiert",$r,$msg);
        $logger->error("Typ $type nicht definiert");
        return OK;
    }
}

1;
