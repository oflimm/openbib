#####################################################################
#
#  OpenBib::Mojo::Controller::Admin::Databases
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

package OpenBib::Mojo::Controller::Admin::Databases;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

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
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::Statistics;
use OpenBib::User;
use OpenBib::Search::Factory;

use base 'OpenBib::Mojo::Controller::Admin';

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Shared Args
    my $config         = $self->stash('config');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }

    my $dbinfo_ref = $config->get_dbinfo_overview();
    
    my $ttdata={                # 
        catalogs   => $dbinfo_ref,
    };
    
    return $self->print_page($config->{tt_admin_databases_tname},$ttdata);
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');
    my $user           = $self->stash('user');
    my $lang           = $self->stash('lang');
    my $path_prefix    = $self->stash('path_prefix');
    my $location       = $self->stash('location');

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    if (!$self->authorization_successful('right_create')){
        return $self->print_authorization_error();
    }

    # newdbname ggf. loeschen
    delete $input_data_ref->{newdbname} if (defined $input_data_ref->{newdbname});
    
    if ($input_data_ref->{dbname} eq "" || $input_data_ref->{description} eq "") {
        return $self->print_warning($msg->maketext("Sie müssen mindestens einen Katalognamen und eine Beschreibung eingeben."),2);
    }
    
    if ($config->db_exists($input_data_ref->{dbname})) {
        return $self->print_warning($msg->maketext("Es existiert bereits ein Katalog unter diesem Namen"),3);
    }

    if ($input_data_ref->{locationid} eq ""){
        delete $input_data_ref->{locationid};
    }
    
    my $new_databaseid = $config->new_databaseinfo($input_data_ref);

    if ($self->stash('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{admin_loc}/$config->{databases_loc}/id/$input_data_ref->{dbname}/edit.html?l=$lang");
    }
    else {
        $logger->debug("Weiter zum Record");
        if ($new_databaseid){ # Datensatz erzeugt, wenn neue id
            $logger->debug("Weiter zur DB $input_data_ref->{dbname}");
            $self->stash('status',201); # created
            $self->stash('databaseid',$input_data_ref->{dbname});
            $self->stash('location',"$location/$input_data_ref->{dbname}");
            return $self->show_record;
        }
    }

    return;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $dbname         = $self->strip_suffix($self->param('databaseid'));

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');

    if (!$self->authorization_successful('right_read')){
        return $self->print_authorization_error();
    }
    
    $logger->debug("Show Record $dbname");

    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;

    if (!$dbinfo_ref){
        $logger->error("Database $dbname couldn't be found.");
    }

    my $searcher   = OpenBib::Search::Factory->create_searcher({database => $dbname, config => $config });

    my $indexed_doc_count = $searcher->get_number_of_documents; 
    
    my $ttdata={
        databaseinfo      => $dbinfo_ref,
        indexed_doc_count => $indexed_doc_count,
    };
    
    return $self->print_page($config->{tt_admin_databases_record_tname},$ttdata);
}


sub show_record_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $dbname         = $self->param('databaseid')     || '';

    # Shared Args
    my $r              = $self->stash('r');
    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');
    
    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }
    
    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;

    my $searcher   = OpenBib::Search::Factory->create_searcher({database => $dbname, config => $config });

    my $indexed_doc_count = $searcher->get_number_of_documents; 

    my $searchengine_map_ref = {};
    
    foreach my $this_searchengine ($dbinfo_ref->databaseinfo_searchengines){
        $logger->debug("Adding $dbname");
        $searchengine_map_ref->{$this_searchengine->searchengine} = 1;
    }    
    
    my $ttdata={
	searchengine_map => $searchengine_map_ref,
        databaseinfo => $dbinfo_ref,
        indexed_doc_count => $indexed_doc_count,
    };
    
    return $self->print_page($config->{tt_admin_databases_record_edit_tname},$ttdata);
}

