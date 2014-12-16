####################################################################
#
#  OpenBib::Handler::Apache::Users::Searchprofiles
#
#  Dieses File ist (C) 2005-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Users::Searchprofiles;

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

use base 'OpenBib::Handler::Apache::Users';

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
        'confirm_delete_record'         => 'confirm_delete_record',
        'dispatch_to_representation'    => 'dispatch_to_representation',
        'dispatch_to_user'              => 'dispatch_to_user',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub dispatch_to_user {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view           = $self->param('view');

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

    if (! $user->{ID}){
        return $self->tunnel_through_authenticator;            
    }
    else {
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{searchprofiles_loc}";
        
        return $self->redirect($new_location,'303 See Other');
    }

    return;
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
    
    if (!$self->authorization_successful){
        $self->print_authorization_error();
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
    
    $self->print_page($config->{tt_users_searchprofiles_tname},$ttdata);
    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $profileid      = $self->strip_suffix($self->param('searchprofileid'));

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

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $idnresult="";

    #####################################################################   
    # Anzeigen der Profilmanagement-Seite
    #####################################################################   

    my $profilename="";
    
    # Zuerst Profil-Description zur User-ID holen
    $profilename = $user->get_profilename_of_usersearchprofileid($profileid);

    my $checkeddb_ref = {};

    foreach my $dbname ($user->get_profiledbs_of_usersearchprofileid($profileid)){
        $checkeddb_ref->{$dbname}=1;
    }
    
    my $targettype     = $user->get_targettype_of_session($session->{ID});

    my $maxcolumn      = $config->{databasechoice_maxcolumn};
    my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});
    
    # TT-Data erzeugen
    my $colspan=$maxcolumn*3;
    
    my $ttdata={
        targettype     => $targettype,
        profilename    => $profilename,
        maxcolumn      => $maxcolumn,
        colspan        => $colspan,
        catdb          => \@catdb,
    };
    
    $self->print_page($config->{tt_users_searchprofiles_record_tname},$ttdata,$r);
    return Apache2::Const::OK;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $profileid      = $self->strip_suffix($self->param('searchprofileid'));

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

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    # Zuerst Profil-Description zur ID holen
    my $profilename = $user->get_profilename_of_usersearchprofileid($profileid);

    my $checkeddb_ref = {};
    
    foreach my $dbname ($user->get_profiledbs_of_usersearchprofileid($profileid)){
        $checkeddb_ref->{$dbname}=1;
    }
    
    my $targettype     = $user->get_targettype_of_session($session->{ID});

    my $maxcolumn      = $config->{databasechoice_maxcolumn};
    my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});
    
    # TT-Data erzeugen
    my $colspan=$maxcolumn*3;
    
    my $ttdata={
        targettype     => $targettype,
        profilename    => $profilename,
        profileid      => $profileid,
        maxcolumn      => $maxcolumn,
        colspan        => $colspan,
        catdb          => \@catdb,
    };
    
    $self->print_page($config->{tt_users_searchprofiles_record_edit_tname},$ttdata);
    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $profileid      = $self->strip_suffix($self->param('searchprofileid'));

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
    my $profilename = $query->param('profilename') || '';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    # Wenn keine Profileid (=kein Profil diesen Namens)
    # existiert, dann Fehlermeldung
    unless ($profileid) {
        $self->print_warning($msg->maketext("Es existiert kein Profil mit der ID $profileid"));
        return;
    }
    
    $user->update_dbprofile($profileid,$profilename,\@databases);

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
    my $location       = $self->param('location');

    # CGI Args
    my @databases   = ($query->param('db'))?$query->param('db'):();
    my $profilename = $query->param('profilename') || '';

    if (!$self->authorization_successful){
        $self->print_authorization_error();
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
        $profileid = $user->new_dbprofile($profilename,\@databases);
    }

    $logger->debug("Created Profile $profilename with ID $profileid");
    
    if ($self->param('representation') eq "html"){
        my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/$config->{searchprofiles_loc}/id/$profileid/edit";
        
        $self->query->method('GET');
        $self->query->content_type('text/html');
        $self->query->headers_out->add(Location => $new_location);
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($profileid){
            $logger->debug("Weiter zum Record $profileid");
            $self->param('status',Apache2::Const::HTTP_CREATED);
            $self->param('searchprofileid',$profileid);
            $self->param('location',"$location/$profileid");
            $self->show_record;
        }
    }

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $userid         = $self->param('userid');
    my $profileid      = $self->strip_suffix($self->param('searchprofileid'));

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

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $user->delete_dbprofile($profileid);

    $self->return_baseurl;

    return;
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view');
    my $profileid      = $self->strip_suffix($self->param('searchprofileid'));
    my $config         = $self->param('config');

    my $ttdata={
        profileid => $profileid,
    };
    
    $logger->debug("Asking for confirmation");
    $self->print_page($config->{tt_users_searchprofiles_record_delete_confirm_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');
    my $lang           = $self->param('lang');
    my $user           = $self->param('user');

    my $config = OpenBib::Config->instance;

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{searchprofiles_loc}.html?l=$lang";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
