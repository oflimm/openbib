#####################################################################
#
#  OpenBib::DatabaseChoice
#
#  Dieses File ist (C) 2001-2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::DatabaseChoice;

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
use OpenBib::L10N;

sub handler {
    my $r=shift;
  
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Uebergabe
    my $sessionID = ($query->param('sessionID'))?$query->param('sessionID'):'';
    my @databases = ($query->param('database'))?$query->param('database'):();
    my $singleidn = $query->param('singleidn') || '';
    my $action    = ($query->param('action'))?$query->param('action'):'';
    my $do_choose = $query->param('do_choose') || '';
    my $verf      = $query->param('verf')      || '';
    my $hst       = $query->param('hst')       || '';
    my $swt       = $query->param('swt')       || '';
    my $kor       = $query->param('kor')       || '';
    my $sign      = $query->param('sign')      || '';
    my $isbn      = $query->param('isbn')      || '';
    my $issn      = $query->param('issn')      || '';
    my $notation  = $query->param('notation')  || '';
    my $ejahr     = $query->param('ejahr')     || '';
    my $queryid   = $query->param('queryid')   || '';
  
    my %checkeddb;
  
    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen
  
    my $sessiondbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $userdbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
      
        $sessiondbh->disconnect();
        $userdbh->disconnect();
      
        return OK;
    }

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }
    
    my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);

    my $idnresult="";
  
    # Wenn Kataloge ausgewaehlt wurden
    if ($do_choose) {
        # Zuerst die bestehende Auswahl loeschen
      
        $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
      
        # Wenn es eine neue Auswahl gibt, dann wird diese eingetragen
        foreach my $database (@databases) {
            $idnresult=$sessiondbh->prepare("insert into dbchoice (sessionid,dbname) values (?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$database) or $logger->error($DBI::errstr);
        }

        # Neue Datenbankauswahl ist voreingestellt
        $idnresult=$sessiondbh->prepare("delete from sessionprofile where sessionid = ? ") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

        $idnresult=$sessiondbh->prepare("insert into sessionprofile values (?,'dbauswahl') ") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    
        $idnresult->finish();
      
        $r->internal_redirect("http://$config->{servername}$config->{searchframe_loc}?sessionID=$sessionID&view=$view");
    }
    # ... sonst anzeigen
    else {
        $idnresult=$sessiondbh->prepare("select dbname from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
        while (my $result=$idnresult->fetchrow_hashref()) {
            my $dbname = decode_utf8($result->{'dbname'});
            $checkeddb{$dbname}="checked=\"checked\"";
        }
        $idnresult->finish();

        my $lastcategory="";
        my $count=0;

        my $maxcolumn=$config->{databasechoice_maxcolumn};
      
        $idnresult=$sessiondbh->prepare("select * from dbinfo where active=1 order by orgunit ASC, description ASC") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);

        my @catdb=();

        while (my $result=$idnresult->fetchrow_hashref) {
            my $category   = decode_utf8($result->{'orgunit'});
            my $name       = decode_utf8($result->{'description'});
            my $systemtype = decode_utf8($result->{'system'});
            my $pool       = decode_utf8($result->{'dbname'});
            my $url        = decode_utf8($result->{'url'});
            my $sigel      = decode_utf8($result->{'sigel'});
	
            my $rcolumn;

            if ($category ne $lastcategory) {
                while ($count % $maxcolumn != 0) {
                    $rcolumn=($count % $maxcolumn)+1;

                    # 'Leereintrag erzeugen'
                    push @catdb, { 
                        column     => $rcolumn, 
                        category   => $lastcategory,
                        db         => '',
                        name       => '',
                        systemtype => '',
                        sigel      => '',
                        url        => '',
                    };
                    $count++;
                }
                $count=0;
            }

            $lastcategory=$category;

            $rcolumn=($count % $maxcolumn)+1;

            my $checked="";
            if (defined $checkeddb{$pool}) {
                $checked="checked=\"checked\"";
            }

            push @catdb, { 
                column     => $rcolumn,
                category   => $category,
                db         => $pool,
                name       => $name,
                systemtype => $systemtype,
                sigel      => $sigel,
                url        => $url,
                checked    => $checked,
            };


            $count++;
        }
      
        # TT-Data erzeugen
        my $colspan=$maxcolumn*3;

        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $sessionID,
            maxcolumn  => $maxcolumn,
            colspan    => $colspan,
            catdb      => \@catdb,
            config     => $config,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_databasechoice_tname},$ttdata,$r);
        $idnresult->finish();
        $sessiondbh->disconnect();
        return OK;
    }
  
    $sessiondbh->disconnect();
    $userdbh->disconnect();
  
    return OK;
}

1;
