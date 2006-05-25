#####################################################################
#
#  OpenBib::Common::Util
#
#  Dieses File ist (C) 2004-2006 Oliver Flimm <flimm@openbib.org>
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
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Digest::MD5();
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX();
use Template;
use YAML ();

use OpenBib::Config;
use OpenBib::Template::Provider;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

my $benchmark;

if ($OpenBib::Config::config{benchmark}) {
    use Benchmark ':hireswallclock';
}

sub init_new_session {
    my ($sessiondbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sessionID="";

    my $havenewsessionID=0;
    
    while ($havenewsessionID == 0) {
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
        if ($anzahl == 0 ) {
            $havenewsessionID=1;
      
            my $createtime = POSIX::strftime('%Y-%m-%d% %H:%M:%S', localtime());


            my $queryoptions_ref={
                hitrange  => undef,
                offset    => undef,
                maxhits   => undef,
                l         => undef,
                profil    => undef,
                autoplus  => undef,
            };

            # Eintrag in die Datenbank
            $idnresult=$sessiondbh->prepare("insert into session (sessionid,createtime,queryoptions) values (?,?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$createtime,YAML::Dump($queryoptions_ref)) or $logger->error($DBI::errstr);
        }
        $idnresult->finish();
    }
    return $sessionID;
}

sub session_is_valid {
    my ($sessiondbh,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if ($sessionID eq "-1") {
        return 1;
    }

    my $idnresult=$sessiondbh->prepare("select count(sessionid) from session where sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionID) or $logger->error($DBI::errstr);

    my @idn=$idnresult->fetchrow_array();
    my $anzahl=$idn[0];

    $idnresult->finish();

    if ($anzahl == 1) {
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
  
    while(my $res=$userresult->fetchrow_hashref()){
        $cred[0] = decode_utf8($res->{loginname});
        $cred[1] = decode_utf8($res->{pin});
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
  
    while (my $res=$userresult->fetchrow_hashref()){
        $username = decode_utf8($res->{loginname});
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
  
    while(my $res=$userresult->fetchrow_hashref()){
        $userid = decode_utf8($res->{'userid'});
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
    my $view = decode_utf8($result->{'viewname'}) || '';

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
  
    my $dbname  = decode_utf8($result->{'dbname'}) || '';
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

sub get_targetdb_of_session {
    my ($userdbh,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $globalsessionID="$config{servername}:$sessionID";
    my $userresult=$userdbh->prepare("select db from usersession,logintarget where usersession.sessionid = ? and usersession.targetid = logintarget.targetid") or $logger->error($DBI::errstr);

    $userresult->execute($globalsessionID) or $logger->error($DBI::errstr);
  
    my $targetdb="";
  
    while(my $res=$userresult->fetchrow_hashref()){
        $targetdb = decode_utf8($res->{'db'});
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
  
    while(my $res=$userresult->fetchrow_hashref()){
        $targettype = decode_utf8($res->{'type'});
    }

    return $targettype;
}

sub get_css_by_browsertype {
    my ($r)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $useragent=$r->subprocess_env('HTTP_USER_AGENT');

    $logger->debug("User-Agent: $useragent");

    my $stylesheet="";
  
    if ( $useragent=~/Mozilla.5.0/ || $useragent=~/MSIE 5/ || $useragent=~/MSIE 6/ || $useragent=~/Konqueror"/ ) {
        if ($useragent=~/MSIE/) {
            $stylesheet="openbib-ie.css";
        }
        else {
            $stylesheet="openbib.css";
        }
    }
    else {
        if ($useragent=~/MSIE/) {
            $stylesheet="openbib-simple-ie.css";
        }
        else {
            $stylesheet="openbib-simple.css";
        }
    }

    return $stylesheet;
}

sub load_queryoptions {
    my ($sessiondbh,$sessionID)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    if (!$sessionID){
      $logger->fatal("No SessionID");
      return {};
    }	

    my $request=$sessiondbh->prepare("select queryoptions from session where sessionid = ?") or $logger->error($DBI::errstr);

    $request->execute($sessionID) or $logger->error($DBI::errstr);
  
    my $res=$request->fetchrow_hashref();

    $logger->debug($res->{queryoptions});
    my $queryoptions_ref = YAML::Load($res->{queryoptions});

    $request->finish();

    return $queryoptions_ref;
}

sub dump_queryoptions {
    my ($sessiondbh,$sessionID,$queryoptions_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $request=$sessiondbh->prepare("update session set queryoptions=? where sessionid = ?") or $logger->error($DBI::errstr);

    $request->execute(YAML::Dump($queryoptions_ref),$sessionID) or $logger->error($DBI::errstr);

    $request->finish();

    return;
}

sub merge_queryoptions {
    my ($options1_ref,$options2_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Eintragungen in options1_ref werden, wenn sie in options2_ref
    # gesetzt sind, von diesen ueberschrieben
    
    foreach my $key (keys %$options1_ref){
        if (exists $options2_ref->{$key}){
            $options1_ref->{$key}=$options2_ref->{$key};
        }
    }
}

sub get_queryoptions {
    my ($sessiondbh,$query) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Hinweis: Bisher wuerde statt $query direkt das Request-Objekt $r
    # uebergeben und an dieser Stelle wieder ein $query-Objekt via
    # Apache::Request daraus erzeugt. Bei Requests, die via POST
    # sowohl mit dem enctype multipart/form-data wie auch
    # multipart/form-data abgesetzt wurden, lassen sich keine
    # Parameter ala sessionID extrahieren.  Das ist ein grosses
    # Problem. Andere Informationen lassen sich ueber das $r
    # aber sehr wohl extrahieren, z.B. der Useragent.

    my $sessionID=$query->param('sessionID');

    if (!$sessionID){
      $logger->fatal("No SessionID");
      return {};
    }	

    # Queryoptions zur Session einladen (default: alles undef)
    my $queryoptions_ref = load_queryoptions($sessiondbh,$sessionID);

    my $default_queryoptions_ref={
        hitrange  => 20,
        offset    => 1,
        maxhits   => 500,
        l         => 'de',
        profil    => '',
        autoplus  => '',
    };

    my $altered=0;
    # Abgleich mit uebergebenen Parametern
    # Uebergebene Parameter 'ueberschreiben'und gehen vor
    foreach my $option (keys %$default_queryoptions_ref){
        if (defined $query->param($option)){
            $queryoptions_ref->{$option}=$query->param($option);
	    $logger->debug("Option $option received via HTTP");
	    $altered=1;
        }
    }

    # Abgleich mit Default-Werten:
    # Verbliebene "undefined"-Werte werden mit Standard-Werten belegt
    foreach my $option (keys %$queryoptions_ref){
        if (!defined $queryoptions_ref->{$option}){
            $queryoptions_ref->{$option}=$default_queryoptions_ref->{$option};
	    $logger->debug("Option $option got default value");
	    $altered=1;
        }
    }

    if ($altered){
      dump_queryoptions($sessiondbh,$sessionID,$queryoptions_ref);
      $logger->debug("Options changed and dumped to DB");
    }

    return $queryoptions_ref;
}

sub print_warning {
    my ($warning,$r,$msg)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my $stylesheet=get_css_by_browsertype($r);

    my $query=Apache::Request->new($r);

    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);

    my $view=get_viewname_of_session($sessiondbh,$sessionID);
 
    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
#        INCLUDE_PATH   => $config{tt_include_path},
#        ABSOLUTE       => 1,
        OUTPUT         => $r,    # Output geht direkt an Apache Request
    });
  
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,

        errmsg     => $warning,
        config     => \%config,
        msg        => $msg,
    };
  
    # Dann Ausgabe des neuen Headers
    print $r->send_http_header("text/html");
  
    $template->process($config{tt_error_tname}, $ttdata) || do {
        $r->log_reason($template->error(), $r->filename);
        return SERVER_ERROR;
    };
  
    return;
}

sub print_info {
    my ($info,$r,$msg)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
  
    my $stylesheet=get_css_by_browsertype($r);

    my $query=Apache::Request->new($r);

    my $sessionID=($query->param('sessionID'))?$query->param('sessionID'):'';

    my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or $logger->error_die($DBI::errstr);

    my $view=get_viewname_of_session($sessiondbh,$sessionID);
 
    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
#        INCLUDE_PATH   => $config{tt_include_path},
#        ABSOLUTE       => 1,
        OUTPUT         => $r,    # Output geht direkt an Apache Request
    });
  
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,

        info_msg   => $info,
        config     => \%config,
        msg        => $msg,
    };
  
    # Dann Ausgabe des neuen Headers
    print $r->send_http_header("text/html");
  
    $template->process($config{tt_info_message_tname}, $ttdata) || do {
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

    # View- und Datenbank-spezifisches Templating
    my $database = $ttdata->{'view'};
    my $view     = $ttdata->{'view'};

    if ($view && -e "$config{tt_include_path}/views/$view/$templatename") {
        $templatename="views/$view/$templatename";
    }

    # Database-Template ist spezifischer als View-Template und geht vor
    if ($database && -e "$config{tt_include_path}/database/$database/$templatename") {
        $templatename="database/$database/$templatename";
    }

    $logger->debug("Using Template $templatename");
  
    my $template = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config{tt_include_path},
	    ABSOLUTE       => 1,
        }) ],
#         INCLUDE_PATH   => $config{tt_include_path},
#         ABSOLUTE       => 1,     # Notwendig fuer Kaskadierung
         OUTPUT         => $r,    # Output geht direkt an Apache Request
#         RECURSION      => 1,
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
    my ($r,$nav,$usequerycache,$msg)=@_;

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

        if (defined($argself[$i+1])) {
            $value=$argself[$i+1];
        }

        if ($key ne "sortorder" && $key ne "sorttype" && $key ne "trefferliste" && $key ne "sortall" && $key ne "sessionID" && $key ne "queryid") {
            $fullargs{$key}=$value;
        }
        elsif ($key eq "sortorder") {
            $sortorder=$value;
        }
        elsif ($key eq "sorttype") {
            $sorttype=$value;
        }
        elsif ($key eq "trefferliste") {
            $fullargs{$key}=$value;
            $trefferliste=$value;
        }
        elsif ($key eq "sortall") {
            $fullargs{$key}=$value;
            $sortall=$value;
        }
        elsif ($key eq "sessionID") {
            $fullargs{$key}=$value;
            $sessionID=$value;
        }
        elsif ($key eq "queryid") {
            $fullargs{$key}=$value;
            $queryid=$value;
        }

    }

    #Defaults setzen, falls Parameter nicht uebergeben
    $sortorder = "up"     unless ($sortorder);
    $sorttype  = "author" unless ($sorttype);

    # Bei der ersten Suche kann der 'trefferliste'-Parameter nicht
    # uebergeben werden. Daher wird er jetzt hier nachtraeglich gesetzt.

    if ($trefferliste eq "") {
        $trefferliste="all";
    }

    my %cacheargs=();

    $cacheargs{trefferliste} = $trefferliste;
    $cacheargs{sessionID}    = $sessionID;
    $cacheargs{queryid}      = $queryid;

    my $queryargs_ref="";

    if ($usequerycache) {
        $queryargs_ref=\%cacheargs;
    }
    else {
        $queryargs_ref=\%fullargs;
    }

    my %fullstring=('up'        => $msg->maketext("aufsteigend"),
                    'down'      => $msg->maketext("absteigend"),
                    'author'    => $msg->maketext("nach Autor/Körperschaft"),
                    'publisher' => $msg->maketext("nach Verlag"),
                    'signature' => $msg->maketext("nach Signatur"),
                    'title'     => $msg->maketext("nach Titel"),
                    'yearofpub' => $msg->maketext("nach Erscheinungsjahr"),
                );

    my $katalogtyp=$msg->maketext("pro Katalog");

    if ($sortall eq "1") {
        $katalogtyp=$msg->maketext("katalogübergreifend");
    }

    my $thissortstring=$fullstring{$sorttype}." / ".$fullstring{$sortorder};

    $thissortstring=$thissortstring." / $katalogtyp" if ($nav);

    my @sortselect=();

    if ($nav eq 'sortsingle') {
        push @sortselect, {
            val  => 0,
            desc => $msg->maketext("pro Katalog"),
        };
    }
    elsif ($nav eq 'sortall') {
        push @sortselect, {
            val  => 1,
            desc => $msg->maketext("katalogübergreifend"),
        };
    }
    elsif ($nav eq 'sortboth') {
        push @sortselect, {
            val  => 0,
            desc => $msg->maketext("pro Katalog"),
        };

        push @sortselect, {
            val  => 1,
            desc => $msg->maketext("katalogübergreifend"),
        };
    }

    return ($queryargs_ref,\@sortselect,$thissortstring);
}

sub by_yearofpub {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0425}[0]{content} && defined $line1{T0425}[0]{content})?cleanrl($line1{T0425}[0]{content}):"";
    my $line2=(exists $line2{T0425}[0]{content} && defined $line2{T0425}[0]{content})?cleanrl($line2{T0425}[0]{content}):"";

    my ($yline1)=$line1=~m/(\d\d\d\d)/;
    my ($yline2)=$line2=~m/(\d\d\d\d)/;

    $yline1=0 if (!defined $yline1);
    $yline2=0 if (!defined $yline2);

    $yline1 <=> $yline2;
}

sub by_yearofpub_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0425}[0]{content} && defined $line1{T0425}[0]{content})?cleanrl($line1{T0425}[0]{content}):"";
    my $line2=(exists $line2{T0425}[0]{content} && defined $line2{T0425}[0]{content})?cleanrl($line2{T0425}[0]{content}):"";

    my ($yline1)=$line1=~m/(\d\d\d\d)/;
    my ($yline2)=$line2=~m/(\d\d\d\d)/;

    $yline1=0 if (!defined $yline1);
    $yline2=0 if (!defined $yline2);

    $yline2 <=> $yline1;
}


