#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Server
#
#  Dieses File ist (C) 2004-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Admin::Server;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::SubRequest ();
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
use OpenBib::Database::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'databaseinfo'       => 'process_databaseinfo',
        'viewinfo'           => 'process_viewinfo',
        'libraryinfo'        => 'process_libraryinfo',
        'profile'            => 'process_profile',
        'session'            => 'process_session',
        'user'               => 'process_user',
        'orgunit'            => 'process_orgunit',
        'statistics'         => 'process_statistics',
        'subject'            => 'process_subject',
        'subjects'           => 'process_subjects',
        'status'             => 'process_status',
        'login'              => 'process_login',
        'logout'             => 'process_logout',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub process_databaseinfo {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $stid           = $self->param('stid')           || '';
    my $action         = $self->param('action')         || '';
    my $representation = $self->param('representation') || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
}

sub process_login {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $stid           = $self->param('stid')           || '';
    my $action         = $self->param('action')         || '';
    my $representation = $self->param('representation') || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    my $adminuser   = $config->{adminuser};
    my $adminpasswd = $config->{adminpasswd};

    # Expliziter aufruf und default bei keiner Parameteruebergabe
    if ($action eq "form" || ($r->method eq "GET" && ! scalar $r->args) ) {
    
        # TT-Data erzeugen
    
        my $ttdata={
            view       => $view,
            
            stylesheet => $stylesheet,
            config     => $config,     
            msg        => $msg,
        };

        my $templatename = ($stid && $stid ne "default")?"tt_admin_login_".$stid."_tname":"tt_admin_login_tname";

        OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

        return Apache2::Const::OK;
    }
  
    ###########################################################################
    elsif ($action eq "authenticate") {

        # Variables for this action
        my $passwd          = $query->param('passwd')          || '';
        my $username        = $query->param('username')        || '';
        
        # Sessionid erzeugen
        if ($username ne $adminuser) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben als Benutzer entweder keinen oder nicht den Admin-Benutzer eingegeben"),$r,$msg);
            return Apache2::Const::OK;
        }
        
        if ($passwd ne $adminpasswd) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben ein falsches Passwort eingegeben"),$r,$msg);
            return Apache2::Const::OK;
        }
        
        # Session ist nun authentifiziert und wird mit dem Admin 
        # assoziiert.
        $session->set_user($adminuser);
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,

            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            session    => $session,
            config     => $config,

            msg        => $msg,
        };

        my $templatename = ($stid && $stid ne "default")?"tt_admin_loggedin_".$stid."_tname":"tt_admin_loggedin_tname";

        OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
        return Apache2::Const::OK;
    }
    
}

sub process_status {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $stid           = $self->param('stid')           || '';
    my $action         = $self->param('action')         || '';
    my $representation = $self->param('representation') || '';

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance({ apreq => $r });
    my $query   = Apache2::Request->new($r);

    my $stylesheet   = OpenBib::Common::Util::get_css_by_browsertype($r);

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    # Ist der Nutzer ein Admin?
    my $user         = OpenBib::User->instance({sessionID => $session->{ID}});

    # Admin-SessionID ueberpruefen
    # Entweder als Master-Adminuser eingeloggt, oder der Benutzer besitzt die Admin-Rolle
    my $adminsession = $session->is_authenticated_as($adminuser) || $user->is_admin;

    if (!$adminsession) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"),$r,$msg);
        return Apache2::Const::OK;
    }

    $logger->debug("Server: ".$r->get_server_name);

    if ($action eq "show"){   
        my $loadbalancertargets_ref = $config->get_loadbalancertargets;
        
        my $ttdata={
            loadbalancertargets => $loadbalancertargets_ref,
            
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            config     => $config,
            session    => $session,
            user       => $user,
            msg        => $msg,
        };
        
        my $templatename = ($stid && $stid ne "default")?"tt_admin_showoperations_".$stid."_tname":"tt_admin_showoperations_tname";
        
        OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
    }
    elsif ($action eq "edit
    
}


sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $action         = $self->param('action')         || '';
    my $representation = $self->param('representation') || '';

    my $config = OpenBib::Config->instance;

    # Verbindung zur SQL-Datenbank herstellen
    my $dbh
        = OpenBib::Database::DBI->connect("DBI:$config->{configdbimodule}:dbname=$config->{configdbname};host=$config->{configdbhost};port=$config->{configdbport}", $config->{configdbuser}, $config->{configdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $query=Apache2::Request->new($r);

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    # Standardwerte festlegen
  
    my $adminuser   = $config->{adminuser};
    my $adminpasswd = $config->{adminpasswd};

    # Main-Actions
    my $do_login                   = $query->param('do_login')        || '';
    my $do_loginmask               = $query->param('do_loginmask')    || '';
    my $do_showcat                 = $query->param('do_showcat')      || '';
    my $do_editcat                 = $query->param('do_editcat')      || '';
    my $do_showlibinfo             = $query->param('do_showlibinfo')  || '';
    my $do_editlibinfo             = $query->param('do_editlibinfo')  || '';
    my $do_showops                 = $query->param('do_showops')      || '';
    my $do_editserver              = $query->param('do_editserver')   || '';
    my $do_editcat_rss             = $query->param('do_editcat_rss')  || '';
    my $do_showprofiles            = $query->param('do_showprofiles') || '';
    my $do_editprofile             = $query->param('do_editprofile')  || '';
    my $do_editorgunit             = $query->param('do_editorgunit')  || '';
    my $do_showsubjects            = $query->param('do_showsubjects') || '';
    my $do_editsubject             = $query->param('do_editsubject')  || '';
    my $do_showviews               = $query->param('do_showviews')    || '';
    my $do_editview                = $query->param('do_editview')     || '';
    my $do_editview_rss            = $query->param('do_editview_rss') || '';
    my $do_showimx                 = $query->param('do_showimx')      || '';
    my $do_showsessions            = $query->param('do_showsessions') || '';
    my $do_editsession             = $query->param('do_editsession')  || '';
    my $do_exploresessions         = $query->param('do_exploresessions') || '';
    my $do_showstat                = $query->param('do_showstat')     || '';
    my $do_showuser                = $query->param('do_showuser')     || '';
    my $do_edituser                = $query->param('do_edituser')     || '';
    my $do_searchuser              = $query->param('do_searchuser')   || '';
    my $do_showlogintarget         = $query->param('do_showlogintarget')     || '';
    my $do_editlogintarget         = $query->param('do_editlogintarget')     || '';
    my $do_logout                  = $query->param('do_logout')       || '';

    # Sub-Actions
    my $do_new          = $query->param('do_new')          || 0;
    my $do_del          = $query->param('do_del')          || 0;
    my $do_change       = $query->param('do_change')       || 0;
    my $do_edit         = $query->param('do_edit')         || 0;
    my $do_show         = $query->param('do_show')         || 0;

    # Variables
    my $hostid          = $query->param('hostid')          || '';
    my $userid          = $query->param('userid')          || '';
    my $passwd          = $query->param('passwd')          || '';
    my $orgunit         = $query->param('orgunit')         || '';
    my $description     = decode_utf8($query->param('description'))     || '';
    my $shortdesc       = $query->param('shortdesc')       || '';
    my $system          = $query->param('system')          || '';
    my $dbname          = $query->param('dbname')          || '';
    my $sigel           = $query->param('sigel')           || '';
    my $url             = $query->param('url')             || '';
    my $use_libinfo     = $query->param('use_libinfo')     || 0;
    my $active          = $query->param('active')          || 0;

    my $nr              = $query->param('nr')              || 0;

    my $roleid          = $query->param('roleid')          || '';
    my @roles           = ($query->param('roles'))?$query->param('roles'):();
    
    my $surname         = decode_utf8($query->param('surname'))         || '';
    my $commonname      = decode_utf8($query->param('commonname'))      || '';
    
    my $viewname        = $query->param('viewname')        || '';
    my @viewdb          = ($query->param('viewdb'))?$query->param('viewdb'):();

    # Profile
    my $profilename     = $query->param('profilename')     || '';
    my @profiledb       = ($query->param('profiledb'))?$query->param('profiledb'):();

    my @orgunitdb       = ($query->param('orgunitdb'))?$query->param('orgunitdb'):();
    
    my @databases       = ($query->param('db'))?$query->param('db'):();

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
        description        => $description,
        shortdesc          => $shortdesc,
        system             => $system,
        dbname             => $dbname,
        sigel              => $sigel,
        url                => $url,
        use_libinfo        => $use_libinfo,
        active             => $active,
        host               => $host,
        protocol           => $protocol,
        remotepath         => $remotepath,
        remoteuser         => $remoteuser,
        remotepassword     => $remotepasswd,
        titlefile          => $titfilename,
        personfile         => $autfilename,
        corporatebodyfile  => $korfilename,
        subjectfile        => $swtfilename,
        classificationfile => $notfilename,
        holdingsfile       => $mexfilename,
        autoconvert        => $autoconvert,
        circ               => $circ,
        circurl            => $circurl,
        circwsurl          => $circcheckurl,
        circdb             => $circdb,
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

    my $thisuserinfo_ref = {
        id    => $userid,
        roles => \@roles,
    };
    
    # Expliziter aufruf und default bei keiner Parameteruebergabe
    if ($do_loginmask || ($r->method eq "GET" && ! scalar $r->args) ) {
    
        # TT-Data erzeugen
    
        my $ttdata={
            view       => $view,
            
            stylesheet => $stylesheet,
            config     => $config,     
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_login_tname},$ttdata,$r);
        return Apache2::Const::OK;
    }
  
    ###########################################################################
    elsif ($do_login) {

        # Sessionid erzeugen
        if ($username ne $adminuser) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben als Benutzer entweder keinen oder nicht den Admin-Benutzer eingegeben"),$r,$msg);
            return Apache2::Const::OK;
        }
        
        if ($passwd ne $adminpasswd) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben ein falsches Passwort eingegeben"),$r,$msg);
            return Apache2::Const::OK;
        }
        
        # Session ist nun authentifiziert und wird mit dem Admin 
        # assoziiert.
        $session->set_user($adminuser);
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,

            stylesheet => $stylesheet,
            sessionID  => $session->{ID},

            session    => $session,
            config     => $config,

            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_loggedin_tname},$ttdata,$r);
        return Apache2::Const::OK;
    }
  
    # Ab hier gehts nur weiter mit korrekter SessionID

    my $user         = OpenBib::User->instance({sessionID => $session->{ID}});

    # Admin-SessionID ueberpruefen
    # Entweder als Master-Adminuser eingeloggt, oder der Benutzer besitzt die Admin-Rolle
    my $adminsession = $session->is_authenticated_as($adminuser) || $user->is_admin;

    if (!$adminsession) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie greifen auf eine nicht autorisierte Session zu"),$r,$msg);
        return Apache2::Const::OK;
    }

    $logger->debug("Server: ".$r->get_server_name);
    ###########################################################################
    if ($do_editcat) {
    
        # Zuerst schauen, ob Aktionen gefordert sind
        if ($do_del) {
            $config->del_databaseinfo($dbname);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showcat=1");
            return Apache2::Const::OK;

        }
        elsif ($do_change) {
            $logger->debug("do_editcat: $do_editcat do_change: $do_change");

            $logger->debug("Info: ".YAML::Dump($thisdbinfo_ref));

            $config->update_databaseinfo($thisdbinfo_ref);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showcat=1");
            return Apache2::Const::OK;
        }
        elsif ($do_new) {

            if ($dbname eq "" || $description eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Katalognamen und eine Beschreibung eingeben."),$r,$msg);

                return Apache2::Const::OK;
            }

            if ($config->db_exists($dbname)) {

                OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein Katalog unter diesem Namen"),$r,$msg);

                return Apache2::Const::OK;
            }

            $config->new_databaseinfo($thisdbinfo_ref);
            
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showcat=1");
            return Apache2::Const::OK;
        }
        elsif ($do_edit) {
            my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
      
            my $ttdata={
                view       => $view,

                stylesheet => $stylesheet,
		  
                databaseinfo    => $dbinfo_ref,
		  
                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editcat_tname},$ttdata,$r);
        }
    }
    elsif ($do_editcat_rss){
        
        if ($do_change) {
	    $config->update_databaseinfo_rss($dbname,$rsstype,$active,$rssid);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_editcat_rss=1&dbname=$dbname&do_edit=1");
            return Apache2::Const::OK;
        }
        elsif ($do_new){
	    $config->new_databaseinfo_rss($dbname,$rsstype);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_editcat_rss=1&dbname=$dbname&do_edit=1");
            return Apache2::Const::OK;              
        }
        
        if ($do_edit) {
            my $rssfeed_ref= $config->get_rssfeeds_of_db($dbname);;
            
            my $katalog={
                dbname      => $dbname,
                rssfeeds    => $rssfeed_ref,
            };
            
            
            my $ttdata={
                view       => $view,
            
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
                
                katalog    => $katalog,
                
                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_admin_editcat_rss_tname},$ttdata,$r);
        }
    }
    elsif ($do_showcat) {
        my $dbinfo_ref = $config->get_dbinfo_overview();

        my $ttdata={
            view       => $view,

            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            kataloge   => $dbinfo_ref,

            config     => $config,
            session    => $session,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showcat_tname},$ttdata,$r);
    }
    elsif ($do_editlibinfo) {
    
        # Zuerst schauen, ob Aktionen gefordert sind
        if ($do_del) {
            $config->del_libinfo($dbname);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showcat=1");
            return Apache2::Const::OK;

        }
        elsif ($do_change) {
            $logger->debug("do_editlibinfo: $do_editlibinfo do_change: $do_change");

            $logger->debug("Info: ".YAML::Dump($thislibinfo_ref));

            $config->update_libinfo($dbname,$thislibinfo_ref);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showcat=1");
            return Apache2::Const::OK;
        }
        elsif ($do_edit) {
            my $libinfo_ref = $config->get_libinfo($dbname);
      
            my $ttdata={
                view       => $view,

                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
                dbname     => $dbname,
                libinfo    => $libinfo_ref,
		  
                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editlibinfo_tname},$ttdata,$r);
        }
    }
    elsif ($do_showprofiles) {
        my $profileinfo_ref = $config->get_profileinfo_overview();

        my $ttdata={
            view       => $view,

            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            profiles   => $profileinfo_ref,
            config     => $config,
            session    => $session,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showprofiles_tname},$ttdata,$r);
    }
    elsif ($do_editprofile) {
    
        # Zuerst schauen, ob Aktionen gefordert sind
    
        if ($do_del) {
	    $config->del_profile($profilename);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showprofiles=1");
            return Apache2::Const::OK;
      
        }
        elsif ($do_change) {
	    $config->update_profile({
                profilename => $profilename,
                description => $description,
            });
            
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showprofiles=1");
      
            return Apache2::Const::OK;
        }
        elsif ($do_new) {

            if ($profilename eq "" || $description eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Profilnamen und eine Beschreibung eingeben."),$r,$msg);

                return Apache2::Const::OK;
            }

	    my $ret = $config->new_profile({
                profilename => $profilename,
                description => $description,
            });

	    if ($ret == -1){
	      OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"),$r,$msg);
	      return Apache2::Const::OK;
	    }

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_editprofile=1&do_edit=1&profilename=$profilename");
            return Apache2::Const::OK;
        }
        elsif ($do_edit) {

	    my $profileinfo_ref = $config->get_profileinfo({ profilename => $profilename })->single();

            my $profilename = $profileinfo_ref->profilename;
            my $description = $profileinfo_ref->description;
            
            my @profiledbs  = $config->get_profiledbs($profilename);

            my $profile={
		profilename  => $profilename,
		description  => $description,
		profiledbs   => \@profiledbs,
            };

            my $ttdata={
                view       => $view,

                stylesheet => $stylesheet,
                sessionID  => $session->{ID},

                profile    => $profile,

                dbnames    => \@dbnames,

                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editprofile_tname},$ttdata,$r);
      
        }
    
    }
    elsif ($do_editorgunit) {
    
        # Zuerst schauen, ob Aktionen gefordert sind
    
        if ($do_del) {
	    $config->del_orgunit($profilename,$orgunit);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_editprofile=1;profilename=$profilename;do_edit=1");
            return Apache2::Const::OK;
      
        }
        elsif ($do_change) {
	    $config->update_orgunit({
                profilename => $profilename,
                orgunit     => $orgunit,
                description => $description,
                orgunitdb   => \@orgunitdb,
                nr          => $nr,
            });
            
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_editprofile=1;profilename=$profilename;do_edit=1");
      
            return Apache2::Const::OK;
        }
        elsif ($do_new) {

            if ($profilename eq "" || $orgunit eq "" || $description eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Profilnamen, den Namen einer Organisationseinheit und deren Beschreibung eingeben."),$r,$msg);

                return Apache2::Const::OK;
            }

	    my $ret = $config->new_orgunit({
                profilename => $profilename,
                orgunit     => $orgunit,
                description => $description,
            });

	    if ($ret == -1){
	      OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits eine Organisationseinheit unter diesem Namen"),$r,$msg);
	      return Apache2::Const::OK;
	    }

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_editorgunit=1&do_edit=1&profilename=$profilename&orgunit=$orgunit");
            return Apache2::Const::OK;
        }
        elsif ($do_edit) {

	    my $profileinfo_ref = $config->get_profileinfo({ profilename => $profilename })->single();
            my $orgunitinfo_ref = $config->get_orgunitinfo($profilename,$orgunit);
           
            my @orgunitdbs   = $config->get_profiledbs($profilename,$orgunit);

            $orgunitinfo_ref->{dbnames} = \@orgunitdbs;
            
            my $ttdata={
                view       => $view,

                stylesheet => $stylesheet,
                sessionID  => $session->{ID},

                profileinfo    => $profileinfo_ref,

                orgunitinfo    => $orgunitinfo_ref,
                
                dbnames    => \@dbnames,

                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editorgunit_tname},$ttdata,$r);
      
        }
    
    }
    elsif ($do_showsubjects) {
        my $subjects_ref = OpenBib::User->get_subjects;

        my $ttdata={
            view       => $view,

            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            subjects   => $subjects_ref,
            config     => $config,
            session    => $session,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showsubjects_tname},$ttdata,$r);
    }
    elsif ($do_editsubject) {
        # Zuerst schauen, ob Aktionen gefordert sind
    
        if ($do_del) {
	    $config->del_subject($subject);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showsubjects=1");
            return Apache2::Const::OK;
      
        }
        elsif ($do_change) {
	    $config->update_subject({
                name                 => $subject,
                description          => $description,
                id                   => $subjectid,
                classifications      => \@classifications,
                type                 => $type,
            });
            
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_editsubject=1;subjectid=$subjectid;do_edit=1");
      
            return Apache2::Const::OK;
        }
        elsif ($do_new) {

            if ($subject eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Namen f&uuml;r das Themenbebiet eingeben."),$r,$msg);

                return Apache2::Const::OK;
            }

	    my $ret = $config->new_subject({
                name        => $subject,
                description => $description,
            });

	    if ($ret == -1){
	      OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein Themengebiet unter diesem Namen"),$r,$msg);
	      return Apache2::Const::OK;
	    }

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showsubjects=1");
            return Apache2::Const::OK;
        }
        elsif ($do_edit) {

	    my $subject_ref = OpenBib::User->get_subject({ id => $subjectid});

            my $ttdata={
                view       => $view,

                stylesheet => $stylesheet,
                sessionID  => $session->{ID},

                subject    => $subject_ref,

                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editsubject_tname},$ttdata,$r);
      
        }
    
    }
    elsif ($do_showops) {
        my $loadbalancertargets_ref = $config->get_loadbalancertargets;

        my $ttdata={
            loadbalancertargets => $loadbalancertargets_ref,

            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            config     => $config,
            session    => $session,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showoperations_tname},$ttdata,$r);
    }
    elsif ($do_editserver) {

        if ($do_del) {
	    $config->del_server({id => $hostid});

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showops=1");
            return Apache2::Const::OK;
      
        }
        elsif ($do_change) {
	    $config->update_server({
                id                   => $hostid,
                active               => $active,
            });
            
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showops=1");
      
            return Apache2::Const::OK;
        }
        elsif ($do_new) {

            if ($host eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen einen Servernamen eingeben."),$r,$msg);

                return Apache2::Const::OK;
            }
            $logger->debug("Host: $host Active: $active");
            
	    my $ret = $config->new_server({
                host                 => $host,
                active               => $active,
            });

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showops=1");
            return Apache2::Const::OK;
        }

        my $loadbalancertargets_ref = $config->get_loadbalancertargets;

        my $ttdata={
            loadbalancertargets => $loadbalancertargets_ref,

            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            config     => $config,
            session    => $session,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showoperations_tname},$ttdata,$r);
    }
    elsif ($do_showviews) {
        my $viewinfo_ref = $config->get_viewinfo_overview();

        my $ttdata={
            view       => $view,

            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            views      => $viewinfo_ref,
            config     => $config,
            session    => $session,
            user       => $user,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_admin_showviews_tname},$ttdata,$r);
    }
    elsif ($do_editview) {
        # Zuerst schauen, ob Aktionen gefordert sind
    
        if ($do_del) {
	    $config->del_view($viewname);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showviews=1");
            return Apache2::Const::OK;
      
        }
        elsif ($do_change) {
	    $config->update_view({
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

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showviews=1");
      
            return Apache2::Const::OK;
        }
        elsif ($do_new) {

            if ($viewname eq "" || $description eq "" || $profilename eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens einen Viewnamen, eine Beschreibung sowie ein Katalog-Profil eingeben."),$r,$msg);

                return Apache2::Const::OK;
            }

	    my $ret = $config->new_view({
				    viewname    => $viewname,
				    description => $description,
                                    profilename => $profilename,
				    active      => $active,
                                    start_loc   => $viewstart_loc,
                                    start_stid  => $viewstart_stid,
                                });

	    if ($ret == -1){
	      OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein View unter diesem Namen"),$r,$msg);
	      return Apache2::Const::OK;
	    }

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_editview=1&do_edit=1&viewname=$viewname");
            return Apache2::Const::OK;
        }
        elsif ($do_edit) {
            my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

	    my $viewinfo_obj  = $config->get_viewinfo($viewname);

            my $viewname    = $viewinfo_obj->viewname;
            my $description = $viewinfo_obj->description;
            my $primrssfeed = $viewinfo_obj->rssfeed;
            my $start_loc   = $viewinfo_obj->start_loc;
            my $start_stid  = $viewinfo_obj->start_stid;
            my $profilename = $viewinfo_obj->profilename;
            my $active      = $viewinfo_obj->active;
             
            my @profiledbs       = $config->get_profiledbs($profilename);

            my @viewdbs          = $config->get_viewdbs($viewname);

            my $all_rssfeeds_ref = $config->get_rssfeed_overview();
            
            my $viewrssfeed_ref=$config->get_rssfeeds_of_view($viewname);

            my $viewinfo={
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
                view       => $view,
                
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
		  
                dbnames    => \@profiledbs,

                viewinfo   => $viewinfo,

                dbinfo     => $dbinfotable,
                
                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_editview_tname},$ttdata,$r);
      
        }
    
    }
    elsif ($do_editview_rss){

      if ($do_change) {

	  $config->update_view_rss({
			       viewname => $viewname,
			       rsstype  => $rsstype,
			       rssid    => $rssid,
			       rssids   => \@rssids,
			      });

          if ($rsstype eq "primary"){
              $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_editview_rss=1&do_edit=1&viewname=$viewname");
              return Apache2::Const::OK;
          }
          elsif ($rsstype eq "all") {
              $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showviews=1");
              return Apache2::Const::OK;
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


          my $viewinfo_ref={
              name        => $viewname,
              description => $viewdesc,
              primrssfeed => $primrssfeed,
              rssfeeds    => $viewrssfeeds_ref,
          };
          
          
          my $ttdata={
              view        => $view,
              
              stylesheet  => $stylesheet,
              sessionID   => $session->{ID},
              
              viewinfo    => $viewinfo_ref,

              allrssfeeds => $allrssfeed_ref,

              config      => $config,
              session     => $session,
              user        => $user,
              msg         => $msg,
          };
          
          OpenBib::Common::Util::print_page($config->{tt_admin_editview_rss_tname},$ttdata,$r);
      }
  }
    elsif ($do_showsessions) {

        my @sessions=$session->get_info_of_all_active_sessions();

        my $ttdata={
            view       => $view,
                
            stylesheet => $stylesheet,

	    session    => $session,
            sessionID  => $session->{ID},
	         
            sessions   => \@sessions,

            config     => $config,
            session    => $session,
            user       => $user,
            msg        => $msg,
        };

	$stid=~s/[^0-9]//g;

	my $templatename = ($stid)?"tt_admin_showsessions_".$stid."_tname":"tt_admin_showsessions_tname";

	OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);

        return Apache2::Const::OK;
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
                view       => $view,

                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
	         
                session    => $singlesession,

                queries    => \@queries,

                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };

            OpenBib::Common::Util::print_page($config->{tt_admin_editsession_tname},$ttdata,$r);

            return Apache2::Const::OK;
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
                view       => $view,

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
            
            return Apache2::Const::OK;
	    
            
	}
        else {
            
            unless ($fromdate && $todate){
                OpenBib::Common::Util::print_warning($msg->maketext("Bitte geben Sie ein Anfangs- sowie ein End-Datum an!"),$r,$msg);
                return Apache2::Const::OK;
                
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
                view       => $view,

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
            
            return Apache2::Const::OK;
	}
    }
    elsif ($do_showstat) {

        my $statistics = new OpenBib::Statistics();

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            
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

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            
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

        # Zuerst schauen, ob Aktionen gefordert sind
        if ($do_del) {
            $config->del_logintarget($targetid);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showlogintarget=1");
            return Apache2::Const::OK;

        }
        elsif ($do_change) {

            $config->update_logintarget($thislogintarget_ref);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showlogintarget=1");
            return Apache2::Const::OK;
        }
        elsif ($do_new) {

            if ($description eq "") {

                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen mindestens eine Beschreibung eingeben."),$r,$msg);

                return Apache2::Const::OK;
            }

            if ($user->logintarget_exists({description => $thislogintarget_ref->{description}})) {

                OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein Anmeldeziel unter diesem Namen"),$r,$msg);

                return Apache2::Const::OK;
            }

            $config->new_logintarget($thislogintarget_ref);
            
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showlogintarget=1");
            return Apache2::Const::OK;
        }
        elsif ($do_edit) {
            
            my $logintarget_ref = $user->get_logintarget_by_id($targetid);
            
            my $ttdata={
                view       => $view,
                
                stylesheet  => $stylesheet,
                sessionID   => $session->{ID},
                
                logintarget => $logintarget_ref,
                
                user        => $user,
                session    => $session,
                config      => $config,
                msg         => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_admin_editlogintarget_tname},$ttdata,$r);
        }
    }
    elsif ($do_showuser) {

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            
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
    ###########################################################################
    elsif ($do_edituser) {

        # Zuerst schauen, ob Aktionen gefordert sind
        if ($do_change) {
            $config->update_user($thisuserinfo_ref);

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{admin_loc}{name}?do_showuser=1;stid=1");
            return Apache2::Const::OK;
        }
        elsif ($do_edit) {
            my $userinfo = new OpenBib::User({ID => $userid })->get_info;
            
            
            my $ttdata={
                view       => $view,

                userinfo   => $userinfo,
                
                stylesheet => $stylesheet,
                sessionID  => $session->{ID},
		  
                config     => $config,
                session    => $session,
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_admin_edituser_tname},$ttdata,$r);
        }
    }
    elsif ($do_searchuser) {

        my $userlist_ref = [];

        # Verbindung zur SQL-Datenbank herstellen
        my $userdbh
            = OpenBib::Database::DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
                or $logger->error_die($DBI::errstr);
        
        my $sql_stmt = "select userid from user where ";
        my @sql_where = ();
        my @sql_args = ();

        if ($roleid) {
            $sql_stmt = "select userid from userrole where roleid=?";
            push @sql_args, $roleid;
        }
        else {
            if ($username) {
                push @sql_where,"loginname = ?";
                push @sql_args, $username;
            }
            
            if ($commonname) {
                push @sql_where, "nachname = ?";
                push @sql_args, $commonname;
            }
            
            if ($surname) {
                push @sql_where, "vorname = ?";
                push @sql_args, $surname;
            }

            if (!@sql_where){
                OpenBib::Common::Util::print_warning($msg->maketext("Bitte geben Sie einen Suchbegriff ein."),$r,$msg);
                return Apache2::Const::OK;
            }
            
            $sql_stmt.=join(" and ",@sql_where);
        }
        

        $logger->debug($sql_stmt);
        
        my $request = $userdbh->prepare($sql_stmt);
        $request->execute(@sql_args);

        $logger->debug("Looking up user $username/$surname/$commonname");
        
        while (my $result=$request->fetchrow_hashref){
            $logger->debug("Found ID $result->{userid}");
            my $single_user = new OpenBib::User({ID => $result->{userid}});
            push @$userlist_ref, $single_user->get_info;
        }
        
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            
            sessionID  => $session->{ID},
            
            session    => $session,
            
            userlist   => $userlist_ref,
            
            user       => $user,
            config     => $config,
            msg        => $msg,
        };
        
	$stid=~s/[^0-9]//g;

	my $templatename = ($stid)?"tt_admin_searchuser_".$stid."_tname":"tt_admin_searchuser_tname";

	OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);


    }
    elsif ($do_logout) {

        my $ttdata={
            view       => $view,
            
            stylesheet => $stylesheet,
            sessionID  => $session->{ID},
            
            config     => $config,
            session    => $session,
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
  
    return Apache2::Const::OK;
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
