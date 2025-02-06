####################################################################
#
#  OpenBib::Mojo::Controller::Users::Searchprofiles
#
#  Dieses File ist (C) 2005-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Users::Searchprofiles;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Users';

sub dispatch_to_user {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatches Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    if (! $user->{ID}){
        return $self->tunnel_through_authenticator;            
    }
    else {
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{searchprofiles_loc}";
        
      return $self->redirect($new_location,303);
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
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

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
    };
    
    return $self->print_page($config->{tt_users_searchprofiles_tname},$ttdata);
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
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
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

    my @catdb          = $config->get_infomatrix_of_active_databases({view => $view, checkeddb_ref => $checkeddb_ref});
    
    # TT-Data erzeugen
    
    my $ttdata={
        targettype     => $targettype,
        profilename    => $profilename,
	profileid      => $profileid,
        catdb          => \@catdb,
    };
    
    return $self->print_page($config->{tt_users_searchprofiles_record_tname},$ttdata,$r);
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
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
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
    
    return $self->print_page($config->{tt_users_searchprofiles_record_edit_tname},$ttdata);
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
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI Args
    my @databases  = ($query->stash('db'))?$query->param('db'):();
    my $profilename = $query->stash('profilename') || '';

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    # Wenn keine Profileid (=kein Profil diesen Namens)
    # existiert, dann Fehlermeldung
    unless ($profileid) {
        return $self->print_warning($msg->maketext("Es existiert kein Profil mit der ID $profileid"));
    }
    
    $user->update_dbprofile($profileid,$profilename,\@databases);

    return $self->return_baseurl;
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');
    my $location       = $self->stash('location');

    # CGI Args
    my @databases   = ($query->stash('db'))?$query->param('db'):();
    my $profilename = $query->stash('profilename') || '';

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    # Wurde ueberhaupt ein Profilname eingegeben?
    if (!$profilename) {
        return $self->print_warning($msg->maketext("Sie haben keinen Profilnamen eingegeben!"));
    }
    
    my $profileid = $user->dbprofile_exists($profilename);
    
    # Wenn Profileid bereits
    # existiert, dann Fehlermeldung.
    if ($profileid) {
        return $self->print_warning($msg->maketext("Es existiert bereits ein Profil unter diesem Namen!"));
    }
    else {
        $profileid = $user->new_dbprofile($profilename,\@databases);
    }

    $logger->debug("Created Profile $profilename with ID $profileid");
    
    if ($self->stash('representation') eq "html"){
        my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/$config->{searchprofiles_loc}/id/$profileid/edit";

        # TODO Get?
        $self->header_add('Content-Type' => 'text/html');
        $self->redirect($new_location);
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($profileid){
            $logger->debug("Weiter zum Record $profileid");
            $self->stash('status','201');
            $self->stash('searchprofileid',$profileid);
            $self->stash('location',"$location/$profileid");
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
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    $user->delete_dbprofile($profileid);

    return $self->return_baseurl;
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $profileid      = $self->strip_suffix($self->stash('searchprofileid'));
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    my $profilename = $user->get_profilename_of_usersearchprofileid($profileid);
    
    my $ttdata={
        profileid   => $profileid,
	profilename => $profilename,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_users_searchprofiles_record_delete_confirm_tname},$ttdata);
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->stash('view')           || '';
    my $userid         = $self->stash('userid')         || '';
    my $path_prefix    = $self->stash('path_prefix');
    my $lang           = $self->stash('lang');
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{searchprofiles_loc}.html?l=$lang";

    # TODO Get?
    $self->header_add('Content-Type' => 'text/html');
    return $self->redirect($new_location);
}

1;
