#####################################################################
#
#  OpenBib::Handler::PSGI::Classifications.pm
#
#  Copyright 2009-2020 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Classifications;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);
use Encode qw/decode_utf8 encode_utf8/;

use OpenBib::Record::Classification;
use OpenBib::Catalog::Factory;
use OpenBib::Common::Util;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_record');
    $self->run_modes(
        'show_record'     => 'show_record',
        'show_collection' => 'show_collection',
#	'show_warning'    => 'show_warning',
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
    my $database         = $self->param('database');
    my $classificationid = $self->strip_suffix($self->decode_id($self->param('classificationid')));

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
    my $stid          = $query->param('stid')     || '';
    my $callback      = $query->param('callback') || '';
    my $lang          = $query->param('lang')     || $queryoptions->get_option('l') || 'de';
    my $format        = $query->param('format')   || 'full';
    my $no_log        = $query->param('no_log')  || '';

    if ($database && $classificationid ){ # Valide Informationen etc.
        $logger->debug("ID: $classificationid - DB: $database");
        
        my $record = OpenBib::Record::Classification->new({database => $database, id => $classificationid})->load_full_record;
        
        my $authenticatordb = $user->get_targetdb_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            database      => $database, # Zwingend wegen common/subtemplate
            qopts         => $queryoptions->get_options,
            record        => $record,
            id            => $classificationid,
            format        => $format,
            activefeed    => $config->get_activefeeds_of_db($database),
            authenticatordb => $authenticatordb,
        };

        # Log Event
        
        if (!$no_log){
            $session->log_event({
                type      => 13,
                content   => {
                    id       => $classificationid,
                    database => $database,
                },
                serialize => 1,
            });
        }
        
        return $self->print_page($config->{'tt_classifications_record_tname'},$ttdata);

    }
    else {
        return $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname/Id spezifiziert."));
    }
}

sub show_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view');
    my $database         = $self->strip_suffix($self->param('database'));

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
    my $callback      = $query->param('callback') || '';
    my $lang          = $query->param('lang')     || $queryoptions->get_option('l') || 'de';
    my $no_log        = $query->param('no_log')   || '';


    if ($database){ # Valide Informationen etc.
        
        my $catalog_args_ref = OpenBib::Common::Util::query2hashref($query);
        $catalog_args_ref->{database} = $database if (defined $database);
        $catalog_args_ref->{l}        = $lang if (defined $lang);

        my $catalog = OpenBib::Catalog::Factory->create_catalog($catalog_args_ref);

        my $classifications_ref = $catalog->get_classifications;

	# my $thisref = ref $classifications_ref;

        # if ($logger->is_debug){
	#     $logger->debug("Ref: $thisref");       	    
        #     $logger->debug(YAML::Dump($classifications_ref));
        # }

	# my $temp_ref = {};

	# if ($thisref ne "HASH"){
	#     $temp_ref->{item} = $classifications_ref;
	#     $temp_ref->{hits} = scalar @$classifications_ref;

	#     $classifications_ref = $temp_ref;
	# }

	my $is_error = (defined $classifications_ref->{error} && $classifications_ref->{error})?1:0;
	
        # TT-Data erzeugen
        my $ttdata={
            database             => $database,
            classifications      => $classifications_ref->{items},
	    hits                 => $classifications_ref->{hits},
	    classification_error => $is_error,
        };
        
        return $self->print_page($config->{'tt_classifications_tname'},$ttdata);
    }
    else {
        return $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname spezifiziert."));
    }
}

1;
