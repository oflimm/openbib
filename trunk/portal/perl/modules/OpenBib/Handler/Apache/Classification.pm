#####################################################################
#
#  OpenBib::Handler::Apache::Classification.pm
#
#  Copyright 2009-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Classification;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);
use Encode qw/decode_utf8 encode_utf8/;

use OpenBib::Record::Classification;
use OpenBib::Search::Backend::EZB;
use OpenBib::Search::Backend::DBIS;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_record');
    $self->run_modes(
        'show_record'     => 'show_record',
        'show_collection' => 'show_collection',
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
    my $classificationid = $self->strip_suffix($self->param('classificationid'));

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
    my $no_log         = $query->param('no_log')  || '';

    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;

    if ($database && $classificationid ){ # Valide Informationen etc.
        $logger->debug("ID: $classificationid - DB: $database");
        
        my $record = OpenBib::Record::Classification->new({database => $database, id => $classificationid})->load_full_record;
        
        my $authenticationtargetdb = $user->get_targetdb_of_session($session->{ID});

        # TT-Data erzeugen
        my $ttdata={
            database      => $database, # Zwingend wegen common/subtemplate
            dbinfo        => $dbinfotable,
            qopts         => $queryoptions->get_options,
            record        => $record,
            id            => $classificationid,
            format        => $format,
            activefeed    => $config->get_activefeeds_of_db($database),
            authenticationtargetdb => $authenticationtargetdb,
        };

        $self->print_page($config->{'tt_classification_tname'},$ttdata);

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
    }
    else {
        $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname/Id spezifiziert."));
    }

    return Apache2::Const::OK;
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
    my $stid          = $query->param('stid')     || '';
    my $callback      = $query->param('callback') || '';
    my $lang          = $query->param('lang')     || $queryoptions->get_option('l') || 'de';
    my $format        = $query->param('format')   || 'full';
    my $no_log         = $query->param('no_log')  || '';

    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;

    if ($database){ # Valide Informationen etc.

        my $system = $config->get_system_of_db($database);

        $logger->debug("System is: $system");
        
        # EZB
        if    ($system eq "Backend: EZB"){
            $logger->debug("Dispatching to Backend EZB");
            $self->show_collection_ezb();
        }
        # DBIS
        elsif ($system eq "Backend: DBIS"){
            $logger->debug("Dispatching to Backend DBIS");
            $self->show_collection_dbis();
        }
        # Lokale Datenbank
        else {
            $logger->debug("Dispatching to Backend SQL");
            $self->show_collection_sql();
        }
    }
    else {
        $self->print_warning($msg->maketext("Die Resource wurde nicht korrekt mit Datenbankname spezifiziert."));
    }

    return Apache2::Const::OK;
}

sub show_collection_ezb {
    my $self = shift;

        # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->strip_suffix($self->param('database'));

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
    my $type           = decode_utf8($query->param('type'))     || 'cloud';
    my $access_green   = decode_utf8($query->param('access_green'))     || 0;
    my $access_yellow  = decode_utf8($query->param('access_yellow'))    || 0;
    my $access_red     = decode_utf8($query->param('access_red'))       || 0;
    my $id             = decode_utf8($query->param('id'))       || undef;
    my $sc             = decode_utf8($query->param('sc'))       || '';
    my $lc             = decode_utf8($query->param('lc'))       || '';
    my $sindex         = decode_utf8($query->param('sindex'))   || 0;
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    
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
    
    $logger->debug(YAML::Dump($subjects_ref));
    
    # TT-Data erzeugen
    my $ttdata={
        dbinfo        => $dbinfotable,
        database      => $database,
        type          => $type,
        access_green  => $access_green,
        access_yellow => $access_yellow,
        access_red    => $access_red,
        subjects      => $subjects_ref,
    };
    
    $self->print_page($config->{'tt_classification_collection_tname'},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_collection_dbis {
        my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $database       = $self->strip_suffix($self->param('database'));

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
    my $type           = decode_utf8($query->param('type'))     || 'cloud';

    my $access_green   = decode_utf8($query->param('access_green'))     || 0;
    my $access_yellow  = decode_utf8($query->param('access_yellow'))    || 0;
    my $access_red     = decode_utf8($query->param('access_red'))       || 0;
    my $access_de      = decode_utf8($query->param('access_de'))        || 0;
    my $id             = decode_utf8($query->param('id'))       || undef;
    my $lett           = decode_utf8($query->param('lett'))     || '';

    my $sc             = decode_utf8($query->param('sc'))       || '';
    my $lc             = decode_utf8($query->param('lc'))       || '';
    my $sindex         = decode_utf8($query->param('sindex'))   || 0;
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    my $colors  = $access_green + $access_yellow*44;
    my $ocolors = $access_red*8 + $access_de*32;

    # Wenn keine Parameter uebergeben wurden, dann Defaults nehmen
    if (!$colors && !$ocolors){
        $logger->debug("Using defaults for color and ocolor");

        $colors  = $config->{dbis_colors};
        $ocolors = $config->{dbis_ocolors};

        my $colors_mask  = dec2bin($colors);
        my $ocolors_mask = dec2bin($ocolors);
        
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
    
    $logger->debug(YAML::Dump($subjects_ref));
    
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
    
    $self->print_page($config->{'tt_classification_collection_tname'},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_collection_sql {
    my $self = shift;

    return;
}

sub dec2bin {
    my $str = unpack("B32", pack("N", shift));
    $str =~ s/^0+(?=\d)//;   # strip leading zeroes
    return $str;
}
sub bin2dec {
    return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}

1;
