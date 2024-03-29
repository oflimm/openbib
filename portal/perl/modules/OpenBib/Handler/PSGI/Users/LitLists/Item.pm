#####################################################################
#
#  OpenBib::Handler::PSGI::Users::LitLists::Item.pm
#
#  Copyright 2009-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Users::LitLists::Item;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Benchmark ':hireswallclock';
use Encode qw(decode_utf8);
use DBI;
use JSON::XS;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;
use URI::Escape;
use XML::RSS;
use YAML::Syck;

use OpenBib::Search::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show_collection'                          => 'show_collection',
        'create_record'                            => 'create_record',
        'update_record'                            => 'update_record',
        'delete_record'                            => 'delete_record',
        'show_record'                              => 'show_record',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

# Alle Titel in der Literaturliste
sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $litlistid      = $self->param('litlistid');

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

    # CGI Args
    my $sorttype       = $query->param('srt')    || "tstamp";
    my $sortorder      = $query->param('srto')   || "desc";

    if ($logger->is_debug){
	$logger->debug("A Litlist QueryOptions-Object with options ".YAML::Syck::Dump($queryoptions->get_options));
    }
    
    my $items = $user->get_litlistentries({litlistid => $litlistid, queryoptions => $queryoptions, view => $view});

    # TT-Data erzeugen
    my $ttdata = {
        items       => $items,
    };
    
    return $self->print_page($config->{tt_users_litlists_item_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view');
    my $litlistid      = $self->param('litlistid');
    my $itemid         = $self->strip_suffix($self->param('itemid')) || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    
    # CGI Args
    my $method         = $query->param('_method')     || '';

    my $litlist_is_public = $user->litlist_is_public({litlistid => $litlistid});
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;
    my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);

    if (!$user_owns_litlist){
        # Aufruf der privaten Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
        
        return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
    }

    if ($method eq "DELETE"){
        return $self->delete_record;
    }
 
    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid, view => $view});
        
    my $singlelitlistitem = $user->get_single_litlistentry({ litlistid => $litlistid, itemid => $itemid });

    if (!%$singlelitlistitem){
        return $self->print_warning("Dieser Eintrag in der Literaturliste existiert nicht.");
    }
    
    # TT-Data erzeugen
    my $ttdata={
        litlistitem    => $singlelitlistitem,
    };
    
    return $self->print_page($config->{tt_litlists_item_record_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $litlistid      = $self->param('litlistid')             || '';
    my $representation = $self->param('representation') || 'html';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if ($input_data_ref->{error} == 1){
        return $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
    }

    $input_data_ref->{litlistid} = $litlistid;
    
    if (!$litlistid && ( (!$input_data_ref->{titleid} && !$input_data_ref->{dbname}) || !$input_data_ref->{record}) ){
        return $self->print_warning($msg->maketext("Sie haben entweder keine entsprechende Liste eingegeben, Titel und Datenbank existieren nicht oder Sie haben die Daten nicht via JSON geliefert."));
    }
        
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;
        
    if (!$user_owns_litlist) {
        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
        
        return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
    }

    my $new_itemid = $user->add_litlistentry($input_data_ref);

    if ($self->param('representation') eq "html"){
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{litlists_loc}/id/$litlistid/edit.html?l=$lang";

        # TODO GET?
        $self->header_add('Content-Type' => 'text/html');
        $self->redirect($new_location);
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_itemid){
            $logger->debug("Weiter zum Record $new_itemid");
            $self->param('status',201);
            $self->param('itemid',$new_itemid);
            $self->param('location',"$location/$new_itemid");
            $self->show_record;
        }
    }

    return;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view');
    my $litlistid      = $self->param('litlistid')               || '';
    my $itemid         = $self->strip_suffix($self->param('itemid')) || '';
    my $representation = $self->param('representation') || 'html';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if ($input_data_ref->{error} == 1){
        return $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
    }
    
    $input_data_ref->{litlistid} = $litlistid;
    $input_data_ref->{itemid}    = $itemid;

    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;

    if (!$user_owns_litlist) {
        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });

        return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
    }

    if ($user->update_litlistentry($input_data_ref) > 0){
        return $self->print_warning($msg->maketext("Der Eintrag in der Literaturliste existiert nicht"));
    }   
    
    if ($self->param('representation') eq "html"){
        # Anpassen eines Kommentars
        
        my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{litlists_loc}/id/$litlistid/edit.html?l=$lang";

        # TODO GET?
        $self->header_add('Content-Type' => 'text/html');
        $self->redirect($new_location);
    }
    else {
        $logger->debug("Weiter zum Record $itemid");
        $self->show_record;
    }

    return;

}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $litlistid      = $self->param('litlistid')      || '';
    my $itemid         = $self->strip_suffix($self->param('itemid')) || '';
    my $representation = $self->param('representation') || 'html';
    
    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    if (!$itemid || !$litlistid) {
        return $self->print_warning($msg->maketext("Keine Titelid, Titel-Datenbank oder Literaturliste vorhanden."));
    }

    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;

    if (!$user_owns_litlist) {
        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
        
        return $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
    }
    
    $user->del_litlistentry({ entryid => $itemid, litlistid => $litlistid});

    return unless ($self->param('representation') eq "html");

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{litlists_loc}/id/$litlistid/edit.html?l=$lang";

    $logger->debug("Redirecting to $new_location");
    
    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    return $self->redirect($new_location,303);
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/litlists.html";

    $logger->debug("Redirecting to $new_location");

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    return $self->redirect($new_location,303);
}

sub get_input_definition {
    my $self=shift;
    
    return {
        titleid => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        dbname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        record => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        comment => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
    };
}

1
;
