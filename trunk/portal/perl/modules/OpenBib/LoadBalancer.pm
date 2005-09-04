#####################################################################
#
#  OpenBib::LoadBalancer
#
#  Dieses File ist (C) 1997-2004 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::LoadBalancer;

use strict;
use warnings;
no warnings 'redefine';

use Apache::Constants qw(:common REDIRECT);
use Apache::Request ();
use HTTP::Request;
use HTTP::Response;
use IO::Socket;
use LWP::UserAgent;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::LoadBalancer::Util();
use OpenBib::Common::Util();
use OpenBib::Config();

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $ua=new LWP::UserAgent(timeout => 5);
    my $urlquery=$r->args;      #query->url(-query=>1);

    $urlquery=~s/^.+?\?//;

    # Aktuellen Load der Server holen zur dynamischen Lastverteilung
    my @servertab=@{$config{loadbalancertargets}};

    my %serverload=();

    foreach my $target (@servertab) {
        $serverload{"$target"}=-1.0;
    }
  
    my $problem=0;
  
    # Fuer jeden Server, auf den verteilt werden soll, wird nun
    # per LWP der Load bestimmt.
    foreach my $targethost (@servertab) {
        my $request  = new HTTP::Request POST => "http://$targethost$config{serverload_loc}";
        my $response = $ua->request($request);

        if ($response->is_success) {
            $logger->debug("Getting ", $response->content);
        }
        else {
            $logger->error("Getting ", $response->status_line);
        }
    
        my $content=$response->content();
    
        if ($content eq "" || $content=~m/SessionDB: offline/m) {
            $problem=1;
        }
        elsif ($content=~m/^Load: (\d+\.\d+)/m) {
            my $load=$1;
            $serverload{$targethost}=$load;
        }
    
        # Wenn der Load fuer einen Server nicht bestimmt werden kann,
        # dann wird der Admin darueber benachrichtigt
    
        if ($problem == 1) {
            OpenBib::LoadBalancer::Util::benachrichtigung("Es ist der Server $targethost ausgefallen");
            $problem=0;
            next;
        }
    }
  
    my $minload="1000.0";
    my $bestserver="";

    # Nun wird der Server bestimmt, der den geringsten Load hat

    foreach my $targethost (@servertab) {
        if ($serverload{$targethost} > -1.0 && $serverload{$targethost} <= $minload) {
            $bestserver=$targethost;
            $minload=$serverload{$targethost};
        }
    }

    # Wenn wir keinen 'besten Server' bestimmen konnten, dann sind alle
    # ausgefallen, dem Benutzer wird eine 'Hinweisseite' ausgegeben
    if ($bestserver eq "") {

        # TT-Data erzeugen
        my $ttdata={
            title        => 'KUG - Wartungsarbeiten',
            show_corporate_banner => 0,
            show_foot_banner      => 1,
            config       => \%config,
        };

        OpenBib::Common::Util::print_page($config{tt_loadbalancer_tname},$ttdata,$r);
        OpenBib::LoadBalancer::Util::benachrichtigung("Achtung: Es sind *alle* Server ausgefallen");

        return OK;
    }

    $r->header_out(Location => "http://$bestserver$config{startopac_loc}?$urlquery");
    $r->status(REDIRECT);
    $r->send_http_header;
  
    return OK;
}

1;
