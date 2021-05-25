#####################################################################
#
#  OpenBib::Handler::PSGI::Locations::MailOrders
#
#  Dieses File ist (C) 2020 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Locations::MailOrders;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Digest::MD5;
use Email::Valid;
use Email::Stuffer;
use File::Slurper 'read_binary';
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Socket;
use Template;
use URI::Escape;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'mail'                  => 'mail',
        'show_collection'       => 'show_collection',
        'dispatch_to_representation'           => 'dispatch_to_representation',
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
    my $locationid     = $self->param('locationid');

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
    my $database       = ($query->param('dbname'     ))?$query->param('dbname'):'';
    my $titleid        = ($query->param('titleid'    ))?$query->param('titleid'):'';
    my $mark           = ($query->param('mark'       ))?$query->param('mark'):'';
    my $mnr            = ($query->param('mnr'        ))?$query->param('mnr'):'';

    if (!$titleid){
	return $self->print_warning("Zuwenige Parameter übergeben");
    }

    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_full_record;
    
    # TT-Data erzeugen
    my $ttdata={
	mark       => $mark,
	mnr        => $mnr,
	locationid => $locationid,
	record     => $record,
	database   => $database
    };
    
    return $self->print_page($config->{tt_locations_record_mailorders_tname},$ttdata);
}

sub mail {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $locationid     = $self->param('locationid')     || '';

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
    my $scope       = $query->param('scope');
    my $zweigabteil = $query->param('zweigabteil');
    my $title       = $query->param('title');
    my $siasnr      = $query->param('siasnr');
    my $mnr         = $query->param('mnr');
    my $corporation = $query->param('corporation');
    my $person      = $query->param('person');
    my $publisher   = $query->param('publisher');
    my $mark        = $query->param('mark');
    my $userid      = $query->param('userid');
    my $username    = $query->param('username');
    my $pickup      = $query->param('pickup');
    my $remark      = $query->param('remark');
    my $email       = ($query->param('email'))?$query->param('email'):'';
    my $receipt     = $query->param('receipt');

    # Ab hier ist in $user->{ID} entweder die gueltige Userid oder nichts, wenn
    # die Session nicht authentifiziert ist
    if ($email eq "") {
        return $self->print_warning($msg->maketext("Sie haben keine Mailadresse eingegeben."));
    }

    if (!defined $config->get('mailorders')->{scope}{$scope}) {
        return $self->print_warning($msg->maketext("Eine Bestellung ist nicht moeglich."));
    }

    if (!$username || !$pickup || !$email){
        return $self->print_warning($msg->maketext("Sie müssen alle Pflichtfelder ausfüllen."));
    }

    unless (Email::Valid->address($email)) {
        return $self->print_warning($msg->maketext("Sie haben eine ungültige Mailadresse eingegeben."));
    }	

    # Bei angemeldeten Usern wird deren Username als Userid gesetzt und ueberschreibt damit den Standartwert 'Anonym'

    if ($user->{ID}){
	$userid = $user->get_username;
    }
    
    # TT-Data erzeugen
    
    my $ttdata={
        view        => $view,
	location    => $locationid,

	scope       => $scope,
	zweigabteil => $zweigabteil,
	title       => $title,
	siasnr      => $siasnr,
	mnr         => $mnr,
	corporation => $corporation,
	person      => $person,
	publisher   => $publisher,
	mark        => $mark,
	userid      => $userid,
	username    => $username,
	pickup      => $pickup,
	remark      => $remark,
	email       => $email,

	    
        config      => $config,
        user        => $user,
        msg         => $msg,
    };

    my $anschreiben="";
    my $afile = "an." . $$;

    my $maintemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #        ABSOLUTE      => 1,
        #        INCLUDE_PATH  => $config->{tt_include_path},
        # Es ist wesentlich, dass OUTPUT* hier und nicht im
        # Template::Provider definiert wird
        RECURSION      => 1,
        OUTPUT_PATH   => '/tmp',
        OUTPUT        => $afile,
    });

    $maintemplate->process($config->{tt_locations_record_mailorders_mail_body_tname}, $ttdata ) || do { 
        $logger->error($maintemplate->error());
        $self->header_add('Status',400); # server error
        return;
    };

    my $mail_to = $config->{mailorders}{scope}{$scope}{recipient};

    if ($receipt){
	$mail_to.=",$email";
    }
    
    my $anschfile="/tmp/" . $afile;

    Email::Stuffer->to($mail_to)
	->from($config->{mailorders}{scope}{$scope}{sender})
	->subject("$scope: Bestellung per Mail")
	->text_body(read_binary($anschfile))
	->send;
    
    unlink $anschfile;
    
    return $self->print_page($config->{tt_locations_record_mailorders_mail_success_tname},$ttdata);
}

1;
__END__

=head1 NAME

OpenBib::Locations::MailOrders - Bestellung per Mail

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::Locations::MailOrders stellt einen Dienst zur 
verfuegung, um fuer einzelne Standorte eine vereinfachte Bestellmoeglichkeit
von Medien ueber eine einfache Mail-Bestellung abzuwickeln.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
