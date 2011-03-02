#####################################################################
#
#  OpenBib::Handler::Apache::Circulation
#
#  Dieses File ist (C) 2004-2010 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Circulation;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::SubRequest ();
use Apache2::URI ();
use APR::URI ();
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
use OpenBib::Config::CirculationInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    my $view           = $self->param('view')           || '';

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);

    my $session = OpenBib::Session->instance({ apreq => $r });

    my $user       = OpenBib::User->instance({sessionID => $session->{ID}});
    
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

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);
        return Apache2::Const::OK;
    }

    my $sessionlogintarget = $user->get_targetdb_of_session($session->{ID});

    unless($user->{ID}){
        # Aufruf-URL
        my $return_url = $r->parsed_uri->unparse;

        # Return-URL in der Session abspeichern

        $session->set_returnurl($return_url);

        if ($validtarget){
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{login_loc}{name}?do_login=1;type=circulation;validtarget=$validtarget");
        }
        else {
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{login_loc}{name}?do_login=1");
        }
        return Apache2::Const::OK;
    }
    # wenn der Benutzer bereits fuer ein anderes Target authentifiziert ist
    else {
        if ($validtarget && $validtarget ne $sessionlogintarget){
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{login_loc}{name}?do_login=1;type=circulation;validtarget=$validtarget");
            return Apache2::Const::OK;
        }
        
    }
    
    my ($loginname,$password) = $user->get_credentials();
    my $database              = $user->get_targetdb_of_session($session->{ID});

    my $circinfotable         = OpenBib::Config::CirculationInfoTable->instance;

    if ($action eq "showcirc") {

        if ($circaction eq "reservations") {
            my $circexlist=undef;

            eval {
                my $soap = SOAP::Lite
                    -> uri("urn:/Circulation")
                        -> proxy($circinfotable->{$database}{circcheckurl});
                my $result = $soap->get_reservations(
                    SOAP::Data->name(parameter  =>\SOAP::Data->value(
                        SOAP::Data->name(username => $loginname)->type('string'),
                        SOAP::Data->name(password => $password)->type('string'),
                        SOAP::Data->name(database => $circinfotable->{$database}{circdb})->type('string'))));
                
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

                database     => $database,
                    
                utf2iso      => sub {
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
		    return $string;
                },
		  
                show_corporate_banner => 0,
                show_foot_banner      => 1,
                config       => $config,
                user         => $user,
                msg          => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_circulation_reserv_tname},$ttdata,$r);

        }
        elsif ($circaction eq "reminders") {
            my $circexlist=undef;

            eval {
                my $soap = SOAP::Lite
                    -> uri("urn:/Circulation")
                        -> proxy($circinfotable->{$database}{circcheckurl});
                my $result = $soap->get_reminders(
                    SOAP::Data->name(parameter  =>\SOAP::Data->value(
                        SOAP::Data->name(username => $loginname)->type('string'),
                        SOAP::Data->name(password => $password)->type('string'),
                        SOAP::Data->name(database => $circinfotable->{$database}{circdb})->type('string'))));
                
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
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_circulation_remind_tname},$ttdata,$r);
        }
        elsif ($circaction eq "orders") {
            my $circexlist=undef;

            eval {
                my $soap = SOAP::Lite
                    -> uri("urn:/Circulation")
                        -> proxy($circinfotable->{$database}{circcheckurl});
                my $result = $soap->get_orders(
                    SOAP::Data->name(parameter  =>\SOAP::Data->value(
                        SOAP::Data->name(username => $loginname)->type('string'),
                        SOAP::Data->name(password => $password)->type('string'),
                        SOAP::Data->name(database => $circinfotable->{$database}{circdb})->type('string'))));
                
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
                user       => $user,
                msg        => $msg,
            };
      
            OpenBib::Common::Util::print_page($config->{tt_circulation_orders_tname},$ttdata,$r);
        }
        else {
            my $circexlist=undef;
      
            eval {
                my $soap = SOAP::Lite
                    -> uri("urn:/Circulation")
                        -> proxy($circinfotable->{$database}{circcheckurl});
                my $result = $soap->get_borrows(
                    SOAP::Data->name(parameter  =>\SOAP::Data->value(
                        SOAP::Data->name(username => $loginname)->type('string'),
                        SOAP::Data->name(password => $password)->type('string'),
                        SOAP::Data->name(database => $circinfotable->{$database}{circdb})->type('string'))));
                
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

                database   => $database,

                utf2iso    => sub {
		    my $string=shift;
		    $string=~s/([^\x20-\x7F])/'&#' . ord($1) . ';'/gse;
		    return $string;
                },
		  
                show_corporate_banner => 0,
                show_foot_banner      => 1,
                config     => $config,
                user       => $user,
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
            
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{login_loc}{name}?do_login=1;type=circulation;validtarget=$validtarget");
            
            return Apache2::Const::OK;
        }

        my $circexlist=undef;

        $logger->info("Zweigstelle: $zweigstelle");
        
        eval {
            my $soap = SOAP::Lite
                -> uri("urn:/Circulation")
                    -> proxy($circinfotable->{$database}{circcheckurl});
            my $result = $soap->make_reservation(
                SOAP::Data->name(parameter  =>\SOAP::Data->value(
                    SOAP::Data->name(username     => $loginname)->type('string'),
                    SOAP::Data->name(password     => $password)->type('string'),
                    SOAP::Data->name(mediennummer => $mediennummer)->type('string'),
                    SOAP::Data->name(ausgabeort   => $ausgabeort)->type('string'),
                    SOAP::Data->name(zweigstelle  => $zweigstelle)->type('string'),
                    SOAP::Data->name(database     => $circinfotable->{$database}{circdb})->type('string'))));
            
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
            user       => $user,
            msg        => $msg,
        };
        
        OpenBib::Common::Util::print_page($config->{tt_circulation_make_reserv_tname},$ttdata,$r);
    }
    elsif ($action eq "cancel_reservation"){

        unless($sessionlogintarget eq $validtarget){
            # Aufruf-URL
            my $return_url = $r->parsed_uri->unparse;
            
            # Return-URL in der Session abspeichern
            
            $session->set_returnurl($return_url);
            
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{login_loc}{name}?do_login=1;type=circulation;validtarget=$validtarget");
            
            return Apache2::Const::OK;
        }

        my $circexlist=undef;

        $logger->info("Zweigstelle: $zweigstelle");

        eval {
            my $soap = SOAP::Lite
                -> uri("urn:/Circulation")
                    -> proxy($circinfotable->{$database}{circcheckurl});
            my $result = $soap->cancel_reservation(
                SOAP::Data->name(parameter  =>\SOAP::Data->value(
                    SOAP::Data->name(username     => $loginname)->type('string'),
                    SOAP::Data->name(password     => $password)->type('string'),
                    SOAP::Data->name(mediennummer => $mediennummer)->type('string'),
                    SOAP::Data->name(zweigstelle  => $zweigstelle)->type('string'),
                    SOAP::Data->name(database     => $circinfotable->{$database}{circdb})->type('string'))));
            
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

        $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{circulation_loc}{name}?action=showcirc;circaction=reservations");

        return Apache2::Const::OK;
    }
    elsif ($action eq "make_order"){

        unless($sessionlogintarget eq $validtarget){
            # Aufruf-URL
            my $return_url = $r->parsed_uri->unparse;
            
            # Return-URL in der Session abspeichern
            
            $session->set_returnurl($return_url);
            
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{login_loc}{name}?do_login=1;type=circulation;validtarget=$validtarget");
            
            return Apache2::Const::OK;
        }

        my $circexlist=undef;

        $logger->info("Zweigstelle: $zweigstelle");

        eval {
            my $soap = SOAP::Lite
                -> uri("urn:/Circulation")
                    -> proxy($circinfotable->{$database}{circcheckurl});
            my $result = $soap->make_order(
                SOAP::Data->name(parameter  =>\SOAP::Data->value(
                    SOAP::Data->name(username     => $loginname)->type('string'),
                    SOAP::Data->name(password     => $password)->type('string'),
                    SOAP::Data->name(mediennummer => $mediennummer)->type('string'),
                    SOAP::Data->name(ausgabeort   => $ausgabeort)->type('string'),
                    SOAP::Data->name(zweigstelle  => $zweigstelle)->type('string'),
                    SOAP::Data->name(database     => $circinfotable->{$database}{circdb})->type('string'))));
            
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
            user       => $user,
            msg        => $msg,
        };
        
        OpenBib::Common::Util::print_page($config->{tt_circulation_make_order_tname},$ttdata,$r);
    }
    elsif ($action eq "renew_loans"){

        unless($sessionlogintarget eq $validtarget){
            # Aufruf-URL
            my $return_url = $r->parsed_uri->unparse;
            
            # Return-URL in der Session abspeichern
            
            $session->set_returnurl($return_url);
            
            $r->internal_redirect("http://$config->{servername}$config->{base_loc}/$view/$config->{handler}{login_loc}{name}?do_login=1;type=circulation;validtarget=$validtarget");
            
            return Apache2::Const::OK;
        }

        my $circexlist=undef;

        eval {
            my $soap = SOAP::Lite
                -> uri("urn:/Circulation")
                    -> proxy($circinfotable->{$database}{circcheckurl});
            my $result = $soap->renew_loans(
                SOAP::Data->name(parameter  =>\SOAP::Data->value(
                    SOAP::Data->name(username     => $loginname)->type('string'),
                    SOAP::Data->name(password     => $password)->type('string'),
                    SOAP::Data->name(database     => $circinfotable->{$database}{circdb})->type('string'))));
            
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
            user       => $user,
            msg        => $msg,
        };
        
        OpenBib::Common::Util::print_page($config->{tt_circulation_renew_loans_tname},$ttdata,$r);
    }
    else {
        OpenBib::Common::Util::print_warning($msg->maketext("Unerlaubte Aktion"),$r,$msg);
    }
    return Apache2::Const::OK;
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