sub update_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    
    my $view           = $self->stash('view')           || '';
    my $dbname         = $self->stash('databaseid')             || '';
    my $path_prefix    = $self->stash('path_prefix');
    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');

    if (!$self->authorization_successful('right_update')){
        return $self->print_authorization_error();
    }

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();
    $input_data_ref->{dbname} = $dbname; # dbname wird durch Resourcenbestandteil ueberschrieben

    if ($logger->is_debug()){
	$logger->debug("Processing databaseinfo with: ".YAML::Dump($input_data_ref));
    }

    
    if ($logger->is_debug){
        $logger->debug("Info: ".YAML::Dump($input_data_ref));
    }
    
    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }
    
    if ($input_data_ref->{locationid} eq ""){
        $input_data_ref->{locationid} = \'NULL';
    }
    else {
        my $location = $config->get_locationinfo->single({identifier => $input_data_ref->{locationid} });
	
        if ($location){
            $input_data_ref->{locationid} = $location->id;
        }
        else {
            $input_data_ref->{locationid} = \'NULL';
        }
    }
    
    if ($input_data_ref->{parentdbid}){
        my $parentdb = $config->get_databaseinfo->single({dbname => $input_data_ref->{parentdbid} });
	
        if ($parentdb){
            $input_data_ref->{parentdbid} = $parentdb->id;
        }
        else {
            $input_data_ref->{parentdbid} = \'NULL';
        }
    }
    else {
        $input_data_ref->{parentdbid} = \'NULL';
    }

    if ($input_data_ref->{newdbname}){
	$input_data_ref->{dbname} = $input_data_ref->{newdbname};
	delete $input_data_ref->{newdbname};
	$config->new_databaseinfo($input_data_ref);
    }
    else {
       delete $input_data_ref->{newdbname};
       $config->update_databaseinfo($input_data_ref);
    }

	
    if ($self->stash('representation') eq "html"){
        # TODO GET?
        return $self->redirect("$path_prefix/$config->{databases_loc}");
    }
    else {
        $logger->debug("Weiter zum Record");
        $logger->debug("Weiter zur DB $dbname");
        return $self->show_record;
    }
}

sub confirm_delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $dbname         = $self->strip_suffix($self->stash('databaseid'));
    my $config         = $self->stash('config');

    my $dbinfo_ref = $config->get_databaseinfo->search({ dbname => $dbname})->single;
    
    my $ttdata={
        databaseinfo => $dbinfo_ref,
    };
    
    $logger->debug("Asking for confirmation");

    return $self->print_page($config->{tt_admin_databases_record_delete_confirm_tname},$ttdata);
}

sub delete_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    my $r              = $self->stash('r');

    my $view           = $self->stash('view');
    my $dbname         = $self->stash('databaseid');
    my $path_prefix    = $self->stash('path_prefix');
    my $config         = $self->stash('config');
    my $msg            = $self->stash('msg');

    if (!$self->authorization_successful('right_delete')){
        return $self->print_authorization_error();
    }
    
    if (!$config->db_exists($dbname)) {        
        return $self->print_warning($msg->maketext("Es existiert kein Katalog unter diesem Namen"));
    }

    $logger->debug("Deleting database record $dbname");
    
    $config->del_databaseinfo($dbname);

    return unless ($self->stash('representation') eq "html");
    
    # TODO GET?
    return $self->redirect("$path_prefix/$config->{databases_loc}");
}

sub get_input_definition {
    my $self=shift;
    
    return {
        description => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        shortdesc => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        system => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        schema => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        dbname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        sigel => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        url => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        searchengines => {
            default  => [],
            encoding => 'none',
            type     => 'array',
        },
        locationid => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        active => {
            default  => 'false',
            encoding => 'none',
            type     => 'scalar',
        },
        host => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        protocol => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        remotepath => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        remoteuser => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        remotepassword => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        titlefile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        personfile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        corporatebodyfile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        subjectfile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        classificationfile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        holdingfile => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        autoconvert => {
            default  => 'false',
            encoding => 'none',
            type     => 'bool',
        },
        circ => {
            default  => 'false',
            encoding => 'none',
            type     => 'bool',
        },
        circtype => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        circurl => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        circwsurl => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        circdb => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        newdbname => {
            default  => '',
            encoding => 'none',
            type     => 'scalar',
        },
        parentdbid => {
            default  => undef,
            encoding => 'none',
            type     => 'scalar',
        },
    };
}

1;
