#####################################################################
#
#  OpenBib::Handler::PSGI::CartItems
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

package OpenBib::Handler::PSGI::CartItems;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use URI::Escape;

use DBI;
use Email::Valid;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use MIME::Lite;
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

#    $self->start_mode('show_collection');
    $self->run_modes(
        'save_collection'                      => 'save_collection',
        'mail_collection'                      => 'mail_collection',
        'mail_collection_send'                 => 'mail_collection_send',
        'print_collection'                     => 'print_collection',
        'show_collection_count'                => 'show_collection_count',
        'show_collection'                      => 'show_collection',
        'show_record'                          => 'show_record',
        'create_record'                        => 'create_record',
        'update_record'                        => 'update_record',
        'delete_record'                        => 'delete_record',
        'print_authorization_error'            => 'print_authentication_error',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );
        
    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection {
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
    my $method                  = $query->param('_method')                 || '';
    my $dbname                  = $query->param('dbname')                  || '';
    my $titleid                 = $query->param('titleid')                 || '';
    my $action                  = $query->param('action')                  || 'show';
    my $show                    = $query->param('show')                    || 'short';
    my $type                    = $query->param('type')                    || 'HTML';
    my $format                  = $query->param('format')                  || 'short';

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

    if ($recordlist->get_size() != 0) {
        my $sorttype          = $queryoptions->get_option('srt');
        my $sortorder         = $queryoptions->get_option('srto');
        
        if ($sortorder && $sorttype){
            $recordlist->sort({order=>$sortorder,type=>$sorttype});
        }
    }
    
    # TT-Data erzeugen
    my $ttdata={
        qopts             => $queryoptions->get_options,
        format            => $format,

        recordlist        => $recordlist,
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
    my $database                = $query->param('db')                || '';
    my $singleidn               = $query->param('singleidn')               || '';
    my $litlistid               = $query->param('litlistid')               || '';
    my $do_collection_delentry  = $query->param('do_collection_delentry')  || '';
    my $do_collection_showcount = $query->param('do_collection_showcount') || '';
    my $do_litlist_addentry     = $query->param('do_litlist_addentry')     || '';
    my $do_addlitlist           = $query->param('do_addlitlist')           || '';
    my $do_addtags              = $query->param('do_addtags')              || '';
    my $title                   = $query->param('title')                   || '';
    my $action                  = $query->param('action')                  || 'show';
    my $show                    = $query->param('show')                    || 'short';
    my $type                    = $query->param('type')                    || 'HTML';
    my $tags                    = $query->param('tags')                    || '';
    my $tags_type               = $query->param('tags_type')               || 1;
    my $littype                 = $query->param('littype')                 || 1;

    my $format                  = $query->param('format')                  || 'short';

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
    my $r              = $self->param('r');
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $id             = $self->strip_suffix($self->param('itemid'));

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

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }
    
    my $record = $self->get_single_item_in_collection($id);
    
    # TT-Data erzeugen
    my $ttdata={
        record         => $record,
        query          => $query,
        qopts          => $queryoptions->get_options,
        
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
    my $do_cartitems_delentry  = $query->param('do_cartitems_delentry')  || '';
    my $do_litlists_addentry     = $query->param('do_litlists_addentry')     || '';
    my $do_addlitlist           = $query->param('do_addlitlist')           || '';
    my $do_addtags              = $query->param('do_addtags')              || '';

    my $tags                    = $query->param('tags')                    || '';
    my $tags_type               = $query->param('tags_type')               || 1;
    my $litlistid               = $query->param('litlistid')               || '';
    my $title                   = $query->param('title')                   || '';
    my $littype                 = $query->param('littype')                 || 1;

    if (!$self->authorization_successful){
        return $self->print_authorization_error();
    }

    # Process WWW-UI-Shortcuts
    if ($do_cartitems_delentry || $do_litlists_addentry || $do_addlitlist || $do_addtags ) {

        # Shortcut: Delete multiple items via POST
        if ($query->param('do_cartitems_delentry')) {
            foreach my $listid ($query->param('id')) {
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
            
            foreach my $listid ($query->param('id')) {
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
            
            foreach my $listid ($query->param('id')) {
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
                
                if ($query->param('id')){
                    foreach my $listid ($query->param('id')) {
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
        
        if ($self->param('representation') eq "html"){
            return $self->print_info($msg->maketext("Der Titel wurde zu Ihrer Merkliste hinzugef&uuml;gt."));
        }
        else {
            $logger->debug("Weiter zum Record");
            if ($new_titleid){
                $logger->debug("Weiter zur Titelid $new_titleid");
                $self->param('status',201); # created
                $self->param('itemid',$new_titleid);
                $self->param('location',"$location/item/".uri_escape_utf8($new_titleid));
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

    return unless ($self->param('representation') eq "html");

    return $self->print_info($msg->maketext("Der Titel wurde zu Ihrer Merkliste hinzugef&uuml;gt."));
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('itemid'));


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
        return $self->print_authorization_error();
    }
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $self->delete_item_from_collection($id);

    return unless ($self->param('representation') eq "html");
    
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
    my $format                  = $query->param('format')                || '';
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $logger->info("SessionID: $session->{ID}");

    my $username=$user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title();

    # Druck eines Titels
    if ($id && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $id}));
    }
    else {
        $recordlist = $self->get_items_in_collection()
    }
    
    $recordlist->load_full_records;
    
    # TT-Data erzeugen
    my $ttdata={
        qopts      => $queryoptions->get_options,		
        format     => $format,

        username   => $username,
        id         => $id,
        database   => $database,
        recordlist => $recordlist,
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
    my $format                  = $query->param('format')                || '';
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $logger->info("SessionID: $session->{ID}");

    my $username=$user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title();
    
    if ($id && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $id}));
    }
    else {
        $recordlist = $self->get_items_in_collection()
    }
    
    $recordlist->load_full_records;
    
    # TT-Data erzeugen
    my $ttdata={
        qopts       => $queryoptions->get_options,		
        format      => $format,
        recordlist  => $recordlist,
    };
    
    $self->param('content_type','text/plain');
    $self->header_add("Content-Disposition" => "attachment;filename=\"kugliste.txt\"");
    return $self->print_page($config->{tt_cartitems_save_plain_tname},$ttdata);

}

sub mail_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $id             = $self->strip_suffix($self->decode_id($self->param('titleid')));

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
    my $format                  = $query->param('format')                || '';

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $logger->info("SessionID: $session->{ID}");

    my $username=$user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title();
    
    if ($id && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $id}));
    }
    else {
        $recordlist = $self->get_items_in_collection()
    }
    
    $recordlist->load_full_records;
    
    # TT-Data erzeugen
    my $ttdata={
        qopts       => $queryoptions->get_options,				
        format      => $format,

        username    => $username,
        titleid     => $id,
        database    => $database,
        recordlist  => $recordlist,
    };
    
    return $self->print_page($config->{tt_cartitems_mail_tname},$ttdata);
}

