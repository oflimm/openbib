#####################################################################
#
#  OpenBib::Common::Util
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
                sorttype  => undef,
                sortorder => undef,
                hitrange  => undef,
                offset    => undef,
                maxhits   => undef,
                lang      => undef,
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

    my $query=Apache::Request->new($r);
    my $view=($query->param('view'))?$query->param('view'):undef;

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

    my $request=$sessiondbh->prepare("select queryoptions from session where sessionid = ?") or $logger->error($DBI::errstr);

    $request->execute($sessionID) or $logger->error($DBI::errstr);
  
    my $res=$request->fetchrow_hashref();

    $request->finish();

    return YAML::Load($res->{queryoptions});
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
    my ($sessiondbh,$r) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $query=Apache::Request->new($r);

    my $sessionID=$query->param('sessionID');
    
    # Queryoptions zur Session einladen (default: alles undef)
    my $queryoptions_ref = load_queryoptions($sessiondbh,$sessionID);

    my $default_queryoptions_ref={
        sorttype  => 'author',
        sortorder => 'up',
        hitrange  => 20,
        offset    => 1,
        maxhits   => 500,
        lang      => 'de',
        profil    => '',
        autoplus  => '',
    };

    # Abgleich mit uebergebenen Parametern
    # Uebergene Parameter 'ueberschreiben' bestehende werden
    # (undef oder gesetzt)
    foreach my $option (keys %$queryoptions_ref){
        if (defined $query->param($option)){
            $queryoptions_ref->{$option}=$query->param($option);
        }
    }

    # Abgleich mit Default-Werten:
    # Verbliebene "undefined"-Werte werden mit Standard-Werten belegt
    foreach my $option (keys %$queryoptions_ref){
        if (!defined $queryoptions_ref->{$option}){
            $queryoptions_ref->{$option}=$default_queryoptions_ref->{$option};
        }
    }

    dump_queryoptions($sessiondbh,$sessionID,$queryoptions_ref);
    
    return $queryoptions_ref;
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
    my ($reqarray_ref,$dbh)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my %metaidns;
    my @midns=();
    my $atime;
    my $btime;
    my $timeall;
  
    my @reqarray=@$reqarray_ref;
  
    foreach my $idnrequest (@reqarray) {
    
        if ($config{benchmark}) {
            $atime=new Benchmark;
        }
    
        my $idnresult=$dbh->prepare("$idnrequest") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error("Request: $idnrequest - ".$DBI::errstr);
    
        my @idnres;
        while (@idnres=$idnresult->fetchrow) {	    
      
            if (!$metaidns{$idnres[0]}) {
                push @midns, $idnres[0];
            }
            $metaidns{$idnres[0]}=1;
        }
        $idnresult->finish();
    
        if ($config{benchmark}) {
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
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config{tt_include_path},
        }) ],
#        INCLUDE_PATH   => $config{tt_include_path},
        ABSOLUTE       => 1,
        OUTPUT         => $r,    # Output geht direkt an Apache Request
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

sub print_info {
    my ($info,$r)=@_;

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
        }) ],
#        INCLUDE_PATH   => $config{tt_include_path},
        ABSOLUTE       => 1,
        OUTPUT         => $r,    # Output geht direkt an Apache Request
    });
  
    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
	      
        show_corporate_banner => 0,
        show_foot_banner => 0,
        invisible_links => 0,
	      
        info_msg     => $info,
        config     => \%config,
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
        }) ],
#        INCLUDE_PATH   => $config{tt_include_path},
        ABSOLUTE       => 1,     # Notwendig fuer Kaskadierung
        OUTPUT         => $r,    # Output geht direkt an Apache Request
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

    my %fullstring=('up'        => 'aufsteigend',
                    'down'      => 'absteigend',
                    'author'    => 'nach Autor/Körperschaft',
                    'publisher' => 'nach Verlag',
                    'signature' => 'nach Signatur',
                    'title'     => 'nach Titel',
                    'yearofpub' => 'nach Erscheinungsjahr'
                );

    my $katalogtyp="pro Katalog";

    if ($sortall eq "1") {
        $katalogtyp="katalogübergreifend";
    }

    my $thissortstring=$fullstring{$sorttype}." / ".$fullstring{$sortorder};

    $thissortstring=$thissortstring." / $katalogtyp" if ($nav);

    my @sortselect=();

    if ($nav eq 'sortsingle') {
        push @sortselect, {
            val  => 0,
            desc => "pro Katalog",
        };
    }
    elsif ($nav eq 'sortall') {
        push @sortselect, {
            val  => 1,
            desc => "katalogübergreifend",
        };
    }
    elsif ($nav eq 'sortboth') {
        push @sortselect, {
            val  => 0,
            desc => "pro Katalog",
        };

        push @sortselect, {
            val  => 1,
            desc => "katalogübergreifend",
        };
    }

    return ($queryargs_ref,\@sortselect,$thissortstring);
}

