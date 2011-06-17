####################################################################
#
#  OpenBib::Handler::Apache::Resource::User::Profile
#
#  Dieses File ist (C) 2005-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Resource::User::Profile;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::SubRequest ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'negotiate_url'                 => 'negotiate_url',
        'show_collection_as_html'       => 'show_collection_as_html',
        'show_collection_as_json'       => 'show_collection_as_json',
        'show_collection_as_rdf'        => 'show_collection_as_rdf',
        'show_record_form'              => 'show_record_form',
        'show_record_negotiate'         => 'show_record_negotiate',
        'create_record'                 => 'create_record',
        'update_record'                 => 'update_record',
        'delete_record'                 => 'delete_record',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')           || '';

    my $config = OpenBib::Config->instance;
    
    my $query=Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });        

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
    
    my $queryoptions = OpenBib::QueryOptions->instance($query);

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    unless($user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben sich nicht authentifiziert."),$r,$msg);
        return Apache2::Const::OK;
    }

    #####################################################################   
    # Anzeigen der Profilmanagement-Seite
    #####################################################################   

    my @userdbprofiles = $user->get_all_profiles;
    my $targettype     = $user->get_targettype_of_session($session->{ID});

    my $checkeddb_ref = {};

    my $maxcolumn      = $config->{databasechoice_maxcolumn};
    my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});
    
    # TT-Data erzeugen
    my $colspan=$maxcolumn*3;
    
    my $ttdata={
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $session->{ID},
        targettype     => $targettype,
        userdbprofiles => \@userdbprofiles,
        maxcolumn      => $maxcolumn,
        colspan        => $colspan,
        catdb          => \@catdb,
        dbinfo         => $dbinfotable,
        config         => $config,
        user           => $user,
        msg            => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_resource_user_profile_collection_tname},$ttdata,$r);
    return Apache2::Const::OK;
}

sub show_record_negotiate {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $profileid      = $self->param('profileid')      || '';

    my $config = OpenBib::Config->instance;
    
    my $query=Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });        

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    # CGI Args
    my $method         = $query->param('_method')     || '';

    my $checkeddb_ref;

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    unless($user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben sich nicht authentifiziert."),$r,$msg);
        return Apache2::Const::OK;
    }

    if ($method eq "DELETE"){
        $self->delete_record;
        return;
    }

    my $idnresult="";

    #####################################################################   
    # Anzeigen der Profilmanagement-Seite
    #####################################################################   

    my $profilname="";
    
    # Zuerst Profil-Description zur ID holen
    $profilname = $user->get_profilename_of_profileid($profileid);
    
    foreach my $dbname ($user->get_profiledbs_of_profileid($profileid)){
        $checkeddb_ref->{$dbname}=1;
    }
    
    my $targettype     = $user->get_targettype_of_session($session->{ID});

    my $maxcolumn      = $config->{databasechoice_maxcolumn};
    my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});
    
    # TT-Data erzeugen
    my $colspan=$maxcolumn*3;
    
    my $ttdata={
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $session->{ID},
        targettype     => $targettype,
        profilname     => $profilname,
        maxcolumn      => $maxcolumn,
        colspan        => $colspan,
        catdb          => \@catdb,
        config         => $config,
        user           => $user,
        msg            => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_resource_user_profile_tname},$ttdata,$r);
    return Apache2::Const::OK;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $profileid      = $self->param('profileid')      || '';

    my $config = OpenBib::Config->instance;
    
    my $query=Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });        

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    my $checkeddb_ref;

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    unless($user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben sich nicht authentifiziert."),$r,$msg);
        return Apache2::Const::OK;
    }

    my $idnresult="";

    #####################################################################   
    # Anzeigen der Profilmanagement-Seite
    #####################################################################   

    my $profilname="";
    
    # Zuerst Profil-Description zur ID holen
    $profilname = $user->get_profilename_of_profileid($profileid);
    
    foreach my $dbname ($user->get_profiledbs_of_profileid($profileid)){
        $checkeddb_ref->{$dbname}=1;
    }
    
    my $targettype     = $user->get_targettype_of_session($session->{ID});

    my $maxcolumn      = $config->{databasechoice_maxcolumn};
    my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});
    
    # TT-Data erzeugen
    my $colspan=$maxcolumn*3;
    
    my $ttdata={
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $session->{ID},
        targettype     => $targettype,
        profilname     => $profilname,
        profileid      => $profileid,
        maxcolumn      => $maxcolumn,
        colspan        => $colspan,
        catdb          => \@catdb,
        config         => $config,
        user           => $user,
        msg            => $msg,
    };
    
    OpenBib::Common::Util::print_page($config->{tt_resource_user_profile_edit_tname},$ttdata,$r);
    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $profileid      = $self->param('profileid')      || '';

    my $config = OpenBib::Config->instance;
    
    my $query=Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });        

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Uebergabe
    my @databases  = ($query->param('db'))?$query->param('db'):();

    my $checkeddb_ref;

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    unless($user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben sich nicht authentifiziert."),$r,$msg);
        return Apache2::Const::OK;
    }

    my $idnresult="";


    # Wenn keine Profileid (=kein Profil diesen Namens)
    # existiert, dann Fehlermeldung
    unless ($profileid) {
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert kein Profil mit der ID $profileid"),$r,$msg);
        return;
    }
    
    # Jetzt habe ich eine profileid und kann Eintragen
    # Auswahl wird immer durch aktuelle ueberschrieben.
    # Daher erst potentiell loeschen
    $user->delete_profiledbs($profileid);
    
    foreach my $database (@databases) {
        # ... und dann eintragen
        $user->add_profiledb($profileid,$database);
    }

    $self->return_baseurl;

    return;
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;
    
    my $query=Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });        

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    # CGI-Uebergabe
    my @databases  = ($query->param('db'))?$query->param('db'):();

    # Main-Actions
    my $profilename = $query->param('profilename') || '';
 
    my $checkeddb_ref;

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    unless($user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben sich nicht authentifiziert."),$r,$msg);
        return Apache2::Const::OK;
    }

    my $idnresult="";

    # Wurde ueberhaupt ein Profilname eingegeben?
    if (!$profilename) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keinen Profilnamen eingegeben!"),$r,$msg);
        return Apache2::Const::OK;
    }
    
    my $profileid = $user->dbprofile_exists($profilename);
    
    # Wenn Profileid bereits
    # existiert, dann Fehlermeldung.
    if ($profileid) {
        OpenBib::Common::Util::print_warning($msg->maketext("Es existiert bereits ein Profil unter diesem Namen!"),$r,$msg);
        return;
    }
    else {
        $profileid = $user->new_dbprofile($profilename);
    }
    
    # Jetzt habe ich eine profileid und kann Eintragen
    # Auswahl wird immer durch aktuelle ueberschrieben.
    # Daher erst potentiell loeschen
    $user->delete_profiledbs($profileid);
    
    foreach my $database (@databases) {
        # ... und dann eintragen
        $user->add_profiledb($profileid,$database);
    }

    my $new_location = "$path_prefix/$config->{resource_user_loc}/$userid/profile/$profileid.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    $self->return_baseurl;

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $profileid      = $self->param('profileid')      || '';

    my $config = OpenBib::Config->instance;
    
    my $query=Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });        

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    unless($user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben sich nicht authentifiziert."),$r,$msg);
        return Apache2::Const::OK;
    }

    my $idnresult="";

    $user->delete_dbprofile($profileid);
    $user->delete_profiledbs($profileid);

    $self->return_baseurl;

    return;
}
    
