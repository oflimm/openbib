#####################################################################
#
#  OpenBib::Handler::Apache::Collection
#
#  Dieses File ist (C) 2001-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Collection;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common M_GET);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::RequestIO (); # print, rflush
use Apache2::SubRequest (); # internal_redirect
use Apache2::URI ();
use APR::URI ();
use URI::Escape;

use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use MIME::Lite;
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::ManageCollection::Util;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
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

    if ($userid && !$self->is_authenticated('user',$userid)){
        $self->print_warning($msg->maketext("Sie sind nicht korrekt authentifiziert"));
        return;
    }
    
    # CGI Args
    my $method                  = $query->param('_method')                 || '';
    my $dbname                  = $query->param('dbname')                  || '';
    my $titleid                 = $query->param('titleid')                 || '';
    my $litlistid               = $query->param('litlistid')               || '';
    my $do_collection_delentry  = $query->param('do_collection_delentry')  || '';
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

    # Shortcuts via Method

    if ($method eq "POST"){
        $self->create_record;
        return;
    }

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    $logger->debug(":".$user->is_authenticated.":$do_addlitlist");

    if (! $user->is_authenticated && $do_addlitlist) {
        $logger->debug("Nicht authentifizierter Nutzer versucht Literaturlisten anzulegen");

        $self->return_loginurl;
        return;
    }
    elsif (! $user->is_authenticated && $do_addtags) {
        $logger->debug("Nicht authentifizierter Nutzer versucht Tags anzulegen");

        $self->return_loginurl;
        return;
    }

    $logger->info("SessionID: $session->{ID}");
    
    my $idnresult="";

    if ($do_litlist_addentry) {
        my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});
        
        foreach my $listid ($query->param('id')) {
            my $record;
            if ($user->{ID}) {
                $record = $user->get_single_item_in_collection($listid);
            }
            else {
                $record = $session->get_single_item_in_collection($listid);
            }

            if ($record && $litlist_properties_ref->{userid} eq $user->{ID}) {
                $user->add_litlistentry({ titid => $record->{id}, titdb => $record->{database}, litlistid => $litlistid});
            }
        }
        
        $r->internal_redirect("$config->{base_loc}/$view/$config->{litlists_loc}?action=manage&litlistid=$litlistid&do_showlitlist=1");
        return Apache2::Const::OK;
        
    }
    elsif ($do_addlitlist) {
        if (!$title) {
            $self->print_warning($msg->maketext("Sie müssen einen Titel f&uuml;r Ihre Literaturliste eingeben."));
	    
            return Apache2::Const::OK;
        }
        
        $user->add_litlist({ title =>$title, type => $littype});
        
        $r->internal_redirect("$config->{base_loc}/$view/$config->{managecollection_loc}?action=show&type=HTML");
        return Apache2::Const::OK;
    }
    elsif ($do_addtags) {
        if (!$tags) {
            $self->print_warning($msg->maketext("Sie müssen Tags f&uuml;r die ausgew&auml;hlten Titel eingeben."));
            return Apache2::Const::OK;
        }
        
        if ($user->{ID}){
            my $username = $user->get_username;
            
            if ($query->param('id')){
                foreach my $listid ($query->param('id')) {
                    my $record = $user->get_single_item_in_collection($listid);

                    if ($record){
                        $user->add_tags({
                            tags      => $tags,
                            titid     => $record->{id},
                            titdb     => $record->{database},
                            username  => $username,
                            type      => $tags_type,
                        });
                    }
                }
            }
            else {
                $self->print_warning($msg->maketext("Sie haben keine Titel ausgew&auml;hlt."));
                return Apache2::Const::OK;
            }
        }
        else {
            $self->print_warning($msg->maketext("Bitte authentifizieren Sie sich unter Mein KUG."));
        }

        $self->return_baseurl;
    }
    
    my $recordlist = new OpenBib::RecordList::Title();
    
    if ($userid && $userid == $user->{ID}) {
        $recordlist = $user->get_items_in_collection();
    }
    else {
        $recordlist = $session->get_items_in_collection();
    }

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
        dbinfo            => $dbinfotable,
    };
    
    $self->print_page($config->{tt_collection_tname},$ttdata);
    return Apache2::Const::OK;
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
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    $logger->info("SessionID: $session->{ID}");
    
    my $idnresult="";

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    # Dementsprechend einen LoginLink oder ein ProfilLink ausgeben
    my $anzahl="";
    
    if ($user->{ID}) {
        # Anzahl Eintraege der privaten Merkliste bestimmen
        # Zuallererst Suchen, wieviele Titel in der Merkliste vorhanden sind.
        $anzahl =    $user->get_number_of_items_in_collection();
    } else {
        #  Zuallererst Suchen, wieviele Titel in der Merkliste vorhanden sind.
        $anzahl = $session->get_number_of_items_in_collection();
    }
    
    # Start der Ausgabe mit korrektem Header
    $r->content_type("text/plain");
    
    $r->print($anzahl);
    
    return Apache2::Const::OK;
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

    my $dbinfotable    = OpenBib::Config::DatabaseInfoTable->instance;

    if ($method eq "DELETE"){
        $self->delete_record;
        return;
    }

    # TT-Data erzeugen
    my $ttdata={
        query          => $query,
        qopts          => $queryoptions->get_options,
        
        dbinfo         => $dbinfotable,
    };
    
    $self->print_page($config->{tt_collection_record_tname},$ttdata);

    return Apache2::Const::OK;
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
    
    if ($userid && !$self->is_authenticated('user',$userid)){
        $self->print_warning($msg->maketext("Sie sind nicht korrekt authentifiziert"));
        return;
    }

    # Shortcut: Delete multiple items via POST
    if ($query->param('do_collection_delentry')) {
        foreach my $listid ($query->param('id')) {
            if ($user->{ID}) {
                $user->delete_item_from_collection({
                    id       => $listid,
                });
            }
            else {
                $session->delete_item_from_collection({
                    id       => $listid,
                });
            }
        }

        $self->return_baseurl;

        return;
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (defined $input_data_ref->{error} && $input_data_ref->{error} == 1){
        $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
        return Apache2::Const::OK;
    }
    
    # Einfuegen eines Titels in die Merkliste
    if ($userid && $userid == $user->{ID}) {
        $user->add_item_to_collection($input_data_ref);
    }
    # Anonyme Session
    else {
        $session->add_item_to_collection($input_data_ref);
    }

    return unless ($self->param('representation') eq "html");

    $self->print_info($msg->maketext("Der Titel wurde zu Ihrer Merkliste hinzugef&uuml;gt."));
    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $userid         = $self->param('userid')         || '';
    my $itemid         = $self->strip_suffix($self->param('itemid'))         || '';

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
    
    if ($userid && !$self->is_authenticated('user',$userid)){
        $self->print_warning($msg->maketext("Sie sind nicht korrekt authentifiziert"));
        return;
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{itemid} = $itemid;
    
    if (defined $input_data_ref->{error} && $input_data_ref->{error} == 1){
        $self->print_warning($msg->maketext("JSON konnte nicht geparst werden"));
        return Apache2::Const::OK;
    }
    
    # Einfuegen eines Titels in die Merkliste
    if ($userid && $userid == $user->{ID}) {
        $user->update_item_in_collection($input_data_ref);
    }
    # Anonyme Session
    else {
        $session->update_item_in_collection($input_data_ref);
    }

    return unless ($self->param('representation') eq "html");

    $self->print_info($msg->maketext("Der Titel wurde zu Ihrer Merkliste hinzugef&uuml;gt."));
    return Apache2::Const::OK;
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
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    $logger->info("Trying to delete $id in SessionID: $session->{ID}");

    if ($user->{ID}) {
        $user->delete_item_from_collection({
            id => $id,
        });
    }
    else {
        $session->delete_item_from_collection({
            id       => $id,
        });
    }

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
    
    # CGI Args
    my $format                  = $query->param('format')                || '';
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    $logger->info("SessionID: $session->{ID}");

    my $username=$user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title();

    # Obsolet?
    if ($id && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $id}));
    }
    else {
        if ($user->{ID}) {
            $recordlist = $user->get_items_in_collection();
        }
        else {
            $recordlist = $session->get_items_in_collection()
        }
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
        dbinfo     => $dbinfotable,
    };
        
    $self->print_page($config->{tt_collection_print_tname},$ttdata);
    return Apache2::Const::OK;
}

