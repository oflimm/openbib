#####################################################################
#
#  OpenBib::Admin
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

package OpenBib::Admin;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Digest::MD5;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Session;

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

    my $session;
    
    if ($query->param('sessionID')){
        $session   = new OpenBib::Session({
            sessionID => $query->param('sessionID'),
        });
    }
    else {
        $session = new OpenBib::Session();
    }
  
    # Standardwerte festlegen
  
    my $adminuser   = $config->{adminuser};
    my $adminpasswd = $config->{adminpasswd};

    # Main-Actions
    my $do_login        = $query->param('do_login')        || '';
    my $do_loginmask    = $query->param('do_loginmask')    || '';
    my $do_showcat      = $query->param('do_showcat')      || '';
    my $do_editcat      = $query->param('do_editcat')      || '';
    my $do_editcat_rss  = $query->param('do_editcat_rss')  || '';
    my $do_showviews    = $query->param('do_showviews')    || '';
    my $do_editview     = $query->param('do_editview')     || '';
    my $do_editview_rss = $query->param('do_editview_rss') || '';
    my $do_showimx      = $query->param('do_showimx')      || '';
    my $do_showsessions = $query->param('do_showsessions') || '';
    my $do_editsession  = $query->param('do_editsession')  || '';
    my $do_logout       = $query->param('do_logout')       || '';

    # Sub-Actions
    my $do_new          = $query->param('do_new')          || '';
    my $do_del          = $query->param('do_del')          || '';
    my $do_change       = $query->param('do_change')       || '';
    my $do_edit         = $query->param('do_edit')         || '';
    my $do_show         = $query->param('do_show')         || '';

    my $user            = $query->param('user')            || '';
    my $passwd          = $query->param('passwd')          || '';
    my $dbid            = $query->param('dbid')            || '';
    my $orgunit         = $query->param('orgunit')         || '';
    my $description     = $query->param('description')     || '';
    my $shortdesc       = $query->param('shortdesc')       || '';
    my $system          = $query->param('system')          || '';
    my $dbname          = $query->param('dbname')          || '';
    my $sigel           = $query->param('sigel')           || '';
    my $url             = $query->param('url')             || '';
    my $active          = $query->param('active')          || '';

    my $viewname        = $query->param('viewname')        || '';
    my @viewdb          = ($query->param('viewdb'))?$query->param('viewdb'):();
    my $viewid          = $query->param('viewid')          || '';

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

    my @rssfeeds        = ($query->param('rssfeeds'))?$query->param('rssfeeds'):();

    
    my $primrssfeed     = $query->param('primrssfeed')     || '';
    my $rsstype         = $query->param('rss_type')        || '';

    my $singlesessionid = $query->param('singlesessionid') || '';

    my $rssid           = $query->param('rssid') || '';
    my @rssids          = ($query->param('rssids'))?$query->param('rssids'):();

    my $queryoptions_ref
        = $session->get_queryoptions($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
  
    my $dbinforesult=$config->{dbh}->prepare("select dbname,description from dbinfo where active=1 order by description") or $logger->error($DBI::errstr);
    $dbinforesult->execute() or $logger->error($DBI::errstr);
  
    my @dbnames=();
  
    my $singledbname="";
    while (my $result=$dbinforesult->fetchrow_hashref()) {
        my $dbname      = decode_utf8($result->{'dbname'});
        my $description = decode_utf8($result->{'description'});
    
        $singledbname={
            dbname      => $dbname,
            description => $description,
        };
    
        push @dbnames, $singledbname;
    }
  
    $dbinforesult->finish();

    # Expliziter aufruf und default bei keiner Parameteruebergabe
    if ($do_loginmask || ($r->method eq "GET" && ! scalar $r->args) ) {
    
        # TT-Data erzeugen
    
        my $ttdata={
            stylesheet => $stylesheet,
            config     => $config,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_login_tname},$ttdata,$r);
        return OK;
    }
  
    ###########################################################################
    elsif ($do_login) {
    
        # Sessionid erzeugen
        if ($user ne $adminuser) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben als Benutzer entweder keinen oder nicht den Admin-Benutzer eingegeben"),$r,$msg);
            return OK;
        }
    
        if ($passwd ne $adminpasswd) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben ein falsches Passwort eingegeben"),$r,$msg);
            return OK;
        }

        # Session ist nun authentifiziert und wird mit dem Admin 
        # assoziiert.
        my $idnresult=$session->{dbh}->prepare("update session set benutzernr = ? where sessionID = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($adminuser,$session->{ID}) or $logger->error($DBI::errstr);

        # TT-Data erzeugen
        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            config     => $config,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_loggedin_tname},$ttdata,$r);
        return OK;
    }
  
    # Ab hier gehts nur weiter mit korrekter SessionID
  
    # Admin-SessionID ueberpruefen
    my $idnresult=$session->{dbh}->prepare("select count(*) as rowcount from session where benutzernr = ? and sessionid = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($adminuser,$session->{ID}) or $logger->error($DBI::errstr);
    my $res=$idnresult->fetchrow_hashref;

    my $rows=$res->{rowcount};

    $idnresult->finish;
  
    if ($rows <= 0) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"),$r,$msg);
        return OK;
    }
  
    ###########################################################################
    if ($do_editcat) {
    
        # Zuerst schauen, ob Aktionen gefordert sind
        if ($do_del) {
            my $idnresult=$config->{dbh}->prepare("delete from dbinfo where dbname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $idnresult=$config->{dbh}->prepare("delete from titcount where dbname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $idnresult=$config->{dbh}->prepare("delete from dboptions where dbname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $idnresult->finish();
      
            # Und nun auch die Datenbank komplett loeschen
            system("$config->{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showcat=1");
            return OK;

        }
        elsif ($do_change) {
            my $idnresult=$config->{dbh}->prepare("update dbinfo set orgunit = ?, description = ?, shortdesc = ?, system = ?, dbname = ?, sigel = ?, url = ?, active = ? where dbid = ?") or $logger->error($DBI::errstr); # 
            $idnresult->execute($orgunit,$description,$shortdesc,$system,$dbname,$sigel,$url,$active,$dbid) or $logger->error($DBI::errstr);
            $idnresult->finish();

            $idnresult=$config->{dbh}->prepare("update dboptions set protocol = ?, host = ?, remotepath = ?, remoteuser = ?, remotepasswd = ?, titfilename = ?, autfilename = ?, korfilename = ?, swtfilename = ?, notfilename = ?, mexfilename = ?, filename = ?, autoconvert = ?, circ = ?, circurl = ?, circcheckurl = ?, circdb = ? where dbname= ?") or $logger->error($DBI::errstr);
            $idnresult->execute($protocol,$host,$remotepath,$remoteuser,$remotepasswd,$titfilename,$autfilename,$korfilename,$swtfilename,$notfilename,$mexfilename,$filename,$autoconvert,$circ,$circurl,$circcheckurl,$circdb,$dbname) or $logger->error($DBI::errstr);
            $idnresult->finish();

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showcat=1");
            return OK;
        }
        elsif ($do_new) {

            if ($dbname eq "" || $description eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Katalognamen und eine Beschreibung eingeben."),$r,$msg);

                $idnresult->finish();
                return OK;
            }

            my $idnresult=$config->{dbh}->prepare("select count(dbid) as rowcount from dbinfo where dbname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);

            my $res=$idnresult->fetchrow_hashref;
            my $rows=$res->{rowcount};
            
            if ($rows > 0) {

                OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein Katalog unter diesem Namen"),$r,$msg);

                $idnresult->finish();
                return OK;
            }

            $idnresult=$config->{dbh}->prepare("insert into dbinfo values (NULL,?,?,?,?,?,?,?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($orgunit,$description,$shortdesc,$system,$dbname,$sigel,$url,$active) or $logger->error($DBI::errstr);
            $idnresult=$config->{dbh}->prepare("insert into titcount values (?,'0')") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $idnresult=$config->{dbh}->prepare("insert into dboptions values (?,'','','','','','','','','','','','',0,0,'','','')") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $idnresult->finish();
      
            # Und nun auch die Datenbank zuerst komplett loeschen (falls vorhanden)
            system("$config->{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
      
            # ... und dann wieder anlegen
            system("$config->{tool_dir}/createpool.pl $dbname > /dev/null 2>&1");

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showcat=1");
            return OK;
        }
        elsif ($do_edit) {
            my $idnresult=$config->{dbh}->prepare("select * from dbinfo where dbid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbid) or $logger->error($DBI::errstr);
      
            my $result=$idnresult->fetchrow_hashref();
      
            my $dbid        = decode_utf8($result->{'dbid'});
            my $orgunit     = decode_utf8($result->{'orgunit'});
            my $description = decode_utf8($result->{'description'});
            my $shortdesc   = decode_utf8($result->{'shortdesc'});
            my $system      = decode_utf8($result->{'system'});
            my $dbname      = decode_utf8($result->{'dbname'});
            my $sigel       = decode_utf8($result->{'sigel'});
            my $url         = decode_utf8($result->{'url'});
            my $active      = decode_utf8($result->{'active'});

            $idnresult=$config->{dbh}->prepare("select * from dboptions where dbname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            $result=$idnresult->fetchrow_hashref();

            my $host         = decode_utf8($result->{'host'});
            my $protocol     = decode_utf8($result->{'protocol'});
            my $remotepath   = decode_utf8($result->{'remotepath'});
            my $remoteuser   = decode_utf8($result->{'remoteuser'});
            my $remotepasswd = decode_utf8($result->{'remotepasswd'});
            my $filename     = decode_utf8($result->{'filename'});
            my $titfilename  = decode_utf8($result->{'titfilename'});
            my $autfilename  = decode_utf8($result->{'autfilename'});
            my $korfilename  = decode_utf8($result->{'korfilename'});
            my $swtfilename  = decode_utf8($result->{'swtfilename'});
            my $notfilename  = decode_utf8($result->{'notfilename'});
            my $mexfilename  = decode_utf8($result->{'mexfilename'});
            my $autoconvert  = decode_utf8($result->{'autoconvert'});
            my $circ         = decode_utf8($result->{'circ'});
            my $circurl      = decode_utf8($result->{'circurl'});
            my $circcheckurl = decode_utf8($result->{'circcheckurl'});
            my $circdb       = decode_utf8($result->{'circdb'});

            my $rssfeed_ref  = {};
            $idnresult=$config->{dbh}->prepare("select * from rssfeeds where dbname = ? order by type,subtype") or $logger->error($DBI::errstr);
            $idnresult->execute($dbname) or $logger->error($DBI::errstr);
            while (my $result=$idnresult->fetchrow_hashref()){
                my $type         = $result->{'type'};
                my $subtype      = $result->{'subtype'};
                my $subtypedesc  = $result->{'subtypedesc'};
                my $active       = $result->{'active'};

                push @{$rssfeed_ref->{$type}}, {
                    subtype     => $subtype,
                    subtypedesc => $subtypedesc,
                    active      => $active
                };
            }
            
            my $katalog={
                dbid        => $dbid,
                orgunit     => $orgunit,
                description => $description,
                shortdesc   => $shortdesc,
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

                rssfeeds    => $rssfeed_ref,
            };
      
      
            my $ttdata={
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
		  
                katalog    => $katalog,
		  
                config     => $config,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editcat_tname},$ttdata,$r);
        }
    }
    elsif ($do_editcat_rss){
        
        if ($do_change) {
            my $request=$config->{dbh}->prepare("update rssfeeds set dbname = ?, type = ?, active = ? where id = ?") or $logger->error($DBI::errstr);
            $request->execute($dbname,$rsstype,$active,$rssid) or $logger->error($DBI::errstr);
            $request->finish();
            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_editcat_rss=1&dbid=$dbid&dbname=$dbname&do_edit=1");
            return OK;
        }
        elsif ($do_new){
            my $request=$config->{dbh}->prepare("insert into rssfeeds values (NULL,?,?,-1,'',0)") or $logger->error($DBI::errstr);
            $request->execute($dbname,$rsstype) or $logger->error($DBI::errstr);
            $request->finish();
            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_editcat_rss=1&dbid=$dbid&dbname=$dbname&do_edit=1");
            return OK;              
        }
        
        if ($do_edit) {
            my $request=$config->{dbh}->prepare("select * from dbinfo where dbid = ?") or $logger->error($DBI::errstr);
            $request->execute($dbid) or $logger->error($DBI::errstr);
            
            my $result=$request->fetchrow_hashref();
            
            my $dbid        = decode_utf8($result->{'dbid'});
            my $dbname      = decode_utf8($result->{'dbname'});
            
            my $rssfeed_ref=[];
            
            $request=$config->{dbh}->prepare("select * from rssfeeds where dbname = ? order by type,subtype") or $logger->error($DBI::errstr);
            $request->execute($dbname) or $logger->error($DBI::errstr);
            while (my $result=$request->fetchrow_hashref()){
                my $id           = decode_utf8($result->{'id'});
                my $type         = decode_utf8($result->{'type'});
                my $subtype      = decode_utf8($result->{'subtype'});
                my $subtypedesc  = decode_utf8($result->{'subtypedesc'});
                my $active       = decode_utf8($result->{'active'});
                
                push @$rssfeed_ref, {
                    id          => $id,
                    type        => $type,
                    subtype     => $subtype,
                    subtypedesc => $subtypedesc,
                    active      => $active
                };
            }

            $request->finish();
            
            my $katalog={
                dbid        => $dbid,
                dbname      => $dbname,
                rssfeeds    => $rssfeed_ref,
            };
            
            
            my $ttdata={
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
                
                katalog    => $katalog,
                
                config     => $config,
                msg        => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_admin_editcat_rss_tname},$ttdata,$r);
        }
    }
    elsif ($do_showcat) {
        my @kataloge=();

        my $idnresult=$config->{dbh}->prepare("select dbinfo.*,titcount.count,dboptions.autoconvert from dbinfo,titcount,dboptions where dbinfo.dbname=titcount.dbname and titcount.dbname=dboptions.dbname order by orgunit,dbname") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);

        my $katalog;
        while (my $result=$idnresult->fetchrow_hashref()) {
            my $dbid        = decode_utf8($result->{'dbid'});
            my $orgunit     = decode_utf8($result->{'orgunit'});
            my $autoconvert = decode_utf8($result->{'autoconvert'});

            my $orgunits_ref=$config->{orgunits};

            my @orgunits=@$orgunits_ref;

            foreach my $unit_ref (@orgunits) {
                my %unit=%$unit_ref;
                if ($unit{short} eq $orgunit) {
                    $orgunit=$unit{desc};
                }
            }

            my $description = decode_utf8($result->{'description'});
            my $system      = decode_utf8($result->{'system'});
            my $dbname      = decode_utf8($result->{'dbname'});
            my $sigel       = decode_utf8($result->{'sigel'});
            my $url         = decode_utf8($result->{'url'});
            my $active      = decode_utf8($result->{'active'});
            my $count       = decode_utf8($result->{'count'});

            if (!$description) {
                $description="Keine Bezeichnung";
            }

            $katalog={
		dbid        => $dbid,
		orgunit     => $orgunit,
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
            sessionID  => $session->{ID},
            kataloge   => \@kataloge,

            config     => $config,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showcat_tname},$ttdata,$r);

        $idnresult->finish();
    }
    elsif ($do_showviews) {
        my @views=();

        my $view="";

        my $idnresult=$config->{dbh}->prepare("select * from viewinfo order by viewname") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);
        while (my $result=$idnresult->fetchrow_hashref()) {
            my $viewid      = decode_utf8($result->{'viewid'});
            my $viewname    = decode_utf8($result->{'viewname'});
            my $description = decode_utf8($result->{'description'});
            my $active      = decode_utf8($result->{'active'});

            $active="Ja" if ($active eq "1");
            $active="Nein" if ($active eq "0");
      
            my $idnresult2=$config->{dbh}->prepare("select * from viewdbs where viewname = ? order by dbname") or $logger->error($DBI::errstr);
            $idnresult2->execute($viewname);
      
            my @viewdbs=();
            while (my $result2=$idnresult2->fetchrow_hashref()) {
                my $dbname = decode_utf8($result2->{'dbname'});
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
            sessionID  => $session->{ID},
            views      => \@views,
            config     => $config,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showviews_tname},$ttdata,$r);
    
        $idnresult->finish();
    
    }
    elsif ($do_editview) {
    
        # Zuerst schauen, ob Aktionen gefordert sind
    
        if ($do_del) {
            my $idnresult=$config->{dbh}->prepare("delete from viewinfo where viewid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewid) or $logger->error($DBI::errstr);
            $idnresult=$config->{dbh}->prepare("delete from viewdbs where viewname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname) or $logger->error($DBI::errstr);
            $idnresult->finish();
            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showviews=1");
            return OK;
      
        }
        elsif ($do_change) {

            # Zuerst die Aenderungen in der Tabelle Viewinfo vornehmen

            my $idnresult=$config->{dbh}->prepare("update viewinfo set viewname = ?, description = ?, active = ? where viewid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname,$description,$active,$viewid) or $logger->error($DBI::errstr);

            # Primary RSS-Feed fuer Autodiscovery eintragen
            if ($primrssfeed){
                $idnresult=$config->{dbh}->prepare("update viewinfo set primrssfeed = ? where viewid = ?") or $logger->error($DBI::errstr);
                $idnresult->execute($primrssfeed,$viewid) or $logger->error($DBI::errstr);
            }
            
            # Datenbanken zunaechst loeschen

            $idnresult=$config->{dbh}->prepare("delete from viewdbs where viewname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname) or $logger->error($DBI::errstr);

      
            # Dann die zugehoerigen Datenbanken eintragen
            foreach my $singleviewdb (@viewdb) {
                $idnresult=$config->{dbh}->prepare("insert into viewdbs values (?,?)") or $logger->error($DBI::errstr);
                $idnresult->execute($viewname,$singleviewdb) or $logger->error($DBI::errstr);
            }

            # RSS-Feeds zunaechst loeschen
            $idnresult=$config->{dbh}->prepare("delete from viewrssfeeds where viewname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname) or $logger->error($DBI::errstr);

            # Dann die zugehoerigen Feeds eintragen
            foreach my $singleviewrssfeed (@rssfeeds) {
                $idnresult=$config->{dbh}->prepare("insert into viewrssfeeds values (?,?)") or $logger->error($DBI::errstr);
                $idnresult->execute($viewname,$singleviewrssfeed) or $logger->error($DBI::errstr);
            }

            
            $idnresult->finish();

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showviews=1");
      
            return OK;
        }
        elsif ($do_new) {

            if ($viewname eq "" || $description eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Viewnamen und eine Beschreibung eingeben."),$r,$msg);

                $idnresult->finish();
                return OK;
            }


            my $idnresult=$config->{dbh}->prepare("select count(*) as rowcount from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname) or $logger->error($DBI::errstr);
            my $res=$idnresult->fetchrow_hashref;
            my $rows=$res->{rowcount};

            if ($rows > 0) {

                OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"),$r,$msg);

                $idnresult->finish();
                return OK;
            }
      
            $idnresult=$config->{dbh}->prepare("insert into viewinfo values (NULL,?,?,?)") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname,$description,$active) or $logger->error($DBI::errstr);



            $idnresult=$config->{dbh}->prepare("select viewid from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname);


            $res       = $idnresult->fetchrow_hashref();
            my $viewid = decode_utf8($res->{viewid});

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_editview=1&do_edit=1&viewid=$viewid");
            return OK;
        }
        elsif ($do_edit) {


            my $idnresult=$config->{dbh}->prepare("select * from viewinfo where viewid = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewid) or $logger->error($DBI::errstr);
      
            my $result=$idnresult->fetchrow_hashref();

            my $viewid      = decode_utf8($result->{'viewid'});
            my $viewname    = decode_utf8($result->{'viewname'});
            my $description = decode_utf8($result->{'description'});
            my $primrssfeed = decode_utf8($result->{'primrssfeed'});
            my $active      = decode_utf8($result->{'active'});

            $idnresult=$config->{dbh}->prepare("select * from viewdbs where viewname = ? order by dbname") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname) or $logger->error($DBI::errstr);
      
            my @viewdbs=();
            while (my $result=$idnresult->fetchrow_hashref()) {
                my $dbname = decode_utf8($result->{'dbname'});
                push @viewdbs, $dbname;
            }

            $idnresult=$config->{dbh}->prepare("select * from rssfeeds order by dbname,type,subtype") or $logger->error($DBI::errstr);
            $idnresult->execute() or $logger->error($DBI::errstr);
      
            my @allrssfeeds=();
            while (my $result=$idnresult->fetchrow_hashref()) {
                push @allrssfeeds, {
                    feedid      => decode_utf8($result->{'id'}),
                    dbname      => decode_utf8($result->{'dbname'}),
                    type        => decode_utf8($result->{'type'}),
                    subtype     => decode_utf8($result->{'subtype'}),
                    subtypedesc => decode_utf8($result->{'subtypedesc'}),
                };
            }


            $idnresult=$config->{dbh}->prepare("select rssfeed from viewrssfeeds where viewname=?") or $logger->error($DBI::errstr);
            $idnresult->execute($viewname) or $logger->error($DBI::errstr);
      
            my %viewrssfeed=();
            while (my $result=$idnresult->fetchrow_hashref()) {
                my $rssfeed = $result->{'rssfeed'};
                $viewrssfeed{$rssfeed}=1;
            }


            $idnresult->finish();

            my $view={
		viewid       => $viewid,
		viewname     => $viewname,
		description  => $description,
		active       => $active,
		viewdbs      => \@viewdbs,
                allrssfeeds  => \@allrssfeeds,
                viewrssfeed  => \%viewrssfeed,
                primrssfeed  => $primrssfeed,
            };

            my $ttdata={
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
		  
                dbnames    => \@dbnames,

                view       => $view,
		  
                config     => $config,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editview_tname},$ttdata,$r);
      
        }
    
    }
    elsif ($do_editview_rss){

      if ($do_change) {
          if ($rsstype eq "primary"){
              my $request=$config->{dbh}->prepare("update viewinfo set rssfeed = ? where viewid = ?") or $logger->error($DBI::errstr);
              $request->execute($rssid,$viewid) or $logger->error($DBI::errstr);
              $request->finish();
              $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&action=editviewrss&viewid=$viewid&viewrssaction=Bearbeiten");
              return OK;
          }
          elsif ($rsstype eq "all") {
              my $request=$config->{dbh}->prepare("delete from viewrssfeeds where viewname = ?");
              $request->execute($viewname);

              $request=$config->{dbh}->prepare("insert into viewrssfeeds values (?,?)") or $logger->error($DBI::errstr);
              foreach my $rssid (@rssids){
                  $request->execute($viewname,$rssid) or $logger->error($DBI::errstr);
              }
              $request->finish();
              $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&action=editviewrss&viewid=$viewid&viewrssaction=Bearbeiten");
              return OK;
          }
      }
      elsif ($do_new){
          my $request=$config->{dbh}->prepare("insert into rssfeeds values (NULL,?,?,-1,'',0)") or $logger->error($DBI::errstr);
          $request->execute($dbname,$rsstype) or $logger->error($DBI::errstr);
          $request->finish();
          $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&action=editcatrss&dbid=$dbid&dbname=$dbname&catrssaction=Bearbeiten");
          return OK;
      }
      elsif ($do_edit) {
          my $request=$config->{dbh}->prepare("select * from viewinfo where viewid=?") or $logger->error($DBI::errstr);
          $request->execute($viewid) or $logger->error($DBI::errstr);
          
          my $result=$request->fetchrow_hashref();
          
          my $viewid        = decode_utf8($result->{'viewid'});
          my $viewname      = decode_utf8($result->{'viewname'});
          my $viewdesc      = decode_utf8($result->{'description'});
          my $primrssfeed   = decode_utf8($result->{'rssfeed'});
          
          my $allrssfeed_ref=[];
          
          $request=$config->{dbh}->prepare("select rssfeeds.id, rssfeeds.dbname, dbinfo.description, rssfeeds.type, rssfeeds.active  from rssfeeds,dbinfo where rssfeeds.dbname=dbinfo.dbname order by dbinfo.description,rssfeeds.type,rssfeeds.subtype") or $logger->error($DBI::errstr);
          $request->execute() or $logger->error($DBI::errstr);
          while (my $result=$request->fetchrow_hashref()){
              my $id           = decode_utf8($result->{'id'});
              my $dbname       = decode_utf8($result->{'dbname'});
              my $description  = decode_utf8($result->{'description'});
              my $type         = decode_utf8($result->{'type'});
              my $subtype      = decode_utf8($result->{'subtype'});
              my $subtypedesc  = decode_utf8($result->{'subtypedesc'});
              my $active       = decode_utf8($result->{'active'});
              
              push @$allrssfeed_ref, {
                  id          => $id,
                  dbname      => $dbname,
                  description => $description,
                  type        => $type,
                  subtype     => $subtype,
                  subtypedesc => $subtypedesc,
                  active      => $active
              };
          }

          my $viewrssfeeds_ref={};
          
          $request=$config->{dbh}->prepare("select * from viewrssfeeds where viewname = ?") or $logger->error($DBI::errstr);
          $request->execute($viewname) or $logger->error($DBI::errstr);
          while (my $result=$request->fetchrow_hashref()){
              my $rssfeedid        = decode_utf8($result->{'rssfeed'});
              $viewrssfeeds_ref->{$rssfeedid}=1;
          }


          my $view={
              id          => $viewid,
              name        => $viewname,
              description => $viewdesc,
              primrssfeed => $primrssfeed,
              rssfeeds    => $viewrssfeeds_ref,
          };
          
          
          my $ttdata={
              stylesheet  => $stylesheet,
              sessionID   => $session->{ID},
              
              view        => $view,

              allrssfeeds => $allrssfeed_ref,

              config      => $config,
              msg         => $msg,
          };
          
          OpenBib::Common::Util::print_page($config->{tt_admin_editview_rss_tname},$ttdata,$r);
      }
  }
    elsif ($do_showimx) {

        my @kataloge=();

        my $idnresult=$config->{dbh}->prepare("select dbinfo.*,titcount.count from dbinfo,titcount where dbinfo.dbname=titcount.dbname order by orgunit,dbname") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);

        my $katalog;
        while (my $result=$idnresult->fetchrow_hashref()) {
            my $dbid    = decode_utf8($result->{'dbid'});
            my $orgunit = decode_utf8($result->{'orgunit'});

            my $orgunits_ref=$config->{orgunits};

            my @orgunits=@$orgunits_ref;

            foreach my $unit_ref (@orgunits) {
                my %unit=%$unit_ref;
                if ($unit{short} eq $orgunit) {
                    $orgunit=$unit{desc};
                }
            }

            my $description = decode_utf8($result->{'description'});
            my $system      = decode_utf8($result->{'system'});
            my $dbname      = decode_utf8($result->{'dbname'});
            my $sigel       = decode_utf8($result->{'sigel'});
            my $url         = decode_utf8($result->{'url'});
            my $active      = decode_utf8($result->{'active'});

            $active="Ja"   if ($active eq "1");
            $active="Nein" if ($active eq "0");

            my $count       = decode_utf8($result->{'count'});

            $katalog={
		dbid        => $dbid,
		orgunit     => $orgunit,
		description => $description,
		system      => $system,
		dbname      => $dbname,
		sigel       => $sigel,
		active      => $active,
		url         => $url,
		count       => $count,
            };

            push @kataloge, $katalog;
        }

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            kataloge   => \@kataloge,

            config     => $config,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showimx_tname},$ttdata,$r);

        $idnresult->finish();
    }
    elsif ($do_showsessions) {

        my $idnresult=$session->{dbh}->prepare("select * from session order by createtime") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);
        my $session="";
        my @sessions=();

        while (my $result=$idnresult->fetchrow_hashref()) {
            my $singlesessionid = decode_utf8($result->{'sessionid'});
            my $createtime      = decode_utf8($result->{'createtime'});
            my $benutzernr      = decode_utf8($result->{'benutzernr'});

            my $idnresult2=$session->{dbh}->prepare("select count(*) as rowcount from queries where sessionid = ?") or $logger->error($DBI::errstr);
            $idnresult2->execute($singlesessionid) or $logger->error($DBI::errstr);

            my $res2=$idnresult2->fetchrow_hashref;
            my $numqueries=$res2->{rowcount};

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
            sessionID  => $session->{ID},
	         
            sessions   => \@sessions,

            config     => $config,
            msg        => $msg,
        };

        OpenBib::Common::Util::print_page($config->{tt_admin_showsessions_tname},$ttdata,$r);
        return OK;
    }
    elsif ($do_editsession) {

        if ($do_show) {
            my $idnresult=$session->{dbh}->prepare("select * from session where sessionID = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($singlesessionid) or $logger->error($DBI::errstr);

            my $result=$idnresult->fetchrow_hashref();
            my $createtime = decode_utf8($result->{'createtime'});
            my $benutzernr = decode_utf8($result->{'benutzernr'});

            my $idnresult2=$session->{dbh}->prepare("select * from queries where sessionid = ?") or $logger->error($DBI::errstr);
            $idnresult2->execute($singlesessionid) or $logger->error($DBI::errstr);

            my $numqueries=0;

            my @queries=();
            my $singlequery="";
            while (my $result2=$idnresult2->fetchrow_hashref()) {
                my $dbases = decode_utf8($result2->{'dbases'});
                $dbases=~s/\|\|/ ; /g;
                
                push @queries, {
                    id          => decode_utf8($result2->{queryid}),
                    searchquery => Storable::thaw(pack "H*",$result2->{query}),
                    hits        => decode_utf8($result2->{hits}),
                    dbases      => $dbases,
                };

                $numqueries++;
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
                sessionID  => $session->{ID},
	         
                session    => $session,

                queries    => \@queries,

                config     => $config,
                msg        => $msg,
            };

            OpenBib::Common::Util::print_page($config->{tt_admin_editsession_tname},$ttdata,$r);

            $idnresult->finish;
            $idnresult2->finish;
            return OK;
        }
    }
    elsif ($do_logout) {

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            
            config     => $config,
            msg        => $msg,
        };
      
        OpenBib::Common::Util::print_page($config->{tt_admin_logout_tname},$ttdata,$r);

        my $idnresult=$session->{dbh}->prepare("delete from session where benutzernr = ? and sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($adminuser,$session->{ID}) or $logger->error($DBI::errstr);

    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Keine gültige Aktion oder Session"),$r,$msg);
    }
  
  LEAVEPROG: sleep 0;
  
    return OK;
}


1;
