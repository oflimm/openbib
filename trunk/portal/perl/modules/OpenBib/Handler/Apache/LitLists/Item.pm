#####################################################################
#
#  OpenBib::Handler::Apache::LitList::Item.pm
#
#  Copyright 2009-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::LitList::Item;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Apache2::Reload;
use Apache2::Request;
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

use OpenBib::Search::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

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
    my $sorttype       = $query->param('srt')    || "person";
    my $sortorder      = $query->param('srto')   || "asc";

    my $items = $user->get_litlistentries({litlistid => $litlistid, sortorder => $sortorder, sorttype => $sorttype});

    # TT-Data erzeugen
    my $ttdata = {
        items       => $items,
    };
    
    $self->print_page($config->{tt_litlists_item_tname},$ttdata);
    return Apache2::Const::OK;
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

    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;
    my $subjects_ref   = $user->get_subjects;
    
    my $litlist_is_public = $user->litlist_is_public({litlistid => $litlistid});
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;
    my $userrole_ref = $user->get_roles_of_user($user->{ID}) if ($user_owns_litlist);

    if (!$user_owns_litlist){
        $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
        
        # Aufruf der privaten Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
        
        return;
    }

    if ($method eq "DELETE"){
        $self->delete_record;
        return;
    }
 
    my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
        
    my $singlelitlistitem = $user->get_single_litlistentry({ litlistid => $litlistid, itemid => $itemid });

    if (!%$singlelitlistitem){
        $self->print_warning("Dieser Eintrag in der Literaturliste existiert nicht.");
    }
    
    # TT-Data erzeugen
    my $ttdata={
        litlistitem    => $singlelitlistitem,
        dbinfo         => $dbinfotable,
    };
    
    $self->print_page($config->{tt_litlists_item_record_tname},$ttdata);

    return Apache2::Const::OK;
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
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if ($input_data_ref->{error} == 1){
        $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
        return Apache2::Const::OK;
    }

    $input_data_ref->{litlistid} = $litlistid;
    
    if (!$litlistid && ( (!$input_data_ref->{titleid} && !$input_data_ref->{dbname}) || !$input_data_ref->{record}) ){
        $self->print_warning($msg->maketext("Sie haben entweder keine entsprechende Liste eingegeben, Titel und Datenbank existieren nicht oder Sie haben die Daten nicht via JSON geliefert."));
        
        return Apache2::Const::OK;
    }
        
    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;
        
    if (!$user_owns_litlist) {
        $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));
        
        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
        
        return;
    }

    my $new_itemid = $user->add_litlistentry($input_data_ref);

    if ($self->param('representation') eq "html"){
        my $new_location = "$path_prefix/$config->{litlists_loc}/id/$litlistid/edit";
        
        $self->query->method('GET');
        $self->query->content_type('text/html');
        $self->query->headers_out->add(Location => $new_location);
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_itemid){
            $logger->debug("Weiter zum Record $new_itemid");
            $self->param('status',Apache2::Const::HTTP_CREATED);
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
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if ($input_data_ref->{error} == 1){
        $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
        return Apache2::Const::OK;
    }
    
    $input_data_ref->{litlistid} = $litlistid;
    $input_data_ref->{itemid}    = $itemid;

    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;

    if (!$user_owns_litlist) {
        $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));

        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });

        return;
    }

    if ($user->update_litlistentry($input_data_ref) > 0){
        $self->print_warning($msg->maketext("Der Eintrag in der Literaturliste existiert nicht"));
        return Apache2::Const::OK;
    }   
    
    return unless ($self->param('representation') eq "html");

    # Anpassen eines Kommentars
    
    my $new_location = "$path_prefix/$config->{litlists_loc}/id/$litlistid/edit";
    
    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

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
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');    
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    if (!$itemid || !$litlistid) {
        $self->print_warning($msg->maketext("Keine Titelid, Titel-Datenbank oder Literaturliste vorhanden."));
        
        return Apache2::Const::OK;
    }

    my $user_owns_litlist = ($user->{ID} eq $user->get_litlist_owner({litlistid => $litlistid}))?1:0;

    if (!$user_owns_litlist) {
        $self->print_warning($msg->maketext("Ihnen geh&ouml;rt diese Literaturliste nicht."));

        # Aufruf der Literaturlisten durch "Andere" loggen
        $session->log_event({
            type      => 800,
            content   => $litlistid,
        });
        
        return;
    }
    
    $user->del_litlistentry({ entryid => $itemid, litlistid => $litlistid});

    return unless ($self->param('representation') eq "html");

    my $new_location = "$path_prefix/$config->{litlists_loc}/id/$litlistid/edit";
    
    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

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

    my $new_location = "$path_prefix/$config->{users_loc}/id/$userid/litlists.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

    return;
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
