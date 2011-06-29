####################################################################
#
#  OpenBib::Handler::Apache::Resource::User::Profile
#
#  Dieses File ist (C) 2005-2011 Oliver Flimm <flimm@openbib.org>
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

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'               => 'show_collection',
        'show_record_form'              => 'show_record_form',
        'show_record'                   => 'show_record',
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

    # Dispatches Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my @userdbprofiles = $user->get_all_profiles;
    my $targettype     = $user->get_targettype_of_session($session->{ID});

    my $checkeddb_ref = {};

    my $maxcolumn      = $config->{databasechoice_maxcolumn};
    my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});
    
    # TT-Data erzeugen
    my $colspan=$maxcolumn*3;
    
    my $ttdata={
        targettype     => $targettype,
        userdbprofiles => \@userdbprofiles,
        maxcolumn      => $maxcolumn,
        colspan        => $colspan,
        catdb          => \@catdb,
        dbinfo         => $dbinfotable,
    };
    
    $self->print_page($config->{tt_user_profile_collection_tname},$ttdata);
    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $profileid      = $self->strip_suffix($self->param('profileid'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $method         = $query->param('_method')     || '';

    if (!$self->is_authenticated('user',$userid)){
        return;
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

    my $checkeddb_ref = {};

    foreach my $dbname ($user->get_profiledbs_of_profileid($profileid)){
        $checkeddb_ref->{$dbname}=1;
    }
    
    my $targettype     = $user->get_targettype_of_session($session->{ID});

    my $maxcolumn      = $config->{databasechoice_maxcolumn};
    my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});
    
    # TT-Data erzeugen
    my $colspan=$maxcolumn*3;
    
    my $ttdata={
        targettype     => $targettype,
        profilname     => $profilname,
        maxcolumn      => $maxcolumn,
        colspan        => $colspan,
        catdb          => \@catdb,
    };
    
    $self->print_page($config->{tt_user_profile_tname},$ttdata,$r);
    return Apache2::Const::OK;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $profileid      = $self->strip_suffix($self->param('profileid'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    # Zuerst Profil-Description zur ID holen
    my $profilname = $user->get_profilename_of_profileid($profileid);

    my $checkeddb_ref = {};
    
    foreach my $dbname ($user->get_profiledbs_of_profileid($profileid)){
        $checkeddb_ref->{$dbname}=1;
    }
    
    my $targettype     = $user->get_targettype_of_session($session->{ID});

    my $maxcolumn      = $config->{databasechoice_maxcolumn};
    my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});
    
    # TT-Data erzeugen
    my $colspan=$maxcolumn*3;
    
    my $ttdata={
        targettype     => $targettype,
        profilname     => $profilname,
        profileid      => $profileid,
        maxcolumn      => $maxcolumn,
        colspan        => $colspan,
        catdb          => \@catdb,
    };
    
    $self->print_page($config->{tt_user_profile_edit_tname},$ttdata);
    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $profileid      = $self->strip_suffix($self->param('profileid'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my @databases  = ($query->param('db'))?$query->param('db'):();

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    # Wenn keine Profileid (=kein Profil diesen Namens)
    # existiert, dann Fehlermeldung
    unless ($profileid) {
        $self->print_warning($msg->maketext("Es existiert kein Profil mit der ID $profileid"));
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

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my @databases   = ($query->param('db'))?$query->param('db'):();
    my $profilename = $query->param('profilename') || '';

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    # Wurde ueberhaupt ein Profilname eingegeben?
    if (!$profilename) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keinen Profilnamen eingegeben!"),$r,$msg);
        return Apache2::Const::OK;
    }
    
    my $profileid = $user->dbprofile_exists($profilename);
    
    # Wenn Profileid bereits
    # existiert, dann Fehlermeldung.
    if ($profileid) {
        $self->print_warning($msg->maketext("Es existiert bereits ein Profil unter diesem Namen!"));
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

    my $new_location = "$path_prefix/$config->{user_loc}/$userid/profile/$profileid.html";

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

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $profileid      = $self->strip_suffix($self->param('profileid'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->is_authenticated('user',$userid)){
        return;
    }

    $user->delete_dbprofile($profileid);
    $user->delete_profiledbs($profileid);

    $self->return_baseurl;

    return;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');

    my $config = OpenBib::Config->instance;

    my $new_location = "$path_prefix/$config->{user_loc}/$userid/profile.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