sub show_collectionzzz {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;
    
    my $query=Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });        

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Uebergabe
    my @databases  = ($query->param('db'))?$query->param('db'):();

    # Main-Actions
    my $do_showprofile = $query->param('do_showprofile') || '';
    my $do_saveprofile = $query->param('do_saveprofile') || '';
    my $do_delprofile  = $query->param('do_delprofile' ) || '';

    my $newprofile = $query->param('newprofile') || '';
    my $profileid   = $query->param('profileid')   || '';

    my $checkeddb_ref;

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    unless($user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben sich nicht authentifiziert."),$r,$msg);
        return Apache2::Const::OK;
    }

    my $idnresult="";

    #####################################################################   
    # Anzeigen der Profilmanagement-Seite
    #####################################################################   

    if ($do_showprofile) {
        my $profilname="";
    
        if ($profileid) {
            # Zuerst Profil-Description zur ID holen
            $profilname = $user->get_profilename_of_profileid($profileid);

            foreach my $dbname ($user->get_profiledbs_of_profileid($profileid)){
                $checkeddb_ref->{$dbname}=1;
            }
        }
    
        my @userdbprofiles = $user->get_all_profiles;
        my $targettype     = $user->get_targettype_of_session($session->{ID});

        my $maxcolumn      = $config->{databasechoice_maxcolumn};
        my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});

        # TT-Data erzeugen
        my $colspan=$maxcolumn*3;
    
        my $ttdata={
            view           => $view,
            stylesheet     => $stylesheet,
            sessionID      => $session->{ID},
            targettype     => $targettype,
            profilname     => $profilname,
            userdbprofiles => \@userdbprofiles,
            maxcolumn      => $maxcolumn,
            colspan        => $colspan,
            catdb          => \@catdb,
            config         => $config,
            user           => $user,
            msg            => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_databaseprofile_tname},$ttdata,$r);
        return Apache2::Const::OK;
    }

    #####################################################################   
    # Abspeichern eines Profils
    #####################################################################   

    elsif ($do_saveprofile) {
    
        # Wurde ueberhaupt ein Profilname eingegeben?
        if (!$newprofile) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keinen Profilnamen eingegeben!"),$r,$msg);
            return Apache2::Const::OK;
        }

        my $profileid = $user->dbprofile_exists($newprofile);

        # Wenn noch keine Profileid (=kein Profil diesen Namens)
        # existiert, dann wird eins erzeugt.
        unless ($profileid) {
            $profileid = $user->new_dbprofile($newprofile);
        }
    
        # Jetzt habe ich eine profileid und kann Eintragen
        # Auswahl wird immer durch aktuelle ueberschrieben.
        # Daher erst potentiell loeschen
        $user->delete_profiledbs($profileid);
    
        foreach my $database (@databases) {
            # ... und dann eintragen
            $user->add_profiledb($profileid,$database);
        }
        $r->internal_redirect("http://$r->get_server_name$path_prefix/$config->{databaseprofile_loc}?do_showprofile=1");
    }
    # Loeschen eines Profils
    elsif ($do_delprofile) {
        $user->delete_dbprofile($profileid);
        $user->delete_profiledbs($profileid);

        $r->internal_redirect("http://$r->get_server_name$path_prefix/$config->{databaseprofile_loc}?do_showprofile=1");
    }
    # ... andere Aktionen sind nicht erlaubt
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Keine gültige Aktion"),$r,$msg);
    }
    return Apache2::Const::OK;
}

