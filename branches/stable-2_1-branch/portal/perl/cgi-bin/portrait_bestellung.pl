#!/usr/bin/perl -w

#####################################################################
#
#  portrait_bestellung.pl
#
#  Bestellung eines Portraits in den LS Historische Sammlungen
#
#  Copyright 2008 Oliver Flimm <flimm@ub.uni-koeln.de>
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

use CGI qw/:standard/;                        # CGI-Handling (or require)
use Log::Log4perl qw(get_logger :levels);
use DBI;
use Template;
use Encode qw/decode_utf8 encode_utf8/;
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

my $bnr      = ($query->param('bnr'))?$query->param('bnr'):'';
my $password = ($query->param('password'))?$query->param('password'):'';

$bnr=~s/%23/#/;


my $titel    = ($query->param('titel'))?$query->param('titel'):'';
my $person   = ($query->param('person'))?$query->param('person'):'';
my $signatur = ($query->param('signatur'))?$query->param('signatur'):'';

#####################################################################
# Variablen in <FORM>, die den Such-Flu"s steuern 
#####################################################################

  
#####                                                          ######
####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
#####                                                          ######

###########                                               ###########
############## B E G I N N  P R O G R A M M F L U S S ###############
###########                                               ###########

my $logfile='/var/log/openbib/portrait_bestellung.log';

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

my $config = new OpenBib::Config();

$logger->debug("Bnr:$bnr - OPAC-Pin:$password - Titel: $titel - Person: $person - Signatur:$signatur");
# Ueberpruefen, ob der Nutzer korrekt ist

my $soap = new SOAP::Lite
    ->default_ns("urn:/Authentication")
    ->proxy($config->{olws}{'urn:/Authentication'}{'portrait'}{'url'});

my $result = $soap->authenticate_user(
    SOAP::Data->name(parameters  =>\SOAP::Data->value(
        SOAP::Data->name(username => $bnr)->type('string'),
        SOAP::Data->name(password => $password)->type('string'),
        SOAP::Data->name(database => $config->{olws}{'urn:/Authentication'}{'portrait'}{'database'})->type('string')))
  );

my %userinfo=();
unless ($result->fault) {
    if (defined $result->result) {
        %userinfo = %{$result->result};
        $userinfo{'erfolgreich'} = "1"
    } else {
        $userinfo{'erfolgreich'} = "0"
    }
}

if ($userinfo{'erfolgreich'} eq "1"){
    
    my $anschreiben="";
    my $afile = "an." . $$;
    
    my $mainttdata = {
        bnr       => $bnr,
        titel     => decode_utf8($titel),
        person    => decode_utf8($person),
        signatur  => $signatur,
        userinfo  => \%userinfo,
    };
    
    my $maintemplate = Template->new({
        INCLUDE_PATH   => $config->{tt_include_path},
        ABSOLUTE       => 1,
        RECURSION      => 1,
        OUTPUT_PATH   => '/tmp',
        OUTPUT        => $afile,
    });
    
    $maintemplate->process('portrait-bestellung', $mainttdata ) || do {
        my $resulttemplate = Template->new({ 
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        });
        
        # Dann Ausgabe des neuen Headers
        print header;
        
        $resulttemplate->process('portrait-bestellung_fehler', {
            grund => $maintemplate->error(),
        });

    };
    
    my $mailmsg = MIME::Lite->new(
        From            => $config->{contact_email},
        To              => 'portraitbestellung@ub.uni-koeln.de',
        Subject         => 'Bestellung eines Portraits in den LS Hist. Sammlungen',
        Type            => 'multipart/mixed'
    );
    
    my $anschfile="/tmp/" . $afile;
    
    $mailmsg->attach(
        Type            => 'TEXT',
        Encoding        => '8bit',
        Path            => $anschfile,
    );
    
    $mailmsg->send('sendmail', "/usr/lib/sendmail -t -oi -f$config->{contact_email}");
    
    
    my $resulttemplate2 = Template->new({ 
        INCLUDE_PATH   => $config->{tt_include_path},
        ABSOLUTE       => 1,
    });
        
    # Dann Ausgabe des neuen Headers
    print header;
    
    $resulttemplate2->process('portrait-bestellung_erfolg', $mainttdata);

}
else {
    my $template = Template->new({ 
        INCLUDE_PATH   => $config->{tt_include_path},
        ABSOLUTE       => 1,
    });
    
    # Dann Ausgabe des neuen Headers
    print header;
    
    $template->process('portrait-bestellung_fehler', { grund => 'Kombination Benutzername/Opac-Pin ung&uuml;ltig'});
}