sub by_publisher {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0412}[0]{content} && defined $line1{T0412}[0]{content})?cleanrl($line1{T0412}[0]{content}):"";
    my $line2=(exists $line2{T0412}[0]{content} && defined $line2{T0412}[0]{content})?cleanrl($line2{T0412}[0]{content}):"";

    $line1 cmp $line2;
}

sub by_publisher_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0412}[0]{content} && defined $line1{T0412}[0]{content})?cleanrl($line1{T0412}[0]{content}):"";
    my $line2=(exists $line2{T0412}[0]{content} && defined $line2{T0412}[0]{content})?cleanrl($line2{T0412}[0]{content}):"";

    $line2 cmp $line1;
}

sub by_signature {
    my %line1=%$a;
    my %line2=%$b;

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?cleanrl($line1{X0014}[0]{content}):"0";
    my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?cleanrl($line2{X0014}[0]{content}):"0";

    $line1 cmp $line2;
}

sub by_signature_down {
    my %line1=%$a;
    my %line2=%$b;

    # Sortierung anhand erster Signatur
    my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?cleanrl($line1{X0014}[0]{content}):"";
    my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?cleanrl($line2{X0014}[0]{content}):"";

    $line2 cmp $line1;
}

sub by_author {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{PC0001}[0]{content} && defined $line1{PC0001}[0]{content})?cleanrl($line1{PC0001}[0]{content}):"";
    my $line2=(exists $line2{PC0001}[0]{content} && defined $line2{PC0001}[0]{content})?cleanrl($line2{PC0001}[0]{content}):"";

    $line1 cmp $line2;
}