sub show_collectionxxx {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;
    
    my $query=Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });        

    my $user    = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    # CGI-Uebergabe
    my @databases  = ($query->param('db'))?$query->param('db'):();

    # Main-Actions
    my $do_showprofile = $query->param('do_showprofile') || '';
    my $do_saveprofile = $query->param('do_saveprofile') || '';
    my $do_delprofile  = $query->param('do_delprofile' ) || '';

    my $newprofile = $query->param('newprofile') || '';
    my $profileid   = $query->param('profileid')   || '';

    my $checkeddb_ref;

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    unless($user->{ID}){
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben sich nicht authentifiziert."),$r,$msg);
        return Apache2::Const::OK;
    }

    my $idnresult="";

    #####################################################################   
    # Anzeigen der Profilmanagement-Seite
    #####################################################################   

    if ($do_showprofile) {
        my $profilname="";
    
        if ($profileid) {
            # Zuerst Profil-Description zur ID holen
            $profilname = $user->get_profilename_of_profileid($profileid);

            foreach my $dbname ($user->get_profiledbs_of_profileid($profileid)){
                $checkeddb_ref->{$dbname}=1;
            }
        }
    
        my @userdbprofiles = $user->get_all_profiles;
        my $targettype     = $user->get_targettype_of_session($session->{ID});

        my $maxcolumn      = $config->{databasechoice_maxcolumn};
        my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});

        # TT-Data erzeugen
        my $colspan=$maxcolumn*3;
    
        my $ttdata={
            view           => $view,
            stylesheet     => $stylesheet,
            sessionID      => $session->{ID},
            targettype     => $targettype,
            profilname     => $profilname,
            userdbprofiles => \@userdbprofiles,
            maxcolumn      => $maxcolumn,
            colspan        => $colspan,
            catdb          => \@catdb,
            config         => $config,
            user           => $user,
            msg            => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_databaseprofile_tname},$ttdata,$r);
        return Apache2::Const::OK;
    }

    #####################################################################   
    # Abspeichern eines Profils
    #####################################################################   

    elsif ($do_saveprofile) {
    
        # Wurde ueberhaupt ein Profilname eingegeben?
        if (!$newprofile) {
            OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keinen Profilnamen eingegeben!"),$r,$msg);
            return Apache2::Const::OK;
        }

        my $profileid = $user->dbprofile_exists($newprofile);

        # Wenn noch keine Profileid (=kein Profil diesen Namens)
        # existiert, dann wird eins erzeugt.
        unless ($profileid) {
            $profileid = $user->new_dbprofile($newprofile);
        }
    
        # Jetzt habe ich eine profileid und kann Eintragen
        # Auswahl wird immer durch aktuelle ueberschrieben.
        # Daher erst potentiell loeschen
        $user->delete_profiledbs($profileid);
    
        foreach my $database (@databases) {
            # ... und dann eintragen
            $user->add_profiledb($profileid,$database);
        }
        $r->internal_redirect("http://$r->get_server_name$path_prefix/$config->{databaseprofile_loc}?do_showprofile=1");
    }
    # Loeschen eines Profils
    elsif ($do_delprofile) {
        $user->delete_dbprofile($profileid);
        $user->delete_profiledbs($profileid);

        $r->internal_redirect("http://$r->get_server_name$path_prefix/$config->{databaseprofile_loc}?do_showprofile=1");
    }
    # ... andere Aktionen sind nicht erlaubt
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Keine gültige Aktion"),$r,$msg);
    }
    return Apache2::Const::OK;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;

    my $new_location = "$path_prefix/$config->{resource_user_loc}/$userid/profile.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
