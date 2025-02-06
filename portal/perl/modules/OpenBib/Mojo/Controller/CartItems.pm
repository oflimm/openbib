#####################################################################
#
#  OpenBib::Mojo::Controller::CartItems
#
#  Dieses File ist (C) 2001-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::CartItems;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use URI::Escape;

use DBI;
use Data::Pageset;
use Email::Valid;
use Encode qw/decode_utf8 encode_utf8/;
use Email::Stuffer;
use File::Slurper qw/read_binary read_text/;
use HTML::Entities qw/decode_entities/;
use HTML::Escape qw/escape_html/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::User;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_collection {
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

    # CGI Args
    my $method                  = $r->param('_method')                 || '';
    my $dbname                  = $r->param('dbname')                  || '';
    my $titleid                 = $r->param('titleid')                 || '';
    my $action                  = $r->param('action')                  || 'show';
    my $show                    = $r->param('show')                    || 'short';
    my $type                    = $r->param('type')                    || 'HTML';
    my $format                  = $r->param('format')                  || 'short';
    
    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
#     # Shortcuts via Method

#     if ($method eq "POST"){
#         $self->create_record;
#         return;
#     }

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $logger->info("SessionID: $session->{ID}");
    
    my $recordlist = $self->get_items_in_collection();

    # if ($recordlist->get_size() != 0) {
    #     my $sorttype          = $queryoptions->get_option('srt');
    #     my $sortorder         = $queryoptions->get_option('srto');
        
    #     if ($sortorder && $sorttype){
    #         $recordlist->sort({order=>$sortorder,type=>$sorttype});
    #     }
    # }

    my $total_count = $self->get_number_of_items_in_collection();
    
    my $nav = Data::Pageset->new({
        'total_entries'    => $total_count,
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });
    
    # TT-Data erzeugen
    my $ttdata={
        qopts             => $queryoptions->get_options,
        format            => $format,

	hits              => $total_count,
	nav               => $nav,
        recordlist        => $recordlist,

	highlightquery    => \&highlightquery,
	sort_circulation => \&sort_circulation,
	
    };
    
    return $self->print_page($config->{tt_cartitems_tname},$ttdata);
}

