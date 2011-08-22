#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Subject
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

package OpenBib::Handler::Apache::Admin::Subject;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Log;
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Apache2::SubRequest ();
use Date::Manip qw/ParseDate UnixDate/;
use DBI;
use Digest::MD5;
use Encode qw/decode_utf8 encode_utf8/;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
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

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'           => 'show_collection',
        'show_record_form'          => 'show_record_form',
        'create_record'             => 'create_record',
        'update_record'             => 'update_record',
        'delete_record'             => 'delete_record',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $subjects_ref = OpenBib::User->get_subjects;
    
    my $ttdata={
        subjects   => $subjects_ref,
    };
    
    $self->print_page($config->{tt_admin_subject_tname},$ttdata);

    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view');
    my $subjectid        = $self->param('subjectid');

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $subject_ref = OpenBib::User->get_subject({ id => $subjectid});
    
    my $ttdata={
        subject    => $subject_ref,
    };
    
    $self->print_page($config->{tt_admin_subject_record_edit_tname},$ttdata);

    return;
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $description     = decode_utf8($query->param('description'))     || '';
    my $subject         = $query->param('subject')                      || '';

    if (!$self->is_authenticated('admin')){
        return;
    }

    if ($subject eq "") {
        $self->print_warning($msg->maketext("Sie müssen mindestens einen Namen f&uuml;r das Themenbebiet eingeben."));
        return Apache2::Const::OK;
    }
    
    my $ret = $user->new_subject({
        name        => $subject,
        description => $description,
    });
    
    if ($ret == -1){
        $self->print_warning($msg->maketext("Es existiert bereits ein Themengebiet unter diesem Namen"));
        return Apache2::Const::OK;
    }
    
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_subject_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $subjectid      = $self->param('subjectid');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $method          = decode_utf8($query->param('_method')) || '';
    my $confirm         = $query->param('confirm') || 0;
    my $subject         = decode_utf8($query->param('subject'))         || '';
    my $description     = decode_utf8($query->param('description'))     || '';
    my @classifications = ($query->param('classifications'))?$query->param('classifications'):();
    my $type            = $query->param('type')            || '';
    
    if (!$self->is_authenticated('admin')){
        return;
    }

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden

    if ($method eq "DELETE"){
        $logger->debug("About to delete $subjectid");
        
        if ($confirm){
            my $ttdata={
                subjectid  => $subjectid,
            };

            $logger->debug("Asking for confirmation");
            $self->print_page($config->{tt_admin_subject_record_delete_confirm_tname},$ttdata);

            return Apache2::Const::OK;
        }
        else {
            $logger->debug("Redirecting to delete location");
            $self->delete_record;
            return;
        }
    }

    # Ansonsten POST oder PUT => Aktualisieren

    $user->update_subject({
        name                 => $subject,
        description          => $description,
        id                   => $subjectid,
        classifications      => \@classifications,
        type                 => $type,
    });

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_subject_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $subjectid      = $self->param('subjectid');

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->is_authenticated('admin')){
        return;
    }

    $user->del_subject({ id => $subjectid });

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_subject_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

1;
