#####################################################################
#
#  OpenBib::Handler::Apache::Admin::Topics
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

package OpenBib::Handler::Apache::Admin::Topics;

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
use OpenBib::EZB;
use OpenBib::DBIS;
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
        'show_collection'           => 'show_collection',
        'show_collection_form'      => 'show_collection_form',
        'show_record_form'          => 'show_record_form',
        'show_record'               => 'show_record',
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
    my $user           = $self->param('user');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $topics_ref = $user->get_topics;
    
    my $ttdata={
        topics   => $topics_ref,
    };
    
    $self->print_page($config->{tt_admin_topic_tname},$ttdata);

    return;
}

sub show_collection_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view');

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $topics_ref = $user->get_topics;
    
    my $ttdata={
        topics   => $topics_ref,
    };
    
    $self->print_page($config->{tt_admin_topic_edit_tname},$ttdata);

    return;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view');
    my $topicid        = $self->strip_suffix($self->param('topicid'));

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $topic_ref = $user->get_topic({ id => $topicid});
    my $ezb         = OpenBib::EZB->new;
    my $dbis        = OpenBib::DBIS->new;
    
    my $ttdata={
        topic    => $topic_ref,
        ezb        => $ezb,
        dbis       => $dbis,
    };
    
    $self->print_page($config->{tt_admin_topic_record_tname},$ttdata);

    return;
}


sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view');
    my $topicid        = $self->param('topicid');

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    my $topic_ref = $user->get_topic({ id => $topicid});
    my $ezb         = OpenBib::EZB->new;
    my $dbis        = OpenBib::DBIS->new;
    
    my $ttdata={
        topic    => $topic_ref,
        ezb        => $ezb,
        dbis       => $dbis,
    };
    
    $self->print_page($config->{tt_admin_topic_record_edit_tname},$ttdata);

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
    my $location       = $self->param('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    if ($input_data_ref->{name} eq "") {
        $self->print_warning($msg->maketext("Sie müssen mindestens einen Namen f&uuml;r das Themenbebiet eingeben."));
        return Apache2::Const::OK;
    }

    if ($user->topic_exists($input_data_ref->{name})){
        $self->print_warning($msg->maketext("Ein Themenbebiet diesen Namens existiert bereits."));
        return Apache2::Const::OK;
    }
    
    my $new_topicid = $user->new_topic($input_data_ref);
    
    if (!$new_topicid ){
        $self->print_warning($msg->maketext("Es existiert bereits ein Themengebiet unter diesem Namen"));
        return Apache2::Const::OK;
    }
    
    if ($self->param('representation') eq "html"){
        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_topics_loc}");
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_topicid){
            $logger->debug("Weiter zum Record $new_topicid");
            $self->param('status',Apache2::Const::HTTP_CREATED);
            $self->param('topicid',$new_topicid);
            $self->param('location',"$location/$new_topicid");
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
    my $topicid      = $self->param('topicid');

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $path_prefix    = $self->param('path_prefix');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CGI Args
    my $method          = decode_utf8($query->param('_method')) || '';
    my $confirm         = $query->param('confirm') || 0;

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    # Method workaround fuer die Unfaehigkeit von Browsern PUT/DELETE in Forms
    # zu verwenden

    if ($method eq "DELETE"){
        $logger->debug("About to delete $topicid");
        
        if ($confirm){
            my $ttdata={
                topicid  => $topicid,
            };

            $logger->debug("Asking for confirmation");
            $self->print_page($config->{tt_admin_topic_record_delete_confirm_tname},$ttdata);

            return Apache2::Const::OK;
        }
        else {
            $logger->debug("Redirecting to delete location");
            $self->delete_record;
            return;
        }
    }

    # Ansonsten POST oder PUT => Aktualisieren

    $user->update_topic({
        name                 => $input_data_ref->{name},
        description          => $input_data_ref->{description},
        id                   => $topicid,
    });

    if ($self->param('representation') eq "html"){
        $self->query->method('GET');
        $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_topics_loc}");
        $self->query->status(Apache2::Const::REDIRECT);
    }
    else {
        $logger->debug("Weiter zum Record");
        $logger->debug("Weiter zum Record $topicid");
        $self->show_record;
    }
    

    return;
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $topicid      = $self->param('topicid');

    # Shared Args
    my $config         = $self->param('config');
    my $user           = $self->param('user');
    my $path_prefix    = $self->param('path_prefix');

    if (!$self->authorization_successful){
        $self->print_authorization_error();
        return;
    }

    $user->del_topic({ id => $topicid });

    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{admin_topics_loc}");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
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
