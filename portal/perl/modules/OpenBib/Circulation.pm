#####################################################################
#
#  OpenBib::Circulation
#
#  Dieses File ist (C) 2004-2006 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Circulation;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache::Constants qw(:common);
use Apache::Reload;
use Apache::Request ();
use DBI;
use Digest::MD5;
use Email::Valid;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Socket;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
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

    my $session    = new OpenBib::Session({
        sessionID => $query->param('sessionID'),
    });

    my $user       = new OpenBib::User();
    
    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);

    my $action     = ($query->param('action'    ))?$query->param('action'):'none';
    my $circaction = ($query->param('circaction'))?$query->param('circaction'):'none';
    my $offset     = ($query->param('offset'    ))?$query->param('offset'):0;
    my $listlength = ($query->param('listlength'))?$query->param('listlength'):10;

    # Aktive Aenderungen des Nutzerkontos
    my $validtarget   = ($query->param('validtarget'))?$query->param('validtarget'):undef;
    my $mediennummer  = ($query->param('mnr'        ))?$query->param('mnr'):undef;
    my $ausgabeort    = ($query->param('aort'       ))?$query->param('aort'):0;
    my $zweigstelle   = ($query->param('zst'        ))?$query->param('zst'):0;

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
  
    my $userid             = $user->get_userid_of_session($session->{ID});
    my $sessionlogintarget = $user->get_targetdb_of_session($session->{ID});

    unless($userid){
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;

        # Return-URL in der Session abspeichern

        $session->set_returnurl($return_url);

        if ($validtarget){
            $r->internal_redirect("http://$config->{servername}$config->{login_loc}?sessionID=$session->{ID};view=$view;do_login=1;type=circulation;validtarget=$validtarget");
        }
        else {
            $r->internal_redirect("http://$config->{servername}$config->{login_loc}?sessionID=$session->{ID};view=$view;do_login=1");
        }
        return OK;
    }
    # wenn der Benutzer bereits fuer ein anderes Target authentifiziert ist
    else {
      if ($validtarget && $validtarget ne $sessionlogintarget){
	$r->internal_redirect("http://$config->{servername}$config->{login_loc}?sessionID=$session->{ID};view=$view;do_login=1;type=circulation;validtarget=$validtarget");
	return OK;
      }
      
    }

    my ($loginname,$password) = $user->get_cred_for_userid($userid);
    my $database              = $user->get_targetdb_of_session($session->{ID});
    my $targetcircinfo_ref    = $config->get_targetcircinfo();

    if ($action eq "showcirc") {

        if ($circaction eq "reservations") {
            my $circexlist=undef;

            eval {
                my $soap = SOAP::Lite
                    -> uri("urn:/Circulation")
                        -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
                my $result = $soap->get_reservations(
                    SOAP::Data->name(parameter  =>\SOAP::Data->value(
                        SOAP::Data->name(username => $loginname)->type('string'),
                        SOAP::Data->name(password => $password)->type('string'),
                        SOAP::Data->name(database => $targetcircinfo_ref->{$database}{circdb})->type('string'))));
                
                unless ($result->fault) {
                    $circexlist=$result->result;
                }
                else {
                    $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                }
            };
            
            if ($@){
                $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
	    }
      
            # TT-Data erzeugen
      
            my $ttdata={
                view         => $view,
                stylesheet   => $stylesheet,
		  
                sessionID    => $session->{ID},
                loginname    => $loginname,
                password     => $password,
		  
                reservations => $circexlist,
		  
                utf2iso      => sub {
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
		    return $string;
                },
		  
                show_corporate_banner => 0,
                show_foot_banner      => 1,
                config       => $config,
                msg          => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_circulation_reserv_tname},$ttdata,$r);

        }
        elsif ($circaction eq "reminders") {
            my $circexlist=undef;

            eval {
                my $soap = SOAP::Lite
                    -> uri("urn:/Circulation")
                        -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
                my $result = $soap->get_reminders(
                    SOAP::Data->name(parameter  =>\SOAP::Data->value(
                        SOAP::Data->name(username => $loginname)->type('string'),
                        SOAP::Data->name(password => $password)->type('string'),
                        SOAP::Data->name(database => $targetcircinfo_ref->{$database}{circdb})->type('string'))));
                
                unless ($result->fault) {
                    $circexlist=$result->result;
                }
                else {
                    $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                }
            };

            if ($@){
                $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
	    }
            
            # TT-Data erzeugen
      
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
		  
                sessionID  => $session->{ID},
                loginname  => $loginname,
                password   => $password,
		  
                reminders  => $circexlist,
		  
                utf2iso    => sub {
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
		    return $string;
                },
		  
                show_corporate_banner => 0,
                show_foot_banner      => 1,
                config     => $config,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_circulation_remind_tname},$ttdata,$r);
        }
        elsif ($circaction eq "orders") {
            my $circexlist=undef;

            eval {
                my $soap = SOAP::Lite
                    -> uri("urn:/Circulation")
                        -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
                my $result = $soap->get_orders(
                    SOAP::Data->name(parameter  =>\SOAP::Data->value(
                        SOAP::Data->name(username => $loginname)->type('string'),
                        SOAP::Data->name(password => $password)->type('string'),
                        SOAP::Data->name(database => $targetcircinfo_ref->{$database}{circdb})->type('string'))));
                
                unless ($result->fault) {
                    $circexlist=$result->result;
                }
                else {
                    $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                }
            };
            
            if ($@){
                $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
            }
                
            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
		  
                sessionID  => $session->{ID},
                loginname  => $loginname,
                password   => $password,
		  
                orders     => $circexlist,
		  
                utf2iso    => sub {
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
		    return $string;
                },
		  
                show_corporate_banner => 0,
                show_foot_banner      => 1,
                config     => $config,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_circulation_orders_tname},$ttdata,$r);
        }
        else {
            my $circexlist=undef;

            eval {
                my $soap = SOAP::Lite
                    -> uri("urn:/Circulation")
                        -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
                my $result = $soap->get_borrows(
                    SOAP::Data->name(parameter  =>\SOAP::Data->value(
                        SOAP::Data->name(username => $loginname)->type('string'),
                        SOAP::Data->name(password => $password)->type('string'),
                        SOAP::Data->name(database => $targetcircinfo_ref->{$database}{circdb})->type('string'))));
                
                unless ($result->fault) {
                    $circexlist=$result->result;
                }
                else {
                    $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                }
            };
            
            if ($@){
                $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
            }

            # TT-Data erzeugen
            my $ttdata={
                view       => $view,
                stylesheet => $stylesheet,
		  
                sessionID  => $session->{ID},
                loginname  => $loginname,
                password   => $password,
		  
                borrows    => $circexlist,
		  
                utf2iso    => sub {
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
		    return $string;
                },
		  
                show_corporate_banner => 0,
                show_foot_banner      => 1,
                config     => $config,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_circulation_tname},$ttdata,$r);
        }


    }
    elsif ($action eq "make_reservation"){

        unless($sessionlogintarget eq $validtarget){
            # Aufruf-URL
            my $return_url = $r->parsed_uri->unparse;
            
            # Return-URL in der Session abspeichern
            
            $session->set_returnurl($return_url);
            
            $r->internal_redirect("http://$config->{servername}$config->{login_loc}?sessionID=$session->{ID};view=$view;do_login=1;type=circulation;validtarget=$validtarget");
            
            return OK;
        }
        
        my $circexlist=undef;
        
        $logger->info("Zweigstelle: $zweigstelle");
        
        eval {
            my $soap = SOAP::Lite
                -> uri("urn:/Circulation")
                    -> proxy($targetcircinfo_ref->{$database}{circcheckurl});
            my $result = $soap->make_reservation(
                SOAP::Data->name(parameter  =>\SOAP::Data->value(
                    SOAP::Data->name(username     => $loginname)->type('string'),
                    SOAP::Data->name(password     => $password)->type('string'),
                    SOAP::Data->name(mediennummer => $mediennummer)->type('string'),
                    SOAP::Data->name(ausgabeort   => $ausgabeort)->type('string'),
                    SOAP::Data->name(zweigstelle  => $zweigstelle)->type('string'),
                    SOAP::Data->name(database     => $targetcircinfo_ref->{$database}{circdb})->type('string'))));
            
            unless ($result->fault) {
                $circexlist=$result->result;
            }
            else {
                $logger->error("SOAP MediaStatus Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
            }
        };
        
        if ($@){
            $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
        }

        # TT-Data erzeugen
        my $ttdata={
            view       => $view,
            stylesheet => $stylesheet,
            
            sessionID  => $session->{ID},
            
            result     => $circexlist,
            
            config     => $config,
            msg        => $msg,
        };
        
        OpenBib::Common::Util::print_page($config->{tt_circulation_make_reserv_tname},$ttdata,$r);
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Unerlaubte Aktion"),$r,$msg);
    }
    return OK;
}

1;
__END__

=head1 NAME

OpenBib::Circulation - Benutzerkonto

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs bietet dem Benutzer des 
Suchportals einen Einblick in das jeweilige Benutzerkonto und gibt
eine Aufstellung der ausgeliehenen, vorgemerkten sowie ueberzogenen
Medien.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
