#!/usr/bin/perl -w

#####################################################################
#
#  mail_bestellung.pl
#
#  Bestellung eines Titels per Mail fuer einen Katalog
#
#  Copyright 2008-2013 Oliver Flimm <flimm@ub.uni-koeln.de>
#
#  Dieses Programm ist freie Software. Sie k"onnen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es w"unschen) jeder sp"ateren Version.
#
#  Die Ver"offentlichung dieses Programms erfolgt in der
#  Hoffnung, da"s es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEW"AHRLEISTUNG - sogar ohne die implizite Gew"ahrleistung
#  der MARKTREIFE oder der EIGNUNG F"UR EINEN BESTIMMTEN ZWECK.
#  Details finden Sie in der GNU General Public License.
#
#  Sie sollten eine Kopie der GNU General Public License zusammen
#  mit diesem Programm erhalten haben. Falls nicht, schreiben Sie
#  an die Free Software Foundation, Inc., 675 Mass Ave, Cambridge,
#  MA 02139, USA.
#
#####################################################################   

#####################################################################
# Einladen der ben"otigten Perl-Module 
#####################################################################

use strict;
use warnings;
no warnings 'redefine';

use Carp;
use CGI qw/:standard/;                        # CGI-Handling (or require)
use Log::Log4perl qw(get_logger :levels);
use DBI;
use Template;
use OpenBib::Template::Provider;
use OpenBib::Common::Util;
use OpenBib::L10N;
use Encode qw/decode_utf8 encode_utf8 encode decode/;
use YAML;
use SOAP::Lite;
use MIME::Lite;
use OpenBib::Config;

####                                                              ### 
###### B E G I N N  V A R I A B L E N D E K L A R A T I O N E N #####
####                                                              ###

#####################################################################
# Lokale Einstellungen - Allgemein 
#####################################################################

my $query=new CGI;

#####################################################################
# Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen 
#####################################################################

my $view     = ($query->param('view'))?$query->param('view'):'kug';
my $database = ($query->param('database'))?$query->param('database'):'';
my $contact  = ($query->param('contact'))?$query->param('contact'):'';
my $mailsubject = ($query->param('mailsubject'))?decode_utf8($query->param('mailsubject')):'Bestellung';

my $username    = ($query->param('username'))?$query->param('username'):'';
my $password    = ($query->param('password'))?$query->param('password'):'';


$username=~s/%23/#/;

my $titel    = ($query->param('titel'))?decode_utf8($query->param('titel')):'';
my $person   = ($query->param('person'))?decode_utf8($query->param('person')):'';
my $signatur = ($query->param('signatur'))?decode_utf8($query->param('signatur')):'';

#####################################################################
# Variablen in <FORM>, die den Such-Flu"s steuern 
#####################################################################

my $contact_whitelist_ref = {
    'portraitbestellung@ub.uni-koeln.de' => 1,
};
  
#####                                                          ######
####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
#####                                                          ######

###########                                               ###########
############## B E G I N N  P R O G R A M M F L U S S ###############
###########                                               ###########

my $logfile='/var/log/openbib/mail_bestellung.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, LOGFILE
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = OpenBib::Config->new;

my $databaseinfo = $config->get_databaseinfo->single({ dbname => $database });

my $wsurl ;
my $wsdbname;

if ($databaseinfo){
    $logger->debug("Got dbinfo");
    $wsurl    = $databaseinfo->get_column('circwsurl');
    $wsdbname = $databaseinfo->get_column('circdb');
    $logger->debug("WSURL: $wsurl - WSDBNAME: $wsdbname");
}
else {
    $logger->debug("Couldn't get dbinfo");
}


# Message Katalog laden
my $msg = OpenBib::L10N->get_handle('de') || $logger->error("L10N-Fehler");
$msg->fail_with( \&OpenBib::L10N::failure_handler );

my $sysprofile = $config->get_profilename_of_view($view);
    
$logger->debug("Username:$username - OPAC-Pin:$password - Titel: $titel - Person: $person - Signatur:$signatur");
# Ueberpruefen, ob der Nutzer korrekt ist
$logger->debug("Database: $database - View: $view - Kontakt: $contact");

if (!defined $contact_whitelist_ref->{contact} && !$contact_whitelist_ref->{$contact}){
    my  $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $database,
        view         => $view,
        profile      => $sysprofile,
        templatename => 'mail-order_error',
    });

    my $ttdata =  {
        database   => $database,
        config     => $config,
        msg        => $msg,
        view       => $view,
        sysprofile => $sysprofile,
        grund      => "Keine valide Mailadresse ($contact)",
    };

    my $template = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
	    ABSOLUTE       => 1,
            STAT_TTL => 60,  # one minute
        }) ],
        COMPILE_EXT => '.ttc',
        COMPILE_DIR => '/tmp/ttc',
        STAT_TTL => 60,  # one minute
        RECURSION      => 1,
    });

    # Dann Ausgabe des neuen Headers
    print $query->header('text/html');

    $template->process($templatename, $ttdata);
}

