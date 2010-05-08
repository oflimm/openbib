#####################################################################
#
#  OpenBib::Handler::Apache::MailCollection
#
#  Dieses File ist (C) 2001-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::MailCollection;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::Request ();
use DBI;
use Email::Valid;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use MIME::Lite;
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $user      = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $email     = ($query->param('email'))?$query->param('email'):'';
    my $subject   = ($query->param('subject'))?$query->param('subject'):'Ihre Merkliste';
    my $singleidn = $query->param('singleidn');
    my $mail      = $query->param('mail');
    my $database  = $query->param('database');
    my $type      = $query->param('type')||'HTML';

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    my $view=$r->subprocess_env('openbib_view') || $config->{defaultview};
  
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if ($email eq "") {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keine Mailadresse eingegeben."),$r,$msg);
        return Apache2::Const::OK;
    }

    unless (Email::Valid->address($email)) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben eine ungültige Mailadresse eingegeben."),$r,$msg);
        return Apache2::Const::OK;
    }	

    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    my $recordlist = new OpenBib::RecordList::Title();
    
    if ($singleidn && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $singleidn}));
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
        type        => $type,
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
    my $datatemplatename=$config->{tt_mailcollection_mail_html_tname};

    if ($type eq "HTML") {
        $filename.=".html";
    }
    else {
        $mimetype="text/plain";
        $filename.=".txt";
        $datatemplatename=$config->{tt_mailcollection_mail_plain_tname};
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

    $maintemplate->process($config->{tt_mailcollection_mail_main_tname}, $mainttdata ) || do { 
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
    
    OpenBib::Common::Util::print_page($config->{tt_mailcollection_success_tname},$ttdata,$r);
    
    unlink $anschfile;
    unlink $mailfile;

    return Apache2::Const::OK;
}

1;
