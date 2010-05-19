#####################################################################
#
#  OpenBib::Handler::Apache::ManageCollection
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

package OpenBib::Handler::Apache::ManageCollection;

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

use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
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

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $user      = OpenBib::User->instance({sessionID => $session->{ID}});
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $database                = $query->param('database')                || '';
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

    my $queryoptions = OpenBib::QueryOptions->instance($query);
    
    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    if (!$session->is_valid()) {
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    my $view=$r->subprocess_env('openbib_view') || $config->{defaultview};

    $logger->debug(":".$user->is_authenticated.":$do_addlitlist");
    if (! $user->is_authenticated && $do_addlitlist) {
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;

        # Return-URL in der Session abspeichern

        $session->set_returnurl($return_url);

        $logger->debug("Nicht authentifizierter Nutzer versucht Literaturliste anzulegen");
        $r->internal_redirect("http://$config->{servername}$config->{login_loc}?sessionID=$session->{ID};view=$view;do_login=1");

        return Apache2::Const::OK;
    }
    elsif (! $user->is_authenticated && $do_addtags) {
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;

        # Return-URL in der Session abspeichern

        $session->set_returnurl($return_url);

        $logger->debug("Nicht authentifizierter Nutzer versucht Tags anzulegen");
        $r->internal_redirect("http://$config->{servername}$config->{login_loc}?sessionID=$session->{ID};view=$view;do_login=1");

        return Apache2::Const::OK;
    }

    $logger->info("SessionID: $session->{ID}");
    
    my $idnresult="";

    # Einfuegen eines Titels ind die Merkliste
    if ($action eq "insert") {
        if ($user->{ID}) {
            $user->add_item_to_collection({
                item => {
                    dbname    => $database,
                    singleidn => $singleidn,
                },
            });
        }
        # Anonyme Session
        else {
            $session->set_item_in_collection({
                database => $database,
                id       => $singleidn,
            });
        }

        OpenBib::Common::Util::print_info($msg->maketext("Der Titel wurde zu Ihrer Merkliste hinzugef&uuml;gt."),$r,$msg);
        return Apache2::Const::OK;
    }
    # Anzeigen des Inhalts der Merkliste
    elsif ($action eq "show") {
        if ($do_collection_showcount) {

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
        elsif ($do_collection_delentry) {
            foreach my $tit ($query->param('titid')) {
                my ($titdb,$titid)=split(":",$tit);
	
                if ($user->{ID}) {
                    $user->delete_item_from_collection({
                        item => {
                            dbname    => $titdb,
                            singleidn => $titid,
                        },
                    });
                } else {
                    $session->clear_item_in_collection({
                        database => $titdb,
                        id       => $titid,
                    });
                }
            }

            my $redirecturl   = "http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{managecollection_loc}{name}";

            if ($view ne "") {
                $redirecturl.=";view=$view";
            }

            $r->internal_redirect($redirecturl);
            return Apache2::Const::OK;
        }
        elsif ($do_litlist_addentry) {
            my $litlist_properties_ref = $user->get_litlist_properties({ litlistid => $litlistid});

            foreach my $tit ($query->param('titid')) {
                my ($titdb,$titid)=split(":",$tit);
	    
                if ($litlist_properties_ref->{userid} eq $user->{ID}) {
                    $user->add_litlistentry({ titid => $titid, titdb => $titdb, litlistid => $litlistid});
                }
            }

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{litlists_loc}{name}?action=manage&litlistid=$litlistid&do_showlitlist=1");
            return Apache2::Const::OK;

	}
        elsif ($do_addlitlist) {
            if (!$title) {
                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen einen Titel f&uuml;r Ihre Literaturliste eingeben."),$r,$msg);
	    
                return Apache2::Const::OK;
            }
	  
            $user->add_litlist({ title =>$title, type => $littype});

            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{managecollection_loc}{name}?action=show&type=HTML");
            return Apache2::Const::OK;
	}
        elsif ($do_addtags) {
            if (!$tags) {
                OpenBib::Common::Util::print_warning($msg->maketext("Sie müssen Tags f&uuml;r die ausgew&auml;hlten Titel eingeben."),$r,$msg);
                return Apache2::Const::OK;
            }

            if ($user->{ID}){
                my $loginname = $user->get_username;
                
                if ($query->param('titid')){
                    foreach my $tit ($query->param('titid')) {
                        my ($titdb,$titid)=split(":",$tit);
                        
                        $user->add_tags({
                            tags      => $tags,
                            titid     => $titid,
                            titdb     => $titdb,
                            loginname => $loginname,
                            type      => $tags_type,
                        });
                        
                    }
                }
                else {
                    OpenBib::Common::Util::print_warning($msg->maketext("Sie haben keine Titel ausgew&auml;hlt."),$r,$msg);
                    return Apache2::Const::OK;
                }
            }
            else {
                OpenBib::Common::Util::print_warning($msg->maketext("Bitte authentifizieren Sie sich unter Mein KUG."),$r,$msg);
            }
            
            my $redirecturl   = "http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{managecollection_loc}{name}";

            if ($view ne "") {
                $redirecturl.=";view=$view";
            }

            $r->internal_redirect($redirecturl);
            return Apache2::Const::OK;
        }
        
        my $recordlist = new OpenBib::RecordList::Title();

        if ($user->{ID}) {
            $recordlist = $user->get_items_in_collection();
        }
        else {
            $recordlist = $session->get_items_in_collection();
        }

        if ($recordlist->get_size() == 0) {

            # TT-Data erzeugen
            my $ttdata={
                view           => $view,
                stylesheet     => $stylesheet,
                sessionID      => $session->{ID},
                qopts          => $queryoptions->get_options,

                config         => $config,
                user           => $user,
                msg            => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_managecollection_empty_tname},$ttdata,$r);
            return Apache2::Const::OK;
        }

        # TT-Data erzeugen
        my $ttdata={
            view              => $view,
            stylesheet        => $stylesheet,
            sessionID         => $session->{ID},
            qopts             => $queryoptions->get_options,
            type              => $type,
            show              => $show,
            recordlist        => $recordlist,
            dbinfo            => $dbinfotable,

	    user              => $user,
            config            => $config,
            user              => $user,
            msg               => $msg,
        };
    
        OpenBib::Common::Util::print_page($config->{tt_managecollection_show_tname},$ttdata,$r);
        return Apache2::Const::OK;
    }
    # Abspeichern der Merkliste
    elsif ($action eq "save" || $action eq "print" || $action eq "mail") {
        my $loginname=$user->get_username();

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

        if ($action eq "save"){
            # TT-Data erzeugen
            my $ttdata={
                view        => $view,
                stylesheet  => $stylesheet,
                sessionID   => $session->{ID},
                qopts       => $queryoptions->get_options,		
                type        => $type,
                show        => $show,
                recordlist  => $recordlist,
                dbinfo      => $dbinfotable,
                
                config     => $config,
                msg        => $msg,
            };

            if ($type eq "HTML") {
                $r->content_type('text/html');
                $r->headers_out->add("Content-Disposition" => "attachment;filename=\"kugliste.html\"");
                OpenBib::Common::Util::print_page($config->{tt_managecollection_save_html_tname},$ttdata,$r);
            }
            else {
                $r->content_type('text/plain');
                $r->headers_out->add("Content-Disposition" => "attachment;filename=\"kugliste.txt\"");
                OpenBib::Common::Util::print_page($config->{tt_managecollection_save_plain_tname},$ttdata,$r);
            }
            return Apache2::Const::OK;
        }
        elsif ($action eq "print"){
            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,		
                sessionID  => $session->{ID},
                qopts      => $queryoptions->get_options,		
                type       => $type,
                show       => $show,
                loginname  => $loginname,
                singleidn  => $singleidn,
                database   => $database,
                recordlist => $recordlist,
                dbinfo     => $dbinfotable,

                config     => $config,
                msg        => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_managecollection_print_tname},$ttdata,$r);
            return Apache2::Const::OK;
        }
        elsif ($action eq "mail"){
            # TT-Data erzeugen
            my $ttdata={
                view        => $view,
                stylesheet  => $stylesheet,
                sessionID   => $session->{ID},
                qopts       => $queryoptions->get_options,				
                type        => $type,
                show        => $show,
                loginname   => $loginname,
                singleidn   => $singleidn,
                database    => $database,
                recordlist  => $recordlist,
                dbinfo      => $dbinfotable,
                
                config      => $config,
                msg         => $msg,
            };
            
            OpenBib::Common::Util::print_page($config->{tt_managecollection_mail_tname},$ttdata,$r);
            return Apache2::Const::OK;
        }
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Unerlaubte Aktion"),$r,$msg);
        return Apache2::Const::OK;
    }
    return Apache2::Const::OK;
}

1;
