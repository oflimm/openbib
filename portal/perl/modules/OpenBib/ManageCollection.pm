#####################################################################
#
#  OpenBib::ManageCollection
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

package OpenBib::ManageCollection;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common M_GET);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use POSIX;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::ManageCollection::Util;

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

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);


    # Verbindung zur SQL-Datenbank herstellen
    my $sessiondbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd})
            or $logger->error_die($DBI::errstr);

    my $userdbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{userdbname};host=$config->{userdbhost};port=$config->{userdbport}", $config->{userdbuser}, $config->{userdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $sessionID = $query->param('sessionID') || '';
    my $database  = $query->param('database')  || '';
    my $singleidn = $query->param('singleidn') || '';
    my $loeschen  = $query->param('loeschen')  || '';
    my $action    = ($query->param('action'))?$query->param('action'):'none';
    my $type      = ($query->param('type'))?$query->param('type'):'HTML';

    my $queryoptions_ref
        = OpenBib::Common::Util::get_queryoptions($sessiondbh,$query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions_ref->{l}) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    # Haben wir eine authentifizierte Session?
    my $userid=OpenBib::Common::Util::get_userid_of_session($userdbh,$sessionID);
  
    # Ab hier ist in $userid entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    $logger->debug(YAML::Dump($queryoptions_ref));

    my $targetdbinfo_ref
        = $config->get_targetdbinfo();

    my $targetcircinfo_ref
        = $config->get_targetcircinfo();

    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=OpenBib::Common::Util::get_viewname_of_session($sessiondbh,$sessionID);
    }

    my $idnresult="";

    # Einfuegen eines Titels ind die Merkliste
    if ($action eq "insert") {
        if ($userid) {
            # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
            my $idnresult=$userdbh->prepare("select count(*) as rowcount from treffer where userid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($userid,$database,$singleidn) or $logger->error($DBI::errstr);
            my $res    = $idnresult->fetchrow_hashref;
            my $anzahl = $res->{rowcount};

            $idnresult->finish();

            if ($anzahl == 0) {
                # Zuerst Eintragen der Informationen
                my $idnresult=$userdbh->prepare("insert into treffer values (?,?,?)") or $logger->error($DBI::errstr);
                $idnresult->execute($userid,$database,$singleidn) or $logger->error($DBI::errstr);
                $idnresult->finish();
            }
        }
        # Anonyme Session
        else {
            # Zuallererst Suchen, ob der Eintrag schon vorhanden ist.
            my $idnresult=$sessiondbh->prepare("select count(*) as rowcount from treffer where sessionid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
            $idnresult->execute($sessionID,$database,$singleidn) or $logger->error($DBI::errstr);
            my $res    = $idnresult->fetchrow_hashref;
            my $anzahl = $res->{rowcount};
            $idnresult->finish();
      
            if ($anzahl == 0) {
                # Zuerst Eintragen der Informationen
                my $idnresult=$sessiondbh->prepare("insert into treffer values (?,?,?)") or $logger->error($DBI::errstr);
                $idnresult->execute($sessionID,$database,$singleidn) or $logger->error($DBI::errstr);
                $idnresult->finish();
            }
        }

        # Dann Ausgabe des neuen Headers via Redirect
        $r->internal_redirect("http://$config->{servername}$config->{headerframe_loc}?sessionID=$sessionID");
    }
    # Anzeigen des Inhalts der Merkliste
    elsif ($action eq "show") {
        if ($loeschen eq "Los") {
            foreach my $loeschtit ($query->param('loeschtit')) {
                my ($loeschdb,$loeschidn)=split(":",$loeschtit);
	
                if ($userid) {
                    my $idnresult=$userdbh->prepare("delete from treffer where userid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
                    $idnresult->execute($userid,$loeschdb,$loeschidn) or $logger->error($DBI::errstr);
                    $idnresult->finish();
                }
                else {
                    my $idnresult=$sessiondbh->prepare("delete from treffer where sessionid = ? and dbname = ? and singleidn = ?") or $logger->error($DBI::errstr);
                    $idnresult->execute($sessionID,$loeschdb,$loeschidn) or $logger->error($DBI::errstr);
                    $idnresult->finish();
                }
            }
        }

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

        my @collection=();

        my @dbidnlist=();
        while (my $result=$idnresult->fetchrow_hashref()) {
            my $database  = decode_utf8($result->{'dbname'});
            my $singleidn = decode_utf8($result->{'singleidn'});

            push @dbidnlist, {
                database  => $database,
                singleidn => $singleidn,
            };
        }

        $idnresult->finish();

        if ($#dbidnlist < 0){
            OpenBib::Common::Util::print_warning($msg->maketext("Derzeit ist Ihre Merkliste leer"),$r,$msg);
            $sessiondbh->disconnect();
            $userdbh->disconnect();
            return OK;
        }
        
        foreach my $dbidn_ref (@dbidnlist) {
            my $database  = $dbidn_ref->{database};
            my $singleidn = $dbidn_ref->{singleidn};
      
            my $dbh
                = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                    or $logger->error_die($DBI::errstr);

            my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
                titidn             => $singleidn,
                dbh                => $dbh,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                database           => $database,
                sessionID          => $sessionID
            });

#            if ($type eq "Text") {
#                $normset=OpenBib::ManageCollection::Util::titset_to_text($normset);
#            }
#            elsif ($type eq "EndNote") {
#                $normset=OpenBib::ManageCollection::Util::titset_to_endnote($normset);
#            }

            $dbh->disconnect();

            $logger->debug("Merklistensatz geholt");
  
            push @collection, {
                database => $database,
                dbdesc   => $targetdbinfo_ref->{dbinfo}{$database},
                titidn   => $singleidn,
                tit      => $normset,
                mex      => $mexnormset,
                circ     => $circset
            };
        }
    
        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            sessionID  => $sessionID,
            qopts      => $queryoptions_ref,
            type       => $type,
            collection => \@collection,
            config     => $config,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_managecollection_show_tname},$ttdata,$r);
        return OK;
    }
    # Abspeichern der Merkliste
    elsif ($action eq "save") {
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
      
            my $dbh
                = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                    or $logger->error_die($DBI::errstr);
      
            my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
                titidn             => $singleidn,
                dbh                => $dbh,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                database           => $database,
                sessionID          => $sessionID
            });
      
