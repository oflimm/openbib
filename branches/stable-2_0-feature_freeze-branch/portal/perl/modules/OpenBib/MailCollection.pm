#####################################################################
#
#  OpenBib::MailCollection
#
#  Dieses File ist (C) 2001-2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::MailCollection;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Email::Valid;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use MIME::Lite;
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $query=Apache::Request->instance($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $session   = new OpenBib::Session({
        sessionID => $query->param('sessionID'),
    });

    my $user      = new OpenBib::User();
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $email     = ($query->param('email'))?$query->param('email'):'';
    my $subject   = ($query->param('subject'))?$query->param('subject'):'Ihre Merkliste';
    my $singleidn = $query->param('singleidn');
    my $mail      = $query->param('mail');
    my $database  = $query->param('database');
    my $type      = $query->param('type')||'HTML';


    $logger->debug("SessionID: ".$session->{ID});

    my $queryoptions_ref
        = $session->get_queryoptions($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );

    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return OK;
    }
    
    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }
  
    # Haben wir eine authentifizierte Session?
  
    my $userid=$user->get_userid_of_session($session->{ID});
  
    # Ab hier ist in $userid entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if ($email eq "") {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keine Mailadresse eingegeben."),$r,$msg);
        return OK;
    }

    unless (Email::Valid->address($email)) {
        OpenBib::Common::Util::print_warning($msg->maketext("Sie haben eine ungültige Mailadresse eingegeben."),$r,$msg);
        return OK;
    }	

    my $targetdbinfo_ref
        = $config->get_targetdbinfo();
    
    my $targetcircinfo_ref
        = $config->get_targetcircinfo();

    my @dbidnlist=();
    
    if ($singleidn && $database) {
        push @dbidnlist, {
            database  => $database,
            singleidn => $singleidn,
        };
    }
    else {
        # Schleife ueber alle Treffer
        my $idnresult="";

        if ($userid) {
            $idnresult=$user->{dbh}->prepare("select * from treffer where userid = ? order by dbname") or $logger->error($DBI::errstr);
            $idnresult->execute($userid) or $logger->error($DBI::errstr);
        }
        else {
            $idnresult=$session->{dbh}->prepare("select * from treffer where sessionid = ? order by dbname") or $logger->error($DBI::errstr);
            $idnresult->execute($session->{ID}) or $logger->error($DBI::errstr);
        }

        while (my $result=$idnresult->fetchrow_hashref()) {
            my $database  = decode_utf8($result->{'dbname'});
            my $singleidn = decode_utf8($result->{'singleidn'});
	
            push @dbidnlist, {
                database  => $database,
                singleidn => $singleidn,
            };
        }

        $idnresult->finish();
    }      

    my @collection=();
    
    foreach my $dbidn_ref (@dbidnlist) {
        my $database  = $dbidn_ref->{database};
        my $singleidn = $dbidn_ref->{singleidn};
      
        my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);
      
        my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
            titidn             => $singleidn,
            dbh                => $dbh,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => $targetcircinfo_ref,
            database           => $database,
            sessionID          => $session->{ID}
        });
      
#         if ($type eq "Text") {
#             $normset=OpenBib::ManageCollection::Util::titset_to_text($normset);
#         }
#         elsif ($type eq "EndNote") {
#             $normset=OpenBib::ManageCollection::Util::titset_to_endnote($normset);
#         }
      
        $dbh->disconnect();
      
        $logger->debug("Merklistensatz geholt");
      
        push @collection, {
            database => $database,
            dbdesc   => $targetdbinfo_ref->{dbinfo}{$database},
            titidn   => $singleidn,
            tit      => $normset,
            mex      => $mexnormset,
            circ     => $circset,
        };
    }
    
    # TT-Data erzeugen
    
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        sessionID  => $session->{ID},
	qopts      => $queryoptions_ref,
        type       => $type,
        collection => \@collection,
        config     => $config,
        msg        => $msg,
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
        $r->log_reason($datatemplate->error(), $r->filename);
        return SERVER_ERROR;
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
        $r->log_reason($maintemplate->error(), $r->filename);
        return SERVER_ERROR;
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

    return OK;
}

1;
