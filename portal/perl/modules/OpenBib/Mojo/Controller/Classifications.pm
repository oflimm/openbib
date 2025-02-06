#####################################################################
#
#  OpenBib::Mojo::Controller::Classifications.pm
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

package OpenBib::Mojo::Controller::Classifications;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);
use Encode qw/decode_utf8 encode_utf8/;

use OpenBib::Record::Classification;
use OpenBib::Catalog::Factory;
use OpenBib::Common::Util;

use Mojo::Base 'OpenBib::Mojo::Controller', -signatures;

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view             = $self->param('view');
    my $database         = $self->param('database');
    my $classificationid = $self->strip_suffix($self->decode_id($self->param('classificationid')));

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
    my $stid          = $r->param('stid')     || '';
    my $callback      = $r->param('callback') || '';
    my $lang          = $r->param('lang')     || $queryoptions->get_option('l') || 'de';
    my $format        = $r->param('format')   || 'full';
    my $no_log        = $r->param('no_log')  || '';

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
    my $callback      = $r->param('callback') || '';
    my $lang          = $r->param('lang')     || $queryoptions->get_option('l') || 'de';
    my $no_log        = $r->param('no_log')   || '';


    if ($database){ # Valide Informationen etc.
        
        my $catalog_args_ref = OpenBib::Common::Util::query2hashref($query);
        $catalog_args_ref->{database} = $database if (defined $database);
        $catalog_args_ref->{l}        = $lang if (defined $lang);

        my $catalog = OpenBib::Catalog::Factory->create_catalog($catalog_args_ref);

        my $classifications_ref = $catalog->get_classifications;
        
        if ($logger->is_debug){
            $logger->debug(YAML::Dump($classifications_ref));
        }
        
        # TT-Data erzeugen
        my $ttdata={
            database        => $database,
            classifications => $classifications_ref,
        };
        
        return $self->print_page($config->{'tt_classifications_tname'},$ttdata);
    }
    else {
        return $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname spezifiziert."));
    }
}

sub show_collection_ezb {
    my $self = shift;

        # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->strip_suffix($self->param('database'));

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
    my $type           = decode_utf8($r->param('type'))     || 'cloud';
    my $access_green   = decode_utf8($r->param('access_green'))     || 0;
    my $access_yellow  = decode_utf8($r->param('access_yellow'))    || 0;
    my $access_red     = decode_utf8($r->param('access_red'))       || 0;
    my $id             = decode_utf8($r->param('id'))       || undef;
    my $sc             = decode_utf8($r->param('sc'))       || '';
    my $lc             = decode_utf8($r->param('lc'))       || '';
    my $sindex         = decode_utf8($r->param('sindex'))   || 0;
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    my $colors = $access_green + $access_yellow*2 + $access_red*4;

    if (!$colors){
        $colors=$config->{ezb_colors};

        my $colors_mask  = dec2bin($colors);

        $logger->debug("Access: mask($colors_mask)");
        
        $access_green  = ($colors_mask & 0b001)?1:0;
        $access_yellow = ($colors_mask & 0b010)?1:0;
        $access_red    = ($colors_mask & 0b100)?1:0;
    }

    $logger->debug("Access: colors($colors) green($access_green) yellow($access_yellow) red($access_red)");
    
    my $ezb = new OpenBib::Search::Backend::EZB({colors => $colors, lang => $queryoptions->get_option('l') });
    
    my $subjects_ref = $ezb->get_subjects();
    
    if ($logger->is_debug){
        $logger->debug(YAML::Dump($subjects_ref));
    }
    
    # TT-Data erzeugen
    my $ttdata={
        database      => $database,
        type          => $type,
        access_green  => $access_green,
        access_yellow => $access_yellow,
        access_red    => $access_red,
        subjects      => $subjects_ref,
    };
    
    return $self->print_page($config->{'tt_classifications_tname'},$ttdata);
}