my $result;

eval {
    my $soap = new SOAP::Lite
        ->default_ns("urn:/Authentication")
            ->proxy($wsurl);
    
    $result = $soap->authenticate_user(
        SOAP::Data->name(parameters  =>\SOAP::Data->value(
            SOAP::Data->name(username => $username)->type('string'),
            SOAP::Data->name(password => $password)->type('string'),
            SOAP::Data->name(database => $wsdbname)->type('string')))
      );
};

if ($@){
    $logger->error($@);
}

my %userinfo=();
unless ($result->fault) {
    if (defined $result->result) {
        %userinfo = %{$result->result};
        $userinfo{'erfolgreich'} = "1"
    } else {
        $userinfo{'erfolgreich'} = "0"
    }
}

$logger->debug("Erfolgreich?: ".$userinfo{'erfolgreich'});
if ($userinfo{'erfolgreich'} eq "1"){
    
    my $anschreiben="";
    my $afile = "an." . $$;

    # Web
    my $mainttdata = {
        contact    => $contact,
        database   => $database,
        config     => $config,
        msg        => $msg,
        view       => $view,
        sysprofile => $sysprofile,
        username   => $username,
        titel      => $titel,
        person     => $person,
        signatur   => $signatur,
        userinfo   => \%userinfo,
    };

    # Mail
    my $mailttdata = {
        contact    => $contact,
        database   => $database,
        config     => $config,
        msg        => $msg,
        view       => $view,
        sysprofile => $sysprofile,
        username        => $username,
        titel      => encode_utf8($titel),
        person     => encode_utf8($person),
        signatur   => encode_utf8($signatur),
        userinfo   => \%userinfo,
    };

    my $maintemplate = Template->new({
        INCLUDE_PATH   => $config->{tt_include_path},
        ABSOLUTE       => 1,
        RECURSION      => 1,
        OUTPUT_PATH   => '/tmp',
        OUTPUT        => $afile,
    });

    my  $mailtemplatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $database,
        view         => $view,
        profile      => $sysprofile,
        templatename => 'mail-order',
    });

    $maintemplate->process($mailtemplatename, $mailttdata ) || do {
        my $resulttemplate = Template->new({ 
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        });
        
        # Dann Ausgabe des neuen Headers
        print $query->header('text/html');
        
        $resulttemplate->process('mail-order_error', {
            grund => $maintemplate->error(), database => $database, view => $view, sysprofile => $sysprofile 
        });

    };
    
    my $mailmsg = MIME::Lite->new(
        From            => $contact,
        To              => $contact,
        Subject         => $mailsubject,
        Type            => 'multipart/mixed'
    );
    
    my $anschfile="/tmp/" . $afile;

    my $part =  MIME::Lite->new(
        Type            => 'TEXT',
        Path            => $anschfile,
    );

    $part->attr('content-type.charset' => 'UTF-8');
    
    $mailmsg->attach($part);
    
    $mailmsg->send('sendmail', "/usr/lib/sendmail -t -oi -f$contact");
    
    my  $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $database,
        view         => $view,
        profile      => $sysprofile,
        templatename => 'mail-order_success',
    });

    my $resulttemplate2 = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
	    ABSOLUTE       => 1,
            STAT_TTL => 60,  # one minute
        }) ],
        COMPILE_EXT => '.ttc',
        COMPILE_DIR => '/tmp/ttc',
        STAT_TTL => 60,  # one minute
        RECURSION      => 1,
    });

    # Dann Ausgabe des neuen Headers
    print $query->header('text/html');
    
    $resulttemplate2->process($templatename, $mainttdata);

}
else {

    my  $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $database,
        view         => $view,
        profile      => $sysprofile,
        templatename => 'mail-order_error',
    });

    my $ttdata =  {
        database   => $database,
        config     => $config,
        msg        => $msg,
        view       => $view,
        sysprofile => $sysprofile,
        grund      => 'Kombination Benutzername/Opac-Pin ung&uuml;ltig',
    };

    my $template = Template->new({ 
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
	    ABSOLUTE       => 1,
            STAT_TTL => 60,  # one minute
        }) ],
        COMPILE_EXT => '.ttc',
        COMPILE_DIR => '/tmp/ttc',
        STAT_TTL => 60,  # one minute
        RECURSION      => 1,
    });

    # Dann Ausgabe des neuen Headers
    print $query->header('text/html');

    $template->process($templatename, $ttdata);
}
