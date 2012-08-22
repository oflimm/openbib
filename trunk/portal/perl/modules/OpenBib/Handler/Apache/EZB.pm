#####################################################################
#
#  OpenBib::Handler::Apache::EZB.pm
#
#  Copyright 2008-2011 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::EZB;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Benchmark ':hireswallclock';
use Encode qw/decode_utf8 encode_utf8/;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;

use OpenBib::BibSonomy;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::EZB;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_collection');
    $self->run_modes(
        'show_collection'            => 'show_collection',
        'show_collection_by_subject' => 'show_collection_by_subject',
        'show_record'                => 'show_record',
        'search_collection'          => 'search_collection',
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
    my $view           = $self->param('view')           || '';

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
    
    my $ezb = new OpenBib::EZB({colors => $colors, lang => $queryoptions->get_option('l') });
    
    my $subjects_ref = $ezb->get_subjects();
    
    $logger->debug(YAML::Dump($subjects_ref));
    
    # TT-Data erzeugen
    my $ttdata={
        type          => $type,
        access_green  => $access_green,
        access_yellow => $access_yellow,
        access_red    => $access_red,
        subjects      => $subjects_ref,
    };
    
    $self->print_page($config->{'tt_ezb_subject_collection_tname'},$ttdata);
    
    return Apache2::Const::OK;
}

sub search_collection {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';

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
    my $action         = decode_utf8($query->param('action'))   || '';
    my $show_cloud     = decode_utf8($query->param('show_cloud'));
    my $notation       = decode_utf8($query->param('notation')) || '';
    my $fs             = decode_utf8($query->param('fs'))       || '';

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
    
    my $ezb = new OpenBib::EZB({colors => $colors, lang => $queryoptions->get_option('l') });
    
    my $subjects_ref = $ezb->get_subjects();
    
    $logger->debug(YAML::Dump($subjects_ref));

    if ($fs){
        my $journals_ref = $ezb->search_journals({
            fs       => $fs,
            notation => $notation,
            sc       => $sc,
            lc       => $lc,
            sindex   => $sindex,
        });
        
        $logger->debug(YAML::Dump($journals_ref));
        
        # TT-Data erzeugen
        my $ttdata={
            sindex        => $sindex,
            access_green  => $access_green,
            access_yellow => $access_yellow,
            access_red    => $access_red,
            journals      => $journals_ref,
            view          => $view,
            stylesheet    => $stylesheet,
            sessionID     => $session->{ID},
            session       => $session,
            useragent     => $useragent,
            config        => $config,
            msg           => $msg,
        };
        
        $self->print_page($config->{'tt_ezb_journal_search_tname'},$ttdata);
    }
    else {
        $self->print_warning($msg->maketext("Kein Suchbegriff vorhanden"));
    }
    
    return Apache2::Const::OK;
}

sub show_collection_by_subject {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $notation       = $self->strip_suffix($self->param('subjectid'));
    
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
    my $access_green   = decode_utf8($query->param('access_green'))     || 0;
    my $access_yellow  = decode_utf8($query->param('access_yellow'))    || 0;
    my $access_red     = decode_utf8($query->param('access_red'))       || 0;
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
    
    my $ezb = new OpenBib::EZB({colors => $colors, lang => $queryoptions->get_option('l') });
    
    my $subjects_ref = $ezb->get_subjects();
    
    $logger->debug(YAML::Dump($subjects_ref));

    if ($notation){
        my $journals_ref = $ezb->get_journals({
            notation => $notation,
            sc       => $sc,
            lc       => $lc,
            sindex   => $sindex,
        });
        
        $logger->debug(YAML::Dump($journals_ref));
        
        # TT-Data erzeugen
        my $ttdata={
            notation      => $notation,
            sindex        => $sindex,
            access_green  => $access_green,
            access_yellow => $access_yellow,
            access_red    => $access_red,
            journals      => $journals_ref,
        };
        
        $self->print_page($config->{'tt_ezb_journal_collection_by_subject_tname'},$ttdata);
    }
    else {
        $self->print_warning($msg->maketext("Keine Notation vorhanden"));
    }
    
    return Apache2::Const::OK;
}

sub show_record {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $id             = $self->strip_suffix($self->param('journalid'));

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
    my $access_green   = decode_utf8($query->param('access_green'))     || 0;
    my $access_yellow  = decode_utf8($query->param('access_yellow'))    || 0;
    my $access_red     = decode_utf8($query->param('access_red'))       || 0;
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
    
    my $ezb = new OpenBib::EZB({colors => $colors, lang => $queryoptions->get_option('l') });
    
    my $subjects_ref = $ezb->get_subjects();
    
    $logger->debug(YAML::Dump($subjects_ref));

    if ($id){
        my $journalinfo_ref = $ezb->get_journalinfo({
            id => $id,
        });
        
        $logger->debug(YAML::Dump($journalinfo_ref));
        
        # TT-Data erzeugen
        my $ttdata={
            sindex        => $sindex,
            journalinfo   => $journalinfo_ref,
        };
        
        $self->print_page($config->{'tt_ezb_journal_record_tname'},$ttdata);
    }
    else {
        $self->print_warning($msg->maketext("Keine Journalid vorhanden"));
    }       

    return Apache2::Const::OK;
}

sub show_journal_readme {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';

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
    my $action         = decode_utf8($query->param('action'))   || '';
    my $show_cloud     = decode_utf8($query->param('show_cloud'));
    my $notation       = decode_utf8($query->param('notation')) || '';
    my $fs             = decode_utf8($query->param('fs'))       || '';

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
    
    my $ezb = new OpenBib::EZB({colors => $colors, lang => $queryoptions->get_option('l') });
    
    my $subjects_ref = $ezb->get_subjects();
    
    $logger->debug(YAML::Dump($subjects_ref));

    if ($id){
        my $journalreadme_ref = $ezb->get_journalreadme({
            id => $id,
        });
        
        $logger->debug("ReadME-Daten: ".YAML::Dump($journalreadme_ref));
        
        if ($journalreadme_ref->{location}){
            $self->header_type('redirect');
            $self->header_props(-type => 'text/html', -url => $journalreadme_ref->{location});
        }
        else {
            
            # TT-Data erzeugen
            my $ttdata={
                sindex        => $sindex,
                journalreadme => $journalreadme_ref,
            };
            
            $self->print_page($config->{'tt_ezb_journal_record_readme_tname'},$ttdata);
        }
    }
    else {
        $self->print_warning($msg->maketext("Keine Journalid vorhanden"));
    }       

    return Apache2::Const::OK;
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