sub save_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched_args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
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

    # CGI Args
    my $format                  = $query->param('format')                || '';
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    $logger->info("SessionID: $session->{ID}");

    my $username=$user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title();
    
    if ($id && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $id}));
    }
    else {
        if ($user->{ID}) {
            $recordlist = $user->get_items_in_collection();
        }
        else {
            $recordlist = $session->get_items_in_collection()
        }
    }
    
    $recordlist->load_full_records;
    
    # TT-Data erzeugen
    my $ttdata={
        qopts       => $queryoptions->get_options,		
        format      => $format,
        recordlist  => $recordlist,
        dbinfo      => $dbinfotable,
    };
    
    if ($format eq "short" || $format eq "full") {
        $self->param('content_type','text/html');
        $r->headers_out->add("Content-Disposition" => "attachment;filename=\"kugliste.html\"");
        $self->print_page($config->{tt_collection_save_html_tname},$ttdata);
    }
    else {
        $self->param('content_type','text/plain');
        $r->headers_out->add("Content-Disposition" => "attachment;filename=\"kugliste.txt\"");
        $self->print_page($config->{tt_collection_save_plain_tname},$ttdata);
    }
    return Apache2::Const::OK;
}

sub mail_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
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

    # CGI Args
    my $format                  = $query->param('format')                || '';

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    $logger->info("SessionID: $session->{ID}");

    my $username=$user->get_username();
    
    my $recordlist = new OpenBib::RecordList::Title();
    
    if ($id && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $id}));
    }
    else {
        if ($user->{ID}) {
            $recordlist = $user->get_items_in_collection();
        }
        else {
            $recordlist = $session->get_items_in_collection()
        }
    }
    
    $recordlist->load_full_records;
    
    # TT-Data erzeugen
    my $ttdata={
        qopts       => $queryoptions->get_options,				
        format      => $format,

        username    => $username,
        id          => $id,
        database    => $database,
        recordlist  => $recordlist,
        dbinfo      => $dbinfotable,
    };
    
    $self->print_page($config->{tt_collection_mail_tname},$ttdata);
    return Apache2::Const::OK;
}

