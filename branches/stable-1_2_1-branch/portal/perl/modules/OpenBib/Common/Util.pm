#####################################################################
#
#  OpenBib::Common::Util
#
#  Dieses File ist (C) 2004-2007 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Common::Util;

use strict;
use warnings;
no warnings 'redefine';

use Apache::Constants qw(:common);
use Apache::Request ();

use Log::Log4perl qw(get_logger :levels);

use POSIX();

use Digest::MD5();
use DBI;

use OpenBib::Config;

use Template;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

my $benchmark;

if ($OpenBib::Config::config{benchmark}){
  use Benchmark ':hireswallclock';
}

sub init_new_session {
  my ($sessiondbh)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $sessionID="";

  my $havenewsessionID=0;
    
  while($havenewsessionID == 0){
    my $gmtime = localtime(time);
    my $md5digest=Digest::MD5->new();
    
    $md5digest->add($gmtime . rand('1024'). $$);
    
    $sessionID=$md5digest->hexdigest;
    
    # Nachschauen, ob es diese ID schon gibt
    
    my $idnresult=$sessiondbh->prepare("select count(sessionid) from session where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

    my @idn=$idnresult->fetchrow_array();
    my $anzahl=$idn[0];
    
    # Wenn wir nichts gefunden haben, dann ist alles ok.
    if ($anzahl == 0 ){
      $havenewsessionID=1;
      
      my $createtime = POSIX::strftime('%Y-%m-%d% %H:%M:%S', localtime());
      
      # Eintrag in die Datenbank
      
      $idnresult=$sessiondbh->prepare("insert into session (sessionid,createtime) values (?,?)") or $logger->error($DBI::errstr);
      $idnresult->execute($sessionID,$createtime) or $logger->error($DBI::errstr);
    }
    
    $idnresult->finish();
  }
  
  return $sessionID;
}

sub session_is_valid {
  my ($sessiondbh,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  if ($sessionID eq "-1"){
    return 1;
  }

  my $idnresult=$sessiondbh->prepare("select count(sessionid) from session where sessionid = ?") or $logger->error($DBI::errstr);
  $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

  my @idn=$idnresult->fetchrow_array();
  my $anzahl=$idn[0];

  $idnresult->finish();

  if ($anzahl == 1){
    return 1;
  }

  return 0;
}

sub get_cred_for_userid {
  my ($userdbh,$userid)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $userresult=$userdbh->prepare("select loginname,pin from user where userid = ?") or $logger->error($DBI::errstr);

  $userresult->execute($userid) or $logger->error($DBI::errstr);
  
  my @cred=();
  
  if ($userresult->rows > 0){
    my $res=$userresult->fetchrow_hashref();
     $cred[0]=$res->{loginname};
     $cred[1]=$res->{pin};
  }

  $userresult->finish();

  return @cred;

}

sub get_username_for_userid {
  my ($userdbh,$userid)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $userresult=$userdbh->prepare("select loginname from user where userid = ?") or $logger->error($DBI::errstr);

  $userresult->execute($userid) or $logger->error($DBI::errstr);
  
  my $username="";
  
  if ($userresult->rows > 0){
    my $res=$userresult->fetchrow_hashref();
    $username=$res->{loginname};
  }

  $userresult->finish();

  return $username;

}

sub get_userid_of_session {
  my ($userdbh,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $globalsessionID="$config{servername}:$sessionID";
  my $userresult=$userdbh->prepare("select userid from usersession where sessionid = ?") or $logger->error($DBI::errstr);

  $userresult->execute($globalsessionID) or $logger->error($DBI::errstr);
  
  my $userid="";
  
  if ($userresult->rows > 0){
    my $res=$userresult->fetchrow_hashref();
    $userid=$res->{'userid'};
  }

  return $userid;
}

sub get_viewname_of_session  {
  my ($sessiondbh,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  # Assoziierten View zur Session aus Datenbank holen
  
  my $idnresult=$sessiondbh->prepare("select viewname from sessionview where sessionid = ?") or $logger->error($DBI::errstr);
  $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
  
  my $result=$idnresult->fetchrow_hashref();
  
  # Entweder wurde ein 'echter' View gefunden oder es wird
  # kein spezieller View verwendet (view='')

  my $view=$result->{'viewname'} || '';

  $idnresult->finish();

  return $view;
}

sub get_primary_rssfeed_of_view  {
    my ($sessiondbh,$viewname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Assoziierten View zur Session aus Datenbank holen
    my $idnresult=$sessiondbh->prepare("select rssfeeds.dbname as dbname,rssfeeds.type as type, rssfeeds.subtype as subtype from rssfeeds,viewinfo where viewname = ? and rssfeeds.id = viewinfo.rssfeed and rssfeeds.active = 1") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname) or $logger->error($DBI::errstr);
  
    my $result=$idnresult->fetchrow_hashref();
  
    my $dbname  = $result->{'dbname'}  || '';
    my $type    = $result->{'type'}    || 0;
    my $subtype = $result->{'subtype'} || 0;

    foreach my $typename (keys %{$config{rss_types}}){
        if ($config{rss_types}{$typename} eq $type){
            $type=$typename;
            last;
        }
    }
    
    $idnresult->finish();

    my $primrssfeedurl="";

    if ($dbname && $type){
        $primrssfeedurl="http://".$config{loadbalancerservername}.$config{connector_rss_loc}."/$type/$dbname.rdf";
    }
    
    return $primrssfeedurl;
}

sub get_activefeeds_of_db  {
    my ($sessiondbh,$dbname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();


    my $activefeeds_ref = {};
    
    my $idnresult=$sessiondbh->prepare("select type from rssfeeds where dbname = ? and active = 1") or $logger->error($DBI::errstr);
    $idnresult->execute($dbname) or $logger->error($DBI::errstr);
  
    while (my $result=$idnresult->fetchrow_hashref()){
        my $type    = $result->{'type'}    || 0;

        $activefeeds_ref->{$type} = 1;
    }

    
    $idnresult->finish();

    return $activefeeds_ref;
}

sub get_targetdb_of_session {
  my ($userdbh,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $globalsessionID="$config{servername}:$sessionID";
  my $userresult=$userdbh->prepare("select db from usersession,logintarget where usersession.sessionid = ? and usersession.targetid = logintarget.targetid") or $logger->error($DBI::errstr);

  $userresult->execute($globalsessionID) or $logger->error($DBI::errstr);
  
  my $targetdb="";
  
  if ($userresult->rows > 0){
    my $res=$userresult->fetchrow_hashref();
    $targetdb=$res->{'db'};
  }

  return $targetdb;
}

sub get_targettype_of_session {
  my ($userdbh,$sessionID)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $globalsessionID="$config{servername}:$sessionID";
  my $userresult=$userdbh->prepare("select type from usersession,logintarget where usersession.sessionid = ? and usersession.targetid = logintarget.targetid") or $logger->error($DBI::errstr);

  $userresult->execute($globalsessionID) or $logger->error($DBI::errstr);
  
  my $targettype="";
  
  if ($userresult->rows > 0){
    my $res=$userresult->fetchrow_hashref();
    $targettype=$res->{'type'};
  }

  return $targettype;
}

sub get_targetdbinfo {
    my ($sessiondbh)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    #####################################################################
    # Dynamische Definition diverser Variablen
  
    # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
  
    my $dbinforesult=$sessiondbh->prepare("select dbname,sigel,url,description from dbinfo") or $logger->error($DBI::errstr);
    $dbinforesult->execute() or $logger->error($DBI::errstr);;
  
    my %sigel   =();
    my %bibinfo =();
    my %dbinfo  =();
    my %dbases  =();
    my %dbnames =();

    while (my $result=$dbinforesult->fetchrow_hashref()) {
        my $dbname      = $result->{'dbname'};
        my $sigel       = $result->{'sigel'};
        my $url         = $result->{'url'};
        my $description = $result->{'description'};
    
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
    
        if ($url ne "") {
            $dbinfo{"$dbname"}="<a href=\"$url\" target=\"_blank\">$description</a>";
        } else {
            $dbinfo{"$dbname"}="$description";
        }
    
        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Bibliothekssigel
    
        $dbases{"$dbname"}="$sigel";

        $dbnames{"$dbname"}=$description;
    }
  
    $dbinforesult->finish;
    
    return {
        sigel   => \%sigel,
        bibinfo => \%bibinfo,
        dbinfo  => \%dbinfo,
        dbases  => \%dbases,
        dbnames => \%dbnames,
    };
}

sub get_css_by_browsertype {
  my ($r)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $useragent=$r->subprocess_env('HTTP_USER_AGENT');

  my $query=Apache::Request->new($r);
  my $view=($query->param('view'))?$query->param('view'):undef;

  my $stylesheet="";
  
  if ( $useragent=~/Mozilla.5.0/ || $useragent=~/MSIE 5/ || $useragent=~/MSIE 6/ || $useragent=~/Konqueror"/ ){
    if ($useragent=~/MSIE/){
      $stylesheet="openbib-ie.css";
    }
    else {
      $stylesheet="openbib.css";
    }
  }
  else {
    if ($useragent=~/MSIE/){
      $stylesheet="openbib-simple-ie.css";
    }
    else {
      $stylesheet="openbib-simple.css";
    }
  }

  return $stylesheet;
}

#####################################################################
## get_sql_result(rreqarray,...): Suche anhand der in reqarray enthaltenen
##                                SQL-Statements, fasse die Ergebnisse zusammen
##                                und liefere sie zur"uck
##
## Und nun jede Menge Variablen, damit mod_perl keine Probleme macht
##
## $dbh

sub get_sql_result {
  my ($rreqarray,$dbh)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my %metaidns;
  my @midns=();
  my $atime;
  my $btime;
  my $timeall;
  
  my @reqarray=@$rreqarray;
  
  my $i=0;    
  
  my $idnrequest;
  
  foreach $idnrequest (@reqarray){
    
    if ($config{benchmark}){
      $atime=new Benchmark;
    }
    
    my $idnresult=$dbh->prepare("$idnrequest") or $logger->error($DBI::errstr);
    $idnresult->execute() or $logger->error("Request: $idnrequest - ".$DBI::errstr);
    
    my @idnres;
    while (@idnres=$idnresult->fetchrow){	    
      
      if (!$metaidns{$idnres[0]}){
	push @midns, $idnres[0];
      }
      $metaidns{$idnres[0]}=1;
    }
    $idnresult->finish();
    
    if ($config{benchmark}){
      $btime=new Benchmark;
      $timeall=timediff($btime,$atime);
      $logger->info("Zeit fuer Idns zu : $idnrequest : ist ".timestr($timeall));
      undef $atime;
      undef $btime;
      undef $timeall;
    }
  }
  
  return @midns;    
}

sub print_simple_header {
  my ($title,$r)=@_;
  
  my $stylesheet=get_css_by_browsertype($r);

  print $r->send_http_header("text/html");

  print << "HEADER";
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<HTML>
<HEAD>
  <meta http-equiv="pragma" content="no-cache">
  $stylesheet
  <link href="/images/openbib/favicon.ico" rel="shortcut icon">
  <TITLE>$title</title>
</HEAD>
<BODY BGCOLOR="#ffffff">
HEADER
  return;
}

sub print_warning {
  my ($warning,$r)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my $stylesheet=get_css_by_browsertype($r);

  my $query=Apache::Request->new($r);

  my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

  my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);

  my $view=get_viewname_of_session($sessiondbh,$sessionID);
 
  my $template = Template->new({
				ABSOLUTE      => 1,
				INCLUDE_PATH  => $config{tt_include_path},
				#    	    PRE_PROCESS   => 'config',
				OUTPUT        => $r,     # Output geht direkt an Apache Request
			       });
  
  # TT-Data erzeugen
  
  my $ttdata={
	      view       => $view,
	      stylesheet => $stylesheet,
	      
	      show_corporate_banner => 0,
	      show_foot_banner => 0,
	      invisible_links => 0,
	      
	      errmsg     => $warning,
	      config     => \%config,
	     };
  
  # Dann Ausgabe des neuen Headers
  
  print $r->send_http_header("text/html");
  
  $template->process($config{tt_error_tname}, $ttdata) || do { 
    $r->log_reason($template->error(), $r->filename);
    return SERVER_ERROR;
  };
  
  return;
}   

sub print_page {
  my ($templatename,$ttdata,$r)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();
  
  my $stylesheet=get_css_by_browsertype($r);


  #####################################################################
  # View- und Datenbank-spezifisches Templating

  my $database=$ttdata->{'database'};
  my $view=$ttdata->{'view'};

  if ($view && -e "$config{tt_include_path}/views/$view/$templatename"){
    $templatename="views/$view/$templatename";
  }

  # Database-Template ist spezifischer als View-Template und geht vor

  if ($database && -e "$config{tt_include_path}/database/$database/$templatename"){
    $templatename="database/$database/$templatename";
  }

  $logger->info("Using Template $templatename");
  
  my $template = Template->new({ 
				ABSOLUTE      => 1, # Notwendig fuer Kaskadierung
				INCLUDE_PATH  => $config{tt_include_path},
				#    	    PRE_PROCESS   => 'config',
				OUTPUT        => $r,     # Output geht direkt an Apache Request
			       });
  
  # Dann Ausgabe des neuen Headers
  
  print $r->send_http_header("text/html");
  
  $template->process($templatename, $ttdata) || do { 
    $r->log_reason($template->error(), $r->filename);
    return SERVER_ERROR;
  };
  
  return;
}   

sub get_sort_nav {
  my ($r,$nav,$usequerycache)=@_;

  my @argself=$r->args;

  my $sorttype="";
  my $sortorder="";
  my $trefferliste="";
  my $sortall="";
  my $sessionID="";
  my $queryid="";

  my $fullargstring="";

  my %fullargs=();

  for (my $i = 0; $i < $#argself; $i += 2) {
    my $key=$argself[$i];

    my $value="";

    if (defined($argself[$i+1])){
      $value=$argself[$i+1];
    }

    if ($key ne "sortorder" && $key ne "sorttype" && $key ne "trefferliste" && $key ne "sortall" && $key ne "sessionID" && $key ne "queryid"){
      $fullargs{$key}=$value;
    }
    elsif ($key eq "sortorder"){
      $sortorder=$value;
    }
    elsif ($key eq "sorttype"){
      $sorttype=$value;
    }
    elsif ($key eq "trefferliste"){
      $fullargs{$key}=$value;
      $trefferliste=$value;
    }
    elsif ($key eq "sortall"){
      $fullargs{$key}=$value;
      $sortall=$value;
    }
    elsif ($key eq "sessionID"){
      $fullargs{$key}=$value;
      $sessionID=$value;
    }
    elsif ($key eq "queryid"){
      $fullargs{$key}=$value;
      $queryid=$value;
    }

  }

  #Defaults setzen, falls Parameter nicht uebergeben

  $sortorder="up" unless ($sortorder);
  $sorttype="author" unless ($sorttype);

  # Bei der ersten Suche kann der 'trefferliste'-Parameter nicht
  # uebergeben werden. Daher wird er jetzt hier nachtraeglich gesetzt.

  if ($trefferliste eq ""){
    $trefferliste="all";
  }

  my %cacheargs=();

  $cacheargs{trefferliste}=$trefferliste;
  $cacheargs{sessionID}=$sessionID;
  $cacheargs{queryid}=$queryid;

  my $queryargs="";

  if ($usequerycache){
    $queryargs=\%cacheargs;
  }
  else {
    $queryargs=\%fullargs;
  }

#  my $navclick= << "NAVCLICK";
#<table width="100%">
#<tr><th>Optionen</th></tr>
#<tr><td class="boxed">
#<b>Sortierung:<b>&nbsp;<select name=sorttype><option value="author">nach Autor</option><option value="title">nach Titel</option><option value="yearofpub">nach Jahr</option><option value="publisher">nach Verlag</option><option value="signature">nach Signatur</option></select>&nbsp;<select name=sortorder><option value="up">aufsteigend</option><option value="down">absteigend</option></select>
#NAVCLICK


  my %fullstring=('up','aufsteigend',
		  'down','absteigend',
		  'author','nach Autor/K&ouml;rperschaft',
		  'publisher','nach Verlag',
		  'signature','nach Signatur',
		  'title','nach Titel',
		  'yearofpub','nach Erscheinungsjahr',
		  'popularity','nach Popularit&auml;t'
		  );

  my $katalogtyp="pro Katalog";

  if ($sortall eq "1"){
    $katalogtyp="katalog&uuml;bergreifend";
  }

  my $thissortstring=$fullstring{$sorttype}." / ".$fullstring{$sortorder};

  $thissortstring=$thissortstring." / $katalogtyp" if ($nav);

  my @sortselect=();

  if ($nav eq 'sortsingle'){
    push @sortselect, {
		       val => 0,
		       desc => "pro Katalog",
		      };
  }
  elsif ($nav eq 'sortall'){
    push @sortselect, {
		       val => 1,
		       desc => "katalog&uuml;bergreifend",
		      };
  }

  elsif ($nav eq 'sortboth'){
    push @sortselect, {
		       val => 0,
		       desc => "pro Katalog",
		      };

    push @sortselect, {
		       val => 1,
		       desc => "katalog&uuml;bergreifend",
		      };
  }

  return ($queryargs,\@sortselect,$thissortstring);
}

sub print_sort_nav {
  my ($r,$nav,$usequerycache)=@_;

  my $myself=$r->uri;

  my $hostself="http://".$r->hostname.$r->uri;
  my @argself=$r->args;


#  print "<p><form method=\"get\" action=\"$hostself\">\n";

  my $sorttype="";
  my $sortorder="";
  my $trefferliste="";
  my $sortall="";
  my $sessionID="";
  my $queryid="";

  my $fullargstring="";

  for (my $i = 0; $i < $#argself; $i += 2) {
    my $key=$argself[$i];

    my $value="";

    if (defined($argself[$i+1])){
      $value=$argself[$i+1];
    }

    if ($key ne "sortorder" && $key ne "sorttype" && $key ne "trefferliste" && $key ne "sortall" && $key ne "sessionID" && $key ne "queryid"){
      $fullargstring.="<input type=\"hidden\" name=\"$key\" value=\"$value\">\n";
    }
    elsif ($key eq "sortorder"){
      $sortorder=$value;
    }
    elsif ($key eq "sorttype"){
      $sorttype=$value;
    }
    elsif ($key eq "trefferliste"){
      $fullargstring.="<input type=\"hidden\" name=\"$key\" value=\"$value\">\n";
      $trefferliste=$value;
    }
    elsif ($key eq "sortall"){
      $fullargstring.="<input type=\"hidden\" name=\"$key\" value=\"$value\">\n";
      $sortall=$value;
    }
    elsif ($key eq "sessionID"){
      $fullargstring.="<input type=\"hidden\" name=\"$key\" value=\"$value\">\n";
      $sessionID=$value;
    }
    elsif ($key eq "queryid"){
      $fullargstring.="<input type=\"hidden\" name=\"$key\" value=\"$value\">\n";
      $queryid=$value;
    }

  }

  #Defaults setzen, falls Parameter nicht uebergeben

  $sortorder="up" unless ($sortorder);
  $sorttype="author" unless ($sorttype);

  # Bei der ersten Suche kann der 'trefferliste'-Parameter nicht
  # uebergeben werden. Daher wird er jetzt hier nachtraeglich gesetzt.

  if ($trefferliste eq ""){
    $trefferliste="all";
  }

  my $cacheargstring= << "CACHEARG";
<input type="hidden" name="trefferliste" value="$trefferliste">
<input type="hidden" name="sessionID" value="$sessionID">
<input type="hidden" name="queryid" value="$queryid">
CACHEARG

  if ($usequerycache){
    print $cacheargstring;
  }
  else {
    print $fullargstring;
  }

  my $navclick= << "NAVCLICK";
<table width="100%">
<tr><th>Optionen</th></tr>
<tr><td class="boxed">
<b>Sortierung:<b>&nbsp;<select name=sorttype><option value="author">nach Autor</option><option value="title">nach Titel</option><option value="yearofpub">nach Jahr</option><option value="publisher">nach Verlag</option><option value="signature">nach Signatur</option></select>&nbsp;<select name=sortorder><option value="up">aufsteigend</option><option value="down">absteigend</option></select>
NAVCLICK


  my %fullstring=('up','aufsteigend',
		  'down','absteigend',
		  'author','nach Autor/K&ouml;rperschaft',
		  'publisher','nach Verlag',
		  'signature','nach Signatur',
		  'title','nach Titel',
		  'yearofpub','nach Erscheinungsjahr'
		  );

  my $katalogtyp="pro Katalog";

  if ($sortall eq "1"){
    $katalogtyp="katalog&uuml;bergreifend";
  }

  my $aktuellstring="<b>derzeit:<b> ".$fullstring{$sorttype}." / ".$fullstring{$sortorder};

  $aktuellstring.=" / $katalogtyp" if ($nav);

  my $sortend="&nbsp;<input type=\"submit\" value=\"Los\"></form>&nbsp;&nbsp;&nbsp;$aktuellstring</td></tr></table><p>\n";

  if ($nav eq 'sortsingle'){
    print $navclick."<select name=\"sortall\"><option value=\"0\">pro Katalog</option></select>".$sortend;
  }
  elsif ($nav eq 'sortall'){
    print $navclick."<select name=\"sortall\"><option value=\"1\">katalog&uuml;bergreifend</option></select>".$sortend;
  }

  elsif ($nav eq 'sortboth'){
    print $navclick."<select name=\"sortall\"><option value=\"0\">pro Katalog</option><option value=\"1\">katalog&uuml;bergreifend</option></select>".$sortend;
  }
  else {
    print $navclick.$sortend;
  }

}

sub by_yearofpub {
  my %line1=%$a;
  my %line2=%$b;

  
  $line1{erschjahr}=0 if ($line1{erschjahr} eq "");
  $line2{erschjahr}=0 if ($line2{erschjahr} eq "");

  ($line1{erschjahr})=$line1{erschjahr}=~m/(\d\d\d\d)/;
  ($line2{erschjahr})=$line2{erschjahr}=~m/(\d\d\d\d)/;

  $line1{erschjahr} <=> $line2{erschjahr};
}

sub by_yearofpub_down {
  my %line1=%$a;
  my %line2=%$b;

  $line1{erschjahr}=0 if ($line1{erschjahr} eq "");
  $line2{erschjahr}=0 if ($line2{erschjahr} eq "");

  ($line1{erschjahr})=$line1{erschjahr}=~m/(\d\d\d\d)/;
  ($line2{erschjahr})=$line2{erschjahr}=~m/(\d\d\d\d)/;

  $line2{erschjahr} <=> $line1{erschjahr};
}


sub by_publisher {
  my %line1=%$a;
  my %line2=%$b;

  $line1{publisher}=cleanrl($line1{publisher}) if ($line1{publisher});
  $line2{publisher}=cleanrl($line2{publisher}) if ($line2{publisher});

  $line1{publisher} cmp $line2{publisher};
}

sub by_publisher_down {
  my %line1=%$a;
  my %line2=%$b;

  $line1{publisher}=cleanrl($line1{publisher}) if ($line1{publisher});
  $line2{publisher}=cleanrl($line2{publisher}) if ($line2{publisher});

  $line2{publisher} cmp $line1{publisher};
}

sub by_signature {
  my %line1=%$a;
  my %line2=%$b;

  $line1{signatur}=cleanrl($line1{signatur}) if ($line1{signatur});
  $line2{signatur}=cleanrl($line2{signatur}) if ($line2{signatur});

  $line1{signatur} cmp $line2{signatur};
}

sub by_signature_down {
  my %line1=%$a;
  my %line2=%$b;

  $line1{signatur}=cleanrl($line1{signatur}) if ($line1{signatur});
  $line2{signatur}=cleanrl($line2{signatur}) if ($line2{signatur});

  $line2{signatur} cmp $line1{signatur};
}

sub by_author {
  my %line1=%$a;
  my %line2=%$b;

  $line1{verfasser}=cleanrl($line1{verfasser}) if ($line1{verfasser});
  $line2{verfasser}=cleanrl($line2{verfasser}) if ($line2{verfasser});

  $line1{verfasser} cmp $line2{verfasser};
}

sub by_author_down {
  my %line1=%$a;
  my %line2=%$b;

  $line1{verfasser}=cleanrl($line1{verfasser}) if ($line1{verfasser});
  $line2{verfasser}=cleanrl($line2{verfasser}) if ($line2{verfasser});

  $line2{verfasser} cmp $line1{verfasser};
}

sub by_title {
  my %line1=%$a;
  my %line2=%$b;

  $line1{title}=cleanrl($line1{title}) if ($line1{title});
  $line2{title}=cleanrl($line2{title}) if ($line2{title});

  $line1{title} cmp $line2{title};
}

sub by_title_down {
  my %line1=%$a;
  my %line2=%$b;

  $line1{title}=cleanrl($line1{title}) if ($line1{title});
  $line2{title}=cleanrl($line2{title}) if ($line2{title});

  $line2{title} cmp $line1{title};
}

sub by_popularity {
  my %line1=%$a;
  my %line2=%$b;

  $line1{popularity}=cleanrl($line1{popularity}) if ($line1{popularity});
  $line2{popularity}=cleanrl($line2{popularity}) if ($line2{popularity});

  $line1{popularity} <=> $line2{popularity};
}

sub by_popularity_down {
  my %line1=%$a;
  my %line2=%$b;

  $line1{popularity}=cleanrl($line1{popularity}) if ($line1{popularity});
  $line2{popularity}=cleanrl($line2{popularity}) if ($line2{popularity});

  $line2{popularity} <=> $line1{popularity};
}

sub sort_buffer {
  my ($sorttype,$sortorder,$routputbuffer,$rsortedoutputbuffer)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my $atime;
  my $btime;
  my $timeall;
  
  if ($config{benchmark}){
    $atime=new Benchmark;
  }

  if ($sorttype eq "author" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_author @$routputbuffer;
  }
  elsif ($sorttype eq "author" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_author_down @$routputbuffer;
  }
  elsif ($sorttype eq "yearofpub" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_yearofpub @$routputbuffer;
  }
  elsif ($sorttype eq "yearofpub" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_yearofpub_down @$routputbuffer;
  }
  elsif ($sorttype eq "publisher" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_publisher @$routputbuffer;
  }
  elsif ($sorttype eq "publisher" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_publisher_down @$routputbuffer;
  }
  elsif ($sorttype eq "signature" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_signature @$routputbuffer;
  }
  elsif ($sorttype eq "signature" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_signature_down @$routputbuffer;
  }
  elsif ($sorttype eq "title" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_title @$routputbuffer;
  }
  elsif ($sorttype eq "title" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_title_down @$routputbuffer;
  }
  elsif ($sorttype eq "popularity" && $sortorder eq "up"){
    @$rsortedoutputbuffer=sort by_popularity @$routputbuffer;
  }
  elsif ($sorttype eq "popularity" && $sortorder eq "down"){
    @$rsortedoutputbuffer=sort by_popularity_down @$routputbuffer;
  }
  else {
    @$rsortedoutputbuffer=@$routputbuffer;
  }

  if ($config{benchmark}){
    $btime=new Benchmark;
    $timeall=timediff($btime,$atime);
    $logger->info("Zeit fuer : sort by $sorttype / $sortorder : ist ".timestr($timeall));
    undef $atime;
    undef $btime;
    undef $timeall;
  }

  return;
}

sub cleanrl {
  my ($line)=@_;

  $line=~s/�/Ue/g;
  $line=~s/�/Ae/g;
  $line=~s/�/Oe/g;
  $line=lc($line);
  $line=~s/&(.)uml;/$1e/g;
  $line=~s/^ +//g;
  $line=~s/^�//g;
  $line=~s/^"//g;
  $line=~s/^'//g;

  return $line;
}

sub updatelastresultset {
  my ($sessiondbh,$sessionID,$rresultset)=@_;

  # Log4perl logger erzeugen
  
  my $logger = get_logger();

  my @resultset=@$rresultset;

  my @nresultset=();

  foreach my $outidx (@resultset){
    
    my %outidx=%$outidx;

    # Eintraege merken fuer Lastresultset
    
    my $katkey=$outidx{idn};
    my $resdatabase=$outidx{database};
    push @nresultset, "$resdatabase:$katkey";
  }

  my $resultsetstring=join("|",@nresultset);

  my $sessionresult=$sessiondbh->prepare("update session set lastresultset = ? where sessionid = ?") or $logger->error($DBI::errstr);
  $sessionresult->execute($resultsetstring,$sessionID) or $logger->error($DBI::errstr);
  $sessionresult->finish();

  return;
}

sub get_loadbalanced_servername {

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $ua=new LWP::UserAgent(timeout => 5);

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

    return $bestserver;
}

sub grundform {
    my ($arg_ref) = @_;
    
    # Set defaults
    my $content   = exists $arg_ref->{content}
        ? $arg_ref->{content}             : "";

    my $category  = exists $arg_ref->{category}
        ? $arg_ref->{category}            : "";

    my $searchreq = exists $arg_ref->{searchreq}
        ? $arg_ref->{searchreq}           : undef;
    
    # Sonderbehandlung verschiedener Kategorien

    # Datum normalisieren

    if ($category eq '0002'){
        if ($content =~ /^(\d\d)\.(\d\d)\.(\d\d\d\d)$/){
            $content=$3.$2.$1;
        }
    }
    
    # ISBN filtern
    if ($category eq "0540"){
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8$9$10/g;
    }

    # ISSN filtern
    if ($category eq "0543"){
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)/$1$2$3$4$5$6$7$8/g;
    }

    # Stopwoerter fuer versch. Kategorien ausfiltern

    if ($category eq "0304" || $category eq "0310" || $category eq "0331"
            || $category eq "0341" || $category eq "0370"){
        $content=OpenBib::Common::Stopwords::strip_first_stopword($content);
    }
    
    # Ausfiltern spezieller HTML-Tags
    $content=~s/&[gl]t;//g;
    $content=~s/&quot;//g;
    $content=~s/&amp;//g;

    if ($searchreq){
        # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
        $content=~s/[^-+\p{Alphabetic}0-9\/: '()"^*]//g;
    }
    else {
        # Ausfiltern nicht akzeptierter Zeichen (Postitivliste)
        $content=~s/[^-+\p{Alphabetic}0-9\/: ']//g;
    }
    
    # Zeichenersetzungen
    $content=~s/'/ /g;
    $content=~s/\// /g;
    $content=~s/:/ /g;
    $content=~s/  / /g;

    # Buchstabenersetzungen
    $content=~s/ü/ue/g;
    $content=~s/ä/ae/g;
    $content=~s/ö/oe/g;
    $content=~s/Ü/Ue/g;
    $content=~s/Ö/Oe/g;
    $content=~s/Ü/Ae/g;
    $content=~s/ß/ss/g;

    $content=~s/é/e/g;
    $content=~s/è/e/g;
    $content=~s/ê/e/g;
    $content=~s/É/E/g;
    $content=~s/È/E/g;
    $content=~s/Ê/E/g;

    $content=~s/á/a/g;
    $content=~s/à/a/g;
    $content=~s/â/a/g;
    $content=~s/Á/A/g;
    $content=~s/À/A/g;
    $content=~s/Â/A/g;

    $content=~s/ó/o/g;
    $content=~s/ò/o/g;
    $content=~s/ô/o/g;
    $content=~s/Ó/O/g;
    $content=~s/Ò/o/g;
    $content=~s/Ô/o/g;

    $content=~s/í/i/g;
    $content=~s/ì/i/g;
    $content=~s/î/i/g;
    $content=~s/Í/I/g;
    $content=~s/Ì/I/g;
    $content=~s/Î/I/g;

    $content=~s/ø/o/g;
    $content=~s/Ø/o/g;
    $content=~s/ñ/n/g;
    $content=~s/Ñ/N/g;
#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;

#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;
#     $content=~s///g;

#    $line=~s/?/g;

#     $line=~s/该/g;
#     $line=~s/?/g;
#     $line=~s/?g;
#     $line=~s/?;
#     $line=~s/?e/g;
#     $line=~s//a/g;
#     $line=~s/?o/g;
#     $line=~s/?u/g;
#     $line=~s/鯥/g;
#     $line=~s/ɯE/g;
#     $line=~s/?/g;
#     $line=~s/oa/g;
#     $line=~s/?/g;
#     $line=~s/?I/g;
#     $line=~s/?g;
#     $line=~s/?O/g;
#     $line=~s/?;
#     $line=~s/?U/g;
#     $line=~s/ /y/g;
#     $line=~s/?Y/g;
#     $line=~s/毡e/g; # ae
#     $line=~s/?/g; # Hacek
#     $line=~s/?/g; # Macron / Oberstrich
#     $line=~s/?/g;
#     $line=~s/&gt;//g;
#     $line=~s/&lt;//g;
#     $line=~s/>//g;
#     $line=~s/<//g;

    return $content;
}

sub normset2bibtex {
    my ($normset_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug(YAML::Dump($normset_ref));
    
    my $bibtex_ref=[];

    # Verfasser und Herausgeber konstruieren
    my $authors_ref  = [];
    my $editors_ref  = [];
    my $keywords_ref = [];

    my ($edition,$publisher,$address,$title,$year,$isbn,$issn,$language);

    foreach my $item_ref (@$normset_ref){
      $logger->debug("Item ".YAML::Dump($item_ref));
      if ($item_ref->{desc} eq "Verfasser" || $item_ref->{desc} eq "Person"){
	my $contents=$item_ref->{contents};
	if ($item_ref->{supplement}=~/Hrsg/){
	  push @$editors_ref, $contents;
	}
	else {
	  push @$authors_ref, $contents;
	}
      }
      if ($item_ref->{desc} eq "Schlagwort"){
	push @$keywords_ref, $item_ref->{contents};
      }
      if ($item_ref->{desc} eq "Auflage" && !$edition){
	$edition = $item_ref->{contents};
      }
      if ($item_ref->{desc} eq "Verlag" && !$publisher){
	$publisher = $item_ref->{contents};
      }
      if ($item_ref->{desc} eq "Verlagsort" && !$address){
	$address   = $item_ref->{contents};
      }
      if ($item_ref->{desc} eq "HST" && !$title){
	$title     = $item_ref->{contents};
      }
      if ($item_ref->{desc} eq "Ersch. Jahr" && !$year){
	$year      = $item_ref->{contents};
      }
      if ($item_ref->{desc} eq "ISBN" && !$isbn){
	$isbn      = $item_ref->{contents};
      }
      if ($item_ref->{desc} eq "ISSN" && !$issn){
	$issn      = $item_ref->{contents};
      }
      if ($item_ref->{desc} eq "Sprache" && !$language){
	$language  = $item_ref->{contents};
      }
    }
    my $author  = join(' and ',@$authors_ref);
    my $editor  = join(' and ',@$editors_ref);
    my $keyword = join(' ; ',@$keywords_ref);

    if ($author){
        push @$bibtex_ref, "author    = \"$author\"";
    }
    if ($editor){
        push @$bibtex_ref, "editor    = \"$editor\"";
    }
    if ($edition){
        push @$bibtex_ref, "edition   = \"$edition\"";
    }
    if ($publisher){
        push @$bibtex_ref, "publisher = \"$publisher\"";
    }
    if ($address){
        push @$bibtex_ref, "address   = \"$address\"";
    }
    if ($title){
        $title=~s/<.?strong>//g;
        $title=~s/&#172;//g;      
        push @$bibtex_ref, "title     = \"$title\"";
    }
    if ($year){
        push @$bibtex_ref, "year      = \"$year\"";
    }
    if ($isbn){
        push @$bibtex_ref, "ISBN      = \"$isbn\"";
    }
    if ($issn){
        push @$bibtex_ref, "ISSN      = \"$issn\"";
    }
    if ($keyword){
        push @$bibtex_ref, "keywords  = \"$keyword\"";
    }
    if ($language){
        push @$bibtex_ref, "language  = \"$language\"";
    }
    
    my $identifier.=substr($author,0,4);
    $identifier.=substr($title,0,4);
    $identifier.=$year;
    $identifier=~s/[^a-zA-Z0-9]//g;

    my $bibtex="";
    
    if ($isbn){
        unshift @$bibtex_ref, "\@book {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }
    else {
        unshift @$bibtex_ref, "\@book {$identifier";
        $bibtex=join(",\n",@$bibtex_ref);
        $bibtex="$bibtex}";
    }

    
    return utf2bibtex($bibtex);
}

sub utf2bibtex {
    my ($string)=@_;

    $string=~s/<.?strong>//g;
    $string=~s/&lt;/</g;
    $string=~s/&gt;/>/g;
    $string=~s/&#172;//g;
    $string=~s/&auml;/{\\"a}/g;
    $string=~s/&ouml;/{\\"o}/g;
    $string=~s/&uuml;/{\\"u}/g;
    $string=~s/&Auml;/{\\"A}/g;
    $string=~s/&Ouml;/{\\"O}/g;
    $string=~s/&Uuml;/{\\"U}/g;
    $string=~s/&szlig;/{\\"s}/g;
    $string=~s/�/{\\"a}/g;
    $string=~s/�/{\\"o}/g;
    $string=~s/�/{\\"u}/g;
    $string=~s/�/{\\"A}/g;
    $string=~s/�/{\\"O}/g;
    $string=~s/�/{\\"U}/g;
    $string=~s/�/{\\"s}/g;
    # Ausfiltern nicht akzeptierter Zeichen (Positivliste)
    $string=~s/[^-+\p{Alphabetic}0-9\n\/&;#: '(){}@<>\\,.="^*[]]//g;

    return $string;
}

1;
__END__

=head1 NAME

 OpenBib::Common::Util - Gemeinsame Funktionen der OpenBib-Module

=head1 DESCRIPTION

 In OpenBib::Common::Util sind all jene Funktionen untergebracht, die 
 von mehr als einem mod_perl-Modul verwendet werden. Es sind dies 
 Funktionen aus den Bereichen Session- und User-Management, Ausgabe 
 von Webseiten oder deren Teilen und Interaktionen mit der 
 Katalog-Datenbank.

=head1 SYNOPSIS

 use OpenBib::Common::Util;

 # Stylesheet-Namen aus mod_perl Request-Object (Browser-Typ) bestimmen
 my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

 # eine neue Session erzeugen und Rueckgabe der $sessionID
 my $sessionID=OpenBib::Common::Util::init_new_session($sessiondbh);

 # Ist die Session gueltig? Nein, dann Warnung und Ausstieg
 unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
   OpenBib::Search::Util::print_warning("Warnungstext",$r);
   exit;
 }

 # Ist die Session authentifiziert? Ja, dann Rueckgabe der positiven $userid,
 # sonst wird nichts zurueckgegeben 
 my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);

 # Ergebnisarray zu SQL-Anfragen (@requests) an DB-Handle $dbh fuellen
 my @resarr=OpenBib::Common::Util::get_sql_result(\@requests,$dbh);

 # Navigationsselement zwecks Sortierung einer Trefferliste ausgeben
 OpenBib::Common::Util::print_sort_nav($r,'',0);

 # Komplette Seite aus Template $templatename, Template-Daten $ttdata und
 # Request-Objekt $r bilden und ausgeben
 OpenBib::Common::Util::print_page($templatename,$ttdata,$r);

 # Ausgabe des Footers
 OpenBib::Common::Util::print_footer();

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