sub by_author_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{PC0001}[0]{content} && defined $line1{PC0001}[0]{content})?cleanrl($line1{PC0001}[0]{content}):"";
    my $line2=(exists $line2{PC0001}[0]{content} && defined $line2{PC0001}[0]{content})?cleanrl($line2{PC0001}[0]{content}):"";

    $line2 cmp $line1;
}

sub by_title {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?cleanrl($line2{T0331}[0]{content}):"";

    $line1 cmp $line2;
}

sub by_title_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?cleanrl($line2{T0331}[0]{content}):"";

    $line2 cmp $line1;
}

sub sort_buffer {
    my ($sorttype,$sortorder,$outputbuffer_ref,$sortedoutputbuffer_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $atime;
    my $btime;
    my $timeall;
  
    if ($config{benchmark}) {
        $atime=new Benchmark;
    }

    if ($sorttype eq "author" && $sortorder eq "up") {
        @$sortedoutputbuffer_ref=sort by_author @$outputbuffer_ref;
    }
    elsif ($sorttype eq "author" && $sortorder eq "down") {
        @$sortedoutputbuffer_ref=sort by_author_down @$outputbuffer_ref;
    }
    elsif ($sorttype eq "yearofpub" && $sortorder eq "up") {
        @$sortedoutputbuffer_ref=sort by_yearofpub @$outputbuffer_ref;
    }
    elsif ($sorttype eq "yearofpub" && $sortorder eq "down") {
        @$sortedoutputbuffer_ref=sort by_yearofpub_down @$outputbuffer_ref;
    }
    elsif ($sorttype eq "publisher" && $sortorder eq "up") {
        @$sortedoutputbuffer_ref=sort by_publisher @$outputbuffer_ref;
    }
    elsif ($sorttype eq "publisher" && $sortorder eq "down") {
        @$sortedoutputbuffer_ref=sort by_publisher_down @$outputbuffer_ref;
    }
    elsif ($sorttype eq "signature" && $sortorder eq "up") {
        @$sortedoutputbuffer_ref=sort by_signature @$outputbuffer_ref;
    }
    elsif ($sorttype eq "signature" && $sortorder eq "down") {
        @$sortedoutputbuffer_ref=sort by_signature_down @$outputbuffer_ref;
    }
    elsif ($sorttype eq "title" && $sortorder eq "up") {
        @$sortedoutputbuffer_ref=sort by_title @$outputbuffer_ref;
    }
    elsif ($sorttype eq "title" && $sortorder eq "down") {
        @$sortedoutputbuffer_ref=sort by_title_down @$outputbuffer_ref;
    }
    else {
        @$sortedoutputbuffer_ref=@$outputbuffer_ref;
    }

    if ($config{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->debug("Zeit fuer : sort by $sorttype / $sortorder : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    return;
}

sub cleanrl {
    my ($line)=@_;

    $line=~s/Ü/Ue/g;
    $line=~s/Ä/Ae/g;
    $line=~s/Ö/Oe/g;
    $line=lc($line);
    $line=~s/&(.)uml;/$1e/g;
    $line=~s/^ +//g;
    $line=~s/^¬//g;
    $line=~s/^"//g;
    $line=~s/^'//g;

    return $line;
}

sub updatelastresultset {
    my ($sessiondbh,$sessionID,$resultset_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my @resultset=@$resultset_ref;

    my @nresultset=();

    foreach my $outidx_ref (@resultset) {
        my %outidx=%$outidx_ref;

        # Eintraege merken fuer Lastresultset
        my $katkey      = (exists $outidx{id})?$outidx{id}:"";
        my $resdatabase = (exists $outidx{database})?$outidx{database}:"";

	$logger->debug("Katkey: $katkey - Database: $resdatabase");

        push @nresultset, "$resdatabase:$katkey";
    }

    my $resultsetstring=join("|",@nresultset);

    my $sessionresult=$sessiondbh->prepare("update session set lastresultset = ? where sessionid = ?") or $logger->error($DBI::errstr);
    $sessionresult->execute($resultsetstring,$sessionID) or $logger->error($DBI::errstr);
    $sessionresult->finish();

    return;
}

sub get_targetdbinfo {
    my ($sessiondbh)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    #####################################################################
    # Dynamische Definition diverser Variablen
  
    # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
  
    my $dbinforesult=$sessiondbh->prepare("select dbname,sigel,url,description,shortdesc from dbinfo") or $logger->error($DBI::errstr);
    $dbinforesult->execute() or $logger->error($DBI::errstr);;
  
    my %sigel   =();
    my %bibinfo =();
    my %dbinfo  =();
    my %dbases  =();
    my %dbnames =();

    while (my $result=$dbinforesult->fetchrow_hashref()) {
        my $dbname      = decode_utf8($result->{'dbname'});
        my $sigel       = decode_utf8($result->{'sigel'});
        my $url         = decode_utf8($result->{'url'});
        my $description = decode_utf8($result->{'description'});
        my $shortdesc   = decode_utf8($result->{'shortdesc'});
    
        ##################################################################### 
        ## Wandlungstabelle Bibliothekssigel <-> Bibliotheksname
    
        $sigel{"$sigel"} = {
			    full  => $description,
			    short => $shortdesc,
			   };
    
        #####################################################################
        ## Wandlungstabelle Bibliothekssigel <-> Informations-URL
    
        $bibinfo{"$sigel"} = "$url";
    
        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Datenbankinfo
    
        # Wenn ein URL fuer die Datenbankinformation definiert ist, dann wird
        # damit verlinkt
    
        if ($url ne "") {
            $dbinfo{"$dbname"} = {
				  full  => "<a href=\"$url\" target=\"_blank\">$description</a>",
				  short => "<a href=\"$url\" target=\"_blank\">$shortdesc</a>",
				 };
        } else {
            $dbinfo{"$dbname"} = {
				  full  => "$description",
				  short => "$shortdesc",
				 };
        }
    
        #####################################################################
        ## Wandlungstabelle  Name SQL-Datenbank <-> Bibliothekssigel
    
        $dbases{"$dbname"}       = "$sigel";

        $dbnames{"$dbname"}      = {
				    full => $description,
				    short => $shortdesc,
				   };
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

sub get_targetcircinfo {
    my ($sessiondbh)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    #####################################################################
    ## Ausleihkonfiguration fuer den Katalog einlesen

    my $dbinforesult=$sessiondbh->prepare("select dbname,circ,circurl,circcheckurl,circdb from dboptions where circ = 1") or $logger->error($DBI::errstr);
    $dbinforesult->execute() or $logger->error($DBI::errstr);;

    my %targetcircinfo=();
    
    while (my $result=$dbinforesult->fetchrow_hashref()) {
        my $dbname                             = decode_utf8($result->{'dbname'});

        $targetcircinfo{$dbname}{circ}         = decode_utf8($result->{'circ'});
        $targetcircinfo{$dbname}{circurl}      = decode_utf8($result->{'circurl'});
        $targetcircinfo{$dbname}{circcheckurl} = decode_utf8($result->{'circcheckurl'});
        $targetcircinfo{$dbname}{circdb}       = decode_utf8($result->{'circdb'});
    }

    $dbinforesult->finish();

    return \%targetcircinfo;
}

sub get_searchquery {
    my ($r)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $query=Apache::Request->new($r);

    # Wandlungstabelle Erscheinungsjahroperator
    my $ejahrop_ref={
        'eq' => '=',
        'gt' => '>',
        'lt' => '<',
    };

    my ($fs, $verf, $hst, $hststring, $swt, $kor, $sign, $isbn, $issn, $mart,$notation,$ejahr,$ejahrop);

    my ($fsnorm, $verfnorm, $hstnorm, $hststringnorm, $swtnorm, $kornorm, $signnorm, $isbnnorm, $issnnorm, $martnorm,$notationnorm,$ejahrnorm);
    
    $fs        = $fsnorm        = decode_utf8($query->param('fs'))            || '';
    $verf      = $verfnorm      = decode_utf8($query->param('verf'))          || '';
    $hst       = $hstnorm       = decode_utf8($query->param('hst'))           || '';
    $hststring = $hststringnorm = decode_utf8($query->param('hststring'))     || '';
    $swt       = $swtnorm       = decode_utf8($query->param('swt'))           || '';
    $kor       = $kornorm       = decode_utf8($query->param('kor'))           || '';
    $sign      = $signnorm      = decode_utf8($query->param('sign'))          || '';
    $isbn      = $isbnnorm      = decode_utf8($query->param('isbn'))          || '';
    $issn      = $issnnorm      = decode_utf8($query->param('issn'))          || '';
    $mart      = $martnorm      = decode_utf8($query->param('mart'))          || '';
    $notation  = $notationnorm  = decode_utf8($query->param('notation'))      || '';
    $ejahr     = $ejahrnorm     = decode_utf8($query->param('ejahr'))         || '';
    $ejahrop   = decode_utf8($query->param('ejahrop'))       || 'eq';

    my $autoplus      = $query->param('autoplus')      || '';
    my $verfindex     = $query->param('verfindex')     || '';
    my $korindex      = $query->param('korindex')      || '';
    my $swtindex      = $query->param('swtindex')      || '';

    #####################################################################
    ## boolX: Verknuepfung der Eingabefelder (leere Felder werden ignoriert)
    ##        AND  - Und-Verknuepfung
    ##        OR   - Oder-Verknuepfung
    ##        NOT  - Und Nicht-Verknuepfung
    my $boolverf      = ($query->param('boolverf'))     ?$query->param('boolverf')
        :"AND";
    my $boolhst       = ($query->param('boolhst'))      ?$query->param('boolhst')
        :"AND";
    my $boolswt       = ($query->param('boolswt'))      ?$query->param('boolswt')
        :"AND";
    my $boolkor       = ($query->param('boolkor'))      ?$query->param('boolkor')
        :"AND";
    my $boolnotation  = ($query->param('boolnotation')) ?$query->param('boolnotation')
        :"AND";
    my $boolisbn      = ($query->param('boolisbn'))     ?$query->param('boolisbn')
        :"AND";
    my $boolissn      = ($query->param('boolissn'))     ?$query->param('boolissn')
        :"AND";
    my $boolsign      = ($query->param('boolsign'))     ?$query->param('boolsign')
        :"AND";
    my $boolejahr     = ($query->param('boolejahr'))    ?$query->param('boolejahr')
        :"AND" ;
    my $boolfs        = ($query->param('boolfs'))       ?$query->param('boolfs')
        :"AND";
    my $boolmart      = ($query->param('boolmart'))     ?$query->param('boolmart')
        :"AND";
    my $boolhststring = ($query->param('boolhststring'))?$query->param('boolhststring')
        :"AND";

    # Sicherheits-Checks

    if ($boolverf ne "AND" && $boolverf ne "OR" && $boolverf ne "NOT") {
        $boolverf      = "AND";
    }

    if ($boolhst ne "AND" && $boolhst ne "OR" && $boolhst ne "NOT") {
        $boolhst       = "AND";
    }

    if ($boolswt ne "AND" && $boolswt ne "OR" && $boolswt ne "NOT") {
        $boolswt       = "AND";
    }

    if ($boolkor ne "AND" && $boolkor ne "OR" && $boolkor ne "NOT") {
        $boolkor       = "AND";
    }

    if ($boolnotation ne "AND" && $boolnotation ne "OR" && $boolnotation ne "NOT") {
        $boolnotation  = "AND";
    }

    if ($boolisbn ne "AND" && $boolisbn ne "OR" && $boolisbn ne "NOT") {
        $boolisbn      = "AND";
    }

    if ($boolissn ne "AND" && $boolissn ne "OR" && $boolissn ne "NOT") {
        $boolissn      = "AND";
    }

    if ($boolsign ne "AND" && $boolsign ne "OR" && $boolsign ne "NOT") {
        $boolsign      = "AND";
    }

    if ($boolejahr ne "AND") {
        $boolejahr     = "AND";
    }

    if ($boolfs ne "AND" && $boolfs ne "OR" && $boolfs ne "NOT") {
        $boolfs        = "AND";
    }

    if ($boolmart ne "AND" && $boolmart ne "OR" && $boolmart ne "NOT") {
        $boolmart      = "AND";
    }

    if ($boolhststring ne "AND" && $boolhststring ne "OR" && $boolhststring ne "NOT") {
        $boolhststring = "AND";
    }

    $boolverf      = "AND NOT" if ($boolverf      eq "NOT");
    $boolhst       = "AND NOT" if ($boolhst       eq "NOT");
    $boolswt       = "AND NOT" if ($boolswt       eq "NOT");
    $boolkor       = "AND NOT" if ($boolkor       eq "NOT");
    $boolnotation  = "AND NOT" if ($boolnotation  eq "NOT");
    $boolisbn      = "AND NOT" if ($boolisbn      eq "NOT");
    $boolissn      = "AND NOT" if ($boolissn      eq "NOT");
    $boolsign      = "AND NOT" if ($boolsign      eq "NOT");
    $boolfs        = "AND NOT" if ($boolfs        eq "NOT");
    $boolmart      = "AND NOT" if ($boolmart      eq "NOT");
    $boolhststring = "AND NOT" if ($boolhststring eq "NOT");

    # Setzen der arithmetischen Ejahrop-Operatoren
    if (exists $ejahrop_ref->{$ejahrop}){
        $ejahrop=$ejahrop_ref->{$ejahrop};
    }
    else {
        $ejahrop="=";
    }
    
    # Filter: ISBN und ISSN

    # Entfernung der Minus-Zeichen bei der ISBN
    $fsnorm   =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;
    $isbnnorm =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\S)/$1$2$3$4$5$6$7$8$9$10/g;

    # Entfernung der Minus-Zeichen bei der ISSN
    $fsnorm   =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8/g;
    $issnnorm =~s/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/$1$2$3$4$5$6$7$8/g;

    my $ejtest;
  
    ($ejtest)=$ejahrnorm=~/.*(\d\d\d\d).*/;
    if (!$ejtest) {
        $ejahrnorm="";              # Nur korrekte Jahresangaben werden verarbeitet
    }                           # alles andere wird ignoriert...
    
    # Filter Rest
    $fsnorm        = OpenBib::Common::Util::grundform({
        content   => $fsnorm,
        searchreq => 1,
    });

    $verfnorm      = OpenBib::Common::Util::grundform({
        content   => $verfnorm,
        searchreq => 1,
    });

    $hstnorm       = OpenBib::Common::Util::grundform({
        content   => $hstnorm,
        searchreq => 1,
    });

    $hststringnorm = OpenBib::Common::Util::grundform({
        content   => $hststringnorm,
        searchreq => 1,
    });

    $swtnorm       = OpenBib::Common::Util::grundform({
        content   => $swtnorm,
        searchreq => 1,
    });

    $kornorm       = OpenBib::Common::Util::grundform({
        content   => $kornorm,
        searchreq => 1,
    });

    $signnorm      = OpenBib::Common::Util::grundform({
        content   => $signnorm,
        searchreq => 1,
    });

    $isbnnorm      = OpenBib::Common::Util::grundform({
        category  => '0540',
        content   => $isbnnorm,
        searchreq => 1,
    });

    $issnnorm      = OpenBib::Common::Util::grundform({
        category  => '0543',
        content   => $issnnorm,
        searchreq => 1,
    });
    
    $martnorm      = OpenBib::Common::Util::grundform({
        content   => $martnorm,
        searchreq => 1,
    });

    $notationnorm  = OpenBib::Common::Util::grundform({
        content   => $notationnorm,
        searchreq => 1,
    });

    $ejahrnorm      = OpenBib::Common::Util::grundform({
        content   => $ejahrnorm,
        searchreq => 1,
    });
    
    # Bei hststring zusaetzlich normieren durch Weglassung des ersten
    # Stopwortes
    $hststringnorm = OpenBib::Common::Stopwords::strip_first_stopword($hststringnorm);

    # Umwandlung impliziter ODER-Verknuepfung in UND-Verknuepfung
    if ($autoplus eq "1" && !$verfindex && !$korindex && !$swtindex) {
        $fsnorm   = OpenBib::VirtualSearch::Util::conv2autoplus($fsnorm)   if ($fs);
        $verfnorm = OpenBib::VirtualSearch::Util::conv2autoplus($verfnorm) if ($verf);
        $hstnorm  = OpenBib::VirtualSearch::Util::conv2autoplus($hstnorm)  if ($hst);
        $kornorm  = OpenBib::VirtualSearch::Util::conv2autoplus($kornorm)  if ($kor);
        $swtnorm  = OpenBib::VirtualSearch::Util::conv2autoplus($swtnorm)  if ($swt);
        $isbnnorm = OpenBib::VirtualSearch::Util::conv2autoplus($isbnnorm) if ($isbn);
        $issnnorm = OpenBib::VirtualSearch::Util::conv2autoplus($issnnorm) if ($issn);
    }

    # Spezielle Trunkierungen

    $signnorm      =~s/\*$/%/;
    $notationnorm  =~s/\*$/%/;
    $hststringnorm =~s/\*$/%/;
    
    my $searchquery_ref={
        fs => {
            val   => $fs,
            norm  => $fsnorm,
            bool  => '',
        },
        verf => {
            val   => $verf,
            norm  => $verfnorm,
            bool  => $boolverf,
        },
        hst => {
            val   => $hst,
            norm  => $hstnorm,
            bool  => $boolhst,
        },
        hststring => {
            val   => $hststring,
            norm  => $hststringnorm,
            bool  => $boolhststring,
        },
        swt => {
            val   => $swt,
            norm  => $swtnorm,
            bool  => $boolswt,
        },
        kor => {
            val   => $kor,
            norm  => $kornorm,
            bool  => $boolkor,
        },
        sign => {
            val   => $sign,
            norm  => $signnorm,
            bool  => $boolsign,
        },
        isbn => {
            val   => $isbn,
            norm  => $isbnnorm,
            bool  => $boolisbn,
        },
        issn => {
            val   => $issn,
            norm  => $issnnorm,
            bool  => $boolissn,
        },
        mart => {
            val   => $mart,
            norm  => $martnorm,
            bool  => $boolmart,
        },
        notation => {
            val   => $notation,
            norm  => $notationnorm,
            bool  => $boolnotation,
        },
        ejahr => {
            val   => $ejahr,
            norm  => $ejahrnorm,
            bool  => $boolejahr,
            arg   => $ejahrop,
        },
    };
    
    return $searchquery_ref;
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
        $content=~s/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/$1$2$3$4$5$6$7$8/g;
    }

    # Stopwoerter fuer versch. Kategorien ausfiltern (Titel-String)

    if ($category eq "0304" || $category eq "0310" || $category eq "0331"
            || $category eq "0341" || $category eq "0370"){

        $content=~s/¬//g;
        $content=~s/\s+$//;
        $content=~s/\s+<.*?>//g;

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

 # Navigationsselement zwecks Sortierung einer Trefferliste erzeugen
 OpenBib::Common::Util::get_sort_nav($r,'',0);

 # Komplette Seite aus Template $templatename, Template-Daten $ttdata und
 # Request-Objekt $r bilden und ausgeben
 OpenBib::Common::Util::print_page($templatename,$ttdata,$r);

=head1 EXPORT

 Es werden keine Funktionen exportiert. Alle Funktionen muessen
 vollqualifiziert verwendet werden.  Bei mod_perl bedeutet dieser
 Verzicht auf den Exporter weniger Speicherverbrauch und mehr
 Performance auf Kosten von etwas mehr Schreibarbeit.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
