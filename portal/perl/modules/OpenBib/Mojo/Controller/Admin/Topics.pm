#####################################################################
#
#  OpenBib::Mojo::Controller::Admin::Topics
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

package OpenBib::Mojo::Controller::Admin::Topics;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

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
use OpenBib::Catalog::Factory;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;

use base 'OpenBib::Mojo::Controller::Admin';

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $topics_ref = $user->get_topics;
    
    my $ttdata={
        topics   => $topics_ref,
    };
    
    return $self->print_page($config->{tt_admin_topics_tname},$ttdata);
}

sub show_collection_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    my $topics_ref = $user->get_topics;
    
    my $ttdata={
        topics   => $topics_ref,
    };
    
    return $self->print_page($config->{tt_admin_topics_edit_tname},$ttdata);
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $topicid        = $self->strip_suffix($self->param('topicid'));

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $topic_ref   = $user->get_topic({ id => $topicid});
    my $ezb         = OpenBib::Catalog::Factory->create_catalog({database => 'ezb' });;
    my $dbis        = OpenBib::Catalog::Factory->create_catalog({database => 'dbis' });
    
    my $ttdata={
        topic      => $topic_ref,
        ezb        => $ezb,
        dbis       => $dbis,
    };
    
    return $self->print_page($config->{tt_admin_topics_record_tname},$ttdata);
}


sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $topicid        = $self->param('topicid');

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    my $topic_ref   = $user->get_topic({ id => $topicid});
    my $ezb         = OpenBib::Catalog::Factory->create_catalog({database => 'ezb' });;
    my $dbis        = OpenBib::Catalog::Factory->create_catalog({database => 'dbis' });
    
    my $ttdata={
        topic      => $topic_ref,
        ezb        => $ezb,
        dbis       => $dbis,
    };
    
    return $self->print_page($config->{tt_admin_topics_record_edit_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');
    my $msg            = $self->stash('msg');
    my $path_prefix    = $self->stash('path_prefix');
    my $location       = $self->stash('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful('right_create')){
        return $self->print_authorization_error();
    }

    if ($input_data_ref->{name} eq "") {
        return $self->print_warning($msg->maketext("Sie müssen mindestens einen Namen f&uuml;r das Themenbebiet eingeben."));
    }

    if ($user->topic_exists($input_data_ref->{name})){
        return $self->print_warning($msg->maketext("Ein Themenbebiet diesen Namens existiert bereits."));
    }
    
    my $new_topicid = $user->new_topic($input_data_ref);
    
    if (!$new_topicid ){
        return $self->print_warning($msg->maketext("Es existiert bereits ein Themengebiet unter diesem Namen"));
    }
    
    if ($self->stash('representation') eq "html"){
        # TODO GET?
        $self->redirect("$path_prefix/$config->{admin_loc}/$config->{topics_loc}");
        return;
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_topicid){
            $logger->debug("Weiter zum Record $new_topicid");
            $self->stash('status',201); # created
            $self->stash('topicid',$new_topicid);
            $self->stash('location',"$location/$new_topicid");
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
    my $topicid        = $self->param('topicid');

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');
    my $lang           = $self->stash('lang');
    my $path_prefix    = $self->stash('path_prefix');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    # Ansonsten POST oder PUT => Aktualisieren

    $user->update_topic({
        name                 => $input_data_ref->{name},
        description          => $input_data_ref->{description},
        id                   => $topicid,
    });

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{topics_loc}.html?l=$lang");
    }
    else {
        $logger->debug("Weiter zum Record");
        $logger->debug("Weiter zum Record $topicid");
        return $self->show_record;
    }
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $topicid        = $self->strip_suffix($self->stash('topicid'));
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');

    my $topic_ref = $user->get_topic({ id => $topicid});
    
    my $ttdata={
        topicid => $topicid,
        topic   => $topic_ref,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_topics_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $topicid        = $self->param('topicid');

    # Shared Args
    my $config         = $self->stash('config');
    my $user           = $self->stash('user');
    my $lang           = $self->stash('lang');
    my $path_prefix    = $self->stash('path_prefix');

    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }

    $user->del_topic({ id => $topicid });

    return unless ($self->stash('representation') eq "html");

    # TODO GET?
    return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{topics_loc}.html?l=$lang");
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