sub show_collection_count {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';

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
    my $database                = $r->param('db')                || '';
    my $singleidn               = $r->param('singleidn')               || '';
    my $litlistid               = $r->param('litlistid')               || '';
    my $do_collection_delentry  = $r->param('do_collection_delentry')  || '';
    my $do_collection_showcount = $r->param('do_collection_showcount') || '';
    my $do_litlist_addentry     = $r->param('do_litlist_addentry')     || '';
    my $do_addlitlist           = $r->param('do_addlitlist')           || '';
    my $do_addtags              = $r->param('do_addtags')              || '';
    my $title                   = $r->param('title')                   || '';
    my $action                  = $r->param('action')                  || 'show';
    my $show                    = $r->param('show')                    || 'short';
    my $type                    = $r->param('type')                    || 'HTML';
    my $tags                    = $r->param('tags')                    || '';
    my $tags_type               = $r->param('tags_type')               || 1;
    my $littype                 = $r->param('littype')                 || 1;

    my $format                  = $r->param('format')                  || 'short';

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $logger->info("SessionID: $session->{ID}");
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    # Dementsprechend einen LoginLink oder ein ProfilLink ausgeben
    
    my $anzahl = $self->get_number_of_items_in_collection();
    
    # Start der Ausgabe mit korrektem Header
    $self->header_add('Content-Type','text/plain');

    return $anzahl;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $id             = $self->strip_suffix($self->param('itemid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');    
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');    
    my $useragent      = $self->stash('useragent');
    
    # CGI Args
    my $method         = $r->param('_method')     || '';

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
    my $record = $self->get_single_item_in_collection($id);
    
    # TT-Data erzeugen
    my $ttdata={
        record         => $record,
        query          => $query,
        qopts          => $queryoptions->get_options,

	highlightquery    => \&highlightquery,
	sort_circulation => \&sort_circulation,	
        
    };
    
    return $self->print_page($config->{tt_cartitems_record_tname},$ttdata);
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
    my $do_cartitems_save       = $r->param('do_cartitems_save')     || '';
    my $do_cartitems_delentry   = $r->param('do_cartitems_delentry') || '';
    my $do_litlists_addentry    = $r->param('do_litlists_addentry')  || '';
    my $do_addlitlist           = $r->param('do_addlitlist')         || '';
    my $do_addtags              = $r->param('do_addtags')            || '';

    my $tags                    = $r->param('tags')                  || '';
    my $tags_type               = $r->param('tags_type')             || 1;
    my $litlistid               = $r->param('litlistid')             || '';
    my $title                   = $r->param('title')                 || '';
    my $littype                 = $r->param('littype')               || 1;

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    # Process WWW-UI-Shortcuts
    if ($do_cartitems_save) {
	return $self->save_collection;
    }
    elsif ($do_cartitems_delentry || $do_litlists_addentry || $do_addlitlist || $do_addtags ) {

        # Shortcut: Delete multiple items via POST
        if ($r->param('do_cartitems_delentry')) {
            foreach my $listid ($r->param('id')) {
                $self->delete_item_from_collection($listid);
            }
            
            $self->return_baseurl;
            
            return;
        }
        
        if (! $user->is_authenticated && $do_addlitlist) {
            $logger->debug("Nicht authentifizierter Nutzer versucht Literaturlisten anzulegen");

            $self->tunnel_through_authenticator('POST');
            return;
        }
        elsif (! $user->is_authenticated && $do_addtags) {
            $logger->debug("Nicht authentifizierter Nutzer versucht Tags anzulegen");

            $self->tunnel_through_authenticator('POST');
            return;
        }
        
        if ($do_litlists_addentry) {
            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid, view => $view});
            
            foreach my $listid ($r->param('id')) {
                my $record = $self->get_single_item_in_collection($listid);
                
                if ($record && $litlist_properties_ref->{userid} eq $user->{ID}) {
                    $user->add_litlistentry({ titleid => $record->{id}, dbname => $record->{database}, litlistid => $litlistid});
                }
            }
            
            $self->return_baseurl;
            
            return;            
        }
        elsif ($do_addlitlist) {
            if (!$title) {
                return $self->print_warning($msg->maketext("Sie müssen einen Titel f&uuml;r Ihre Literaturliste eingeben."));
            }
            
            my $new_litlistid = $user->add_litlist({ title =>$title, type => $littype});

            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $new_litlistid, view => $view});

            $logger->debug("Created new Litlist with id $new_litlistid");
            
            foreach my $listid ($r->param('id')) {
                my $record = $self->get_single_item_in_collection($listid);

                $logger->debug("Record properties Id: $record->{id} database: $record->{database}");
                
                if ($record->{database} && $record->{id} && $litlist_properties_ref->{userid} eq $user->{ID}) {
                    $logger->debug("Adding entry $listid for userid $user->{ID} for litlist $new_litlistid with ownerid $litlist_properties_ref->{userid}");

                    $user->add_litlistentry({ titleid => $record->{id}, dbname => $record->{database}, litlistid => $new_litlistid});
                }
                else {
                    $logger->debug("Can't add entry $listid for userid $user->{ID} for litlist $new_litlistid with ownerid $litlist_properties_ref->{userid}");
                }
            }

            $self->return_baseurl;
            return;
        }
        elsif ($do_addtags) {
            if (!$tags) {
                return $self->print_warning($msg->maketext("Sie müssen Tags f&uuml;r die ausgew&auml;hlten Titel eingeben."));
            }
            
            if ($user->{ID}){
                my $username = $user->get_username;
                
                if ($r->param('id')){
                    foreach my $listid ($r->param('id')) {
                        my $record = $self->get_single_item_in_collection($listid);
                        
                        if ($record){
                            $user->add_tags({
                                tags      => $tags,
                                titleid   => $record->{id},
                                dbname    => $record->{database},
                                userid    => $user->{ID},
                                type      => $tags_type,
                            });
                        }
                    }
                }
                else {
                    return $self->print_warning($msg->maketext("Sie haben keine Titel ausgew&auml;hlt."));
                }
            }
            else {
                return $self->print_warning($msg->maketext("Bitte authentifizieren Sie sich unter Mein KUG."));
            }
            
            return $self->return_baseurl;
        }
    }
    else {
   
        # CGI / JSON input
        my $input_data_ref = $self->parse_valid_input();
        
        if (defined $input_data_ref->{error} && $input_data_ref->{error} == 1){
            return $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
        }
        
        # Einfuegen eines Titels in die Merkliste
        my $new_titleid = $self->add_item_to_collection($input_data_ref);
        
        if ($self->stash('representation') eq "html" || $self->param('representation') eq "include"){
	    my $ttdata={
		cartitem_id => $new_titleid,
		input_data  => $input_data_ref,
		view        => $view,
		userid      => $userid,
		highlightquery    => \&highlightquery,
		sort_circulation => \&sort_circulation,
		
	    };
	    
            return $self->print_page($config->{tt_cartitems_add_tname},$ttdata);
        }
        else {
            $logger->debug("Weiter zum Record");
            if ($new_titleid){
                $logger->debug("Weiter zur Titelid $new_titleid");
                $self->stash('status',201); # created
                $self->stash('itemid',$new_titleid);
                $self->stash('location',"$location/item/".uri_escape_utf8($new_titleid));
                $self->show_record;
                return;
            }
        }
    }
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')                        || '';
    my $itemid         = $self->strip_suffix($self->param('itemid')) || '';

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
    
    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{itemid} = $itemid;
    
    if (defined $input_data_ref->{error} && $input_data_ref->{error} == 1){
        return $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
    }

    # Einfuegen eines Titels in die Merkliste
    $self->update_item_in_collection($input_data_ref);

    return unless ($self->stash('representation') eq "html" || $self->param('representation') eq "include" );

    my $ttdata={
	cartitem_id => $itemid,
	input_data  => $input_data_ref,
	view        => $view,
	highlightquery    => \&highlightquery,
	sort_circulation => \&sort_circulation,

    };
    
    return $self->print_page($config->{tt_cartitems_add_tname},$ttdata);    
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('itemid'));

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
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $self->delete_item_from_collection($id);

    return unless ($self->stash('representation') eq "html");
    
    $self->return_baseurl;

    return;
}