sub mail_collection_send {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $database       = $self->param('database');
    my $id             = $self->strip_suffix($self->decode_id($self->param('titleid')));

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
    my $email     = ($query->param('email'))?$query->param('email'):'';
    my $subject   = ($query->param('subject'))?$query->param('subject'):'Ihre Merkliste';
    $id        = $query->param('id');
    my $mail      = $query->param('mail');
    $database  = $query->param('db');
    my $format    = $query->param('format')||'full';

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if ($email eq "") {
        return $self->print_warning($msg->maketext("Sie haben keine Mailadresse eingegeben."));
    }

    unless (Email::Valid->address($email)) {
        return $self->print_warning($msg->maketext("Sie haben eine ungültige Mailadresse eingegeben."));
    }	

    my $sysprofile= $config->get_profilename_of_view($view);

    my $recordlist = new OpenBib::RecordList::Title();
    
    if ($id && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $id}));
    }
    else {
        $recordlist = $self->get_items_in_collection();
    }

    $recordlist->load_full_records;
    
    # TT-Data erzeugen
    
    my $ttdata={
        view        => $view,
        sysprofile  => $sysprofile,
        stylesheet  => $stylesheet,
        sessionID   => $session->{ID},
	qopts       => $queryoptions->get_options,
        format      => $format,
        recordlist  => $recordlist,
        
        config      => $config,
        user        => $user,
        msg         => $msg,
    };

    my $maildata="";
    my $ofile="ml." . $$;

    my $datatemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        ABSOLUTE      => 1,
        #        INCLUDE_PATH  => $config->{tt_include_path},
        # Es ist wesentlich, dass OUTPUT* hier und nicht im
        # Template::Provider definiert wird
        RECURSION      => 1,
        OUTPUT_PATH   => '/tmp',
        OUTPUT        => $ofile,
    });
  

    my $mimetype="text/html";
    my $filename="kug-merkliste";
    my $datatemplatename=$config->{tt_cartitems_mail_html_tname};

    $logger->debug("Using view $view in profile $sysprofile");
    
    if ($format eq "short" || $format eq "full") {
        $filename.=".html";
    }
    else {
        $mimetype="text/plain";
        $filename.=".txt";
        $datatemplatename=$config->{tt_cartitems_mail_plain_tname};
    }

    $datatemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
        templatename => $datatemplatename,
    });

    $logger->debug("Using database/view specific Template $datatemplatename");
    
    $datatemplate->process($datatemplatename, $ttdata) || do {
        $logger->error($datatemplate->error());
        $self->header_add('Status',400); # server error
        return;
    };
  
    my $anschreiben="";
    my $afile = "an." . $$;

    my $mainttdata = {
		      msg => $msg,
		     };

    my $maintemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        ABSOLUTE      => 1,
        #        INCLUDE_PATH  => $config->{tt_include_path},
        # Es ist wesentlich, dass OUTPUT* hier und nicht im
        # Template::Provider definiert wird
        RECURSION      => 1,
        OUTPUT_PATH   => '/tmp',
        OUTPUT        => $afile,
    });

    my $messagetemplatename = $config->{tt_cartitems_mail_message_tname};
    
    $messagetemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
        templatename => $messagetemplatename,
    });

    $logger->debug("Using database/view specific Template $messagetemplatename");

    $maintemplate->process($messagetemplatename, $mainttdata ) || do { 
    };

    my $mailmsg = MIME::Lite->new(
        From            => $config->{contact_email},
        To              => $email,
        Subject         => $subject,
        Type            => 'multipart/mixed'
    );

    my $anschfile="/tmp/" . $afile;

    $mailmsg->attach(
        Type            => 'TEXT',
        Encoding        => '8bit',
        #Data            => $anschreiben,
	Path            => $anschfile,
    );
  
    my $mailfile="/tmp/" . $ofile;

    $mailmsg->attach(
        Type            => $mimetype,
        Encoding        => '8bit',
        Filename        => $filename,
        #Data            => $maildata,
	Path            => $mailfile,
    );
  
    $mailmsg->send('sendmail', "/usr/lib/sendmail -t -oi -f$config->{contact_email}");

    unlink $anschfile;
    unlink $mailfile;

    return $self->print_page($config->{tt_cartitems_mail_success_tname},$ttdata);
}

