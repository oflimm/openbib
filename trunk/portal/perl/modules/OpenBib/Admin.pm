#####################################################################
#
#  OpenBib::Admin
#
#  Dieses File ist (C) 2004 Oliver Flimm <flimm@openbib.org>
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

use Apache::Constants qw(:common);

use strict;
use warnings;

use Apache::Request();      # CGI-Handling (or require)

use POSIX;

use Digest::MD5;
use DBI;

use Template;

use OpenBib::Common::Util;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {

  my $r=shift;

  my $query=Apache::Request->new($r);

  my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

  #####################################################################
  # Verbindung zur SQL-Datenbank herstellen
  
  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";
  
  # Standardwerte festlegen
  
  # Erstmal Hack, spaeter ueber User-Tabelle in sessiondb
  
  my $adminuser=$config{adminuser};
  my $adminpasswd=$config{adminpasswd};
  
  my $user=$query->param('user') || '';
  my $passwd=$query->param('passwd') || '';
  my $action=$query->param('action') || '';
  
  my $cataction=$query->param('cataction') || '';
  my $confaction=$query->param('confaction') || '';
  my $sessionaction=$query->param('sessionaction') || '';
  my $dbid=$query->param('dbid') || '';
  my $faculty=$query->param('faculty') || '';
  my $description=$query->param('description') || '';
  my $system=$query->param('system') || '';
  my $dbname=$query->param('dbname') || '';
  my $sigel=$query->param('sigel') || '';
  my $url=$query->param('url') || '';
  my $active=$query->param('active') || '';

  my $viewaction=$query->param('viewaction') || '';
  my $viewname=$query->param('viewname') || '';
  my @viewdb=$query->param('viewdb');
  my $viewid=$query->param('viewid') || '';

  my $imxaction=$query->param('imxaction') || '';

  my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';
  
  my $host=$query->param('host') || '';
  my $protocol=$query->param('protocol') || '';
  my $remotepath=$query->param('remotepath') || '';
  my $remoteuser=$query->param('remoteuser') || '';
  my $remotepasswd=$query->param('remotepasswd') || '';
  my $filename=$query->param('filename') || '';
  my $titfilename=$query->param('titfilename') || '';
  my $autfilename=$query->param('autfilename') || '';
  my $korfilename=$query->param('korfilename') || '';
  my $swtfilename=$query->param('swtfilename') || '';
  my $notfilename=$query->param('notfilename') || '';
  my $mexfilename=$query->param('mexfilename') || '';
  my $autoconvert=$query->param('autoconvert') || '';
  my $circ=$query->param('circ') || '';
  my $circurl=$query->param('circurl') || '';
  my $circcheckurl=$query->param('circcheckurl') || '';

  my $singlesessionid=$query->param('singlesessionid') || '';

  # Neue SessionID erzeugen, falls keine vorhanden

  $sessionID=OpenBib::Common::Util::init_new_session($sessiondbh) if ($sessionID eq "");


  # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
  
  my $dbinforesult=$sessiondbh->prepare("select dbname,description from dbinfo where active=1 order by description") or die "Error -- $DBI::errstr";
  $dbinforesult->execute();
  
  my @dbnames=();
  
  my $singledbname="";
  while (my $result=$dbinforesult->fetchrow_hashref()){
    my $dbname=$result->{'dbname'};
    my $description=$result->{'description'};
    
    $singledbname={
		   dbname => $dbname,
		   description => $description,
		  };
    
    push @dbnames, $singledbname;
  }
  
  $dbinforesult->finish();

  if ($action eq "login" || $action eq ""){
    
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
  elsif ($action eq "Einloggen"){
    
    # Sessionid erzeugen
    
    if ($user ne $adminuser){
      OpenBib::Common::Util::print_warning('Sie haben als Benutzer entweder keinen oder nicht den Admin-Benutzer eingegeben',$r);
      $sessiondbh->disconnect;
      return OK;
    }
    
    if ($passwd ne $adminpasswd){
      OpenBib::Common::Util::print_warning('Sie haben ein falsches Passwort eingegeben',$r);
      $sessiondbh->disconnect;
      return OK;
    }

    # Session ist nun authentifiziert und wird mit dem Admin 
    # assoziiert.

    my $idnresult=$sessiondbh->prepare("update session set benutzernr='$adminuser' where sessionID='$sessionID'") or die "Error -- $DBI::errstr";
    $idnresult->execute();


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
  
  my $idnresult=$sessiondbh->prepare("select * from session where benutzernr='$adminuser' and sessionid='$sessionID'") or die "Error -- $DBI::errstr";
  $idnresult->execute();
  my $rows=$idnresult->rows;
  $idnresult->finish;
  
  if ($rows <= 0){
    OpenBib::Common::Util::print_warning('Sie greifen auf eine nicht autorisierte Session zu',$r);
    $sessiondbh->disconnect;
    return OK;
  }
  
  ###########################################################################
  if ($action eq "editcat"){
    
    # Zuerst schauen, ob Aktionen gefordert sind
    
    if ($cataction eq "Löschen"){
      my $idnresult=$sessiondbh->prepare("delete from dbinfo where dbname='$dbname'");
      $idnresult->execute();
      $idnresult=$sessiondbh->prepare("delete from titcount where dbname='$dbname'");
      $idnresult->execute();
      $idnresult=$sessiondbh->prepare("delete from dboptions where dbname='$dbname'");
      $idnresult->execute();
      $idnresult->finish();
      
      # Und nun auch die Datenbank komplett loeschen
      
      system("$config{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
      $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat");
      return OK;

    }
    elsif ($cataction eq "Ändern"){
      my $idnresult=$sessiondbh->prepare("update dbinfo set faculty='$faculty', description='$description', system='$system', dbname='$dbname', sigel='$sigel', url='$url', active='$active' where dbid='$dbid'");
      $idnresult->execute();
      $idnresult->finish();

      $idnresult=$sessiondbh->prepare("update dboptions set protocol='$protocol', host='$host', remotepath='$remotepath', remoteuser='$remoteuser', remotepasswd='$remotepasswd', titfilename='$titfilename', autfilename='$autfilename', korfilename='$korfilename', swtfilename='$swtfilename', notfilename='$notfilename', mexfilename='$mexfilename', filename='$filename', autoconvert='$autoconvert', circ='$circ', circurl='$circurl', circcheckurl='$circcheckurl' where dbname='$dbname'");
      $idnresult->execute();
      $idnresult->finish();

      $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat");
      return OK;
      
    }
    elsif ($cataction eq "Neu"){
      my $idnresult=$sessiondbh->prepare("insert into dbinfo values (NULL,'$faculty','$description','$system','$dbname','$sigel','$url','$active')");
      $idnresult->execute();
      $idnresult=$sessiondbh->prepare("insert into titcount values ('$dbname','0')");
      $idnresult->execute();
      $idnresult=$sessiondbh->prepare("insert into dboptions values ('$dbname','','','','','','','','','','','','',0,0,'','')");
      $idnresult->execute();
      $idnresult->finish();
      
      # Und nun auch die Datenbank zuerst komplett loeschen (falls vorhanden)
      
      system("$config{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
      
      # ... und dann wieder anlegen
      
      system("$config{tool_dir}/createpool.pl $dbname > /dev/null 2>&1");

      $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat");
      return OK;
    }
    elsif ($cataction eq "Bearbeiten"){


      my $idnresult=$sessiondbh->prepare("select * from dbinfo where dbid=$dbid");
      $idnresult->execute();
      
      my $result=$idnresult->fetchrow_hashref();
      
      my $dbid=$result->{'dbid'};
      my $faculty=$result->{'faculty'};
      my $description=$result->{'description'};
      my $system=$result->{'system'};
      my $dbname=$result->{'dbname'};
      my $sigel=$result->{'sigel'};
      my $url=$result->{'url'};
      my $active=$result->{'active'};

      $idnresult=$sessiondbh->prepare("select * from dboptions where dbname='$dbname'");
      $idnresult->execute();
      $result=$idnresult->fetchrow_hashref();
      my $host=$result->{'host'};
      my $protocol=$result->{'protocol'};
      my $remotepath=$result->{'remotepath'};
      my $remoteuser=$result->{'remoteuser'};
      my $remotepasswd=$result->{'remotepasswd'};
      my $filename=$result->{'filename'};
      my $titfilename=$result->{'titfilename'};
      my $autfilename=$result->{'autfilename'};
      my $korfilename=$result->{'korfilename'};
      my $swtfilename=$result->{'swtfilename'};
      my $notfilename=$result->{'notfilename'};
      my $mexfilename=$result->{'mexfilename'};
      my $autoconvert=$result->{'autoconvert'};
      my $circ=$result->{'circ'};
      my $circurl=$result->{'circurl'};
      my $circcheckurl=$result->{'circcheckurl'};

      
      my $katalog={
		   dbid => $dbid,
		   faculty => $faculty,
		   description => $description,
		   system => $system,
		   dbname => $dbname,
		   sigel => $sigel,
		   active => $active,
		   url => $url,

		   imxconfig => {
				 host => $host,
				 protocol => $protocol,
				 remotepath => $remotepath,
				 remoteuser => $remoteuser,
				 remotepasswd => $remotepasswd,
				 filename => $filename,
				 titfilename => $titfilename,
				 autfilename => $autfilename,
				 korfilename => $korfilename,
				 swtfilename => $swtfilename,
				 notfilename => $notfilename,
				 mexfilename => $mexfilename,
				 autoconvert => $autoconvert,
				},

		   circconfig => {
				 circ         => $circ,
				 circurl      => $circurl,
				 circcheckurl => $circcheckurl,
				},
		   
		  };
      
      
      my $ttdata={
		  stylesheet => $stylesheet,
		  sessionID => $sessionID,
		  
		  katalog => $katalog,
		  
		  config     => \%config,
		 };
      
      OpenBib::Common::Util::print_page($config{tt_admin_editcat_tname},$ttdata,$r);
      
    }
    



  }
  elsif ($action eq "showcat"){

    my @kataloge=();

    my $idnresult=$sessiondbh->prepare("select dbinfo.*,titcount.count,dboptions.autoconvert from dbinfo,titcount,dboptions where dbinfo.dbname=titcount.dbname and titcount.dbname=dboptions.dbname order by faculty,dbname");
    $idnresult->execute();

    my $katalog;
    while (my $result=$idnresult->fetchrow_hashref()){
      my $dbid=$result->{'dbid'};
      my $faculty=$result->{'faculty'};
      my $autoconvert=$result->{'autoconvert'};

      my $unitsref=$config{units};

      my @units=@$unitsref;

      my $unitref="";

      foreach $unitref (@units){
	my %unit=%$unitref;
	if ($unit{short} eq $faculty){
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
      my $count=$result->{'count'};

      if (!$description){
	$description="Keine Bezeichnung";
      }

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
		autoconvert => $autoconvert,
	       };

      push @kataloge, $katalog;
    }

    my $ttdata={
		stylesheet => $stylesheet,
		sessionID => $sessionID,
		kataloge => \@kataloge,

		config     => \%config,
	       };
    
    OpenBib::Common::Util::print_page($config{tt_admin_showcat_tname},$ttdata,$r);

    $idnresult->finish();

  }
  elsif ($action eq "showviews"){

    my @views=();

    my $view="";

    my $idnresult=$sessiondbh->prepare("select * from viewinfo order by viewname");
    $idnresult->execute();
    while (my $result=$idnresult->fetchrow_hashref()){
      my $viewid=$result->{'viewid'};
      my $viewname=$result->{'viewname'};
      my $description=$result->{'description'};
      my $active=$result->{'active'};
      $active="Ja" if ($active eq "1");
      $active="Nein" if ($active eq "0");
      
      my $idnresult2=$sessiondbh->prepare("select * from viewdbs where viewname='$viewname' order by dbname");
      $idnresult2->execute();
      
      my @viewdbs=();
      while (my $result2=$idnresult2->fetchrow_hashref()){
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

  elsif ($action eq "editview"){
    
    # Zuerst schauen, ob Aktionen gefordert sind
    
    if ($viewaction eq "Löschen"){
      my $idnresult=$sessiondbh->prepare("delete from viewinfo where viewid='$viewid'");
      $idnresult->execute();
      $idnresult=$sessiondbh->prepare("delete from viewdbs where viewname='$viewname'");
      $idnresult->execute();
      $idnresult->finish();
      $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showviews");
      return OK;
      
    }
    elsif ($viewaction eq "Ändern"){

      # Zuerst die Aenderungen in der Tabelle Viewinfo vornehmen

      my $idnresult=$sessiondbh->prepare("update viewinfo set viewname='$viewname', description='$description', active='$active' where viewid='$viewid'");
      $idnresult->execute();

      # Datenbanken zunaechst loeschen

      $idnresult=$sessiondbh->prepare("delete from viewdbs where viewname='$viewname'");
      $idnresult->execute();

      
      # Dann die zugehoerigen Datenbanken eintragen


      my $singleviewdb="";

      foreach $singleviewdb (@viewdb){
	$idnresult=$sessiondbh->prepare("insert into viewdbs values ('$viewname','$singleviewdb')");
	$idnresult->execute();
      }

      $idnresult->finish();

      $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showviews");
      
      return OK;
    }
    elsif ($viewaction eq "Neu"){

      if ($viewname eq "" || $description eq ""){

	OpenBib::Common::Util::print_warning("Sie m&uuml;ssen einen Viewnamen und eine Beschreibung eingeben.",$r);

	$idnresult->finish();
	$sessiondbh->disconnect();
	return OK;
      }


      my $idnresult=$sessiondbh->prepare("select * from viewinfo where viewname='$viewname'");
      $idnresult->execute();

      if ($idnresult->rows > 0){

	OpenBib::Common::Util::print_warning("Es existiert bereits ein View unter diesem Namen",$r);

	$idnresult->finish();
	$sessiondbh->disconnect();
	return OK;
      }
      
      $idnresult=$sessiondbh->prepare("insert into viewinfo values (NULL,'$viewname','$description','$active')");
      $idnresult->execute();



      $idnresult=$sessiondbh->prepare("select viewid from viewinfo where viewname='$viewname'");
      $idnresult->execute();


      my $res=$idnresult->fetchrow_hashref();

      my $viewid=$res->{viewid};
      

      $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=editview&viewaction=Bearbeiten&viewid=$viewid");
     

      $sessiondbh->disconnect();

      return OK;
    }
    elsif ($viewaction eq "Bearbeiten"){


      my $idnresult=$sessiondbh->prepare("select * from viewinfo where viewid='$viewid'");
      $idnresult->execute();
      
      my $result=$idnresult->fetchrow_hashref();

      my $viewid=$result->{'viewid'};
      my $viewname=$result->{'viewname'};
      my $description=$result->{'description'};
      my $active=$result->{'active'};

      my $idnresult2=$sessiondbh->prepare("select * from viewdbs where viewname='$viewname' order by dbname");
      $idnresult2->execute();
      
      my @viewdbs=();
      while (my $result2=$idnresult2->fetchrow_hashref()){
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
  elsif ($action eq "showimx"){

    my @kataloge=();

    my $idnresult=$sessiondbh->prepare("select dbinfo.*,titcount.count from dbinfo,titcount where dbinfo.dbname=titcount.dbname order by faculty,dbname");
    $idnresult->execute();

    my $katalog;
    while (my $result=$idnresult->fetchrow_hashref()){
      my $dbid=$result->{'dbid'};
      my $faculty=$result->{'faculty'};

      my $unitsref=$config{units};

      my @units=@$unitsref;

      my $unitref="";

      foreach $unitref (@units){
	my %unit=%$unitref;
	if ($unit{short} eq $faculty){
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
  elsif ($action eq "bla"){
    # Zuerst schauen, ob Aktionen gefordert sind
    
    if ($imxaction eq "Alle importieren"){
      OpenBib::Common::Util::print_warning('',$r);
      print_warning("Diese Funktion ist noch nicht implementiert",$query,$stylesheet);
      $sessiondbh->disconnect;
      return OK;
    }
    elsif ($imxaction eq "Import"){
      if ($system eq "s"){
	if ($dbname eq "inst001"){
	  system("nohup $config{autoconv_dir}/bin/autoconvert-sikis-usb.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}
	elsif ($dbname eq "lehrbuchsmlg"){
	  system("nohup $config{autoconv_dir}/bin/autoconvert-sisis.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}
	else {
	  system("nohup $config{autoconv_dir}/bin/autoconvert-sikis.pl -get-via-wget --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}	
      }
      elsif ($system eq "l"){
	if ($dbname eq "inst900"){
	  system("nohup $config{autoconv_dir}/bin/autoconvert-colonia.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	  
	}
	else {
	  system("nohup $config{autoconv_dir}/bin/autoconvert-lars.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}
      }
      elsif ($system eq "a"){
	if ($dbname eq "inst127"){
	  system("nohup $config{autoconv_dir}/bin/autoconvert-ald.pl -get-via-ftp --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}
	else {
	  system("nohup $config{autoconv_dir}/bin/autoconvert-mld.pl -get-via-ftp --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}
      }
      elsif ($system eq "b"){
	system("nohup $config{autoconv_dir}/bin/biblio-autoconvert.pl -get-via-ftp --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
      }
      
      
    }
  }
  elsif ($action eq "showsession"){

    my $idnresult=$sessiondbh->prepare("select * from session order by createtime");
    $idnresult->execute();
    my $session="";
    my @sessions=();

    while (my $result=$idnresult->fetchrow_hashref()){
      my $singlesessionid=$result->{'sessionid'};
      my $createtime=$result->{'createtime'};
      my $benutzernr=$result->{'benutzernr'};

      my $idnresult2=$sessiondbh->prepare("select * from queries where sessionid='$singlesessionid'");
      $idnresult2->execute();
      my $numqueries=$idnresult2->rows;

      if (!$benutzernr){
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
  elsif ($action eq "editsession"){

    if ($sessionaction eq "Anzeigen"){
      my $idnresult=$sessiondbh->prepare("select * from session where sessionID='$singlesessionid'");
      $idnresult->execute();

      my $result=$idnresult->fetchrow_hashref();
      my $createtime=$result->{'createtime'};
      my $benutzernr=$result->{'benutzernr'};

      my $idnresult2=$sessiondbh->prepare("select * from queries where sessionid='$singlesessionid'");
      $idnresult2->execute();

      my $numqueries=$idnresult2->rows;

      my @queries=();
      my $singlequery="";
      while (my $result2=$idnresult2->fetchrow_hashref()){
         my $query=$result2->{'query'};
         my $hits=$result2->{'hits'};
         my $dbases=$result2->{'dbases'};


	 my ($fs,$verf,$hst,$swt,$kor,$sign,$isbn,$issn,$notation,$mart,$ejahr,$hststring,$bool1,$bool2,$bool3,$bool4,$bool5,$bool6,$bool7,$bool8,$bool9,$bool10,$bool11,$bool12)=split('\|\|',$query);

         # Aufbereitung der Suchanfrage fuer die Ausgabe

         $query="";
         $query.="(FS: $fs) " if ($fs);
         $query.="$bool1 (AUT: $verf) " if ($verf);
         $query.="$bool2 (HST: $hst) " if ($hst);
         $query.="$bool3 (SWT: $swt) " if ($swt);
         $query.="$bool4 (KOR: $kor) " if ($kor);
         $query.="$bool5 (NOT: $notation) " if ($notation);
         $query.="$bool6 (SIG: $sign) " if ($sign);
         $query.="$bool7 (EJAHR: $ejahr) " if ($ejahr);
         $query.="$bool8 (ISBN: $isbn) " if ($isbn);
         $query.="$bool9 (ISSN: $issn) " if ($issn);
         $query.="$bool10 (MART: $mart) " if ($mart);
         $query.="$bool11 (HSTR: $hststring) " if ($hststring);

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


      if (!$benutzernr){
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
  elsif ($action eq "logout"){

    my $ttdata={
		  stylesheet => $stylesheet,
		  sessionID => $sessionID,
		  
		  config     => \%config,
		 };
      
    OpenBib::Common::Util::print_page($config{tt_admin_logout_tname},$ttdata,$r);

    my $idnresult=$sessiondbh->prepare("delete from session where benutzernr='$adminuser' and sessionid='$sessionID'") or die "Error -- $DBI::errstr";
    $idnresult->execute();


  }
  else {
    OpenBib::Common::Util::print_warning('Keine g&uuml;ltige Aktion oder Session',$r);
  }
  
 LEAVEPROG: sleep 0;
  
  $sessiondbh->disconnect;
  
  return OK;
}


1;
