#####################################################################
#
#  OpenBib::Handler::Apache::Admin
#
#  Dieses File ist (C) 2004-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Admin;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

sub handler {

    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $query=Apache::Request->instance($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $session;
    
    if ($query->param('sessionID')){
        $session   = OpenBib::Session->instance({
            sessionID => $query->param('sessionID'),
        });
    }
    else {
        $session = OpenBib::Session->instance;
    }

    # Standardwerte festlegen
  
    my $adminuser   = $config->{adminuser};
    my $adminpasswd = $config->{adminpasswd};

    # Main-Actions
    my $do_login        = $query->param('do_login')        || '';
    my $do_loginmask    = $query->param('do_loginmask')    || '';
    my $do_showcat      = $query->param('do_showcat')      || '';
    my $do_editcat      = $query->param('do_editcat')      || '';
    my $do_showlibinfo  = $query->param('do_showlibinfo')  || '';
    my $do_editlibinfo  = $query->param('do_editlibinfo')  || '';
    my $do_editcat_rss  = $query->param('do_editcat_rss')  || '';
    my $do_showprofiles = $query->param('do_showprofiles') || '';
    my $do_editprofile  = $query->param('do_editprofile')  || '';
    my $do_showsubjects = $query->param('do_showsubjects') || '';
    my $do_editsubject  = $query->param('do_editsubject')  || '';
    my $do_showviews    = $query->param('do_showviews')    || '';
    my $do_editview     = $query->param('do_editview')     || '';
    my $do_editview_rss = $query->param('do_editview_rss') || '';
    my $do_showimx      = $query->param('do_showimx')      || '';
    my $do_showsessions = $query->param('do_showsessions') || '';
    my $do_editsession  = $query->param('do_editsession')  || '';
    my $do_exploresessions = $query->param('do_exploresessions') || '';
    my $do_showstat     = $query->param('do_showstat')     || '';
    my $do_showuser     = $query->param('do_showuser')     || '';
    my $do_showlogintarget  = $query->param('do_showlogintarget')     || '';
    my $do_editlogintarget  = $query->param('do_editlogintarget')     || '';
    my $do_logout       = $query->param('do_logout')       || '';

    # Sub-Actions
    my $do_new          = $query->param('do_new')          || '';
    my $do_del          = $query->param('do_del')          || '';
    my $do_change       = $query->param('do_change')       || '';
    my $do_edit         = $query->param('do_edit')         || '';
    my $do_show         = $query->param('do_show')         || '';

    my $user            = $query->param('user')            || '';
    my $passwd          = $query->param('passwd')          || '';
    my $orgunit         = $query->param('orgunit')         || '';
    my $description     = decode_utf8($query->param('description'))     || '';
    my $shortdesc       = $query->param('shortdesc')       || '';
    my $system          = $query->param('system')          || '';
    my $dbname          = $query->param('dbname')          || '';
    my $sigel           = $query->param('sigel')           || '';
    my $url             = $query->param('url')             || '';
    my $use_libinfo     = $query->param('use_libinfo')     || '';
    my $active          = $query->param('active')          || '';

    my $viewname        = $query->param('viewname')        || '';
    my @viewdb          = ($query->param('viewdb'))?$query->param('viewdb'):();

    # Profile
    my $profilename     = $query->param('profilename')     || '';
    my @profiledb       = ($query->param('profiledb'))?$query->param('profiledb'):();

    my @databases       = ($query->param('database'))?$query->param('database'):();

    # dboptions
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

    my $subject         = decode_utf8($query->param('subject'))         || '';
    my $subjectid       = $query->param('subjectid')       || '';

    my @classifications     = ($query->param('classifications'))?$query->param('classifications'):();
    
    my @rssfeeds        = ($query->param('rssfeeds'))?$query->param('rssfeeds'):();
    my $primrssfeed     = $query->param('primrssfeed')     || '';
    my $rsstype         = $query->param('rss_type')        || '';

    my $singlesessionid = $query->param('singlesessionid') || '';

    my $rssid           = $query->param('rssid') || '';
    my @rssids          = ($query->param('rssids'))?$query->param('rssids'):();

    my $targetid        = $query->param('targetid')        || '';
    my $hostname        = $query->param('hostname')        || '';
    my $port            = $query->param('port')            || '';
    my $username        = $query->param('username')        || '';
    my $type            = $query->param('type')            || '';

    # Bibliotheksinfos
    my $li_0010         = $query->param('I0010')          || '';
    my $li_0020         = $query->param('I0020')          || '';
    my $li_0030         = $query->param('I0030')          || '';
    my $li_0040         = $query->param('I0040')          || '';
    my $li_0050         = $query->param('I0050')          || '';
    my $li_0060         = $query->param('I0060')          || '';
    my $li_0070         = $query->param('I0070')          || '';
    my $li_0080         = $query->param('I0080')          || '';
    my $li_0090         = $query->param('I0090')          || '';
    my $li_0100         = $query->param('I0100')          || '';
    my $li_0110         = $query->param('I0110')          || '';
    my $li_0120         = $query->param('I0120')          || '';
    my $li_0130         = $query->param('I0130')          || '';
    my $li_0140         = $query->param('I0140')          || '';
    my $li_0150         = $query->param('I0150')          || '';
    my $li_0160         = $query->param('I0160')          || '';
    my $li_0170         = $query->param('I0170')          || '';
    my $li_0180         = $query->param('I0180')          || '';
    my $li_0190         = $query->param('I0190')          || '';
    my $li_0200         = $query->param('I0200')          || '';
    my $li_0210         = $query->param('I0210')          || '';
    my $li_0220         = $query->param('I0220')          || '';
    my $li_0230         = $query->param('I0230')          || '';
    my $li_0240         = $query->param('I0240')          || '';
    my $li_0250         = $query->param('I0250')          || '';
    my $li_0260         = $query->param('I0260')          || '';
    my $li_1000         = $query->param('I1000')          || '';
    
    my $viewstart_loc   = $query->param('viewstart_loc')             || '';
    my $viewstart_stid  = $query->param('viewstart_stid')            || '';
    
    my $clientip        = $query->param('clientip') || '';

    # Von bis
    my $fromdate        = $query->param('fromdate') || '';
    my $todate          = $query->param('todate')   || '';
    my $year            = $query->param('year')     || UnixDate(ParseDate("today"),"%Y");

    # Sub-Template ID
    my $stid            = $query->param('stid') || '';

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    my $do_dist = 0;
    if (exists $config->{distadmin} && $r->get_server_name eq $config->{distadmin}{master}){
      $do_dist = 1;
    }

    # Verweis: Datenbankname -> Informationen zum zugeh"origen Institut/Seminar
  
    my @dbnames = $config->get_active_database_names();
  
    my $thisdbinfo_ref = {
        orgunit     => $orgunit,
        description => $description,
        shortdesc   => $shortdesc,
        system      => $system,
        dbname      => $dbname,
        sigel       => $sigel,
        url         => $url,
        use_libinfo => $use_libinfo,
        active      => $active,
    };
        
    my $thisdboptions_ref = {
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
        circ         => $circ,
        circurl      => $circurl,
        circcheckurl => $circcheckurl,
        circdb       => $circdb,
    };

    my $thislibinfo_ref = {
        I0010      => $li_0010,
        I0020      => $li_0020,
        I0030      => $li_0030,
        I0040      => $li_0040,
        I0050      => $li_0050,
        I0060      => $li_0060,
        I0070      => $li_0070,
        I0080      => $li_0080,
        I0090      => $li_0090,
        I0100      => $li_0100,
        I0110      => $li_0110,
        I0120      => $li_0120,
        I0130      => $li_0130,
        I0140      => $li_0140,
        I0150      => $li_0150,
        I0160      => $li_0160,
        I0170      => $li_0170,
        I0180      => $li_0180,
        I0190      => $li_0190,
        I0200      => $li_0200,
        I0210      => $li_0210,
        I0220      => $li_0220,
        I0230      => $li_0230,
        I0240      => $li_0240,
        I0250      => $li_0250,
        I0260      => $li_0260,
        I1000      => $li_1000,
    };

    my $thislogintarget_ref = {
			       id          => $targetid,
			       hostname    => $hostname,
			       port        => $port,
			       username    => $username,
			       dbname      => $dbname,
			       description => $description,
			       type        => $type,
			      };
    
    # Expliziter aufruf und default bei keiner Parameteruebergabe
    if ($do_loginmask || ($r->method eq "GET" && ! scalar $r->args) ) {
    
        # TT-Data erzeugen
    
        my $ttdata={
            stylesheet => $stylesheet,
            config     => $config,
            user       => $user,
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
        $session->set_user($adminuser);
        
        # TT-Data erzeugen
        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_loggedin_tname},$ttdata,$r);
        return OK;
    }
  
    # Ab hier gehts nur weiter mit korrekter SessionID
  
    # Admin-SessionID ueberpruefen
    my $adminsession = $session->is_authenticated_as($adminuser);

    if (!$adminsession) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"),$r,$msg);
        return OK;
    }
  
    $logger->debug("Server: ".$r->get_server_name);
    ###########################################################################
    if ($do_editcat) {
    
        # Zuerst schauen, ob Aktionen gefordert sind
        if ($do_del) {
            editcat_del($dbname);

	    my $ret_ref = dist_cmd("editcat_del",{ dbname => $dbname }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showcat=1");
            return OK;

        }
        elsif ($do_change) {
            $logger->debug("do_editcat: $do_editcat do_change: $do_change");

            $logger->debug("Info: ".YAML::Dump($thisdbinfo_ref));
            $logger->debug("Options: ".YAML::Dump($thisdboptions_ref));

            editcat_change($thisdbinfo_ref,$thisdboptions_ref);

	    my $ret_ref = dist_cmd("editcat_change",{ 
						     dbinfo    => $thisdbinfo_ref,
						     dboptions => $thisdboptions_ref,
						 }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showcat=1");
            return OK;
        }
        elsif ($do_new) {

            if ($dbname eq "" || $description eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Katalognamen und eine Beschreibung eingeben."),$r,$msg);

                return OK;
            }

            if ($config->db_exists($dbname)) {

                OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein Katalog unter diesem Namen"),$r,$msg);

                return OK;
            }

            editcat_new($thisdbinfo_ref);
            
	    my $ret_ref = dist_cmd("editcat_new",{ dbinfo => $thisdbinfo_ref }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showcat=1");
            return OK;
        }
        elsif ($do_edit) {
            my $dbinfo_ref = $config->get_dbinfo($dbname);
      
            my $orgunit     = $dbinfo_ref->{'orgunit'};
            my $description = $dbinfo_ref->{'description'};
            my $shortdesc   = $dbinfo_ref->{'shortdesc'};
            my $system      = $dbinfo_ref->{'system'};
            my $dbname      = $dbinfo_ref->{'dbname'};
            my $sigel       = $dbinfo_ref->{'sigel'};
            my $url         = $dbinfo_ref->{'url'};
            my $use_libinfo = $dbinfo_ref->{'use_libinfo'};
            my $active      = $dbinfo_ref->{'active'};

            my $dboptions_ref = $config->get_dboptions($dbname);

            my $host         = $dboptions_ref->{'host'};
            my $protocol     = $dboptions_ref->{'protocol'};
            my $remotepath   = $dboptions_ref->{'remotepath'};
            my $remoteuser   = $dboptions_ref->{'remoteuser'};
            my $remotepasswd = $dboptions_ref->{'remotepasswd'};
            my $filename     = $dboptions_ref->{'filename'};
            my $titfilename  = $dboptions_ref->{'titfilename'};
            my $autfilename  = $dboptions_ref->{'autfilename'};
            my $korfilename  = $dboptions_ref->{'korfilename'};
            my $swtfilename  = $dboptions_ref->{'swtfilename'};
            my $notfilename  = $dboptions_ref->{'notfilename'};
            my $mexfilename  = $dboptions_ref->{'mexfilename'};
            my $autoconvert  = $dboptions_ref->{'autoconvert'};
            my $circ         = $dboptions_ref->{'circ'};
            my $circurl      = $dboptions_ref->{'circurl'};
            my $circcheckurl = $dboptions_ref->{'circcheckurl'};
            my $circdb       = $dboptions_ref->{'circdb'};

            my $rssfeed_ref  = $config->get_rssfeeds_of_db_by_type($dbname);
            
            my $katalog={
                orgunit     => $orgunit,
                description => $description,
                shortdesc   => $shortdesc,
                system      => $system,
                dbname      => $dbname,
                sigel       => $sigel,
                active      => $active,
                url         => $url,
                use_libinfo => $use_libinfo,

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
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editcat_tname},$ttdata,$r);
        }
    }
    elsif ($do_editcat_rss){
        
        if ($do_change) {
	    editcat_rss_change($dbname,$rsstype,$active,$rssid);

	    my $ret_ref = dist_cmd("editcat_rss_change",{ 
							 dbname  => $dbname,
							 rsstype => $rsstype,
							 active  => $active,
							 rssid   => $rssid,
							}) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_editcat_rss=1&dbname=$dbname&do_edit=1");
            return OK;
        }
        elsif ($do_new){
	    editcat_rss_new($dbname,$rsstype);

	    my $ret_ref = dist_cmd("editcat_rss_new",{ 
						      dbname  => $dbname,
						      rsstype => $rsstype,
						     }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_editcat_rss=1&dbname=$dbname&do_edit=1");
            return OK;              
        }
        
        if ($do_edit) {
            my $rssfeed_ref= $config->get_rssfeeds_of_db($dbname);;
            
            my $katalog={
                dbname      => $dbname,
                rssfeeds    => $rssfeed_ref,
            };
            
            
            my $ttdata={
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
                
                katalog    => $katalog,
                
                config     => $config,
                user       => $user,
                msg        => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_admin_editcat_rss_tname},$ttdata,$r);
        }
    }
    elsif ($do_showcat) {
        my $dbinfo_ref = $config->get_dbinfo_overview();

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            kataloge   => $dbinfo_ref,

            config     => $config,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showcat_tname},$ttdata,$r);
    }
    elsif ($do_editlibinfo) {
    
        # Zuerst schauen, ob Aktionen gefordert sind
        if ($do_del) {
            editlibinfo_del($dbname);

	    my $ret_ref = dist_cmd("editlibinfo_del",{ dbname => $dbname }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showcat=1");
            return OK;

        }
        elsif ($do_change) {
            $logger->debug("do_editlibinfo: $do_editlibinfo do_change: $do_change");

            $logger->debug("Info: ".YAML::Dump($thislibinfo_ref));

            editlibinfo_change($dbname,$thislibinfo_ref);

	    my $ret_ref = dist_cmd("editlibinfo_change",{
               
						     libinfo    => $thislibinfo_ref,
						 }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showcat=1");
            return OK;
        }
        elsif ($do_edit) {
            my $libinfo_ref = $config->get_libinfo($dbname);
      
            my $ttdata={
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
                dbname     => $dbname,
                libinfo    => $libinfo_ref,
		  
                config     => $config,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editlibinfo_tname},$ttdata,$r);
        }
    }
    elsif ($do_showprofiles) {
        my $profileinfo_ref = $config->get_profileinfo_overview();

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            profiles   => $profileinfo_ref,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showprofiles_tname},$ttdata,$r);
    }
    elsif ($do_editprofile) {
    
        # Zuerst schauen, ob Aktionen gefordert sind
    
        if ($do_del) {
	    editprofile_del($profilename);

	    my $ret_ref = dist_cmd("editprofile_del",{ profilename => $profilename }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showprofiles=1");
            return OK;
      
        }
        elsif ($do_change) {
	    editprofile_change({
                profilename => $profilename,
                description => $description,
                profiledb   => \@profiledb,
            });
            
	    my $ret_ref = dist_cmd("editprofile_change",{ 
                profilename => $profilename,
                description => $description,
                profiledb   => \@profiledb,
                viewname    => $viewname,
            }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showprofiles=1");
      
            return OK;
        }
        elsif ($do_new) {

            if ($profilename eq "" || $description eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Profilnamen und eine Beschreibung eingeben."),$r,$msg);

                return OK;
            }

	    my $ret = editprofile_new({
                profilename => $profilename,
                description => $description,
            });

	    my $ret_ref = dist_cmd("editprofile_new",{ 
                profilename => $profilename,
                description => $description,
            }) if ($do_dist);

	    if ($ret == -1){
	      OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"),$r,$msg);
	      return OK;
	    }

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_editprofile=1&do_edit=1&profilename=$profilename");
            return OK;
        }
        elsif ($do_edit) {

	    my $profileinfo_ref = $config->get_profileinfo($profilename);

            my $profilename = $profileinfo_ref->{'profilename'};
            my $description = $profileinfo_ref->{'description'};
            
            my @profiledbs  = $config->get_profiledbs($profilename);

            my $profile={
		profilename  => $profilename,
		description  => $description,
		profiledbs   => \@profiledbs,
            };

            my $ttdata={
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},

                profile    => $profile,

                dbnames    => \@dbnames,

                config     => $config,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editprofile_tname},$ttdata,$r);
      
        }
    
    }
    elsif ($do_showsubjects) {
        my $subjects_ref = OpenBib::User->get_subjects;
        my $user         = OpenBib::User->instance({sessionID => $session->{ID}});

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            subjects   => $subjects_ref,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showsubjects_tname},$ttdata,$r);
    }
    elsif ($do_editsubject) {
        my $user       = OpenBib::User->instance({sessionID => $session->{ID}});
    
        # Zuerst schauen, ob Aktionen gefordert sind
    
        if ($do_del) {
	    editsubject_del($subject);

	    my $ret_ref = dist_cmd("editsubject_del",{ id => $subjectid }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showsubjects=1");
            return OK;
      
        }
        elsif ($do_change) {
	    editsubject_change({
                name                 => $subject,
                description          => $description,
                id                   => $subjectid,
                classifications      => \@classifications,
                type                 => $type,
            });
            
	    my $ret_ref = dist_cmd("editsubject_change",{ 
                name                 => $subject,
                description          => $description,
                id                   => $subjectid,
                classifications      => \@classifications,
                type                 => $type,
            }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_editsubject=1;subjectid=$subjectid;do_edit=1");
      
            return OK;
        }
        elsif ($do_new) {

            if ($subject eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Namen f&uuml;r das Themenbebiet eingeben."),$r,$msg);

                return OK;
            }

	    my $ret = editsubject_new({
                name        => $subject,
                description => $description,
            });

	    my $ret_ref = dist_cmd("editsubject_new",{ 
                name        => $subject,
                description => $description,
            }) if ($do_dist);

	    if ($ret == -1){
	      OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein Themengebiet unter diesem Namen"),$r,$msg);
	      return OK;
	    }

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showsubjects=1");
            return OK;
        }
        elsif ($do_edit) {

	    my $subject_ref = OpenBib::User->get_subject({ id => $subjectid});

            my $ttdata={
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},

                subject    => $subject_ref,

                config     => $config,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editsubject_tname},$ttdata,$r);
      
        }
    
    }
    elsif ($do_showviews) {
        my $viewinfo_ref = $config->get_viewinfo_overview();

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            views      => $viewinfo_ref,
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showviews_tname},$ttdata,$r);
    }
    elsif ($do_editview) {
        # Zuerst schauen, ob Aktionen gefordert sind
    
        if ($do_del) {
	    editview_del($viewname);

	    my $ret_ref = dist_cmd("editview_del",{ viewname => $viewname }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showviews=1");
            return OK;
      
        }
        elsif ($do_change) {
	    editview_change({
			     viewname    => $viewname,
			     description => $description,
			     active      => $active,
			     primrssfeed => $primrssfeed,
                             start_loc   => $viewstart_loc,
                             start_stid  => $viewstart_stid,
                             profilename => $profilename,
			     viewdb      => \@viewdb,
			     rssfeeds    => \@rssfeeds,
			    });

	    my $ret_ref = dist_cmd("editview_change",{ 
						      viewname    => $viewname,
						      description => $description,
						      active      => $active,
						      primrssfeed => $primrssfeed,
                                                      start_loc   => $viewstart_loc,
                                                      start_stid  => $viewstart_stid,
                                                      profilename => $profilename,
						      viewdb      => \@viewdb,
						      rssfeeds    => \@rssfeeds,
						     }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showviews=1");
      
            return OK;
        }
        elsif ($do_new) {

            if ($viewname eq "" || $description eq "" || $profilename eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Viewnamen, eine Beschreibung sowie ein Katalog-Profil eingeben."),$r,$msg);

                return OK;
            }

	    my $ret = editview_new({
				    viewname    => $viewname,
				    description => $description,
                                    profilename => $profilename,
				    active      => $active,
                                    start_loc   => $viewstart_loc,
                                    start_stid  => $viewstart_stid,
                                });

	    my $ret_ref = dist_cmd("editview_new",{ 
						   viewname    => $viewname,
						   description => $description,
                                                   profilename => $profilename,						   active      => $active,
                                                   start_loc   => $viewstart_loc,
                                                   start_stid  => $viewstart_stid,
						  }) if ($do_dist);

	    if ($ret == -1){
	      OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"),$r,$msg);
	      return OK;
	    }

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_editview=1&do_edit=1&viewname=$viewname");
            return OK;
        }
        elsif ($do_edit) {
            my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

	    my $viewinfo_ref = $config->get_viewinfo($viewname);

            my $viewname    = $viewinfo_ref->{'viewname'};
            my $description = $viewinfo_ref->{'description'};
            my $primrssfeed = $viewinfo_ref->{'primrssfeed'};
            my $start_loc   = $viewinfo_ref->{'start_loc'};
            my $start_stid  = $viewinfo_ref->{'start_stid'};
            my $profilename = $viewinfo_ref->{'profilename'};
            my $active      = $viewinfo_ref->{'active'};
             
            my @profiledbs       = $config->get_profiledbs($profilename);

            my @viewdbs          = $config->get_viewdbs($viewname);

            my $all_rssfeeds_ref = $config->get_rssfeed_overview();
            
            my $viewrssfeed_ref=$config->get_rssfeeds_of_view($viewname);

            my $view={
		viewname     => $viewname,
		description  => $description,
		active       => $active,
                start_loc    => $start_loc,
                start_stid   => $start_stid,
                profilename  => $profilename,
		viewdbs      => \@viewdbs,
                allrssfeeds  => $all_rssfeeds_ref,
                viewrssfeed  => $viewrssfeed_ref,
                primrssfeed  => $primrssfeed,
            };

            my $ttdata={
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
		  
                dbnames    => \@profiledbs,

                view       => $view,

                dbinfo     => $dbinfotable,
                
                config     => $config,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editview_tname},$ttdata,$r);
      
        }
    
    }
    elsif ($do_editview_rss){

      if ($do_change) {

	  editview_rss_change({
			       viewname => $viewname,
			       rsstype  => $rsstype,
			       rssid    => $rssid,
			       rssids   => \@rssids,
			      });

	  my $ret_ref = dist_cmd("editview_rss_change",{ 
							viewname => $viewname,
							rsstype  => $rsstype,
							rssid    => $rssid,
							rssids   => \@rssids,
						       }) if ($do_dist);

          if ($rsstype eq "primary"){
              $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_editview_rss=1&do_edit=1&viewname=$viewname");
              return OK;
          }
          elsif ($rsstype eq "all") {
              $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showviews=1");
              return OK;
          }
      }
      elsif ($do_edit) {
          my $request=$dbh->prepare("select * from viewinfo where viewname=?") or $logger->error($DBI::errstr);
          $request->execute($viewname) or $logger->error($DBI::errstr);
          
          my $result=$request->fetchrow_hashref();
          
          my $viewname      = decode_utf8($result->{'viewname'});
          my $viewdesc      = decode_utf8($result->{'description'});
          my $primrssfeed   = decode_utf8($result->{'rssfeed'});
          
          my $allrssfeed_ref=[];
          
          $request=$dbh->prepare("select rssfeeds.id, rssfeeds.dbname, dbinfo.description, rssfeeds.type, rssfeeds.active  from rssfeeds,dbinfo where rssfeeds.dbname=dbinfo.dbname order by dbinfo.description,rssfeeds.type,rssfeeds.subtype") or $logger->error($DBI::errstr);
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
          
          $request=$dbh->prepare("select * from viewrssfeeds where viewname = ?") or $logger->error($DBI::errstr);
          $request->execute($viewname) or $logger->error($DBI::errstr);
          while (my $result=$request->fetchrow_hashref()){
              my $rssfeedid        = decode_utf8($result->{'rssfeed'});
              $viewrssfeeds_ref->{$rssfeedid}=1;
          }


          my $view={
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
              user        => $user,
              msg         => $msg,
          };
          
          OpenBib::Common::Util::print_page($config->{tt_admin_editview_rss_tname},$ttdata,$r);
      }
  }
    elsif ($do_showimx) {

        my @kataloge=();

        my $idnresult=$dbh->prepare("select dbinfo.*,titcount.count from dbinfo,titcount where dbinfo.dbname=titcount.dbname order by orgunit,dbname") or $logger->error($DBI::errstr);
        $idnresult->execute() or $logger->error($DBI::errstr);

        my $katalog;
        while (my $result=$idnresult->fetchrow_hashref()) {
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
            my $use_libinfo = decode_utf8($result->{'use_libinfo'});
            my $active      = decode_utf8($result->{'active'});

            $active="Ja"   if ($active eq "1");
            $active="Nein" if ($active eq "0");

            my $count       = decode_utf8($result->{'count'});

            $katalog={
		orgunit     => $orgunit,
		description => $description,
		system      => $system,
		dbname      => $dbname,
		sigel       => $sigel,
		active      => $active,
		url         => $url,
                use_libinfo => $use_libinfo,
		count       => $count,
            };

            push @kataloge, $katalog;
        }

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            kataloge   => \@kataloge,

            config     => $config,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showimx_tname},$ttdata,$r);

        $idnresult->finish();
    }
    elsif ($do_showsessions) {

        my @sessions=$session->get_info_of_all_active_sessions();

        my $ttdata={
            stylesheet => $stylesheet,

	    session    => $session,
            sessionID  => $session->{ID},
	         
            sessions   => \@sessions,

            config     => $config,
            user       => $user,
            msg        => $msg,
        };

	$stid=~s/[^0-9]//g;

	my $templatename = ($stid)?"tt_admin_showsessions_".$stid."_tname":"tt_admin_showsessions_tname";

	OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

        return OK;
    }
    elsif ($do_editsession) {

        if ($do_show) {
            my ($benutzernr,$createtime) = $session->get_info($singlesessionid);
            my @queries                  = $session->get_all_searchqueries({
                sessionid => $singlesessionid,
            });

            if (!$benutzernr) {
                $benutzernr="Anonym";
            }

            my $singlesession={
                singlesessionid => $singlesessionid,
                createtime      => $createtime,
                benutzernr      => $benutzernr,
                numqueries      => $#queries+1,
            };

            my $ttdata={
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
	         
                session    => $singlesession,

                queries    => \@queries,

                config     => $config,
                user       => $user,
                msg        => $msg,
            };

            OpenBib::Common::Util::print_page($config->{tt_admin_editsession_tname},$ttdata,$r);

            return OK;
        }
    }
    elsif ($do_exploresessions) {
        # Verbindung zur SQL-Datenbank herstellen
        my $statisticsdbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
                or $logger->error($DBI::errstr);
        
        if ($do_show) {
            my $serialized_type_ref = {
                1  => 1,
                10 => 1,
            };
            
            
            my $idnresult=$statisticsdbh->prepare("select * from eventlog where sessionid = ? order by tstamp ASC") or $logger->error($DBI::errstr);
            $idnresult->execute($singlesessionid) or $logger->error($DBI::errstr);
            
            my @events = ();
            
            while (my $result=$idnresult->fetchrow_hashref()) {
                my $type        = decode_utf8($result->{'type'});
                my $tstamp      = decode_utf8($result->{'tstamp'});
                my $content     = decode_utf8($result->{'content'});
                
                
                
                if (exists $serialized_type_ref->{$type}){
                    $content=Storable::thaw(pack "H*", $content);
                }
                
                push @events, {
                    type => $type,
                    content => $content,
                    createtime => $tstamp,
                };
            }
            
            
            my $ttdata={
                stylesheet => $stylesheet,
                
                session    => $session,
                sessionID  => $session->{ID},
                
                singlesessionid => $singlesessionid,
                
                events     => \@events,
                
                clientip   => $clientip,
                fromdate   => $fromdate,
                todate     => $todate,
                
                config     => $config,
                user       => $user,
                msg        => $msg,
            };
            
            $stid=~s/[^0-9]//g;
            
            my $templatename = ($stid)?"tt_admin_exploresessions_show".$stid."_tname":"tt_admin_exploresessions_show_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
            return OK;
	    
            
	}
        else {
            
            unless ($fromdate && $todate){
                OpenBib::Common::Util::print_warning($msg->maketext("Bitte geben Sie ein Anfangs- sowie ein End-Datum an!"),$r,$msg);
                return OK;
                
            }
            
            # Eventtyp 102 = Client-IP
            my $sqlstring="select sessionid,tstamp from eventlog where type=102 and content = ? and tstamp > ? and tstamp < ?";
            
            $logger->debug("$sqlstring - $clientip / $fromdate / $todate");
            
            my $idnresult=$statisticsdbh->prepare($sqlstring) or $logger->error($DBI::errstr);
            $idnresult->execute($clientip,$fromdate,$todate) or $logger->error($DBI::errstr);
            my @sessions=();
            
            while (my $result=$idnresult->fetchrow_hashref()) {
                my $singlesessionid = decode_utf8($result->{'sessionid'});
                my $tstamp          = decode_utf8($result->{'tstamp'});
                
                push @sessions, {
                    sessionid  => $singlesessionid,
                    createtime => $tstamp,
                };
            }
            
            
            my $ttdata={
                stylesheet => $stylesheet,
                
                session    => $session,
                sessionID  => $session->{ID},
                
                sessions   => \@sessions,
                
                clientip   => $clientip,
                fromdate   => $fromdate,
                todate     => $todate,
                
                config     => $config,
                user       => $user,
                msg        => $msg,
            };
            
            $stid=~s/[^0-9]//g;
            
            my $templatename = ($stid)?"tt_admin_exploresessions_list".$stid."_tname":"tt_admin_exploresessions_list_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
            return OK;
	}
    }
    elsif ($do_showstat) {

        my $statistics = new OpenBib::Statistics();
	my $user       = OpenBib::User->instance({sessionID => $session->{ID}});

        # TT-Data erzeugen
        my $ttdata={
                    sessionID  => $session->{ID},
                    
                    year       => $year,

		    session    => $session,
		    statistics => $statistics,
		    user       => $user,
		    config     => $config,
		    msg        => $msg,
		   };

	$stid=~s/[^0-9]//g;

	my $templatename = ($stid)?"tt_admin_showstat_".$stid."_tname":"tt_admin_showstat_tname";

	OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

    }
    elsif ($do_showlogintarget) {

	my $user       = OpenBib::User->instance({sessionID => $session->{ID}});

        # TT-Data erzeugen
        my $ttdata={
                    sessionID  => $session->{ID},

		    session    => $session,

		    user       => $user,
		    config     => $config,
		    msg        => $msg,
		   };

	$stid=~s/[^0-9]//g;

	my $templatename = ($stid)?"tt_admin_showlogintarget_".$stid."_tname":"tt_admin_showlogintarget_tname";

	OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);


    }
    elsif ($do_editlogintarget) {

	my $user       = OpenBib::User->instance({sessionID => $session->{ID}});

        # Zuerst schauen, ob Aktionen gefordert sind
        if ($do_del) {
            editlogintarget_del($targetid);

	    my $ret_ref = dist_cmd("editlogintarget_del",{ targetid => $targetid }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showlogintarget=1");
            return OK;

        }
        elsif ($do_change) {

            editlogintarget_change($thislogintarget_ref);

	    my $ret_ref = dist_cmd("editlogintarget_change",{ 
						     logintarget => $thislogintarget_ref,
						 }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showlogintarget=1");
            return OK;
        }
        elsif ($do_new) {

            if ($description eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens eine Beschreibung eingeben."),$r,$msg);

                return OK;
            }

            if ($user->logintarget_exists({description => $thislogintarget_ref->{description}})) {

                OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein Anmeldeziel unter diesem Namen"),$r,$msg);

                return OK;
            }

            editlogintarget_new($thislogintarget_ref);
            
	    my $ret_ref = dist_cmd("editlogintarget_new",{ logintarget => $thislogintarget_ref }) if ($do_dist);

            $r->internal_redirect("http://$config->{servername}$config->{admin_loc}?sessionID=$session->{ID}&do_showlogintarget=1");
            return OK;
        }
        elsif ($do_edit) {

	  my $logintarget_ref = $user->get_logintarget_by_id($targetid);
      
	  my $ttdata={
                stylesheet  => $stylesheet,
                sessionID   => $session->{ID},
		  
                logintarget => $logintarget_ref,
		  
                user        => $user,
                config      => $config,
                msg         => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editlogintarget_tname},$ttdata,$r);
        }
    }
    elsif ($do_showuser) {

	my $user       = OpenBib::User->instance({sessionID => $session->{ID}});

        # TT-Data erzeugen
        my $ttdata={
                    sessionID  => $session->{ID},

		    session    => $session,

		    user       => $user,
		    config     => $config,
		    msg        => $msg,
		   };

	$stid=~s/[^0-9]//g;

	my $templatename = ($stid)?"tt_admin_showuser_".$stid."_tname":"tt_admin_showuser_tname";

	OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);


    }
    elsif ($do_logout) {

        my $ttdata={
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            
            config     => $config,
            user       => $user,
            msg        => $msg,
        };
      
        OpenBib::Common::Util::print_page($config->{tt_admin_logout_tname},$ttdata,$r);

        $session->logout_user($adminuser);
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Keine gültige Aktion oder Session"),$r,$msg);
    }
  
  LEAVEPROG: sleep 0;
  
    return OK;
}