sub by_yearofpub {
    my %line1=%$a;
    my %line2=%$b;

    my ($line1)=$line1{T0425}[0]{content}=~m/(\d\d\d\d)/;
    my ($line2)=$line2{T0425}[0]{content}=~m/(\d\d\d\d)/;
  
    $line1=0 if (!$line1{T0425}[0]{content});
    $line2=0 if (!$line2{T0425}[0]{content});

    $line1 <=> $line2;
}

sub by_yearofpub_down {
    my %line1=%$a;
    my %line2=%$b;

    my ($line1)=$line1{T0425}[0]{content}=~m/(\d\d\d\d)/;
    my ($line2)=$line2{T0425}[0]{content}=~m/(\d\d\d\d)/;

    $line1=0 if (!$line1{T0425}[0]{content});
    $line2=0 if (!$line2{T0425}[0]{content});

    $line2 <=> $line1;
}


sub by_publisher {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=cleanrl($line1{T0412}[0]{content}) if ($line1{T0412}[0]{content});
    my $line2=cleanrl($line2{T0412}[0]{content}) if ($line2{T0412}[0]{content});

    $line1 cmp $line2;
}

sub by_publisher_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=cleanrl($line1{T0412}[0]{content}) if ($line1{T0412}[0]{content});
    my $line2=cleanrl($line2{T0412}[0]{content}) if ($line2{T0412}[0]{content});

    $line2 cmp $line1;
}

sub by_signature {
    my %line1=%$a;
    my %line2=%$b;

    # Sortierung anhand erster Signatur
    my $line1=cleanrl($line1{X0014}[0]{content}) if ($line1{X0014}[0]{content});
    my $line2=cleanrl($line2{X0014}[0]{content}) if ($line2{X0014}[0]{content});

    $line1 cmp $line2;
}

sub by_signature_down {
    my %line1=%$a;
    my %line2=%$b;

    # Sortierung anhand erster Signatur
    my $line1=cleanrl($line1{X0014}[0]{content}) if ($line1{X0014}[0]{content});
    my $line2=cleanrl($line2{X0014}[0]{content}) if ($line2{X0014}[0]{content});

    $line2 cmp $line1;
}

sub by_author {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=cleanrl($line1{PC0001}[0]{content}) if ($line1{PC0001}[0]{content});
    my $line2=cleanrl($line2{PC0001}[0]{content}) if ($line2{PC0001}[0]{content});

    $line1 cmp $line2;
}

sub by_author_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=cleanrl($line1{PC0001}[0]{content}) if ($line1{PC0001}[0]{content});
    my $line2=cleanrl($line2{PC0001}[0]{content}) if ($line2{PC0001}[0]{content});

    $line2 cmp $line1;
}

sub by_title {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=cleanrl($line1{T0331}[0]{content}) if ($line1{T0331}[0]{content});
    my $line2=cleanrl($line2{T0331}[0]{content}) if ($line2{T0331}[0]{content});

    $line1 cmp $line2;
}

sub by_title_down {
    my %line1=%$a;
    my %line2=%$b;

    my $line1=cleanrl($line1{T0331}[0]{content}) if ($line1{T0331}[0]{content});
    my $line2=cleanrl($line2{T0331}[0]{content}) if ($line2{T0331}[0]{content});

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
        my $katkey      = $outidx{id};
        my $resdatabase = $outidx{database};
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
  
    my $dbinforesult=$sessiondbh->prepare("select dbname,sigel,url,description from dbinfo") or $logger->error($DBI::errstr);
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
