#####################################################################
#
#  OpenBib::Mojo::Controller::Users::CartItems
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

package OpenBib::Mojo::Controller::Users::CartItems;

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

use base 'OpenBib::Mojo::Controller::CartItems';

# Authentifizierung wird spezialisiert

sub authorization_successful {
    my $self   = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $basic_auth_failure = $self->stash('basic_auth_failure') || 0;
    my $userid             = $self->stash('userid')             || '';

    $logger->debug("Basic http auth failure: $basic_auth_failure / Userid: $userid ");

    if ($basic_auth_failure || ($userid && !$self->is_authenticated('user',$userid))){
        return 0;
    }

    return 1;
}

sub update_item_in_collection {
    my $self = shift;
    my $input_data_ref = shift;

    my $userid  = $self->stash('userid')                      || '';
    my $user    = $self->stash('user');

    if ($userid && $userid == $user->{ID}) {
        return $user->update_item_in_collection($input_data_ref);
    }

    return;
}

sub add_item_to_collection {
    my $self = shift;
    my $input_data_ref = shift;

    my $userid  = $self->stash('userid')                      || '';

    my $user = $self->stash('user');

    if ($userid && $userid == $user->{ID}) {
        return $user->add_item_to_collection($input_data_ref);
    }
    
    return;
}

sub delete_item_from_collection {
    my $self = shift;
    my $id   = shift;

    my $userid  = $self->stash('userid')                      || '';

    my $user = $self->stash('user');

    if ($userid && $userid == $user->{ID}) {
        return $user->delete_item_from_collection({
            id       => $id,
        });
    }
    
    return;
}

sub get_number_of_items_in_collection {
    my $self = shift;

    my $user = $self->stash('user');
    my $view = $self->stash('view');
    
    return $user->get_number_of_items_in_collection({view => $view});
}

sub get_single_item_in_collection {
    my $self = shift;
    my $listid = shift;

    my $user = $self->stash('user');

    return $user->get_single_item_in_collection($listid);
}

sub get_items_in_collection {
    my $self = shift;

    my $user         = $self->stash('user');
    my $view         = $self->stash('view');
    my $queryoptions = $self->stash('qopts');
    
    return $user->get_items_in_collection({view => $view, queryoptions => $queryoptions });
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
    my $format                  = $query->stash('format')                || '';

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

        username    => $username,
        titleid     => $id,
        database    => $database,

	hits        => $total_count,
	nav         => $nav,	
        recordlist  => $recordlist,

	highlightquery    => \&highlightquery,
	sort_circulation => \&sort_circulation,
	
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
    my $email     = ($query->stash('email'))?$query->param('email'):'';
    my $subject   = ($query->stash('subject'))?$query->param('subject'):'Ihre Merkliste';
    $id           = $query->stash('id');
    my $mail      = $query->stash('mail');
    $database     = $query->stash('db');
    my $format    = $query->stash('format')||'full';

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
	$recordlist->load_full_records;
    }
    else {
        $recordlist = $self->get_items_in_collection();
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
        view        => $view,
        sysprofile  => $sysprofile,
        stylesheet  => $stylesheet,
        sessionID   => $session->{ID},
	qopts       => $queryoptions->get_options,
        format      => $format,

	hits        => $total_count,
	nav         => $nav,		
        recordlist  => $recordlist,
        
        config      => $config,
        user        => $user,
        msg         => $msg,

	highlightquery    => \&highlightquery,
	sort_circulation => \&sort_circulation,
	
    };

    my $maildata="";
    my $ofile="merkliste-" . $$ .".txt";

    my $datatemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
  	    ENCODING     => 'utf8',	    
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
    my $filename="merkliste";
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
    
    $datatemplate->process($datatemplatename, $ttdata, undef, {binmode => ':utf8'}) || do {
        $logger->error($datatemplate->error());
        $self->header_add('Status',400); # server error
        return;
    };
  
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
	ENCODING     => 'utf8',
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
    
    my $anschfile="/tmp/" . $afile;
    my $mailfile ="/tmp/" . $ofile;
    
    Email::Stuffer->to($email)
	->from($config->{contact_email})
	->subject($subject)
	->text_body(read_binary($anschfile))
	->attach_file($mailfile)
	->send;

    unlink $anschfile;
    unlink $mailfile;

    return $self->print_page($config->{tt_cartitems_mail_success_tname},$ttdata);
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

    my $new_location = "$path_prefix/$config->{users_loc}/id/$user->{ID}/$config->{cartitems_loc}.html?l=$lang";

    # TODO GET?
    $self->header_add('Content-Type' => 'text/html');
    $self->redirect($new_location);

    return;
}

1;
