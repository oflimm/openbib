#####################################################################
#
#  OpenBib::MailCollection
#
#  Dieses File ist (C) 2001-2005 Oliver Flimm <flimm@openbib.org>
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

use Apache::Constants qw(:common);
use Apache::Request ();
use DBI;
use Email::Valid;
use Log::Log4perl qw(get_logger :levels);
use MIME::Lite;
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config=\%OpenBib::Config::config;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my %endnote=(
        'Verfasser'   => '%A', # Author
        'Urheber'     => '%C', # Corporate Author
        'HST'         => '%T', # Title of the article or book
        '1'           => '%S', # Title of the serie
        '2'           => '%J', # Journal containing the article
        '3'           => '%B', # Journal Title (refer: Book containing article)
        '4'           => '%R', # Report, paper, or thesis type
        '5'           => '%V', # Volume
        '6'           => '%N', # Number with volume
        '7'           => '%E', # Editor of book containing article
        '8'           => '%P', # Page number(s)
        'Verlag'      => '%I', # Issuer. This is the publisher
        'Verlagsort'  => '%C', # City where published. This is the publishers address
        'Ersch. Jahr' => '%D', # Date of publication
        '11'          => '%O', # Other information which is printed after the reference
        '12'          => '%K', # Keywords used by refer to help locate the reference
        '13'          => '%L', # Label used to number references when the -k flag of refer is used
        '14'          => '%X', # Abstract. This is not normally printed in a reference
        '15'          => '%W', # Where the item can be found (physical location of item)
        'Kollation'   => '%Z', # Pages in the entire document. Tib reserves this for special use
        'Ausgabe'     => '%7', # Edition
        '17'          => '%Y'  # Series Editor
    );

    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen

    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $userdbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $sessionID = $query->param('sessionID');
    my $email     = ($query->param('email'))?$query->param('email'):'';
    my $subject   = ($query->param('subject'))?$query->param('subject'):'Ihre Merkliste';
    my $singleidn = $query->param('singleidn');
    my $mail      = $query->param('mail');
    my $database  = $query->param('database');
    my $type      = $query->param('type')||'HTML';

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }
  
    # Haben wir eine authentifizierte Session?
  
    my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
    # Ab hier ist in $userid entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if ($email eq "") {
        OpenBib::Common::Util::print_warning("Sie haben keine Mailadresse eingegeben.",$r);
  
        $sessiondbh->disconnect();
        $userdbh->disconnect();
        return OK;
    }

    unless (Email::Valid->address($email)) {
        OpenBib::Common::Util::print_warning("Sie haben eine ung&uuml;ltige Mailadresse eingegeben.",$r);
    
        $sessiondbh->disconnect();
        $userdbh->disconnect();
        return OK;
    }	

    my $titeltyp_ref = {
        '1' => 'Einb&auml;ndige Werke und St&uuml;cktitel',
        '2' => 'Gesamtaufnahme fortlaufender Sammelwerke',
        '3' => 'Gesamtaufnahme mehrb&auml;ndig begrenzter Werke',
        '4' => 'Bandauff&uuml;hrung',
        '5' => 'Unselbst&auml;ndiges Werk',
        '6' => 'Allegro-Daten',
        '7' => 'Lars-Daten',
        '8' => 'Sisis-Daten',
        '9' => 'Sonstige Daten',
    };

    my $targetdbinfo_ref
        = OpenBib::Common::Util::get_targetdbinfo($sessiondbh);
    
    my $targetcircinfo_ref
        = OpenBib::Common::Util::get_targetcircinfo($sessiondbh);

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
            $idnresult=$userdbh->prepare("select * from treffer where userid = ? order by dbname") or $logger->error($DBI::errstr);
            $idnresult->execute($userid) or $logger->error($DBI::errstr);
        }
        else {
            $idnresult=$sessiondbh->prepare("select * from treffer where sessionid = ? order by dbname") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
        }

        while (my $result=$idnresult->fetchrow_hashref()) {
            my $database  = $result->{'dbname'};
            my $singleidn = $result->{'singleidn'};
	
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
      
        my $dbh=DBI->connect("DBI:$config{dbimodule}:dbname=$database;host=$config{dbhost};port=$config{dbport}", $config{dbuser}, $config{dbpasswd}) or $logger->error_die($DBI::errstr);
      
        my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
            titidn             => $singleidn,
            hint               => "none",
            dbh                => $dbh,
            sessiondbh         => $sessiondbh,
            searchmultipleaut  => 0,
            searchmultiplekor  => 0,
            searchmultipleswt  => 0,
            searchmultiplekor  => 0,
            searchmultipletit  => 0,
            searchmode         => 2,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => $targetcircinfo_ref,
            hitrange           => -1,
            rating             => '',
            bookinfo           => '',
            sorttype           => '',
            sortorder          => '',
            database           => $database,
            titeltyp_ref       => $titeltyp_ref,
            sessionID          => $sessionID
        });
      
        if ($type eq "Text") {
            $normset=OpenBib::ManageCollection::Util::titset_to_text($normset);
        }
        elsif ($type eq "EndNote") {
            $normset=OpenBib::ManageCollection::Util::titset_to_endnote($normset);
        }
      
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
        sessionID  => $sessionID,
		
        type       => $type,
		
        collection => \@collection,
		
        utf2iso    => sub {
            my $string=shift;
            $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse; 
            return $string;
        },
		
        show_corporate_banner => 0,
        show_foot_banner      => 1,
        config     => \%config,
    };

    my $maildata="";

    my $datatemplate = Template->new({
        ABSOLUTE      => 1,
        INCLUDE_PATH  => $config{tt_include_path},
        OUTPUT        => $maildata,
    });
  

    my $mimetype="text/html";
    my $filename="kug-merkliste";
    my $datatemplatename=$config{tt_mailcollection_mail_html_tname};

    if ($type eq "HTML") {
        $filename.=".html";
    }
    else {
        $mimetype="text/plain";
        $filename.=".txt";
        $datatemplatename=$config{tt_mailcollection_mail_plain_tname};
    }

    $datatemplate->process($datatemplatename, $ttdata) || do { 
        $r->log_reason($datatemplate->error(), $r->filename);
        return SERVER_ERROR;
    };
  
    my $anschreiben="";

    my $maintemplate = Template->new({
        ABSOLUTE      => 1,
        INCLUDE_PATH  => $config{tt_include_path},
        OUTPUT        => $anschreiben,
    });

    $maintemplate->process($config{tt_mailcollection_mail_main_tname}, {}) || do { 
        $r->log_reason($maintemplate->error(), $r->filename);
        return SERVER_ERROR;
    };

    my $msg = MIME::Lite->new(
        From            => $config{contact_email},
        To              => $email,
        Subject         => $subject,
        Type            => 'multipart/mixed'
    );

    $msg->attach(
        Type            => 'TEXT',
        Encoding        => '8bit',
        Data            => $anschreiben,
    );
  
    $msg->attach(
        Type            => $mimetype,
        Encoding        => '8bit',
        Filename        => $filename,
        Data            => $maildata,
    );
  
    $msg->send('sendmail', "/usr/lib/sendmail -t -oi -f$config{contact_email}");
    
    OpenBib::Common::Util::print_page($config{tt_mailcollection_success_tname},$ttdata,$r);
    
    $sessiondbh->disconnect();
    $userdbh->disconnect();

    return OK;
}

1;
