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
  my $dbid=$query->param('dbid') || '';
  my $faculty=$query->param('faculty') || '';
  my $description=$query->param('description') || '';
  my $system=$query->param('system') || '';
  my $dbname=$query->param('dbname') || '';
  my $sigel=$query->param('sigel') || '';
  my $url=$query->param('url') || '';
  my $active=$query->param('active') || '';
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

  # Neue SessionID erzeugen, falls keine vorhanden

  $sessionID=OpenBib::Common::Util::init_new_session($sessiondbh) if ($sessionID eq "");

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
      $idnresult->finish();
      
      # Und nun auch die Datenbank komplett loeschen
      
      system("sudo $config{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
      $r->internal_redirect("http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat");
      return OK;

    }
    elsif ($cataction eq "Ändern"){
      my $idnresult=$sessiondbh->prepare("update dbinfo set faculty='$faculty', description='$description', system='$system', dbname='$dbname', sigel='$sigel', url='$url', active='$active' where dbid='$dbid'");
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
      $idnresult->finish();
      
      # Und nun auch die Datenbank zuerst komplett loeschen (falls vorhanden)
      
      system("sudo $config{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
      
      # ... und dann wieder anlegen
      
      system("sudo $config{tool_dir}/createpool.pl $dbname > /dev/null 2>&1");

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
      
      my $katalog={
		   dbid => $dbid,
		   faculty => $faculty,
		   description => $description,
		   system => $system,
		   dbname => $dbname,
		   sigel => $sigel,
		   active => $active,
		   url => $url,
		   
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
    
    OpenBib::Common::Util::print_page($config{tt_admin_showcat_tname},$ttdata,$r);

    $idnresult->finish();

  }
  elsif ($action eq "showviews"){
    OpenBib::Common::Util::print_simple_header("Biblio-Administration: Views anzeigen",$r);
    
    print << "MASKE3";
<table>
<tr><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat">Kataloge</a></td><td>&nbsp;&nbsp;&nbsp;</td><td align="left"><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showviews"><b>Views</b></a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showsession">Sessions</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=logout"><b>Logout</b></a></td></tr>
</table>
<hr>
<table>
<tr><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showviews"><b>Anzeigen</b></a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=editviews">Bearbeiten</a></td><td>&nbsp;&nbsp;&nbsp;</td></tr>
</table>
<hr>
<table>
<tr><td><b>Viewname</b></td><td><b>Beschreibung</b></td><td><b>Aktiv</b></td><td><b>Datenbanken</b></td></tr>
MASKE3
    
    my $linecolor="aliceblue";
    
    my $idnresult=$sessiondbh->prepare("select * from viewinfo order by viewname");
    $idnresult->execute();
    while (my $result=$idnresult->fetchrow_hashref()){
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

      print << "POOL2";
<tr bgcolor="$linecolor"><td>$viewname</td><td>$description</td><td>$active</td><td>$viewdb</td></tr>
POOL2

      if ($linecolor eq "white"){
	$linecolor="aliceblue";
      }
      else {
	$linecolor="white";
      }
      
      
    }
    
    $idnresult->finish();
    
    print "</table>\n";
    OpenBib::Common::Util::print_footer();
    
  }
  ##############
#   elsif ($action eq "editviewsxxx"){
    
#     # Zuerst schauen, ob Aktionen gefordert sind
    
#     if ($viewaction eq "Löschen"){
#       my $idnresult=$sessiondbh->prepare("delete from viewinfo where viewname='$viewname'");
#       $idnresult->execute();
#       $idnresult=$sessiondbh->prepare("delete from viewdbs where viewname='$viewname'");
#       $idnresult->execute();
#       $idnresult->finish();
      
#     }
#     elsif ($viewaction eq "Ändern"){
#       my $idnresult=$sessiondbh->prepare("update viewinfo set faculty='$faculty', description='$description', system='$system', dbname='$dbname', sigel='$sigel', active='$active' where dbid='$dbid'");
#       $idnresult->execute();
#       $idnresult->finish();
      
#     }
#     elsif ($viewaction eq "Neu"){
#       my $idnresult=$sessiondbh->prepare("insert into dbinfo values (NULL,'$faculty','$description','$system','$dbname','$sigel','$active')");
#       $idnresult->execute();
#       $idnresult=$sessiondbh->prepare("insert into titcount values ('$dbname','0')");
#       $idnresult->execute();
#       $idnresult->finish();
      
#       # Und nun auch die Datenbank zuerst komplett loeschen (falls vorhanden)
      
#       system("sudo $config{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
      
#       # ... und dann wieder anlegen
      
#       system("sudo $config{tool_dir}/createpool.pl $dbname > /dev/null 2>&1");
      
#     }
    
#     OpenBib::Common::Util::print_header("Biblio-Administration: Kataloge bearbeiten",$r);
    
#     print << "MASKE3";
# <table>
# <tr><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat"><b>Kataloge</b></a></td><td>&nbsp;&nbsp;&nbsp;</td><td align="left"><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showviews">Views</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showsession">Sessions</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=logout"><b>Logout</b></a></td></tr>
# </table>
# <hr>
# <table>
# <tr><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat">Anzeigen</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=editcat"><b>Bearbeiten</b></a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=imxcat">Import</a></td></tr>
# </table>
# <hr>
# <table>
# <tr><td><b>Fakult&auml;t</b></td><td><b>Beschreibung</b></td><td><b>System</b></td><td>
# <b>DB-Name</b></td><td><b>Sigel</b></td><td><b>Aktiv</b></td><td><b>Aktion</b></td></tr>
# <form method="get" action="http://$config{servername}$config{admin_loc}"><input type="hidden" name="action" value="editcat"><input type="hidden" name="sessionID" value="$sessionID"><tr bgcolor="$linecolor"><td><select name="faculty"><option value="0ungeb" selected>Fakult&auml;tsungebunden</option><option value="1wiso">Wirtschafts- u. Sozialwissenschaftliche</option><option value="2recht">Rechtswissenschaftliche</option><option value="3ezwheil">Erziehungswissenschaftliche u. Heilp&auml;dagogische</option><option value="4phil">Philosophische</option><option value="5matnat">Mathematisch-Naturwissenschaftliche</option></select></td><td><input type="text" name="description"></td><td><select name="system"><option value="l">Lars</option><option value="a">Allegro</option><option value="b">Bislok</option><option value="s" selected>Sisis</option></select></td><td>
# <input type="text" name="dbname" size="8"></td><td><input type="text" name="sigel" size="3"></td><td><input type="text" name="url" size="20"></td><td><select name=active><option value="1">Ja</option><option value="0" selected>Nein</option></select></td><td><input type="submit" name="cataction" value="Neu"></td></tr></form>
# <tr><td>&nbsp;</td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
# MASKE3



#     my %fak=(
# 	     "1wiso", "Wirtschafts- u. Sozialwissenschaftliche Fakult&auml;t",
# 	     "2recht","Rechtswissenschaftliche Fakult&auml;t",
# 	     "3ezwheil","Erziehungswissenschaftliche u. Heilp&auml;dagogische Fakult&auml;t",
# 	     "4phil","Philosophische Fakult&auml;t",
# 	     "5matnat","Mathematisch-Naturwissenschaftliche Fakult&auml;t",
# 	     "0ungeb","Fakult&auml;tsungebunden"
# 	    );
    
#     my $idnresult=$sessiondbh->prepare("select dbinfo.*,titcount.count from dbinfo,titcount where dbinfo.dbname=titcount.dbname order by faculty,dbname");
#     $idnresult->execute();
#     while (my $result=$idnresult->fetchrow_hashref()){
#       my $dbid=$result->{'dbid'};
#       my $faculty=$result->{'faculty'};
#       my $description=$result->{'description'};
#       my $system=$result->{'system'};
#       my $dbname=$result->{'dbname'};
#       my $sigel=$result->{'sigel'};
#       my $url=$result->{'url'};
#       my $active=$result->{'active'};
#       my $count=$result->{'count'};
      
      
#       my $activechecked0="";
#       my $activechecked1="";
      
#       if ($active eq "1"){
# 	$activechecked1="selected";
#       }
#       elsif ($active eq "0"){
# 	$activechecked0="selected";
#       }
      
      
#       my $systemcheckedsisis="";
#       my $systemcheckedallegro="";
#       my $systemcheckedlars="";
#       my $systemcheckedbislok="";
      
#       if ($system eq "s"){
# 	$systemcheckedsisis="selected";
#       }
#       elsif ($system eq "a"){
# 	$systemcheckedallegro="selected";
#       }
#       elsif ($system eq "l"){
# 	$systemcheckedlars="selected";
#       }
#       elsif ($system eq "b"){
# 	$systemcheckedbislok="selected";
#       }


#       my $facultychecked0ungeb="";
#       my $facultychecked1wiso="";
#       my $facultychecked2recht="";
#       my $facultychecked3ezwheil="";
#       my $facultychecked4phil="";
#       my $facultychecked5matnat="";

#       if ($faculty eq "0ungeb"){
# 	$facultychecked0ungeb="selected";
#       }
#       elsif ($faculty eq "1wiso"){
# 	$facultychecked1wiso="selected";
#       }
#       elsif ($faculty eq "2recht"){
# 	$facultychecked2recht="selected";
#       }
#       elsif ($faculty eq "3ezwheil"){
# 	$facultychecked3ezwheil="selected";
#       }
#       elsif ($faculty eq "4phil"){
# 	$facultychecked4phil="selected";
#       }
#       elsif ($faculty eq "5matnat"){
# 	$facultychecked5matnat="selected";
#       }

#       print << "POOL";
# <form method="get" action="http://$config{servername}$config{admin_loc}"><input type="hidden" name="sessionID" value="$sessionID"><input type="hidden" name="dbid" value="$dbid"><input type="hidden" name="action" value="editcat"><tr bgcolor="$linecolor"><td><select name="faculty"><option value="0ungeb" $facultychecked0ungeb>Fakult&auml;tsungebunden</option><option value="1wiso" $facultychecked1wiso>Wirtschafts- u. Sozialwissenschaftliche</option><option value="2recht" $facultychecked2recht>Rechtswissenschaftliche</option><option value="3ezwheil" $facultychecked3ezwheil>Erziehungswissenschaftliche u. Heilp&auml;dagogische</option><option value="4phil" $facultychecked4phil>Philosophische</option><option value="5matnat" $facultychecked5matnat>Mathematisch-Naturwissenschaftliche</option></select></td><td><input type="text" name="description" value="$description"></td><td><select name="system"><option value="l" $systemcheckedlars>Lars</option><option value="a" $systemcheckedallegro>Allegro</option><option value="b" $systemcheckedbislok>Bislok</option><option value="s" $systemcheckedsisis>Sisis</option></select></td><td>
# <input type="text" name="dbname" value="$dbname" size="8"></td><td><input type="text" name="sigel" value="$sigel" size="3"></td><td><input type="text" name="url" value="$url" size="20"></td><td><select name=active><option value="1" $activechecked1>Ja</option><option value="0" $activechecked0>Nein</option></select></td><td><input type="submit" name="cataction" value="&Auml;ndern">&nbsp;<input type="submit" name="cataction" value="L&ouml;schen"></td></tr></form>
# POOL
      
#     }
    
#     $idnresult->finish();
    
#     print "</table>\n";
#     OpenBib::Common::Util::print_footer();
    
#   }
  elsif ($action eq "imxcat"){
    
    # Zuerst schauen, ob Aktionen gefordert sind
    
    if ($cataction eq "Alle importieren"){
      OpenBib::Common::Util::print_warning('',$r);
      print_warning("Diese Funktion ist noch nicht implementiert",$query,$stylesheet);
      $sessiondbh->disconnect;
      return OK;
    }
    elsif ($cataction eq "Import"){
      if ($system eq "s"){
	if ($dbname eq "inst001"){
	  system("nohup sudo $config{autoconv_dir}/bin/autoconvert-sikis-usb.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}
	elsif ($dbname eq "lehrbuchsmlg"){
	  system("nohup sudo $config{autoconv_dir}/bin/autoconvert-sisis.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}
	else {
	  system("nohup sudo $config{autoconv_dir}/bin/autoconvert-sikis.pl -get-via-wget --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}	
      }
      elsif ($system eq "l"){
	if ($dbname eq "inst900"){
	  system("nohup sudo $config{autoconv_dir}/bin/autoconvert-colonia.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	  
	}
	else {
	  system("nohup sudo $config{autoconv_dir}/bin/autoconvert-lars.pl --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}
      }
      elsif ($system eq "a"){
	if ($dbname eq "inst127"){
	  system("nohup sudo $config{autoconv_dir}/bin/autoconvert-ald.pl -get-via-ftp --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}
	else {
	  system("nohup sudo $config{autoconv_dir}/bin/autoconvert-mld.pl -get-via-ftp --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
	}
      }
      elsif ($system eq "b"){
	system("nohup sudo $config{autoconv_dir}/bin/biblio-autoconvert.pl -get-via-ftp --single-pool=$dbname > /tmp/wwwimx$dbname.log 2>&1 &");
      }
      
      
    }
    
    OpenBib::Common::Util::print_simple_header("Biblio-Administration: Kataloge importieren",$r);

    my $linecolor="aliceblue";
    
    print << "MASKE3";
<table>
<tr><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat"><b>Kataloge</b></a></td><td>&nbsp;&nbsp;&nbsp;</td><td align="left"><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showviews">Views</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showsession">Sessions</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=logout"><b>Logout</b></a></td></tr>
</table>
<hr>
<table>
<tr><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat">Anzeigen</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=editcat">Bearbeiten</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=imxcat"><b>Import</b></a></td></tr>
</table>
<hr>
<table>
<tr><td><b>Beschreibung</b></td><td><b>System</b></td><td><b>DB-Name</b></td><td><b>Titel-Anzahl</b></td><td colspan="2"><b>Aktion</b></td></tr>
<form method="get" action="http://$config{servername}$config{admin_loc}"><input type="hidden" name="sessionID" value="$sessionID"><input type="hidden" name="action" value="imxcat"><tr bgcolor="$linecolor"><td>Alle Datenpools</td><td></td><td></td><td></td><td colspan="2"><input type="submit" name="cataction" value="Alle importieren"></td></tr></form>
<tr><td>&nbsp;</td><td></td><td></td><td></td><td></td><td></td></tr>
MASKE3


    my %fak=(
	     "1wiso", "Wirtschafts- u. Sozialwissenschaftliche Fakult&auml;t",
	     "2recht","Rechtswissenschaftliche Fakult&auml;t",
	     "3ezwheil","Erziehungswissenschaftliche u. Heilp&auml;dagogische Fakult&auml;t",
	     "4phil","Philosophische Fakult&auml;t",
	     "5matnat","Mathematisch-Naturwissenschaftliche Fakult&auml;t",
	     "0ungeb","Fakult&auml;tsungebunden"
	    );
    
    $linecolor="aliceblue";
    
    my $idnresult=$sessiondbh->prepare("select dbinfo.*,titcount.count from dbinfo,titcount where dbinfo.dbname=titcount.dbname order by faculty,dbname");
    $idnresult->execute();
    while (my $result=$idnresult->fetchrow_hashref()){
      my $dbid=$result->{'dbid'};
      my $faculty=$result->{'faculty'};
      my $description=$result->{'description'};
      my $system=$result->{'system'};
      my $descsystem="";
      $descsystem="Sisis" if ($system eq "s");
      $descsystem="Lars" if ($system eq "l");
      $descsystem="Allegro" if ($system eq "a");
      $descsystem="Bislok" if ($system eq "b");
      
      my $dbname=$result->{'dbname'};
      my $sigel=$result->{'sigel'};
      my $url=$result->{'url'};
      my $active=$result->{'active'};
      my $count=$result->{'count'};
      
      
      print << "POOL";
<tr bgcolor="$linecolor"><td>$description</td><td>$descsystem</td><td>$dbname</td><td>$count</td><td><form method="get" action="http://$config{servername}$config{admin_loc}"><input type="hidden" name="sessionID" value="$sessionID"><input type="hidden" name="system" value="$system"><input type="hidden" name="dbname" value="$dbname"><input type="hidden" name="action" value="imxcat"><input type="submit" name="cataction" value="Import"></form></td><td><form method="get" action="http://$config{servername}$config{admin_loc}"><input type="hidden" name="sessionID" value="$sessionID"><input type="hidden" name="system" value="$system"><input type="hidden" name="dbname" value="$dbname"><input type="hidden" name="action" value="config"><input type="submit" name="confaction" value="Import-Optionen"></form></td></tr>
POOL
      
      if ($linecolor eq "white"){
	$linecolor="aliceblue";
      }
      else {
	$linecolor="white";
      }
      
    }
    
    $idnresult->finish();
    
    print "</table>\n";
    OpenBib::Common::Util::print_footer();
    
  }
  elsif ($action eq "showsession"){
    OpenBib::Common::Util::print_simple_header("Biblio-Administration: Sessions anzeigen",$r);
    
    print << "MASKE4";
<table>
<tr><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat">Kataloge</a></td><td>&nbsp;&nbsp;&nbsp;</td><td align="left"><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showviews">Views</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showsession"><b>Sessions</b></a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=logout"><b>Logout</b></a></td></tr>
</table>
<hr>
<table>
<tr><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showsession">Anzeigen</a></td><td>&nbsp;&nbsp;&nbsp;</td></tr>
</table>
<hr>
<table>
<tr><td><b>Session-ID</b></td><td><b>Beginn</b></td><td align="middle"><b>Benutzer</b></td><td align="middle">
<b>Initiale Suchen</b></td></tr>
MASKE4


    my $idnresult=$sessiondbh->prepare("select * from session");
    $idnresult->execute();
    while (my $result=$idnresult->fetchrow_hashref()){
      my $sessionid=$result->{'sessionid'};
      my $createtime=$result->{'createtime'};
      my $benutzernr=$result->{'benutzernr'};

      my $idnresult2=$sessiondbh->prepare("select * from queries where sessionid='$sessionid'");
      $idnresult2->execute();
      my $numqueries=$idnresult2->rows;

      if ($benutzernr eq ""){
	$benutzernr="Anonym";
      }
      
      print << "SESSION";
<tr><td>$sessionid</td><td>$createtime</td><td align="middle">$benutzernr</td><td align="middle">$numqueries</td></tr>
SESSION
      
    }
    
    
    print "</table>";
    
    OpenBib::Common::Util::print_footer();
    $sessiondbh->disconnect;
    return OK;
  }
  elsif ($action eq "config"){
    
    if ($confaction eq "Importparameter ändern"){
      
      my $idnresult=$sessiondbh->prepare("delete from dboptions where dbname='$dbname'") or die "Error -- $DBI::errstr";
      $idnresult->execute();
      $idnresult=$sessiondbh->prepare("insert into dboptions values ('$dbname','$host','$protocol','$remotepath','$remoteuser','$remotepasswd','$filename','$titfilename','$autfilename','$korfilename','$swtfilename','$notfilename','$mexfilename','$autoconvert')") or die "Error -- $DBI::errstr";
      $idnresult->execute();
      
      $idnresult->finish();
            
    }
    
    
    
    
    OpenBib::Common::Util::print_simple_header("Biblio-Administration: Import-Konfiguration",$r);
    
    print << "MASKE";
<table>
<tr><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat">Kataloge</a></td><td>&nbsp;&nbsp;&nbsp;</td><td align="left"><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showviews">Views</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showsession"><b>Sessions</b></a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=logout"><b>Logout</b></a></td></tr>
</table>
<hr>
<table>
<tr><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=showcat">Anzeigen</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=editcat">Bearbeiten</a></td><td>&nbsp;&nbsp;&nbsp;</td><td><a href="http://$config{servername}$config{admin_loc}?sessionID=$sessionID&action=imxcat"><b>Import</b></a></td></tr>
</table>
<hr>
MASKE

    
    my $idnresult=$sessiondbh->prepare("select * from dboptions where dbname='$dbname'");
    $idnresult->execute();
    my $result=$idnresult->fetchrow_hashref();
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
    
    
    my $autoconvertchecked0="";
    my $autoconvertchecked1="";
    
    if ($autoconvert eq "0"){
      $autoconvertchecked0="selected";
    }
    elsif ($autoconvert eq "1"){
      $autoconvertchecked1="selected";
    }
    
    $idnresult=$sessiondbh->prepare("select system from dbinfo where dbname='$dbname'");
    $idnresult->execute();
    $result=$idnresult->fetchrow_hashref();
    my $system=$result->{'system'};
    my $descsystem="";
    $descsystem="Sisis" if ($system eq "s");
    $descsystem="Lars" if ($system eq "l");
    $descsystem="Allegro" if ($system eq "a");
    $descsystem="Bislok" if ($system eq "b");
    
    
    my $protocolcheckedhttp="";
    my $protocolcheckedftp="";
    my $protocolcheckedlokal="";
    
    if ($protocol eq "http"){
      $protocolcheckedhttp="selected";
    }
    if ($protocol eq "ftp"){
      $protocolcheckedftp="selected";
    }
    if ($protocol eq "lokal"){
      $protocolcheckedlokal="selected";
    }
    
    my $lokalcolor="";
    
    if ($protocol eq "lokal"){
      $lokalcolor="slategrey";
    }
    
    
    print << "MASKE2";
<form method="GET" action="http://$config{servername}$config{admin_loc}">
<input type="hidden" name="sessionID" value="$sessionID">
<input type="hidden" name="action" value="config">
<input type="hidden" name="system" value="$system">
<input type="hidden" name="dbname" value="$dbname">

<table>
<tr><td><b>DB-Name</b></td><td>$dbname</td></tr>
<tr><td><b>System</b></td><td>$descsystem</td></tr>
<tr><td><b>Protokoll</b></td><td><select name="protocol"><option value="ftp" $protocolcheckedftp>FTP</option><option value="http" $protocolcheckedhttp>Web</option><option value="lokal" $protocolcheckedlokal>Lokal</option></td></tr>
<tr bgcolor="$lokalcolor"><td><b>Entfernter Rechnername</b></td><td><input type="text" size="20" name="host" value="$host"></td></tr>
<tr bgcolor="$lokalcolor"><td><b>Entferntes Verz.</b></td><td><input type="text" size="20" name="remotepath" value="$remotepath"></td></tr>
<tr bgcolor="$lokalcolor"><td><b>Entfernter Nutzername</b></td><td><input type="text" size="20" name="remoteuser" value="$remoteuser"></td></tr>
<tr bgcolor="$lokalcolor"><td><b>Entferntes Passwort</b></td><td><input type="password" size="20" name="remotepasswd" value="$remotepasswd"></td></tr>
<tr bgcolor="$lokalcolor"><td><b></b></td><td></td></tr>
MASKE2

    
    if ($system eq "s"){
      print << "MASKE1";
<tr bgcolor="$lokalcolor"><td><b>Tit-Datei</b></td><td><input type="text" size="20" name="titfilename" value="$titfilename"></td></tr>
<tr bgcolor="$lokalcolor"><td><b>Aut-Datei</b></td><td><input type="text" size="20" name="autfilename" value="$autfilename"></td></tr>
<tr bgcolor="$lokalcolor"><td><b>Kor-Datei</b></td><td><input type="text" size="20" name="korfilename" value="$korfilename"></td></tr>
<tr bgcolor="$lokalcolor"><td><b>Swt-Datei</b></td><td><input type="text" size="20" name="swtfilename" value="$swtfilename"></td></tr>
<tr bgcolor="$lokalcolor"><td><b>Not-Datei</b></td><td><input type="text" size="20" name="notfilename" value="$notfilename"></td></tr>
<tr bgcolor="$lokalcolor"><td><b>Mex-Datei</b></td><td><input type="text" size="20" name="mexfilename" value="$mexfilename"></td></tr>

MASKE1
    }
    
    print << "MASKE2";
<tr><td><b>DB-Datei</b></td><td><input type="text" size="50" name="filename" value="$filename"></td></tr>
MASKE2


    print << "FOOT";
<tr><td><b>Autokonvertierung (cron)</b></td><td><select name="autoconvert"><option value="0" $autoconvertchecked0>Nein</option><option value="1" $autoconvertchecked1>Ja</option></td></tr>
<tr><td colspan="2"><input type="submit" name="confaction" value="Importparameter &auml;ndern"></td></tr>
</table>
FOOT

    OpenBib::Common::Util::print_footer();
    goto LEAVEPROG;
  }
  elsif ($action eq "logout"){
    OpenBib::Common::Util::print_simple_header("Biblio-Administration: Logout",$r);
    
    my $idnresult=$sessiondbh->prepare("delete from session where sessionid='$sessionID'");
    $idnresult->execute();
    $idnresult->finish();
    
    print "<h1>Sie sind nun ausgeloggt</h1>";
    print "Nochmaliges Einloggen k&ouml;nnen Sie <a href=\"http://$config{servername}$config{admin_loc}?action=login\">hier</a>\n";
    
    OpenBib::Common::Util::print_footer();
  }
  else {
    OpenBib::Common::Util::print_warning('',$r);
    print_warning("Keine g&uuml;ltige Aktion oder Session",$query,$stylesheet);
  }
  
 LEAVEPROG: sleep 0;
  
  $sessiondbh->disconnect;
  
  return OK;
}


1;
