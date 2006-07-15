#####################################################################
#
#  OpenBib::ExternalJump
#
#  Dieses File ist (C) 2005-2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::ExternalJump;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Digest::MD5;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $query=Apache::Request->new($r);

    my $status=$query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments - ".$query->notes("error-notes"));
    }
  
    my $useragent=$r->subprocess_env('HTTP_USER_AGENT');
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Verbindung zur SQL-Datenbank herstellen
  
    my $sessiondbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);
  
    my $userdbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);
  
    # CGI-Uebergabe
    my $sessionID      = ($query->param('sessionID'))?$query->param('sessionID'):'';
    my @databases     = ($query->param('database'))?$query->param('database'):();
    my $singleidn     = $query->param('singleidn')     || '';
    my $action        = ($query->param('action'))?$query->param('action'):'';
    my $fs            = $query->param('fs')            || ''; # Freie Suche
    my $verf          = $query->param('verf')          || '';
    my $hst           = $query->param('hst')           || '';
    my $hststring     = $query->param('hststring')     || '';
    my $swt           = $query->param('swt')           || '';
    my $kor           = $query->param('kor')           || '';
    my $sign          = $query->param('sign')          || '';
    my $isbn          = $query->param('isbn')          || '';
    my $issn          = $query->param('issn')          || '';
    my $notation      = $query->param('notation')      || '';
    my $ejahr         = $query->param('ejahr')         || '';
    my $mart          = $query->param('mart')          || '';
    my $boolhst       = $query->param('boolhst')       || '';
    my $boolswt       = $query->param('boolswt')       || '';
    my $boolkor       = $query->param('boolkor')       || '';
    my $boolnotation  = $query->param('boolnotation')  || '';
    my $boolisbn      = $query->param('boolisbn')      || '';
    my $boolsign      = $query->param('boolsign')      || '';
    my $boolejahr     = $query->param('boolejahr')     || '';
    my $boolissn      = $query->param('boolissn')      || '';
    my $boolverf      = $query->param('boolverf')      || '';
    my $boolfs        = $query->param('boolfs')        || '';
    my $boolmart      = $query->param('boolmart')      || '';
    my $boolhststring = $query->param('boolhststring') || '';
    my $queryid       = $query->param('queryid')       || '';

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
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

    # Authorisierte Session?
    my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
      
    unless (OpenBib::Common::Util::session_is_valid($sessiondbh,$sessionID)){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        $sessiondbh->disconnect();
        $userdbh->disconnect();
    
        return OK;
    }
  
    my $viewdesc = $config->get_viewdesc_from_viewname($view);
  
    my $hits;
    my $searchquery_ref;

    if ($queryid ne "") {
        my $idnresult=$sessiondbh->prepare("select query,hits from queries where queryid = ?") or $logger->error($DBI::errstr);
        $idnresult->execute($queryid) or $logger->error($DBI::errstr);
    
        my $result       = $idnresult->fetchrow_hashref();
        $searchquery_ref = Storable::thaw(pack "H*",$result->{query});
        $hits            = decode_utf8($result->{'hits'});

        $idnresult->finish();

#         $thisquery.="SWT: $swt "        if ($swt);
#         $thisquery.="KOR: $kor "        if ($kor);
#         $thisquery.="NOT: $notation "   if ($notation);
#         $thisquery.="SIG: $sign "       if ($sign);
#         $thisquery.="EJAHR: $ejahr "    if ($ejahr);
#         $thisquery.="ISBN: $isbn "      if ($isbn);
#         $thisquery.="ISSN: $issn "      if ($issn);
#         $thisquery.="MART: $mart "      if ($mart);
#         $thisquery.="HSTR: $hststring " if ($hststring);
#         $thisquery.="= Treffer: $hits"  if ($hits);

#         # Plus-Zeichen entfernen
    
#         $verf  =~s/%2B(\w+)/$1/g;
#         $hst   =~s/%2B(\w+)/$1/g;
#         $kor   =~s/%2B(\w+)/$1/g;
#         $ejahr =~s/%2B(\w+)/$1/g;
#         $isbn  =~s/%2B(\w+)/$1/g;
#         $issn  =~s/%2B(\w+)/$1/g;

#         $verf  =~s/\+(\w+)/$1/g;
#         $hst   =~s/\+(\w+)/$1/g;
#         $kor   =~s/\+(\w+)/$1/g;
#         $ejahr =~s/\+(\w+)/$1/g;
#         $isbn  =~s/\+(\w+)/$1/g;
#         $issn  =~s/\+(\w+)/$1/g;
    
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Keine gültige Anfrage-ID"),$r,$msg);
        $sessiondbh->disconnect();
        $userdbh->disconnect();
    
        return OK;
    }

    # Haben wir eine Benutzernummer? Dann versuchen wir den 
    # Authentifizierten Sprung in die Digibib
    my $loginname = "";
    my $password  = "";

    my $globalsessionID="$config->{servername}:$sessionID";
    my $userresult=$userdbh->prepare("select user.loginname,user.pin,count(user.loginname) as rowcount from usersession,user where usersession.sessionid = ? and user.userid=usersession.userid") or die "Error -- $DBI::errstr";
 
    $userresult->execute($globalsessionID);
    my $res  = $userresult->fetchrow_hashref();
    my $rows = $res->{rowcount};

    if ($rows > 0) {
        $loginname = decode_utf8($res->{'loginname'});
        $password  = decode_utf8($res->{'pin'});
    }
    $userresult->finish();

    my $authurl="";
    unless (Email::Valid->address($loginname)){

        # Hash im loginname durch %23 ersetzen
        $loginname=~s/#/\%23/;

        if ($loginname && $password) {
            $authurl="&USERID=$loginname&PASSWORD=$password";
        }
    }

    # TT-Data erzeugen
    my $ttdata={
        view         => $view,
        stylesheet   => $stylesheet,
        viewdesc     => $viewdesc,
        sessionID    => $sessionID,
        queryid      => $queryid,
	      
	thisquery    => {
			 searchquery => $searchquery_ref,
			 hits        => $hits,
			},

        authurl      => $authurl,
	      
        config       => $config,
        msg          => $msg,
    };

    OpenBib::Common::Util::print_page($config->{tt_externaljump_tname},$ttdata,$r);

    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
}

1;