sub print_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatches Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $id             = $self->strip_suffix($self->decode_id($self->param('titleid')));

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
    my $format                  = $r->param('format')                || '';
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $logger->info("SessionID: $session->{ID}");

    my $username=$user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title();

    # Druck eines Titels
    if ($id && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $id}));
	$recordlist->load_full_records;	
    }
    else {
        $recordlist = $self->get_items_in_collection()
    }
    
    my $total_count = $self->get_number_of_items_in_collection();    

    my $nav = Data::Pageset->new({
        'total_entries'    => $total_count,
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });
    
    # TT-Data erzeugen
    my $ttdata={
        qopts      => $queryoptions->get_options,		
        format     => $format,

        username   => $username,
        id         => $id,
        database   => $database,
        recordlist => $recordlist,

	highlightquery    => \&highlightquery,
	sort_circulation => \&sort_circulation,
    };
        
    return $self->print_page($config->{tt_cartitems_print_tname},$ttdata);
}

sub save_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched_args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $id             = $self->strip_suffix($self->decode_id($self->param('titleid')));

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
    my $format                  = $r->param('format')                || '';

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $logger->info("SessionID: $session->{ID}");

    my $username=$user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title();
    
    if ($id && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $id}));
	$recordlist->load_full_records;
    }
    else {
        $recordlist = $self->get_items_in_collection()
    }
    
    my $total_count = $self->get_number_of_items_in_collection();
    
    my $nav = Data::Pageset->new({
        'total_entries'    => $total_count,
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });
    
    # TT-Data erzeugen
    my $ttdata={
        qopts       => $queryoptions->get_options,		
        format      => $format,

	hits        => $total_count,
	nav         => $nav,		
        recordlist  => $recordlist,

	highlightquery    => \&highlightquery,
	sort_circulation => \&sort_circulation,
	
    };

    my $filename = "merkliste";

    if ($id && $database){
	$filename = "titel_${database}_$id";
    }

    $filename =~s/\W/_/g;
    
    my $formatinfo_ref = $config->get('export_formats');

    my $content_type = "text/plain";
    my $filesuffix   = "txt";
    
    if (defined $formatinfo_ref->{$format} && $formatinfo_ref->{$format}){
	$content_type = $formatinfo_ref->{$format}{'content-type'};
	$filesuffix   = $formatinfo_ref->{$format}{'suffix'};
    }

    $self->stash('content_type',$content_type);
    $self->header_add("Content-Disposition" => "attachment;filename=\"${filename}.$filesuffix\"");
    return $self->print_page($config->{tt_cartitems_save_plain_tname},$ttdata);

}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->stash('view')           || '';
    my $user           = $self->stash('user')           || '';
    my $path_prefix    = $self->stash('path_prefix');
    my $lang           = $self->stash('lang');
    my $config         = $self->stash('config');

    my $new_location = "$path_prefix/$config->{cartitems_loc}.html?l=$lang";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

    return;
}

