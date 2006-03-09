#####################################################################
#
#  OpenBib::RSSFrame
#
#  Dieses File ist (C) 2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::RSSFrame;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;

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

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Uebergabe
    my $sessionID = ($query->param('sessionID'))?$query->param('sessionID'):'';

    # Verbindung zur SQL-Datenbank herstellen
    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
  

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }

    my $rssfeedinfo_ref = {
    };

    if ($view){
        my $request=$sessiondbh->prepare("select dbinfo.dbname,dbinfo.description,dbinfo.faculty,rssfeeds.type from dbinfo,rssfeeds,viewrssfeeds where dbinfo.active=1 and rssfeeds.active=1 and dbinfo.dbname=rssfeeds.dbname and rssfeeds.type = 1 and viewrssfeeds.viewname = ? and viewrssfeeds.rssfeed=rssfeeds.id order by faculty ASC, description ASC");
        $request->execute($view);
        
        
        while (my $result=$request->fetchrow_hashref){
            my $orgunit    = $result->{'faculty'};
            my $name       = $result->{'description'};
            my $pool       = $result->{'dbname'};
            my $rsstype    = $result->{'type'};
            
            push @{$rssfeedinfo_ref->{$orgunit}},{
                pool     => $pool,
                pooldesc => $name,
                type     => 'neuzugang',
            };
        }
    }
    else {
        my $request=$sessiondbh->prepare("select dbinfo.dbname,dbinfo.description,dbinfo.faculty,rssfeeds.type from dbinfo,rssfeeds where dbinfo.active=1 and rssfeeds.active=1 and dbinfo.dbname=rssfeeds.dbname and rssfeeds.type = 1 order by faculty ASC, description ASC");
        $request->execute();
        
        while (my $result=$request->fetchrow_hashref){
            my $orgunit    = $result->{'faculty'};
            my $name       = $result->{'description'};
            my $pool       = $result->{'dbname'};
            my $rsstype    = $result->{'type'};
            
            push @{$rssfeedinfo_ref->{$orgunit}},{
                pool     => $pool,
                pooldesc => $name,
                type     => 'neuzugang',
            };
        }
    }
    
    $sessiondbh->disconnect();

    # TT-Data erzeugen
    my $ttdata={
        view        => $view,
        rssfeedinfo => $rssfeedinfo_ref,
        stylesheet  => $stylesheet,
        config      => \%config,
    };

    OpenBib::Common::Util::print_page($config{tt_rssframe_tname},$ttdata,$r);

    return OK;
}

1;
