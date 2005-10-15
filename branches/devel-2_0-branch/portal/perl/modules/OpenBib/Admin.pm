#####################################################################
#
#  OpenBib::Admin
#
#  Dieses File ist (C) 2004-2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Admin;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Request ();
use DBI;
use Digest::MD5;
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

    # Verbindung zur SQL-Datenbank herstellen
    my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);
  
    # Standardwerte festlegen
  
    my $adminuser   = $config{adminuser};
    my $adminpasswd = $config{adminpasswd};
  
    my $user            = $query->param('user')            || '';
    my $passwd          = $query->param('passwd')          || '';
    my $action          = $query->param('action')          || '';
    my $cataction       = $query->param('cataction')       || '';
    my $confaction      = $query->param('confaction')      || '';
    my $sessionaction   = $query->param('sessionaction')   || '';
    my $dbid            = $query->param('dbid')            || '';
    my $faculty         = $query->param('faculty')         || '';
    my $description     = $query->param('description')     || '';
    my $system          = $query->param('system')          || '';
    my $dbname          = $query->param('dbname')          || '';
    my $sigel           = $query->param('sigel')           || '';
    my $url             = $query->param('url')             || '';
    my $active          = $query->param('active')          || '';

    my $viewaction      = $query->param('viewaction')      || '';
    my $viewname        = $query->param('viewname')        || '';
    my @viewdb          = ($query->param('viewdb'))?$query->param('viewdb'):();
    my $viewid          = $query->param('viewid')          || '';

    my $imxaction       = $query->param('imxaction')       || '';

    my $sessionID       = ($query->param('sessionID'))?$query->param('sessionID'):'';
  
    my $host            = $query->param('host')            || '';
    my $protocol        = $query->param('protocol')        || '';
    my $remotepath      = $query->param('remotepath')      || '';
    my $remoteuser      = $query->param('remoteuser')      || '';
    my $remotepasswd    = $query->param('remotepasswd')    || '';
    my $filename        = $query->param('filename')        || '';
    my $titfilename     = $query->param('titfilename')     || '';
    my $autfilename     = $query->param('autfilename')     || '';
    my $korfilename     = $query->param('korfilename')     || '';
    my $swtfilename     = $query->param('swtfilename')     || '';
    my $notfilename     = $query->param('notfilename')     || '';
    my $mexfilename     = $query->param('mexfilename')     || '';
    my $autoconvert     = $query->param('autoconvert')     || '';
    my $circ            = $query->param('circ')            || '';
    my $circurl         = $query->param('circurl')         || '';
    my $circcheckurl    = $query->param('circcheckurl')    || '';
    my $circdb          = $query->param('circdb')          || '';

    my $singlesessionid = $query->param('singlesessionid') || '';

    # Neue SessionID erzeugen, falls keine vorhanden

    unless ($sessionID){
        $sessionID=OpenBib::Common::Util::init_new_session($sessiondbh);
    }

    # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
  
    my $dbinforesult=$sessiondbh->prepare("select dbname,description from dbinfo where active=1 order by description") or $logger->error($DBI::errstr);
    $dbinforesult->execute() or $logger->error($DBI::errstr);
  
    my @dbnames=();
  
    my $singledbname="";
    while (my $result=$dbinforesult->fetchrow_hashref()) {
        my $dbname      = $result->{'dbname'};
        my $description = $result->{'description'};
    
        $singledbname={
            dbname      => $dbname,
            description => $description,
        };
    
        push @dbnames, $singledbname;
    }
  
    $dbinforesult->finish();

    if ($action eq "login" || $action eq "") {
    
        # TT-Data erzeugen
    
        my $ttdata={
            stylesheet => $stylesheet,
            config     => \%config,
        };
    
        OpenBib::Common::Util::print_page($config{tt_admin_login_tname},$ttdata,$r);
    
        $sessiondbh->disconnect;
        return OK;
    }
  
    ###########################################################################
    elsif ($action eq "Einloggen") {
    
        # Sessionid erzeugen
        if ($user ne $adminuser) {
            OpenBib::Common::Util::print_warning('Sie haben als Benutzer entweder keinen oder nicht den Admin-Benutzer eingegeben',$r);
            $sessiondbh->disconnect;
            return OK;
        }
    
        if ($passwd ne $adminpasswd) {
            OpenBib::Common::Util::print_warning('Sie haben ein falsches Passwort eingegeben',$r);
            $sessiondbh->disconnect;
            return OK;
        }

        # Session ist nun authentifiziert und wird mit dem Admin 
        # assoziiert.
        my $idnresult=$sessiondbh->prepare("update session set benutzernr = ? where sessionID = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($adminuser,$sessionID) or $logger->error($DBI::errstr);

        # TT-Data erzeugen
        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $sessionID,
            config     => \%config,
        };
    
        OpenBib::Common::Util::print_page($config{tt_admin_loggedin_tname},$ttdata,$r);
        
        $sessiondbh->disconnect;
        return OK;
    }
  
    # Ab hier gehts nur weiter mit korrekter SessionID
  
    # Admin-SessionID ueberpruefen
    my $idnresult=$sessiondbh->prepare("select * from session where benutzernr = ? and sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($adminuser,$sessionID) or $logger->error($DBI::errstr);
    my $rows=$idnresult->rows;
    $idnresult->finish;
  
    if ($rows <= 0) {
        OpenBib::Common::Util::print_warning('Sie greifen auf eine nicht autorisierte Session zu',$r);
        $sessiondbh->disconnect;
        return OK;
    }
  
    ###########################################################################
    if ($action eq "editcat") {
    
        # Zuerst schauen, ob Aktionen gefordert sind
        if ($cataction eq "Löschen") {
            my $idnresult=$sessiondbh->prepare("delete from dbinfo where dbname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $idnresult=$sessiondbh->prepare("delete from titcount where dbname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $idnresult=$sessiondbh->prepare("delete from dboptions where dbname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $idnresult->finish();
      
            # Und nun auch die Datenbank komplett loeschen
            system("$config{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
            $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat");
            return OK;

        }
        elsif ($cataction eq "Ändern") {
            my $idnresult=$sessiondbh->prepare("update dbinfo set faculty = ?, description = ?, system = ?, dbname = ?, sigel = ?, url = ?, active = ? where dbid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($faculty,$description,$system,$dbname,$sigel,$url,$active,$dbid) or $logger->error($DBI::errstr);
            $idnresult->finish();

            $idnresult=$sessiondbh->prepare("update dboptions set protocol = ?, host = ?, remotepath = ?, remoteuser = ?, remotepasswd = ?, titfilename = ?, autfilename = ?, korfilename = ?, swtfilename = ?, notfilename = ?, mexfilename = ?, filename = ?, autoconvert = ?, circ = ?, circurl = ?, circcheckurl = ?, circdb = ? where dbname= ?") or $logger->error($DBI::errstr);
            $idnresult->execute($protocol,$host,$remotepath,$remoteuser,$remotepasswd,$titfilename,$autfilename,$korfilename,$swtfilename,$notfilename,$mexfilename,$filename,$autoconvert,$circ,$circurl,$circcheckurl,$circdb,$dbname) or $logger->error($DBI::errstr);
            $idnresult->finish();

            $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat");
            return OK;
        }
        elsif ($cataction eq "Neu") {

            if ($dbname eq "" || $description eq "") {

                OpenBib::Common::Util::print_warning("Sie müssen mindestens einen Katalognamen und eine Beschreibung eingeben.",$r);

                $idnresult->finish();
                $sessiondbh->disconnect();
                return OK;
            }

            my $idnresult=$sessiondbh->prepare("select dbid from dbinfo where dbname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);

            if ($idnresult->rows > 0) {

                OpenBib::Common::Util::print_warning("Es existiert bereits ein Katalog unter diesem Namen",$r);

                $idnresult->finish();
                $sessiondbh->disconnect();
                return OK;
            }

            $idnresult=$sessiondbh->prepare("insert into dbinfo values (NULL,?,?,?,?,?,?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($faculty,$description,$system,$dbname,$sigel,$url,$active) or $logger->error($DBI::errstr);
            $idnresult=$sessiondbh->prepare("insert into titcount values (?,'0')") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $idnresult=$sessiondbh->prepare("insert into dboptions values (?,'','','','','','','','','','','','',0,0,'','','')") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $idnresult->finish();
      
            # Und nun auch die Datenbank zuerst komplett loeschen (falls vorhanden)
            system("$config{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
      
            # ... und dann wieder anlegen
            system("$config{tool_dir}/createpool.pl $dbname > /dev/null 2>&1");

            $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat");
            return OK;
        }
        elsif ($cataction eq "Bearbeiten") {
            my $idnresult=$sessiondbh->prepare("select * from dbinfo where dbid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbid) or $logger->error($DBI::errstr);
      
            my $result=$idnresult->fetchrow_hashref();
      
            my $dbid=$result->{'dbid'};
            my $faculty=$result->{'faculty'};
            my $description=$result->{'description'};
            my $system=$result->{'system'};
            my $dbname=$result->{'dbname'};
            my $sigel=$result->{'sigel'};
            my $url=$result->{'url'};
            my $active=$result->{'active'};

            $idnresult=$sessiondbh->prepare("select * from dboptions where dbname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $result=$idnresult->fetchrow_hashref();
            my $host         = $result->{'host'};
            my $protocol     = $result->{'protocol'};
            my $remotepath   = $result->{'remotepath'};
            my $remoteuser   = $result->{'remoteuser'};
            my $remotepasswd = $result->{'remotepasswd'};
            my $filename     = $result->{'filename'};
            my $titfilename  = $result->{'titfilename'};
            my $autfilename  = $result->{'autfilename'};
            my $korfilename  = $result->{'korfilename'};
            my $swtfilename  = $result->{'swtfilename'};
            my $notfilename  = $result->{'notfilename'};
            my $mexfilename  = $result->{'mexfilename'};
            my $autoconvert  = $result->{'autoconvert'};
            my $circ         = $result->{'circ'};
            my $circurl      = $result->{'circurl'};
            my $circcheckurl = $result->{'circcheckurl'};
            my $circdb       = $result->{'circdb'};

            my $katalog={
                dbid        => $dbid,
                faculty     => $faculty,
                description => $description,
                system      => $system,
                dbname      => $dbname,
                sigel       => $sigel,
                active      => $active,
                url         => $url,

                imxconfig   => {
                    host         => $host,
                    protocol     => $protocol,
                    remotepath   => $remotepath,
                    remoteuser   => $remoteuser,
                    remotepasswd => $remotepasswd,
                    filename     => $filename,
                    titfilename  => $titfilename,
                    autfilename  => $autfilename,
                    korfilename  => $korfilename,
                    swtfilename  => $swtfilename,
                    notfilename  => $notfilename,
                    mexfilename  => $mexfilename,
                    autoconvert  => $autoconvert,
                },

                circconfig  => {
                    circ         => $circ,
                    circurl      => $circurl,
                    circcheckurl => $circcheckurl,
                    circdb       => $circdb,
                },
            };
      
      
            my $ttdata={
                stylesheet => $stylesheet,
                sessionID  => $sessionID,
		  
                katalog    => $katalog,
		  
                config     => \%config,
            };
      
            OpenBib::Common::Util::print_page($config{tt_admin_editcat_tname},$ttdata,$r);
        }
    }
    elsif ($action eq "showcat") {
        my @kataloge=();

        my $idnresult=$sessiondbh->prepare("select dbinfo.*,titcount.count,dboptions.autoconvert from dbinfo,titcount,dboptions where dbinfo.dbname=titcount.dbname and titcount.dbname=dboptions.dbname order by faculty,dbname") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);

        my $katalog;
        while (my $result=$idnresult->fetchrow_hashref()) {
            my $dbid        = $result->{'dbid'};
            my $faculty     = $result->{'faculty'};
            my $autoconvert = $result->{'autoconvert'};

            my $units_ref=$config{units};

            my @units=@$units_ref;

            foreach my $unit_ref (@units) {
                my %unit=%$unit_ref;
                if ($unit{short} eq $faculty) {
                    $faculty=$unit{desc};
                }
            }

            my $description = $result->{'description'};
            my $system      = $result->{'system'};
            $system="Sisis" if ($system eq "s");
            $system="Lars" if ($system eq "l");
            $system="Allegro" if ($system eq "a");
            $system="Bislok" if ($system eq "b");

            my $dbname      = $result->{'dbname'};
            my $sigel       = $result->{'sigel'};
            my $url         = $result->{'url'};
            my $active      = $result->{'active'};
            my $count       = $result->{'count'};

            if (!$description) {
                $description="Keine Bezeichnung";
            }

            $katalog={
		dbid        => $dbid,
		faculty     => $faculty,
		description => $description,
		system      => $system,
		dbname      => $dbname,
		sigel       => $sigel,
		active      => $active,
		url         => $url,
		count       => $count,
		autoconvert => $autoconvert,
            };

            push @kataloge, $katalog;
        }

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $sessionID,
            kataloge   => \@kataloge,

            config     => \%config,
        };
    
        OpenBib::Common::Util::print_page($config{tt_admin_showcat_tname},$ttdata,$r);

        $idnresult->finish();
    }
    elsif ($action eq "showviews") {
        my @views=();

        my $view="";

        my $idnresult=$sessiondbh->prepare("select * from viewinfo order by viewname") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);
        while (my $result=$idnresult->fetchrow_hashref()) {
            my $viewid=$result->{'viewid'};
            my $viewname=$result->{'viewname'};
            my $description=$result->{'description'};
            my $active=$result->{'active'};
            $active="Ja" if ($active eq "1");
            $active="Nein" if ($active eq "0");
      
            my $idnresult2=$sessiondbh->prepare("select * from viewdbs where viewname = ? order by dbname") or $logger->error($DBI::errstr);
            $idnresult2->execute($viewname);
      
            my @viewdbs=();
            while (my $result2=$idnresult2->fetchrow_hashref()) {
                my $dbname=$result2->{'dbname'};
                push @viewdbs, $dbname;
            }

            $idnresult2->finish();

            my $viewdb=join " ; ", @viewdbs;

            $view={
		viewid => $viewid,
		viewname => $viewname,
		description => $description,
		active => $active,
		viewdb => $viewdb,
            };

            push @views, $view;
      
        }

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID => $sessionID,
            views => \@views,
            config     => \%config,
        };
    
        OpenBib::Common::Util::print_page($config{tt_admin_showviews_tname},$ttdata,$r);
    
        $idnresult->finish();
    
    }
    elsif ($action eq "editview") {
    
        # Zuerst schauen, ob Aktionen gefordert sind
    
        if ($viewaction eq "Löschen") {
            my $idnresult=$sessiondbh->prepare("delete from viewinfo where viewid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewid) or $logger->error($DBI::errstr);
            $idnresult=$sessiondbh->prepare("delete from viewdbs where viewname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname) or $logger->error($DBI::errstr);
            $idnresult->finish();
            $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showviews");
            return OK;
      
        }
        elsif ($viewaction eq "Ändern") {

            # Zuerst die Aenderungen in der Tabelle Viewinfo vornehmen

            my $idnresult=$sessiondbh->prepare("update viewinfo set viewname = ?, description = ?, active = ? where viewid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname,$description,$active,$viewid) or $logger->error($DBI::errstr);

            # Datenbanken zunaechst loeschen

            $idnresult=$sessiondbh->prepare("delete from viewdbs where viewname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname) or $logger->error($DBI::errstr);

      
            # Dann die zugehoerigen Datenbanken eintragen
            foreach my $singleviewdb (@viewdb) {
                $idnresult=$sessiondbh->prepare("insert into viewdbs values (?,?)") or $logger->error($DBI::errstr);
                $idnresult->execute($viewname,$singleviewdb) or $logger->error($DBI::errstr);
            }

            $idnresult->finish();

            $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showviews");
      
            return OK;
        }
        elsif ($viewaction eq "Neu") {

            if ($viewname eq "" || $description eq "") {

                OpenBib::Common::Util::print_warning("Sie müssen mindestens einen Viewnamen und eine Beschreibung eingeben.",$r);

                $idnresult->finish();
                $sessiondbh->disconnect();
                return OK;
            }


            my $idnresult=$sessiondbh->prepare("select * from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname) or $logger->error($DBI::errstr);

            if ($idnresult->rows > 0) {

                OpenBib::Common::Util::print_warning("Es existiert bereits ein View unter diesem Namen",$r);

                $idnresult->finish();
                $sessiondbh->disconnect();
                return OK;
            }
      
            $idnresult=$sessiondbh->prepare("insert into viewinfo values (NULL,?,?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname,$description,$active) or $logger->error($DBI::errstr);



            $idnresult=$sessiondbh->prepare("select viewid from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname);


            my $res=$idnresult->fetchrow_hashref();

            my $viewid=$res->{viewid};
      

            $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=editview&viewaction=Bearbeiten&viewid=$viewid");
     

            $sessiondbh->disconnect();

            return OK;
        }
        elsif ($viewaction eq "Bearbeiten") {


            my $idnresult=$sessiondbh->prepare("select * from viewinfo where viewid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewid) or $logger->error($DBI::errstr);
      
            my $result=$idnresult->fetchrow_hashref();

            my $viewid=$result->{'viewid'};
            my $viewname=$result->{'viewname'};
            my $description=$result->{'description'};
            my $active=$result->{'active'};

            my $idnresult2=$sessiondbh->prepare("select * from viewdbs where viewname = ? order by dbname") or $logger->error($DBI::errstr);
            $idnresult2->execute($viewname) or $logger->error($DBI::errstr);
      
            my @viewdbs=();
            while (my $result2=$idnresult2->fetchrow_hashref()) {
                my $dbname=$result2->{'dbname'};
                push @viewdbs, $dbname;
            }

            $idnresult2->finish();

            my $view={
		viewid => $viewid,
		viewname => $viewname,
		description => $description,
		active => $active,
		viewdbs => \@viewdbs,
            };

            my $ttdata={
                stylesheet => $stylesheet,
                sessionID => $sessionID,
		  
                dbnames => \@dbnames,

                view => $view,
		  
                config     => \%config,
            };
      
            OpenBib::Common::Util::print_page($config{tt_admin_editview_tname},$ttdata,$r);
      
        }
    
    }
    elsif ($action eq "showimx") {

        my @kataloge=();

        my $idnresult=$sessiondbh->prepare("select dbinfo.*,titcount.count from dbinfo,titcount where dbinfo.dbname=titcount.dbname order by faculty,dbname") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);

        my $katalog;
        while (my $result=$idnresult->fetchrow_hashref()) {
            my $dbid=$result->{'dbid'};
            my $faculty=$result->{'faculty'};

            my $units_ref=$config{units};

            my @units=@$units_ref;

            foreach my $unit_ref (@units) {
                my %unit=%$unit_ref;
                if ($unit{short} eq $faculty) {
                    $faculty=$unit{desc};
                }
            }

            my $description=$result->{'description'};
            my $system=$result->{'system'};
            $system="Sisis" if ($system eq "s");
            $system="Lars" if ($system eq "l");
            $system="Allegro" if ($system eq "a");
            $system="Bislok" if ($system eq "b");

            my $dbname=$result->{'dbname'};
            my $sigel=$result->{'sigel'};
            my $url=$result->{'url'};
            my $active=$result->{'active'};
            $active="Ja" if ($active eq "1");
            $active="Nein" if ($active eq "0");
            my $count=$result->{'count'};

            $katalog={
		dbid => $dbid,
		faculty => $faculty,
		description => $description,
		system => $system,
		dbname => $dbname,
		sigel => $sigel,
		active => $active,
		url => $url,
		count => $count,
            };

            push @kataloge, $katalog;
        }

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID => $sessionID,
            kataloge => \@kataloge,

            config     => \%config,
        };
    
        OpenBib::Common::Util::print_page($config{tt_admin_showimx_tname},$ttdata,$r);

        $idnresult->finish();
    }
    elsif ($action eq "bla") {
        # Zuerst schauen, ob Aktionen gefordert sind
    
        if ($imxaction eq "Alle importieren") {
            OpenBib::Common::Util::print_warning('',$r);
            print_warning("Diese Funktion ist noch nicht implementiert",$query,$stylesheet);
            $sessiondbh->disconnect;
            return OK;
        }
        elsif ($imxaction eq "Import") {
            if ($system eq "s") {
                if ($dbname eq "inst001") {
                    system("nohup $config{autoconv_dir}/bin/autoconvert-sikis-usb.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
                }
                elsif ($dbname eq "lehrbuchsmlg") {
                    system("nohup $config{autoconv_dir}/bin/autoconvert-sisis.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
                }
                else {
                    system("nohup $config{autoconv_dir}/bin/autoconvert-sikis.pl -get-via-wget --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
                }	
            }
            elsif ($system eq "l") {
                if ($dbname eq "inst900") {
                    system("nohup $config{autoconv_dir}/bin/autoconvert-colonia.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	  
                }
                else {
                    system("nohup $config{autoconv_dir}/bin/autoconvert-lars.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
                }
            }
            elsif ($system eq "a") {
                if ($dbname eq "inst127") {
                    system("nohup $config{autoconv_dir}/bin/autoconvert-ald.pl -get-via-ftp --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
                }
                else {
                    system("nohup $config{autoconv_dir}/bin/autoconvert-mld.pl -get-via-ftp --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
                }
            }
            elsif ($system eq "b") {
                system("nohup $config{autoconv_dir}/bin/biblio-autoconvert.pl -get-via-ftp --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
            }
      
      
        }
    }
    elsif ($action eq "showsession") {

        my $idnresult=$sessiondbh->prepare("select * from session order by createtime") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);
        my $session="";
        my @sessions=();

        while (my $result=$idnresult->fetchrow_hashref()) {
            my $singlesessionid=$result->{'sessionid'};
            my $createtime=$result->{'createtime'};
            my $benutzernr=$result->{'benutzernr'};

            my $idnresult2=$sessiondbh->prepare("select * from queries where sessionid = ?") or $logger->error($DBI::errstr);
            $idnresult2->execute($singlesessionid) or $logger->error($DBI::errstr);
            my $numqueries=$idnresult2->rows;

            if (!$benutzernr) {
                $benutzernr="Anonym";
            }

            $session={
                singlesessionid => $singlesessionid,
                createtime      => $createtime,
                benutzernr      => $benutzernr,
                numqueries      => $numqueries,
            };
            push @sessions, $session;
        }
    

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID => $sessionID,
	         
            sessions => \@sessions,

            config     => \%config,
        };

        OpenBib::Common::Util::print_page($config{tt_admin_showsessions_tname},$ttdata,$r);
    
        $sessiondbh->disconnect;
        return OK;
    }
    elsif ($action eq "editsession") {

        if ($sessionaction eq "Anzeigen") {
            my $idnresult=$sessiondbh->prepare("select * from session where sessionID = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($singlesessionid) or $logger->error($DBI::errstr);

            my $result=$idnresult->fetchrow_hashref();
            my $createtime=$result->{'createtime'};
            my $benutzernr=$result->{'benutzernr'};

            my $idnresult2=$sessiondbh->prepare("select * from queries where sessionid = ?") or $logger->error($DBI::errstr);
            $idnresult2->execute($singlesessionid) or $logger->error($DBI::errstr);

            my $numqueries=$idnresult2->rows;

            my @queries=();
            my $singlequery="";
            while (my $result2=$idnresult2->fetchrow_hashref()) {
                my $query=$result2->{'query'};
                my $hits=$result2->{'hits'};
                my $dbases=$result2->{'dbases'};


                my ($fs,$verf,$hst,$swt,$kor,$sign,$isbn,$issn,$notation,$mart,$ejahr,$hststring,$boolhst,$boolswt,$boolkor,$boolnotation,$boolisbn,$boolsign,$boolejahr,$boolissn,$boolverf,$boolfs,$boolmart,$boolhststring)=split('\|\|',$query);

                # Aufbereitung der Suchanfrage fuer die Ausgabe

                $query="";
                $query.="(FS: $fs) "                         if ($fs);
                $query.="$boolverf (AUT: $verf) "            if ($verf);
                $query.="$boolhst (HST: $hst) "              if ($hst);
                $query.="$boolswt (SWT: $swt) "              if ($swt);
                $query.="$boolkor (KOR: $kor) "              if ($kor);
                $query.="$boolnotation (NOT: $notation) "    if ($notation);
                $query.="$boolsign (SIG: $sign) "            if ($sign);
                $query.="$boolejahr (EJAHR: $ejahr) "        if ($ejahr);
                $query.="$boolisbn (ISBN: $isbn) "           if ($isbn);
                $query.="$boolissn (ISSN: $issn) "           if ($issn);
                $query.="$boolmart (MART: $mart) "           if ($mart);
                $query.="$boolhststring (HSTR: $hststring) " if ($hststring);

                # Bereinigen fuer die Ausgabe

                $query=~s/^.*?\(/(/;
                $dbases=~s/\|\|/ ; /g;

                my $singlequery={
                    query => $query,
                    hits  => $hits,
                    dbases => $dbases,
                };

                push @queries, $singlequery;
            }    


            if (!$benutzernr) {
                $benutzernr="Anonym";
            }

            my $session={
                singlesessionid => $singlesessionid,
                createtime      => $createtime,
                benutzernr      => $benutzernr,
                numqueries      => $numqueries,
            };

            my $ttdata={
                stylesheet => $stylesheet,
                sessionID => $sessionID,
	         
                session => $session,

                queries => \@queries,

                config     => \%config,
            };

            OpenBib::Common::Util::print_page($config{tt_admin_editsession_tname},$ttdata,$r);

            $idnresult->finish;
            $idnresult2->finish;
            $sessiondbh->disconnect;
            return OK;
        }
    }
    elsif ($action eq "logout") {

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID => $sessionID,
		  
            config     => \%config,
        };
      
        OpenBib::Common::Util::print_page($config{tt_admin_logout_tname},$ttdata,$r);

        my $idnresult=$sessiondbh->prepare("delete from session where benutzernr = ? and sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($adminuser,$sessionID) or $logger->error($DBI::errstr);

    }
    else {
        OpenBib::Common::Util::print_warning('Keine gültige Aktion oder Session',$r);
    }
  
  LEAVEPROG: sleep 0;
  
    $sessiondbh->disconnect;
  
    return OK;
}


1;