sub return_loginurl {
    my $self       = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');
    my $view           = $self->stash('view')           || '';
    my $userid         = $self->stash('userid')         || '';
    my $path_prefix    = $self->stash('path_prefix');
    my $config         = $self->stash('config');

    my $return_uri  = uri_escape($r->parsed_uri->unparse);

    my $new_location = "$path_prefix/$config->{login_loc}.html?redirect_to=$return_uri";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

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

sub update_item_in_collection {
    my $self = shift;
    my $input_data_ref = shift;

    my $session = $self->stash('session');
    
    return $session->update_item_in_collection($input_data_ref);
}

sub add_item_to_collection {
    my $self = shift;
    my $input_data_ref = shift;

    my $session = $self->stash('session');

    return $session->add_item_to_collection($input_data_ref);
}

sub delete_item_from_collection {
    my $self = shift;
    my $id = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $session = $self->stash('session');

    $logger->info("Trying to delete $id in SessionID: $session->{ID}");
    
    return $session->delete_item_from_collection({
        id       => $id,
    });
}

sub get_number_of_items_in_collection {
    my $self = shift;

    my $session = $self->stash('session');

    return $session->get_number_of_items_in_collection();
}

sub get_single_item_in_collection {
    my $self = shift;
    my $listid = shift;

    my $session = $self->stash('session');

    return $session->get_single_item_in_collection($listid);
}

sub get_items_in_collection {
    my $self = shift;

    my $session      = $self->stash('session');
    my $queryoptions = $self->stash('qopts');
    
    return $session->get_items_in_collection({ queryoptions => $queryoptions });
}


sub highlightquery {
    my ($searchquery,$content) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Highlight Query

    return $content unless ($searchquery);
    
    my $term_ref = $searchquery->get_searchterms();

    return $content if (scalar(@$term_ref) <= 0);

    if ($logger->is_debug){
        $logger->debug("Terms: ".YAML::Dump($term_ref));
    }
    
    my $terms = join("|", grep /^\w{3,}/ ,@$term_ref);

    return $content if (!$terms);
    
    if ($logger->is_debug){
        $logger->debug("Term_ref: ".YAML::Dump($term_ref)."\nTerms: $terms");
        $logger->debug("Content vor: ".$content);
    }
    
    $content=~s/\b($terms)/<span class="ob-highlight_searchterm">$1<\/span>/ig unless ($content=~/http/);

    if ($logger->is_debug){
        $logger->debug("Content nach: ".$content);
    }
    
    return $content;
}

sub sort_circulation {
    my $array_ref = shift;

    # Schwartz'ian Transform
        
    my @sorted = map { $_->[0] }
    sort { $a->[1] cmp $b->[1] }
    map { [$_, sprintf("%03d:%s:%s:%s",$_->{department_id},$_->{department},$_->{storage},$_->{location_mark})] }
    @{$array_ref};
        
    return \@sorted;
}

1;