sub show_collectionxxx {
    my $self = shift;

        # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->strip_suffix($self->param('database'));

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
    my $type           = decode_utf8($r->param('type'))     || 'cloud';
    my $access_green   = decode_utf8($r->param('access_green'))     || 0;
    my $access_yellow  = decode_utf8($r->param('access_yellow'))    || 0;
    my $access_red     = decode_utf8($r->param('access_red'))       || 0;
    my $id             = decode_utf8($r->param('id'))       || undef;
    my $sc             = decode_utf8($r->param('sc'))       || '';
    my $lc             = decode_utf8($r->param('lc'))       || '';
    my $sindex         = decode_utf8($r->param('sindex'))   || 0;
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    my $colors = $access_green + $access_yellow*2 + $access_red*4;

    if (!$colors){
        $colors=$config->{ezb_colors};

        my $colors_mask  = dec2bin($colors);

        $logger->debug("Access: mask($colors_mask)");
        
        $access_green  = ($colors_mask & 0b001)?1:0;
        $access_yellow = ($colors_mask & 0b010)?1:0;
        $access_red    = ($colors_mask & 0b100)?1:0;
    }

    $logger->debug("Access: colors($colors) green($access_green) yellow($access_yellow) red($access_red)");
    
    my $ezb = new OpenBib::Search::Backend::EZB({colors => $colors, lang => $queryoptions->get_option('l') });
    
    my $subjects_ref = $ezb->get_subjects();
    
    if ($logger->is_debug){
        $logger->debug(YAML::Dump($subjects_ref));
    }
    
    # TT-Data erzeugen
    my $ttdata={
        database      => $database,
        type          => $type,
        access_green  => $access_green,
        access_yellow => $access_yellow,
        access_red    => $access_red,
        subjects      => $subjects_ref,
    };
    
    return $self->print_page($config->{'tt_classifications_tname'},$ttdata);
}

sub show_collection_dbis {
        my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $database       = $self->strip_suffix($self->param('database'));

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
    my $type           = decode_utf8($r->param('type'))     || 'cloud';

    my $access_green   = decode_utf8($r->param('access_green'))     || 0;
    my $access_yellow  = decode_utf8($r->param('access_yellow'))    || 0;
    my $access_red     = decode_utf8($r->param('access_red'))       || 0;
    my $access_de      = decode_utf8($r->param('access_de'))        || 0;
    my $id             = decode_utf8($r->param('id'))       || undef;
    my $lett           = decode_utf8($r->param('lett'))     || '';

    my $sc             = decode_utf8($r->param('sc'))       || '';
    my $lc             = decode_utf8($r->param('lc'))       || '';
    my $sindex         = decode_utf8($r->param('sindex'))   || 0;
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    my $colors  = $access_green + $access_yellow*44;
    my $ocolors = $access_red*8 + $access_de*32;

    # Wenn keine Parameter uebergeben wurden, dann Defaults nehmen
    if (!$colors && !$ocolors){
        $logger->debug("Using defaults for color and ocolor");

        $colors  = $config->{dbis_colors};
        $ocolors = $config->{dbis_ocolors};

        my $colors_mask  = OpenBib::Common::Util::dec2bin($colors);
        my $ocolors_mask = OpenBib::Common::Util::dec2bin($ocolors);
        
        $access_red    = ($ocolors_mask & 0b001000)?1:0;
        $access_de     = ($ocolors_mask & 0b100000)?1:0;
        $access_green  = ($colors_mask  & 0b000001)?1:0;
        $access_yellow = ($colors_mask  & 0b101100)?1:0;
    }
    else {
        $logger->debug("Using CGI values for color and ocolor");
    }
    
    my $dbis = new OpenBib::Search::Backend::DBIS({colors => $colors, ocolors => $ocolors, lang => $queryoptions->get_option('l') });

    my $subjects_ref = $dbis->get_subjects();
    
    if ($logger->is_debug){
        $logger->debug(YAML::Dump($subjects_ref));
    }
    
    # TT-Data erzeugen
    my $ttdata={
        database      => $database,
        type          => $type,
        access_green  => $access_green,
        access_yellow => $access_yellow,
        access_red    => $access_red,
        access_de     => $access_de,
        subjects      => $subjects_ref,
    };
    
    return $self->print_page($config->{'tt_classifications_tname'},$ttdata);
}

sub show_collection_sql {
    my $self = shift;

    return;
}

1;
