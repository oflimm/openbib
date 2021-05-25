#####################################################################
#
#  OpenBib::Handler::PSGI::MailCollection
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

package OpenBib::Handler::PSGI::MailCollection;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Email::Valid;
use Email::Stuffer;
use File::Slurper 'read_binary';
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
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
    my $singleidn = $query->param('singleidn');
    my $mail      = $query->param('mail');
    my $database  = $query->param('db');
    my $type      = $query->param('type')||'HTML';

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if ($email eq "") {
        return $self->print_warning($msg->maketext("Sie haben keine Mailadresse eingegeben."));
    }

    unless (Email::Valid->address($email)) {
        return $self->print_warning($msg->maketext("Sie haben eine ungültige Mailadresse eingegeben."));
    }	

    my $recordlist = new OpenBib::RecordList::Title();
    
    if ($singleidn && $database) {
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $singleidn}));
    }
    else {
        if ($user->{ID}) {
            $recordlist = $user->get_items_in_collection({view => $view});
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
        
        config      => $config,
        user        => $user,
        msg         => $msg,
    };

    my $maildata="";
    my $ofile="merkliste-" . $$ .".txt";

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

    $maintemplate->process($config->{tt_mailcollection_mail_main_tname}, $mainttdata ) || do { 
        $logger->error($maintemplate->error());
        $self->header_add('Status',400); # server error
        return;
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
    
    return $self->print_page($config->{tt_mailcollection_success_tname},$ttdata);
}

1;