sub mail_collection_send {
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
    my $email     = ($query->param('email'))?$query->param('email'):'';
    my $subject   = ($query->param('subject'))?$query->param('subject'):'Ihre Merkliste';
    my $id        = $query->param('id');
    my $mail      = $query->param('mail');
    my $database  = $query->param('db');
    my $format    = $query->param('format')||'full';

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if ($email eq "") {
        $self->print_warning($msg->maketext("Sie haben keine Mailadresse eingegeben."));
        return Apache2::Const::OK;
    }

    unless (Email::Valid->address($email)) {
        $self->print_warning($msg->maketext("Sie haben eine ungültige Mailadresse eingegeben."));
        return Apache2::Const::OK;
    }	

    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    my $recordlist = new OpenBib::RecordList::Title();
    
    if ($id && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $id}));
    }
    else {
        if ($user->{ID}) {
            $recordlist = $user->get_items_in_collection();
        }
        else {
            $recordlist = $session->get_items_in_collection()
        }
    }

    $recordlist->load_full_records;
    
    # TT-Data erzeugen
    
    my $ttdata={
        view        => $view,
        stylesheet  => $stylesheet,
        sessionID   => $session->{ID},
	qopts       => $queryoptions->get_options,
        format      => $format,
        recordlist  => $recordlist,
        dbinfo      => $dbinfotable,
        
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
    my $datatemplatename=$config->{tt_collection_mail_html_tname};

    if ($format eq "short" || $format eq "full") {
        $filename.=".html";
    }
    else {
        $mimetype="text/plain";
        $filename.=".txt";
        $datatemplatename=$config->{tt_collection_mail_plain_tname};
    }

    $datatemplate->process($datatemplatename, $ttdata) || do {
        $r->log_error($datatemplate->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
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

    $maintemplate->process($config->{tt_collection_mail_message_tname}, $mainttdata ) || do { 
        $r->log_error($maintemplate->error(), $r->filename);
        return Apache2::Const::SERVER_ERROR;
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
    
    $self->print_page($config->{tt_collection_mail_success_tname},$ttdata);
    
    unlink $anschfile;
    unlink $mailfile;

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

    my $new_location = ($userid)?"$path_prefix/$config->{user_loc}/$userid/collection.html":"$path_prefix/$config->{collection_loc}.html";

    $self->query->method('GET');
    $self->query->content_type('text/html');
    $self->query->headers_out->add(Location => $new_location);
    $self->query->status(Apache2::Const::REDIRECT);

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

    my $config = OpenBib::Config->instance;

    my $return_uri  = uri_escape($r->parsed_uri->unparse);

    my $new_location = "$path_prefix/$config->{login_loc}.html?redirect_to=$return_uri";

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

1;