#             if ($type eq "Text") {
#                 $normset=OpenBib::ManageCollection::Util::titset_to_text($normset);
#             }
#             elsif ($type eq "EndNote") {
#                 $normset=OpenBib::ManageCollection::Util::titset_to_endnote($normset);
#             }
      
            $dbh->disconnect();
      
            $logger->info("Merklistensatz geholt");
      
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
            qopts      => $queryoptions_ref,		
            type       => $type,
            collection => \@collection,
            config     => $config,
            msg        => $msg,
        };
    
        if ($type eq "HTML") {
      
            print $r->header_out("Content-Type" => "text/html");
            print $r->header_out("Content-Disposition" => "attachment;filename=\"kugliste.html\"");
            OpenBib::Common::Util::print_page($config->{tt_managecollection_save_html_tname},$ttdata,$r);
        }
        else {
            print $r->header_out("Content-Type" => "text/plain");
            print $r->header_out("Content-Disposition" => "attachment;filename=\"kugliste.txt\"");
            OpenBib::Common::Util::print_page($config->{tt_managecollection_save_plain_tname},$ttdata,$r);
        }
        return OK;
    }
    # Verschicken der Merkliste per Mail
    elsif ($action eq "mail") {
        # Weg mit der Singleidn - muss spaeter gefixed werden
        my $userresult=$userdbh->prepare("select loginname from user where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        my $loginname="";
    
        while(my $res=$userresult->fetchrow_hashref()){
            $loginname = decode_utf8($res->{'loginname'});
        }

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
      
            my $dbh
                = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                    or $logger->error_die($DBI::errstr);
      
            my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
                titidn             => $singleidn,
                dbh                => $dbh,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                database           => $database,
                sessionID          => $sessionID
            });
      
#             if ($type eq "Text") {
#                 $normset=OpenBib::ManageCollection::Util::titset_to_text($normset);
#             }
#             elsif ($type eq "EndNote") {
#                 $normset=OpenBib::ManageCollection::Util::titset_to_endnote($normset);
#             }
      
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
            qopts      => $queryoptions_ref,				
            type       => $type,
            loginname  => $loginname,
            singleidn  => $singleidn,
            database   => $database,
            collection => \@collection,
            config     => $config,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_managecollection_mail_tname},$ttdata,$r);
        return OK;
    }
    # Ausdrucken der Merkliste (HTML) ueber Browser
    elsif ($action eq "print") {
        # Weg mit der Singleidn - muss spaeter gefixed werden
        my $userresult=$userdbh->prepare("select loginname from user where userid = ?") or $logger->error($DBI::errstr);
        $userresult->execute($userid) or $logger->error($DBI::errstr);
    
        my $loginname="";
    
        while(my $res=$userresult->fetchrow_hashref()){
            $loginname = decode_utf8($res->{'loginname'});
        }
    
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
      
            my $dbh
                = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
                    or $logger->error_die($DBI::errstr);
      
            my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
                titidn             => $singleidn,
                dbh                => $dbh,
                targetdbinfo_ref   => $targetdbinfo_ref,
                targetcircinfo_ref => $targetcircinfo_ref,
                database           => $database,
                sessionID          => $sessionID
            });
      
#             if ($type eq "Text") {
#                 $normset=OpenBib::ManageCollection::Util::titset_to_text($normset);
#             }
#             elsif ($type eq "EndNote") {
#                 $normset=OpenBib::ManageCollection::Util::titset_to_endnote($normset);
#             }
      
            $dbh->disconnect();
      
            $logger->info("Merklistensatz geholt");
      
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
            qopts      => $queryoptions_ref,		
            type       => $type,
            loginname  => $loginname,
            singleidn  => $singleidn,
            database   => $database,
            collection => \@collection,
            config     => $config,
            msg        => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_managecollection_print_tname},$ttdata,$r);
        return OK;
    }
  
    $sessiondbh->disconnect();
    $userdbh->disconnect();
    return OK;
}

1;
