#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Library
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

package OpenBib::Handler::Apache::Admin::Library;

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

    $self->start_mode('show_record_negotiate');
    $self->run_modes(
        'negotiate_url'             => 'negotiate_url',
        'show_record_as_html'       => 'show_record_as_html',
        'show_record_as_json'       => 'show_record_as_json',
        'show_record_as_rdf'        => 'show_record_as_rdf',
        'show_record_form'          => 'show_record_form',
        'create_record'             => 'create_record',
        'update_record'             => 'update_record',
        'delete_record'             => 'delete_record',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->param('r');

    # Dispatched Args
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');

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

    $logger->debug("Server: ".$r->get_server_name."Representation: $representation");

    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }
    
    my $libinfo_ref = $config->get_libinfo($dbname);
    
    my $ttdata={
        dbname     => $dbname,
        libinfo    => $libinfo_ref,
    };
    
    $self->print_page($config->{tt_admin_library_record_tname},$ttdata);

    return Apache2::Const::OK;
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')                   || '';

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
    my $description     = decode_utf8($query->param('description'))     || '';
    my $shortdesc       = $query->param('shortdesc')       || '';
    my $system          = $query->param('system')          || '';
    my $dbname          = $query->param('dbname')          || '';
    my $sigel           = $query->param('sigel')           || '';
    my $url             = $query->param('url')             || '';
    my $use_libinfo     = $query->param('use_libinfo')     || 0;
    my $active          = $query->param('active')          || 0;

    my $host            = $query->param('host')            || '';
    my $protocol        = $query->param('protocol')        || '';
    my $remotepath      = $query->param('remotepath')      || '';
    my $remoteuser      = $query->param('remoteuser')      || '';
    my $remotepasswd    = $query->param('remotepasswd')    || '';
    my $titfilename     = $query->param('titfilename')     || '';
    my $autfilename     = $query->param('autfilename')     || '';
    my $korfilename     = $query->param('korfilename')     || '';
    my $swtfilename     = $query->param('swtfilename')     || '';
    my $notfilename     = $query->param('notfilename')     || '';
    my $mexfilename     = $query->param('mexfilename')     || '';
    my $autoconvert     = $query->param('autoconvert')     || '';
    my $circ            = $query->param('circ')            || '';
    my $circurl         = $query->param('circurl')         || '';
    my $circcheckurl    = $query->param('circcheckurl')    || '';
    my $circdb          = $query->param('circdb')          || '';

    if (!$self->is_authenticated('admin')){
        return;
    }

    $logger->debug("Server: ".$r->get_server_name);

    my $thisdbinfo_ref = {
        description        => $description,
        shortdesc          => $shortdesc,
        system             => $system,
        dbname             => $dbname,
        sigel              => $sigel,
        url                => $url,
        use_libinfo        => $use_libinfo,
        active             => $active,
        host               => $host,
        protocol           => $protocol,
        remotepath         => $remotepath,
        remoteuser         => $remoteuser,
        remotepassword     => $remotepasswd,
        titlefile          => $titfilename,
        personfile         => $autfilename,
        corporatebodyfile  => $korfilename,
        subjectfile        => $swtfilename,
        classificationfile => $notfilename,
        holdingsfile       => $mexfilename,
        autoconvert        => $autoconvert,
        circ               => $circ,
        circurl            => $circurl,
        circwsurl          => $circcheckurl,
        circdb             => $circdb,
    };
    
    if ($dbname eq "" || $description eq "") {
        
        $self->print_warning($msg->maketext("Sie müssen mindestens einen Katalognamen und eine Beschreibung eingeben."));
        
        return Apache2::Const::OK;
    }
    
    if ($config->db_exists($dbname)) {
        
        $self->print_warning($msg->maketext("Es existiert bereits ein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }
    
    $config->new_databaseinfo($thisdbinfo_ref);

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}/$dbname/edit");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');

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

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }

    my $libinfo_ref = $config->get_libinfo($dbname);
    
    my $ttdata={
        dbname     => $dbname,
        libinfo    => $libinfo_ref,
    };
    
    $self->print_page($config->{tt_admin_library_record_edit_tname},$ttdata);

    return Apache2::Const::OK;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')                   || '';
    my $dbname         = $self->param('databaseid')             || '';

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
    my $method          = decode_utf8($query->param('_method')) || '';
    my $confirm         = $query->param('confirm') || 0;
    # Kategorien der Bibliotheksinfos
    my $li_0010         = $query->param('I0010')          || '';
    my $li_0020         = $query->param('I0020')          || '';
    my $li_0030         = $query->param('I0030')          || '';
    my $li_0040         = $query->param('I0040')          || '';
    my $li_0050         = $query->param('I0050')          || '';
    my $li_0060         = $query->param('I0060')          || '';
    my $li_0070         = $query->param('I0070')          || '';
    my $li_0080         = $query->param('I0080')          || '';
    my $li_0090         = $query->param('I0090')          || '';
    my $li_0100         = $query->param('I0100')          || '';
    my $li_0110         = $query->param('I0110')          || '';
    my $li_0120         = $query->param('I0120')          || '';
    my $li_0130         = $query->param('I0130')          || '';
    my $li_0140         = $query->param('I0140')          || '';
    my $li_0150         = $query->param('I0150')          || '';
    my $li_0160         = $query->param('I0160')          || '';
    my $li_0170         = $query->param('I0170')          || '';
    my $li_0180         = $query->param('I0180')          || '';
    my $li_0190         = $query->param('I0190')          || '';
    my $li_0200         = $query->param('I0200')          || '';
    my $li_0210         = $query->param('I0210')          || '';
    my $li_0220         = $query->param('I0220')          || '';
    my $li_0230         = $query->param('I0230')          || '';
    my $li_0240         = $query->param('I0240')          || '';
    my $li_0250         = $query->param('I0250')          || '';
    my $li_0260         = $query->param('I0260')          || '';
    my $li_1000         = $query->param('I1000')          || '';

    if (!$self->is_authenticated('admin')){
        return;
    }

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden

    if ($method eq "DELETE"){
        $logger->debug("About to delete $dbname");
        
        if ($confirm){
            my $libinfo_ref = $config->get_libinfo($dbname);
            
            my $ttdata={
                libinfo      => $libinfo_ref,
                dbname     => $dbname,
            };

            $logger->debug("Asking for confirmation");
            $self->print_page($config->{tt_admin_library_record_delete_confirm_tname},$ttdata);

            return Apache2::Const::OK;
        }
        else {
            $logger->debug("Redirecting to delete location");
            $self->query->method('DELETE');    
            $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}/$dbname/library");
            $self->query->status(Apache2::Const::REDIRECT);
            return;
        }
    }

    # Ansonsten POST oder PUT => Aktualisieren

    my $thislibinfo_ref = {
        I0010      => $li_0010,
        I0020      => $li_0020,
        I0030      => $li_0030,
        I0040      => $li_0040,
        I0050      => $li_0050,
        I0060      => $li_0060,
        I0070      => $li_0070,
        I0080      => $li_0080,
        I0090      => $li_0090,
        I0100      => $li_0100,
        I0110      => $li_0110,
        I0120      => $li_0120,
        I0130      => $li_0130,
        I0140      => $li_0140,
        I0150      => $li_0150,
        I0160      => $li_0160,
        I0170      => $li_0170,
        I0180      => $li_0180,
        I0190      => $li_0190,
        I0200      => $li_0200,
        I0210      => $li_0210,
        I0220      => $li_0220,
        I0230      => $li_0230,
        I0240      => $li_0240,
        I0250      => $li_0250,
        I0260      => $li_0260,
        I1000      => $li_1000,
    };

    
    $logger->debug("Info: ".YAML::Dump($thislibinfo_ref));
    
    $config->update_libinfo($dbname,$thislibinfo_ref);
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Ards
    my $view           = $self->param('view');
    my $dbname         = $self->param('databaseid');

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

    $logger->debug("Server: ".$r->get_server_name);

    if (!$config->db_exists($dbname)) {        
        $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
        
        return Apache2::Const::OK;
    }
    
    $config->del_libinfo($dbname);
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_database_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