sub editcat_del {
    my ($dbname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("delete from dbinfo where dbname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($dbname) or $logger->error($DBI::errstr);
    $idnresult=$dbh->prepare("delete from titcount where dbname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($dbname) or $logger->error($DBI::errstr);
    $idnresult=$dbh->prepare("delete from dboptions where dbname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($dbname) or $logger->error($DBI::errstr);
    $idnresult->finish();
    
    if ($config->get_system_of_db($dbname) ne "Z39.50"){
        # Und nun auch die Datenbank komplett loeschen
        system("$config->{tool_dir}/destroypool.pl $dbname > /dev/null 2>&1");
    }

    return;
}

sub editcat_change {
    my ($dbinfo_ref,$dboptions_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("update dbinfo set orgunit = ?, description = ?, shortdesc = ?, system = ?, sigel = ?, url = ?, use_libinfo = ?, active = ? where dbname = ?") or $logger->error($DBI::errstr); # 
    $request->execute($dbinfo_ref->{orgunit},$dbinfo_ref->{description},$dbinfo_ref->{shortdesc},$dbinfo_ref->{system},$dbinfo_ref->{sigel},$dbinfo_ref->{url},$dbinfo_ref->{use_libinfo},$dbinfo_ref->{active},$dbinfo_ref->{dbname}) or $logger->error($DBI::errstr);

    # Konvertierung
    $request=$dbh->prepare("update dboptions set protocol = ?, host = ?, remotepath = ?, remoteuser = ?, remotepasswd = ?, titfilename = ?, autfilename = ?, korfilename = ?, swtfilename = ?, notfilename = ?, mexfilename = ?, filename = ?, autoconvert = ? where dbname= ?") or $logger->error($DBI::errstr);
    $request->execute($dboptions_ref->{protocol},$dboptions_ref->{host},$dboptions_ref->{remotepath},$dboptions_ref->{remoteuser},$dboptions_ref->{remotepasswd},$dboptions_ref->{titfilename},$dboptions_ref->{autfilename},$dboptions_ref->{korfilename},$dboptions_ref->{swtfilename},$dboptions_ref->{notfilename},$dboptions_ref->{mexfilename},$dboptions_ref->{filename},$dboptions_ref->{autoconvert},$dbinfo_ref->{dbname}) or $logger->error($DBI::errstr);

    # OLWS
    $request=$dbh->prepare("update dboptions set circ = ?, circurl = ?, circcheckurl=?, circdb = ? where dbname= ?") or $logger->error($DBI::errstr);
    $request->execute($dboptions_ref->{circ},$dboptions_ref->{circurl},$dboptions_ref->{circcheckurl},$dboptions_ref->{circdb},$dbinfo_ref->{dbname}) or $logger->error($DBI::errstr);

    $request->finish();

    return;
}

sub editcat_new {
    my ($dbinfo_ref)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("insert into dbinfo values (?,?,?,?,?,?,?,?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute($dbinfo_ref->{orgunit},$dbinfo_ref->{description},$dbinfo_ref->{shortdesc},$dbinfo_ref->{system},$dbinfo_ref->{dbname},$dbinfo_ref->{sigel},$dbinfo_ref->{url},$dbinfo_ref->{use_libinfo},$dbinfo_ref->{active}) or $logger->error($DBI::errstr);
    $idnresult=$dbh->prepare("insert into titcount values (?,'0',?)") or $logger->error($DBI::errstr);
    $idnresult->execute($dbinfo_ref->{dbname},1) or $logger->error($DBI::errstr);
    $idnresult->execute($dbinfo_ref->{dbname},2) or $logger->error($DBI::errstr);
    $idnresult->execute($dbinfo_ref->{dbname},3) or $logger->error($DBI::errstr);
    $idnresult=$dbh->prepare("insert into dboptions values (?,'','','','','','','','','','','','',0,0,'','','')") or $logger->error($DBI::errstr);
    $idnresult->execute($dbinfo_ref->{dbname}) or $logger->error($DBI::errstr);
    $idnresult->finish();
    
    if ($config->get_system_of_db($dbinfo_ref->{dbname}) ne "Z39.50"){
        # Und nun auch die Datenbank zuerst komplett loeschen (falls vorhanden)
        system("$config->{tool_dir}/destroypool.pl $dbinfo_ref->{dbname} > /dev/null 2>&1");
        
        # ... und dann wieder anlegen
        system("$config->{tool_dir}/createpool.pl $dbinfo_ref->{dbname} > /dev/null 2>&1");
    }
    return;
}

sub editcat_rss_change {
    my ($dbname,$rsstype,$active,$rssid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("update rssfeeds set dbname = ?, type = ?, active = ? where id = ?") or $logger->error($DBI::errstr);
    $request->execute($dbname,$rsstype,$active,$rssid) or $logger->error($DBI::errstr);
    $request->finish();

    return;
}

sub editcat_rss_new {
    my ($dbname,$rsstype,$active,$rssid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("insert into rssfeeds values (NULL,?,?,-1,'',0)") or $logger->error($DBI::errstr);
    $request->execute($dbname,$rsstype) or $logger->error($DBI::errstr);
    $request->finish();

    return;
}

sub editview_del {
    my ($viewname)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("delete from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname) or $logger->error($DBI::errstr);
    $idnresult=$dbh->prepare("delete from viewdbs where viewname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub editlibinfo_change {
    my ($dbname,$libinfo_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $del_request    = $dbh->prepare("delete from libraryinfo where dbname=? and category=?") or $logger->error($DBI::errstr); # 
    my $insert_request = $dbh->prepare("insert into libraryinfo values (?,?,NULL,?)") or $logger->error($DBI::errstr); # 

    foreach my $category (keys %$libinfo_ref){
        my ($category_num)=$category=~/^I(\d+)$/;

        $logger->debug("Changing Category $category_num to $libinfo_ref->{$category}");
        $del_request->execute($dbname,$category_num);
        $insert_request->execute($dbname,$category_num,$libinfo_ref->{$category});
    }

    $del_request->finish();
    $insert_request->finish();

    return;
}

sub editview_change {
    my ($arg_ref) = @_;

    # Set defaults
    my $viewname               = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}            : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;
    my $active                 = exists $arg_ref->{active}
        ? $arg_ref->{active}              : undef;
    my $primrssfeed            = exists $arg_ref->{primrssfeed}
        ? $arg_ref->{primrssfeed}         : undef;
    my $viewdb_ref             = exists $arg_ref->{viewdb}
        ? $arg_ref->{viewdb}              : undef;
    my $start_loc              = exists $arg_ref->{start_loc}
        ? $arg_ref->{start_loc}           : undef;
    my $start_stid             = exists $arg_ref->{start_stid}
        ? $arg_ref->{start_stid}          : undef;
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}         : undef;
    my $rssfeeds_ref           = exists $arg_ref->{rssfeeds}
        ? $arg_ref->{rssfeeds}            : undef;

    my @viewdb   = (defined $viewdb_ref)?@$viewdb_ref:();
    my @rssfeeds = (defined $rssfeeds_ref)?@$rssfeeds_ref:();

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    # Zuerst die Aenderungen in der Tabelle Viewinfo vornehmen
    
    my $idnresult=$dbh->prepare("update viewinfo set description = ?, start_loc = ?, start_stid = ?, profilename = ?, active = ? where viewname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($description,$start_loc,$start_stid,$profilename,$active,$viewname) or $logger->error($DBI::errstr);
    
    # Primary RSS-Feed fuer Autodiscovery eintragen
    if ($primrssfeed){
        $idnresult=$dbh->prepare("update viewinfo set rssfeed = ? where viewname = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($primrssfeed,$viewname) or $logger->error($DBI::errstr);
    }
    
    # Datenbanken zunaechst loeschen
    
    $idnresult=$dbh->prepare("delete from viewdbs where viewname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname) or $logger->error($DBI::errstr);
    
    
    # Dann die zugehoerigen Datenbanken eintragen
    foreach my $singleviewdb (@viewdb) {
        $idnresult=$dbh->prepare("insert into viewdbs values (?,?)") or $logger->error($DBI::errstr);
        $idnresult->execute($viewname,$singleviewdb) or $logger->error($DBI::errstr);
    }
    
    # RSS-Feeds zunaechst loeschen
    $idnresult=$dbh->prepare("delete from viewrssfeeds where viewname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname) or $logger->error($DBI::errstr);
    
    # Dann die zugehoerigen Feeds eintragen
    foreach my $singleviewrssfeed (@rssfeeds) {
        $idnresult=$dbh->prepare("insert into viewrssfeeds values (?,?)") or $logger->error($DBI::errstr);
        $idnresult->execute($viewname,$singleviewrssfeed) or $logger->error($DBI::errstr);
    }
    
    $idnresult->finish();

    return;
}

sub editview_new {
    my ($arg_ref) = @_;

    # Set defaults
    my $viewname               = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname}            : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}         : undef;
    my $start_loc              = exists $arg_ref->{start_loc}
        ? $arg_ref->{start_loc}           : undef;
    my $start_stid             = exists $arg_ref->{stid_loc}
        ? $arg_ref->{start_stid}           : undef;
    my $active                 = exists $arg_ref->{active}
        ? $arg_ref->{active}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select count(*) as rowcount from viewinfo where viewname = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname) or $logger->error($DBI::errstr);
    my $res=$idnresult->fetchrow_hashref;
    my $rows=$res->{rowcount};
    
    if ($rows > 0) {
      $idnresult->finish();
      return -1;
    }
    
    $idnresult=$dbh->prepare("insert into viewinfo values (?,?,NULL,?,?,?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute($viewname,$description,$start_loc,$start_stid,$profilename,$active) or $logger->error($DBI::errstr);
    
    return 1;
}

sub editview_rss_change {
    my ($arg_ref) = @_;

    # Set defaults
    my $viewname               = exists $arg_ref->{viewname}
        ? $arg_ref->{viewname }           : undef;
    my $rsstype                = exists $arg_ref->{rsstype}
        ? $arg_ref->{rsstype }            : undef;
    my $rssid                  = exists $arg_ref->{rssid}
        ? $arg_ref->{rssid}               : undef;
    my $rssids_ref             = exists $arg_ref->{rssids}
        ? $arg_ref->{rssids}              : undef;

    my @rssids = (defined $rssids_ref)?@$rssids_ref:();

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    if ($rsstype eq "primary"){
      my $request=$dbh->prepare("update viewinfo set rssfeed = ? where viewname = ?") or $logger->error($DBI::errstr);
      $request->execute($rssid,$viewname) or $logger->error($DBI::errstr);
      $request->finish();
    }
    elsif ($rsstype eq "all") {
      my $request=$dbh->prepare("delete from viewrssfeeds where viewname = ?");
      $request->execute($viewname);
      
      $request=$dbh->prepare("insert into viewrssfeeds values (?,?)") or $logger->error($DBI::errstr);
      foreach my $rssid (@rssids){
	$request->execute($viewname,$rssid) or $logger->error($DBI::errstr);
      }
      $request->finish();
    }
    
    return;
}

sub editprofile_del {
    my ($profilename)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("delete from profileinfo where profilename = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename) or $logger->error($DBI::errstr);
    $idnresult=$dbh->prepare("delete from profiledbs where profilename = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename) or $logger->error($DBI::errstr);
    $idnresult->finish();

    return;
}

sub editprofile_change {
    my ($arg_ref) = @_;

    # Set defaults
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}         : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;
    my $profiledb_ref          = exists $arg_ref->{profiledb}
        ? $arg_ref->{profiledb}           : undef;

    my @profiledb = (defined $profiledb_ref)?@$profiledb_ref:();

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    # Zuerst die Aenderungen in der Tabelle Profileinfo vornehmen
    
    my $idnresult=$dbh->prepare("update profileinfo set description = ? where profilename = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($description,$profilename) or $logger->error($DBI::errstr);
    
    # Datenbanken zunaechst loeschen
    
    $idnresult=$dbh->prepare("delete from profiledbs where profilename = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename) or $logger->error($DBI::errstr);
    
    
    # Dann die zugehoerigen Datenbanken eintragen
    foreach my $singleprofiledb (@profiledb) {
        $idnresult=$dbh->prepare("insert into profiledbs values (?,?)") or $logger->error($DBI::errstr);
        $idnresult->execute($profilename,$singleprofiledb) or $logger->error($DBI::errstr);
    }
    
    $idnresult->finish();

    return;
}

sub editprofile_new {
    my ($arg_ref) = @_;

    # Set defaults
    my $profilename            = exists $arg_ref->{profilename}
        ? $arg_ref->{profilename}            : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select count(*) as rowcount from profileinfo where profilename = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename) or $logger->error($DBI::errstr);
    my $res=$idnresult->fetchrow_hashref;
    my $rows=$res->{rowcount};
    
    if ($rows > 0) {
      $idnresult->finish();
      return -1;
    }
    
    $idnresult=$dbh->prepare("insert into profileinfo values (?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute($profilename,$description) or $logger->error($DBI::errstr);
    
    return 1;
}

sub editsubject_del {
    my ($arg_ref) = @_;

    # Set defaults
    my $id            = exists $arg_ref->{id};

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $request=$dbh->prepare("delete from subjects where id = ?") or $logger->error($DBI::errstr);
    $request->execute($id) or $logger->error($DBI::errstr);
    $request->finish();

    return;
}

sub editsubject_change {
    my ($arg_ref) = @_;

    # Set defaults
    my $name                     = exists $arg_ref->{name}
        ? $arg_ref->{name}                : undef;
    my $description              = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;
    my $id                       = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $classifications_ref      = exists $arg_ref->{classifications}
        ? $arg_ref->{classifications}     : [];
    my $type                      = exists $arg_ref->{type}
        ? $arg_ref->{type}                : 'BK';

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    # Zuerst die Aenderungen in der Tabelle Profileinfo vornehmen
    
    my $request=$dbh->prepare("update subjects set name = ?, description = ? where id = ?") or $logger->error($DBI::errstr);
    $request->execute(encode_utf8($name),encode_utf8($description),$id) or $logger->error($DBI::errstr);
    $request->finish();

    if (@{$classifications_ref}){       
        $logger->debug("Classifications5 ".YAML::Dump($classifications_ref));

        OpenBib::User->set_classifications_of_subject({
            subjectid       => $id,
            classifications => $classifications_ref,
            type            => $type,
        });
    }

    return;
}

sub editsubject_new {
    my ($arg_ref) = @_;

    # Set defaults
    my $name                   = exists $arg_ref->{name}
        ? $arg_ref->{name}                : undef;
    my $description            = exists $arg_ref->{description}
        ? $arg_ref->{description}         : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $idnresult=$dbh->prepare("select count(*) as rowcount from subjects where name = ?") or $logger->error($DBI::errstr);
    $idnresult->execute($name) or $logger->error($DBI::errstr);
    my $res=$idnresult->fetchrow_hashref;
    my $rows=$res->{rowcount};
    
    if ($rows > 0) {
      $idnresult->finish();
      return -1;
    }
    
    $idnresult=$dbh->prepare("insert into subjects (name,description) values (?,?)") or $logger->error($DBI::errstr);
    $idnresult->execute(encode_utf8($name),encode_utf8($description)) or $logger->error($DBI::errstr);
    
    return 1;
}

sub editlogintarget_del {
    my ($targetid)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $user = OpenBib::User->instance;

    $user->delete_logintarget($targetid);

    return;
}

sub editlogintarget_change {
    my ($logintarget_ref)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug(YAML::Dump($logintarget_ref));
    
    my $user = OpenBib::User->instance;

    $user->update_logintarget({
        targetid    => $logintarget_ref->{id},
        hostname    => $logintarget_ref->{hostname},
        port        => $logintarget_ref->{port},
        username    => $logintarget_ref->{username},
        dbname      => $logintarget_ref->{dbname},
        description => $logintarget_ref->{description},
        type        => $logintarget_ref->{type}
    });
    
    return;
}

sub editlogintarget_new {
    my ($logintarget_ref)=@_;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $user = OpenBib::User->instance;

    $user->new_logintarget({
        hostname    => $logintarget_ref->{hostname},
        port        => $logintarget_ref->{port},
        username    => $logintarget_ref->{username},
        dbname      => $logintarget_ref->{dbname},
        description => $logintarget_ref->{description},
        type        => $logintarget_ref->{type}
    });

    return;
}


sub dist_cmd {
  my ($cmd,$args_ref)=@_;

  # Log4perl logger erzeugen
  my $logger = get_logger();

  my $config = OpenBib::Config->instance;

  foreach my $slave_ref (@{$config->{distadmin}{slaves}}){
    my $soap = SOAP::Lite
      -> uri("urn:/Admin")
	-> proxy($slave_ref->{wsurl});
    my $result = $soap->$cmd($args_ref);
    
    if ($result->fault) {
      $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
    }
    
  }

  return;
}

1;