sub return_baseurl {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $view           = $self->param('view')           || '';
    my $user           = $self->param('user')           || '';
    my $path_prefix    = $self->param('path_prefix');
    my $lang           = $self->param('lang');
    my $config         = $self->param('config');

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
    
    my $r              = $self->param('r');
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $path_prefix    = $self->param('path_prefix');
    my $config         = $self->param('config');

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

    my $session = $self->param('session');
    
    return $session->update_item_in_collection($input_data_ref);
}

sub add_item_to_collection {
    my $self = shift;
    my $input_data_ref = shift;

    my $session = $self->param('session');

    return $session->add_item_to_collection($input_data_ref);
}

sub delete_item_from_collection {
    my $self = shift;
    my $id = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $session = $self->param('session');

    $logger->info("Trying to delete $id in SessionID: $session->{ID}");
    
    return $session->delete_item_from_collection({
        id       => $id,
    });
}

sub get_number_of_items_in_collection {
    my $self = shift;

    my $session = $self->param('session');

    return $session->get_number_of_items_in_collection();
}

sub get_single_item_in_collection {
    my $self = shift;
    my $listid = shift;

    my $session = $self->param('session');

    return $session->get_single_item_in_collection($listid);
}

sub get_items_in_collection {
    my $self = shift;

    my $session = $self->param('session');

    return $session->get_items_in_collection();
}

    
1;
