#####################################################################
#
#  OpenBib::Handler::Apache::Topics::Mappings
#
#  Dieses File ist (C) 2004-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Admin::Topics::Mappings;

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
use OpenBib::Catalog::Factory;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Handler::Apache::Admin';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_record_form'          => 'show_record_form',
        'show_record'               => 'show_record',
        'create_record'             => 'create_record',
        'update_record'             => 'update_record',
        'delete_record'             => 'delete_record',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view');
    my $subjectid        = $self->param('subjectid');
    my $mappingid        = $self->strip_suffix($self->param('mappingid'));

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $subject_ref = $user->get_subject({ id => $subjectid});

    my $mapping = $self->get_mapping_by_id($mappingid);

    unless (defined $mapping) {
        $self->print_warning($msg->maketext("Das Mapping ist nicht definiert."));
        return;
    }
    
    my $ttdata={
        subject    => $subject_ref,
        mapping    => $mapping,
    };
    
    $self->print_page($config->{tt_admin_subject_mapping_record_tname},$ttdata);

    return;
}

sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view');
    my $subjectid        = $self->param('subjectid');
    my $mappingid        = $self->param('mappingid');

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $subject_ref = $user->get_subject({ id => $subjectid});

    my $mapping = $self->get_mapping_by_id($mappingid);

    unless (defined $mapping) {
        $self->print_warning($msg->maketext("Das Mapping ist nicht definiert."));
        return;
    }

    my $ttdata={
        subject    => $subject_ref,
        mapping    => $mapping,
    };
    
    $self->print_page($config->{tt_admin_subject_mapping_record_edit_tname},$ttdata);

    return;
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $subjectid        = $self->param('subjectid');
    my $mappingid        = $self->strip_suffix($self->param('mappingid'));

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $path_prefix    = $self->param('path_prefix');
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    if ($input_data_ref->{subject} eq "") {
        $self->print_warning($msg->maketext("Sie müssen mindestens einen Namen f&uuml;r das Themenbebiet eingeben."));
        return Apache2::Const::OK;
    }
    
    my $new_subjectid = $user->new_subject($input_data_ref);
    
    if (!$new_subjectid ){
        $self->print_warning($msg->maketext("Es existiert bereits ein Themengebiet unter diesem Namen"));
        return Apache2::Const::OK;
    }
    
    if ($self->param('representation') eq "html"){
        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_subjects_loc}");
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_subjectid){
            $logger->debug("Weiter zum Record $new_subjectid");
            $self->param('status',Apache2::Const::HTTP_CREATED);
            $self->param('subjectid',$new_subjectid);
            $self->param('location',"$location/$new_subjectid");
            $self->show_record;
        }
    }

    return;
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $subjectid      = $self->param('subjectid');
    my $mappingid      = $self->strip_suffix($self->param('mappingid'));

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
    
    if (!$self->authorization_successful){
        $self->print_authorization_error();
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
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_subjects_loc}");
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
    my $mappingid      = $self->strip_suffix($self->param('mappingid'));

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $user->del_subject({ id => $subjectid });

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_subjects_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub get_mapping_by_id {
    my $self=shift;
    my $mappingid = shift;

    my $mapping = OpenBib::Catalog::Factory->create_catalog({database => $mapping });
    
    return $mapping;
}

sub get_input_definition {
    my $self=shift;
    
    return {
        description => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        name => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
    };
}
    
1;
