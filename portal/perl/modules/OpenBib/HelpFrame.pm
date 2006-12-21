#####################################################################
#
#  OpenBib::HelpFrame
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

package OpenBib::HelpFrame;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Statistics;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {
    my $r=shift;

    my %checkeddb;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $statistics = new OpenBib::Statistics();

    my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
    
    my $query = Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $useragent=$r->subprocess_env('HTTP_USER_AGENT');
  
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    # Sub-Template ID
    my $stid     = $query->param('stid') || '';
    my $database = $query->param('database') || '';

    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning("Ung&uuml;ltige Session",$r);
        
        $sessiondbh->disconnect();
        
        return OK;
    }

    
    my $dbinforesult=$sessiondbh->prepare("select dbname,sigel,url,description from dbinfo") or $logger->error($DBI::errstr);
    $dbinforesult->execute() or $logger->error($DBI::errstr);;
    
    my %sigel=();
    my %bibinfo=();
    my %dbinfo=();
    my %dbases=();
    
    while (my $result=$dbinforesult->fetchrow_hashref()){
        my $dbname=$result->{'dbname'};
        my $sigel=$result->{'sigel'};
        my $url=$result->{'url'};
        my $description=$result->{'description'};
        
        ##################################################################### 
        ## Wandlungstabelle Bibliothekssigel <-> Bibliotheksname
        
        $sigel{"$sigel"}="$description";
        
        #####################################################################
        ## Wandlungstabelle Bibliothekssigel <-> Informations-URL
        
        $bibinfo{"$sigel"}="$url";
        
        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Datenbankinfo
        
        # Wenn ein URL fuer die Datenbankinformation definiert ist, dann wird
        # damit verlinkt
        
        if ($url ne ""){
            $dbinfo{"$dbname"}="<a href=\"$url\" target=\"_blank\">$description</a>";
        }
        else {
            $dbinfo{"$dbname"}="$description";
        }
        
        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Bibliothekssigel
        
        $dbases{"$dbname"}="$sigel";
    }
    
    $sigel{''}="Unbekannt";
    $bibinfo{''}="http://www.ub.uni-koeln.de/dezkat/bibinfo/noinfo.html";
    $dbases{''}="Unbekannt";


    my $idnresult=$sessiondbh->prepare("select dbname from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    while (my $result=$idnresult->fetchrow_hashref()){
	my $dbname=$result->{'dbname'};
	$checkeddb{$dbname}="checked=\"checked\"";
    }
    $idnresult->finish();
    
    my $lastcategory="";
    my $count=0;
    
    my $maxcolumn=$config{databasechoice_maxcolumn};
    
    my %stype;
    
    $idnresult=$sessiondbh->prepare("select * from dbinfo where active=1 order by faculty ASC, description ASC") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error($DBI::errstr);
    
    my @catdb=();
    
    while (my $result=$idnresult->fetchrow_hashref){
        my $category=$result->{'faculty'};
        my $name=$result->{'description'};
        my $systemtype=$result->{'system'};
        my $pool=$result->{'dbname'};
        my $url=$result->{'url'};
        my $sigel=$result->{'sigel'};
        
        my $rcolumn;
        
        if ($systemtype eq "a"){
            $stype{$pool}="yellow";
        }
        elsif ($systemtype eq "b"){
            $stype{$pool}="red";
        }
        elsif ($systemtype eq "l"){
            $stype{$pool}="green";
        }
        elsif ($systemtype eq "s"){
            $stype{$pool}="blue";
        }
        
        if ($category ne $lastcategory){
            while ($count % $maxcolumn != 0){
                
                $rcolumn=($count % $maxcolumn)+1;
                # 'Leereintrag erzeugen'
                push @catdb, { 
                    column => $rcolumn, 
                    category => $lastcategory,
                    db => '',
                    name => '',
                    systemtype => '',
                    sigel => '',
                    url => '',
                };
                
                $count++;
            }
            
            $count=0;
        }
        $lastcategory=$category;
        
        $rcolumn=($count % $maxcolumn)+1;
        
        my $checked="";
        if (defined $checkeddb{$pool}){
            $checked="checked=\"checked\"";
        }
        
        push @catdb, { 
            column => $rcolumn,
            category => $category,
            db => $pool,
            name => $name,
            systemtype => $stype{$pool},
            sigel => $sigel,
            url => $url,
            checked => $checked,
        };
        
        
        $count++;
    }
    
    # Ueberbleibende Elemente erzeugen, die wegen des Endes und eines ausbleibenden
    # Kategorienwechsels vergessen wuerden
    while ($count % $maxcolumn != 0){
        
        my $rcolumn=($count % $maxcolumn)+1;
        # 'Leereintrag erzeugen'
        push @catdb, { 
            column => $rcolumn,
            category => $lastcategory,
            db => '',
            name => '',
            systemtype => '',
            sigel => '',
            url => '',
        };
        
        $count++;
    }

    
    # Generiere SessionID, wenn noch keine vorhanden ist
    
    my $view="";
    
    if ($query->param('view')){
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }

    my $dbdesc         = $dbinfo{$database};
    $sessiondbh->disconnect();

    my $colspan=$maxcolumn*3;

    # TT-Data erzeugen
    my $ttdata={
        database      => $database,
        view          => $view,
        stylesheet    => $stylesheet,
        dbdesc        => $dbdesc,
        sessionID     => $sessionID,
        useragent     => $useragent,
        config        => \%config,
        statistics    => $statistics,
        maxcolumn  => $maxcolumn,
        colspan    => $colspan,
        catdb      => \@catdb,
    };

    $idnresult->finish();
    $sessiondbh->disconnect();

    $stid=~s/[^0-9]//g;

    my $templatename = ($stid)?"tt_helpframe_".$stid."_tname":"tt_helpframe_tname";

    OpenBib::Common::Util::print_page($config{$templatename},$ttdata,$r);

    return OK;
}

1;
