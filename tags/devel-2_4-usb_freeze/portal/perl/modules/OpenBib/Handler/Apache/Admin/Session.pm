#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Session
#
#  Dieses File ist (C) 2004-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Admin::Session;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common :http);
use Apache2::Log;
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::SubRequest ();
use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use JSON::XS;
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Database::Config;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use CGI::Application::Plugin::Redirect;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_active_collection');
    $self->run_modes(
        'show_active_collection'     => 'show_active_collection',
        'show_active_record'         => 'show_active_record',
        'show_archived_search_form'  => 'show_archived_search_form',
        'show_archived_search'       => 'show_archived_search',
        'show_archived_record'       => 'show_archived_record',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_active_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

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

    if (!$self->is_authenticated('admin')){
        return;
    }

    my @sessions = $session->get_info_of_all_active_sessions();
    
    my $ttdata={
        sessions   => \@sessions,
    };
    
    $self->print_page($config->{tt_admin_session_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_active_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $sessionid      = $self->param('sessionid');

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

    if (!$self->is_authenticated('admin')){
        return;
    }

    my ($username,$createtime) = $session->get_info($sessionid);
    my @queries                = $session->get_all_searchqueries({
        sessionid => $sessionid,
    });
    
    if (!$username) {
        $username="anonymous";
    }
    
    my $singlesession={
        sessionid       => $sessionid,
        createtime      => $createtime,
        username        => $username,
        numqueries      => $#queries+1,
        queries         => \@queries,
    };
    
    my $ttdata={
        thissession  => $singlesession,
        queries    => \@queries,
    };
    
    $self->print_page($config->{tt_admin_session_record_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_archived_search_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

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

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $ttdata={
    };
    
    $self->print_page($config->{tt_admin_session_search_form_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_archived_search {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

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
    my $clientip        = $query->param('clientip') || '';
    my $fromdate        = $query->param('fromdate') || '';
    my $todate          = $query->param('todate')   || '';

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $statisticsdbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
            or $logger->error($DBI::errstr);

    unless (($fromdate && $todate) || $clientip){
        $self->print_warning($msg->maketext("Bitte geben Sie ein Anfangs- sowie ein End-Datum oder alternativ eine IP-Adresse an!"));
        return Apache2::Const::OK;
    }

    my @sql_where = ();
    my @sql_args  = ();
    # Eventtyp 102 = Client-IP
    if ($clientip){
        push @sql_where, "type=102 and content = ?";
        push @sql_args, $clientip;
    }

    push @sql_where, "tstamp > ? and tstamp < ?";
    push @sql_args, ($fromdate,$todate);
    
    my $sqlstring="select sessionid,tstamp from eventlog where ".join(" and ",@sql_where);
    
    $logger->debug("$sqlstring - $clientip / $fromdate / $todate");
    
    my $idnresult=$statisticsdbh->prepare($sqlstring) or $logger->error($DBI::errstr);
    $idnresult->execute(@sql_args) or $logger->error($DBI::errstr);

    my @sessions=();
    
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $singlesessionid = decode_utf8($result->{'sessionid'});
        my $tstamp          = decode_utf8($result->{'tstamp'});
        
        push @sessions, {
            sessionid  => $singlesessionid,
            createtime => $tstamp,
        };
    }
    
    
    my $ttdata={
        sessions   => \@sessions,
        
        clientip   => $clientip,
        fromdate   => $fromdate,
        todate     => $todate,
    };
    
    $self->print_page($config->{tt_admin_session_archived_search},$ttdata);

    return Apache2::Const::OK;
}

sub show_archived_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $sessionid      = $self->param('sessionid');

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

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $statisticsdbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
            or $logger->error($DBI::errstr);
    
    my $serialized_type_ref = {
        1  => 1,
        10 => 1,
    };
    
    
    my $idnresult=$statisticsdbh->prepare("select * from eventlog where sessionid = ? order by tstamp ASC") or $logger->error($DBI::errstr);
    $idnresult->execute($sessionid) or $logger->error($DBI::errstr);
    
    my @events = ();
    
    while (my $result=$idnresult->fetchrow_hashref()) {
        my $type        = decode_utf8($result->{'type'});
        my $tstamp      = decode_utf8($result->{'tstamp'});
        my $content     = decode_utf8($result->{'content'});

        if (exists $serialized_type_ref->{$type}){
            $content=Storable::thaw(pack "H*", $content);
        }
        
        push @events, {
            type       => $type,
            content    => $content,
            createtime => $tstamp,
        };
    }

    my $ttdata = {
        singlesessionid => $sessionid,
        events          => \@events,
    };

    $self->print_page($config->{tt_admin_session_archived_record},$ttdata);
    
    return Apache2::Const::OK;
}

1;
