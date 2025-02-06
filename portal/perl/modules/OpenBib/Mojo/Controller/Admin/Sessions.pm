#####################################################################
#
#  OpenBib::Mojo::Controller::Admin::Sessions
#
#  Dieses File ist (C) 2004-2015 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Mojo::Controller::Admin::Sessions;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Data::Pageset;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use JSON::XS;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Admin';

sub show_active_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI-Parameter

    my $offset = $queryoptions->get_option('page')*$queryoptions->get_option('num')-$queryoptions->get_option('num');
    my $num    = $queryoptions->get_option('num');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my @sessions = $session->get_info_of_all_active_sessions({offset => $offset, num => $num});

    my $total_count = $session->get_number_of_all_active_sessions;
    
    my $nav = Data::Pageset->new({
        'total_entries'    => $total_count,
        'entries_per_page' => $queryoptions->get_option('num'),
        'current_page'     => $queryoptions->get_option('page'),
        'mode'             => 'slide',
    });

    my $ttdata={
        total_count => $total_count,
        nav         => $nav,
        sessions    => \@sessions,
    };
    
    return $self->print_page($config->{tt_admin_sessions_active_tname},$ttdata);
}

sub show_active_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $sid            = $self->strip_suffix($self->param('sessionid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $thissession = $session->get_schema->resultset('Sessioninfo')->search_rs(
        {
            id => $sid,
        }
    )->single;

    if (!$thissession){
        $logger->debug("No such session with id $sid");
        return $self->print_warning($msg->maketext("Diese Session existiert nicht."));
    }
    
    my ($username,$createtime) = ($thissession->username,$thissession->createtime);
    
    my @queries                = $session->get_all_searchqueries({
        sid => $sid,
    });
    
    my @events = ();
    
    foreach my $event ($thissession->eventlogs->all){
        my $type        = $event->type;
        my $tstamp      = $event->tstamp;
        my $content     = $event->content;

        my $sort = substr($tstamp,0,22);
        $sort=~s/\D//g;
        
        next unless ($content);
        
        push @events, {
            sort       => $sort,
            type       => $type,
            content    => $content,
            tstamp     => $tstamp,
        };
    }

    foreach my $event ($thissession->eventlogjsons->all){
        my $type        = $event->type;
        my $tstamp      = $event->tstamp;
        my $content     = encode_utf8($event->content);
        
        my $sort = substr($tstamp,0,22);
        $sort=~s/\D//g;

        next if (!$content);

        my $json_ref;

	eval {
	    $json_ref = decode_json $content;
	};
	
	if ($@){
	    $logger->error("Error decoding JSON ".$@);
	    next;
	}

        push @events, {
            sort       => $sort,
            type       => $type,
            content    => $json_ref,
            tstamp     => $tstamp,
        };
    }

    @events = map { $_->[0] }
        sort { $b->[1] <=> $a->[1] }
            map { [$_, $_->{sort}] }
                @events;
    
    my $singlesession={
        id              => $sid,
        createtime      => $createtime,
        username        => $username,
        numqueries      => $#queries+1,
        queries         => \@queries,
    };
    
    my $ttdata={
        thissession => $singlesession,
        queries     => \@queries,
        events      => \@events,
    };
    
    return $self->print_page($config->{tt_admin_sessions_active_record_tname},$ttdata);
}

sub show_archived_search_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $ttdata={
    };
    
    return $self->print_page($config->{tt_admin_sessions_archived_search_form_tname},$ttdata);
}

sub show_archived_search {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI Args
    my $fromdate        = $r->param('fromdate') || '';
    my $todate          = $r->param('todate')   || '';

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    unless ($fromdate && $todate){
        $logger->debug("No dates given.");
        return $self->print_warning($msg->maketext("Bitte geben Sie ein Anfangs- sowie ein End-Datum an."));
    }

    my $statistics = new OpenBib::Statistics;

    my $sessions = $statistics->get_schema->resultset('Sessioninfo')->search_rs(
        {
            -and => [
                { 'createtime' => { '>=' => $fromdate }},
                { 'createtime' => { '<=' => $todate }}                
            ],
        },
        {
            order_by => ['createtime ASC'],
        }
    );
    
    $logger->debug("$fromdate / $todate");

    my @archived_sessions=();
    
    foreach my $thissession ($sessions->all) {
        my $id              = $thissession->id;
        my $sessionid       = $thissession->sessionid;
        my $createtime      = $thissession->createtime;
        
        push @archived_sessions, {
            id         => $id,
            sessionid  => $sessionid,
            createtime => $createtime,
        };
    }
    
    
    my $ttdata={
        sessions   => \@archived_sessions,
        
        fromdate   => $fromdate,
        todate     => $todate,
    };
    
    return $self->print_page($config->{tt_admin_sessions_archived_search_tname},$ttdata);
}

sub show_archived_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $sid            = $self->strip_suffix($self->param('sessionid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $session        = $self->stash('session');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $queryoptions   = $self->stash('qopts');
    my $stylesheet     = $self->stash('stylesheet');
    my $useragent      = $self->stash('useragent');
    my $path_prefix    = $self->stash('path_prefix');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $statistics = new OpenBib::Statistics;

    my $thissession = $statistics->get_schema->resultset('Sessioninfo')->search_rs(
        {
            id => $sid,
        }
    )->single;

    if (!$thissession){
        $logger->debug("No such session with id $sid");
        return $self->print_warning($msg->maketext("Diese Session existiert nicht."));
    }
    
    my $serialized_type_ref = {
        1  => 1,
        10 => 1,
    };
    
    my @events = ();
    
    foreach my $event ($thissession->eventlogs->all){
        my $type        = $event->type;
        my $tstamp      = $event->tstamp;
        my $content     = $event->content;

        my $sort = substr($tstamp,0,22);
        $sort=~s/\D//g;

        push @events, {
            type       => $type,
            content    => $content,
            tstamp     => $tstamp,
            sort       => $sort,
        };
    }

    foreach my $event ($thissession->eventlogjsons->all){
        my $type        = $event->type;
        my $tstamp      = $event->tstamp;
        my $content     = $event->content;

        my $sort = substr($tstamp,0,22);
        $sort=~s/\D//g;

        my $json_ref;

        eval {
            $json_ref = decode_json $content;
        };

        if ($@){
            $logger->error("Error decoding JSON ".$@);
            next;
        }

        push @events, {
            type       => $type,
            content    => $json_ref,
            tstamp     => $tstamp,
            sort       => $sort,
        };
    }

    @events = map { $_->[0] }
        sort { $b->[1] <=> $a->[1] }
            map { [$_, $_->{sort}] }
                @events;
    
    my $ttdata = {
        sid             => $sid,
        events          => \@events,
    };

    return $self->print_page($config->{tt_admin_sessions_archived_record_tname},$ttdata);
}

1;
