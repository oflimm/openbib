#####################################################################
#
#  OpenBib::UserPrefs
#
#  Dieses File ist (C) 2004-2005 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::UserPrefs;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Request ();
use DBI;
use Email::Valid;
use Log::Log4perl qw(get_logger :levels);
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

    my $showfs        = ($query->param('showfs'))?$query->param('showfs'):'0';
    my $showhst       = ($query->param('showhst'))?$query->param('showhst'):'0';
    my $showhststring = ($query->param('showhststring'))?$query->param('showhststring'):'0';
    my $showverf      = ($query->param('showverf'))?$query->param('showverf'):'0';
    my $showkor       = ($query->param('showkor'))?$query->param('showkor'):'0';
    my $showswt       = ($query->param('showswt'))?$query->param('showswt'):'0';
    my $shownotation  = ($query->param('shownotation'))?$query->param('shownotation'):'0';
    my $showisbn      = ($query->param('showisbn'))?$query->param('showisbn'):'0';
    my $showissn      = ($query->param('showissn'))?$query->param('showissn'):'0';
    my $showsign      = ($query->param('showsign'))?$query->param('showsign'):'0';
    my $showmart      = ($query->param('showmart'))?$query->param('showmart'):'0';
    my $showejahr     = ($query->param('showejahr'))?$query->param('showejahr'):'0';

    my $setmask       = ($query->param('setmask'))?$query->param('setmask'):'';
    my $action        = ($query->param('action'))?$query->param('action'):'none';
    my $targetid      = ($query->param('targetid'))?$query->param('targetid'):'none';
    my $loginname     = ($query->param('loginname'))?$query->param('loginname'):'';
    my $password      = ($query->param('password'))?$query->param('password'):'';
    my $password1     = ($query->param('password1'))?$query->param('password1'):'';
    my $password2     = ($query->param('password2'))?$query->param('password2'):'';
    my $sessionID     = $query->param('sessionID')||'';
  
    my $sessiondbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $userdbh
        = DBI->connect("DBI:$config{dbimodule}:dbname=$config{userdbname};host=$config{userdbhost};port=$config{userdbport}", $config{userdbuser}, $config{userdbpasswd})
            or $logger->error_die($DBI::errstr);
  
    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning("Ungültige Session",$r);

        $sessiondbh->disconnect();
        $userdbh->disconnect();
        return OK;
    }
  
    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }

    my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
    unless($userid){
        OpenBib::Common::Util::print_warning("Diese Session ist nicht authentifiziert.",$r);

        $sessiondbh->disconnect();
        $userdbh->disconnect();
        return OK;
    }
  
    if ($action eq "showfields") {
        my $targetresult=$userdbh->prepare("select * from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
        $targetresult->execute($userid) or $logger->error($DBI::errstr);
    
        my $result=$targetresult->fetchrow_hashref();
    
        my $showfs=$result->{'fs'};
        my $fschecked="";
        $fschecked="checked=\"checked\"" if ($showfs);
    
        my $showhst=$result->{'hst'};
        my $hstchecked="";
        $hstchecked="checked=\"checked\"" if ($showhst);

        my $showhststring=$result->{'hststring'};
        my $hststringchecked="";
        $hststringchecked="checked=\"checked\"" if ($showhststring);
    
        my $showverf=$result->{'verf'};
        my $verfchecked="";
        $verfchecked="checked=\"checked\"" if ($showverf);
    
        my $showkor=$result->{'kor'};
        my $korchecked="";
        $korchecked="checked=\"checked\"" if ($showkor);
    
        my $showswt=$result->{'swt'};
        my $swtchecked="";
        $swtchecked="checked=\"checked\"" if ($showswt);
    
        my $shownotation=$result->{'notation'};
        my $notationchecked="";
        $notationchecked="checked=\"checked\"" if ($shownotation);
    
        my $showisbn=$result->{'isbn'};
        my $isbnchecked="";
        $isbnchecked="checked=\"checked\"" if ($showisbn);
    
        my $showissn=$result->{'issn'};
        my $issnchecked="";
        $issnchecked="checked=\"checked\"" if ($showissn);
    
        my $showsign=$result->{'sign'};
        my $signchecked="";
        $signchecked="checked=\"checked\"" if ($showsign);
    
        my $showmart=$result->{'mart'};
        my $martchecked="";
        $martchecked="checked=\"checked\"" if ($showmart);
    
        my $showejahr=$result->{'ejahr'};
        my $ejahrchecked="";
        $ejahrchecked="checked=\"checked\"" if ($showejahr);
    
        $targetresult->finish();
    
        my $userresult=$userdbh->prepare("select * from user where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        my $res=$userresult->fetchrow_hashref();
    
        my %userinfo=();

        $userinfo{'nachname'}   = $res->{'nachname'};
        $userinfo{'vorname'}    = $res->{'vorname'};
        $userinfo{'strasse'}    = $res->{'strasse'};
        $userinfo{'ort'}        = $res->{'ort'};
        $userinfo{'plz'}        = $res->{'plz'};
        $userinfo{'soll'}       = $res->{'soll'};
        $userinfo{'gut'}        = $res->{'gut'};
        $userinfo{'avanz'}      = $res->{'avanz'}; # Ausgeliehene Medien
        $userinfo{'branz'}      = $res->{'branz'}; # Buchrueckforderungen
        $userinfo{'bsanz'}      = $res->{'bsanz'}; # Bestellte Medien
        $userinfo{'vmanz'}      = $res->{'vmanz'}; # Vormerkungen
        $userinfo{'maanz'}      = $res->{'maanz'}; # ueberzogene Medien
        $userinfo{'vlanz'}      = $res->{'vlanz'}; # Verlaengerte Medien
        $userinfo{'sperre'}     = $res->{'sperre'};
        $userinfo{'sperrdatum'} = $res->{'sperrdatum'};
        $userinfo{'email'}      = $res->{'email'};
        $userinfo{'gebdatum'}   = $res->{'gebdatum'};
        $userinfo{'masktype'}   = $res->{'masktype'};

        my $loginname = $res->{'loginname'};
        my $password  = $res->{'pin'};
    
        my $passwortaenderung = "";
        my $loeschekennung    = "";
    
        # Wenn wir eine gueltige Mailadresse als Loginnamen haben,
        # dann liegt Selbstregistrierung vor und das Passwort kann
        # geaendert werden
        my $email_valid=Email::Valid->address($loginname);

        my $targettype=OpenBib::Common::Util::get_targettype_of_session($userdbh,$sessionID);

        # TT-Data erzeugen
        my $ttdata={
            view             => $view,
            stylesheet       => $stylesheet,
            sessionID        => $sessionID,

            loginname        => $loginname,
            password         => $password,
            email_valid      => $email_valid,
            targettype       => $targettype,
            fschecked        => $fschecked,
            hstchecked       => $hstchecked,
            hststringchecked => $hststringchecked,
            verfchecked      => $verfchecked,
            korchecked       => $korchecked,
            swtchecked       => $swtchecked,
            notationchecked  => $notationchecked,
            isbnchecked      => $isbnchecked,
            issnchecked      => $issnchecked,
            signchecked      => $signchecked,
            martchecked      => $martchecked,
            ejahrchecked     => $ejahrchecked,
            userinfo         => \%userinfo,

            show_corporate_banner => 0,
            show_foot_banner      => 1,
            config           => \%config,
        };
        OpenBib::Common::Util::print_page($config{tt_userprefs_tname},$ttdata,$r);
    }
    elsif ($action eq "changefields") {
        my $targetresult=$userdbh->prepare("update fieldchoice set fs = ?, hst = ?, hststring = ?, verf = ?, kor = ?, swt = ?, notation = ?, isbn = ?, issn = ?, sign = ?, mart = ?, ejahr = ? where userid = ?") or $logger->error($DBI::errstr);
        $targetresult->execute($showfs,$showhst,$showhststring,$showverf,$showkor,$showswt,$shownotation,$showisbn,$showissn,$showsign,$showmart,$showejahr, $userid) or $logger->error($DBI::errstr);
        $targetresult->finish();

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $sessionID,

            show_corporate_banner => 0,
            show_foot_banner      => 0,
            config     => \%config,
        };
        OpenBib::Common::Util::print_page($config{tt_userprefs_changefields_tname},$ttdata,$r);
    }
    elsif ($action eq "Kennung löschen") {
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $sessionID,

            show_corporate_banner => 0,
            show_foot_banner      => 0,
            config     => \%config,
        };
        OpenBib::Common::Util::print_page($config{tt_userprefs_ask_delete_tname},$ttdata,$r);
    }
    elsif ($action eq "Kennung soll wirklich gelöscht werden") {
        # Zuerst werden die Datenbankprofile geloescht
        my $userresult;
        $userresult=$userdbh->prepare("delete from profildb using profildb,userdbprofile where userdbprofile.userid = ? and userdbprofile.profilid=profildb.profilid") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        $userresult=$userdbh->prepare("delete from userdbprofile where userdbprofile.userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        # .. dann die Suchfeldeinstellungen
        $userresult=$userdbh->prepare("delete from fieldchoice where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        # .. dann die Merkliste
        $userresult=$userdbh->prepare("delete from treffer where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        # .. dann die Verknuepfung zur Session
        $userresult=$userdbh->prepare("delete from usersession where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        # und schliesslich der eigentliche Benutzereintrag
        $userresult=$userdbh->prepare("delete from user where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        $userresult->finish();

        # Als naechstes werden die 'normalen' Sessiondaten geloescht
        # Zuallererst loeschen der Trefferliste fuer diese sessionID
        my $idnresult;
        $idnresult=$sessiondbh->prepare("delete from treffer where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    
        $idnresult=$sessiondbh->prepare("delete from dbchoice where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    
        $idnresult=$sessiondbh->prepare("delete from searchresults where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    
        $idnresult=$sessiondbh->prepare("delete from sessionview where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($sessionID) or $logger->error($DBI::errstr);
    
        $idnresult->finish();

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $sessionID,

            show_corporate_banner => 1,
            show_foot_banner      => 0,
            config     => \%config,
        };
        OpenBib::Common::Util::print_page($config{tt_userprefs_userdeleted_tname},$ttdata,$r);
    }
    elsif ($action eq "Password ändern") {
        if ($password1 eq "" || $password1 ne $password2) {
            OpenBib::Common::Util::print_warning("Sie haben entweder kein Passwort eingegeben oder die beiden Passworte stimmen nicht überein",$r);
      
            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }
    
        my $targetresult=$userdbh->prepare("update user set pin = ? where userid = ?") or $logger->error($DBI::errstr);
        $targetresult->execute($password1,$userid) or $logger->error($DBI::errstr);
        $targetresult->finish();
    
        $r->internal_redirect("http://$config{servername}$config{userprefs_loc}?sessionID=$sessionID&action=showfields");
    }
    elsif ($action eq "changemask") {
        if ($setmask eq "") {
            OpenBib::Common::Util::print_warning("Es wurde keine Standard-Recherchemaske ausgewählt",$r);
      
            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }
    
        my $targetresult=$userdbh->prepare("update user set masktype = ? where userid = ?") or $logger->error($DBI::errstr);
        $targetresult->execute($setmask,$userid) or $logger->error($DBI::errstr);
        $targetresult->finish();

        my $idnresult=$sessiondbh->prepare("update sessionmask set masktype = ? where sessionid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($setmask,$sessionID) or $logger->error($DBI::errstr);
    
        $idnresult->finish();

        $r->internal_redirect("http://$config{servername}$config{userprefs_loc}?sessionID=$sessionID&action=showfields");
    }
    else {
        OpenBib::Common::Util::print_warning("Unerlaubte Aktion",$r);
    }
  
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
}

1;
__END__

=head1 NAME

OpenBib::UserPrefs - Verwaltung von Benutzer-Profil-Einstellungen

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs stellt dem Benutzer des 
Suchportals Einstellmoeglichkeiten seines persoenlichen Profils
zur Verfuegung.

=head2 Loeschung seiner Kennung

Loeschung seiner Kennung, so es sich um eine Kennung handelt, die 
im Rahmen der Selbstregistrierung angelegt wurde. Sollte der
Benutzer sich mit einer Kennung aus einer Sisis-Datenbank 
authentifiziert haben, so wird ihm die Loeschmoeglichkeit nicht 
angeboten
 

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
