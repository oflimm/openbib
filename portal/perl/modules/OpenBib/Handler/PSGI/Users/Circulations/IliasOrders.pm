#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Circulations::IliasOrders
#
#  Dieses File ist (C) 2021 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Users::Circulations::IliasOrders;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use DBI;
use Digest::MD5;
use Email::Valid;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use SOAP::Lite;
use Socket;
use Template;
use URI::Escape;

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::ILS::Factory;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;
use JSON::XS qw/encode_json decode_json/;
use LWP::UserAgent;

use base 'OpenBib::Handler::PSGI::Users';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'create_record'         => 'create_record',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    
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

    # CGI / JSON input
    my $input_data_ref = $self->parse_valid_input();

    # CGI Args
    my $database       = $input_data_ref->{'database'};
    my $titleid        = $input_data_ref->{'titleid'};
    my $label          = $input_data_ref->{'label'};
    my $unit_desc      = $input_data_ref->{'unit_desc'};
    my $domain         = $input_data_ref->{'domain'};
    my $subdomain      = $input_data_ref->{'subdomain'};
    my $receipt        = $input_data_ref->{'receipt'};
    my $unit           = $input_data_ref->{'unit'};
    my $volume         = $input_data_ref->{'volume'};
    my $source         = $input_data_ref->{'source'};
    my $articleauthor  = $input_data_ref->{'articleauthor'};
    my $articletitle   = $input_data_ref->{'articletitle'};
    my $issue          = $input_data_ref->{'issue'};
    my $pages          = $input_data_ref->{'pages'};
    my $remark         = $input_data_ref->{'remark'};
    my $numbering      = $input_data_ref->{'numbering'};
    my $confirm        = $input_data_ref->{'confirm'};
   
    unless ($config->get('active_ils')){
	return $self->print_warning($msg->maketext("Die Ausleihfunktionen (Bestellungen, Vormerkungen, Campuslieferdienst, E-Semesterapparat usw.) sind aktuell systemweit deaktiviert."));	
    }

    unless ($database && $label && $unit >= 0 && $titleid){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt"));
    }

    my $refid = "";

    my $session_cache = $session->get_datacache;
    

    if (defined $session_cache->{'ilias'} && defined $session_cache->{ilias}{refid}){
	$refid = $session_cache->{ilias}{refid};
    }

    unless ($refid){
	return $self->print_warning($msg->maketext("Fehler bei der Übertragung der ILIAS Kurs-ID."));
    }
        
    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $email       = $session_cache->{ilias}{email};
    my $accountname = $session_cache->{ilias}{userid};

    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_full_record;
    
    if ($confirm){
	$logger->debug("Showing ilias orderform");
	
	# TT-Data erzeugen
	my $ttdata={
	    record         => $record,
	    database       => $database,
	    titleid        => $titleid,
	    numbering      => $numbering,
	    label          => $label,
	    articleauthor  => $articleauthor,
	    articletitle   => $articletitle,
	    volume         => $volume,
	    issue          => $issue,
	    pages          => $pages,
	    refid          => $refid,
	    accountname    => $accountname,
	    receipt        => $receipt,
	    email          => $email,
	    remark         => $remark,
	    unit           => $unit,
	    unit_desc      => $unit_desc,
	    domain         => $domain,
	    subdomain      => $subdomain,
	    session_cache  => $session_cache,
	};
	
	return $self->print_page($config->{tt_users_circulations_check_ilias_order_tname},$ttdata);
    }
    else {
	$logger->debug("Making ilias order");

	my $fields_ref = $record->to_abstract_fields;

	my $title       = $fields_ref->{title};
	if ($fields_ref->{titlesup}){
	    $title = "$title : ".$fields_ref->{titlesup};
	}
	my $corporation = join(' ; ',@{$fields_ref->{corp}});
	my $author      = join(' ; ',@{$fields_ref->{authors}});
	my $issn        = $fields_ref->{issn};
	my $isbn        = $fields_ref->{isbn};

	my @placepub = ();

	push @placepub, $fields_ref->{place} if ($fields_ref->{place});
	push @placepub, $fields_ref->{publisher} if ($fields_ref->{publisher});
	my $publisher   = join(' : ',@placepub);

	my $source      = $fields_ref->{series};
	my $year        = $fields_ref->{year};
	
	if (!$pages){
	    return $self->print_warning("Bitte geben Sie die gewünschten Seiten an.");
	}
	
	if (!$email){
	    return $self->print_warning("Zur Bestellung im E-Semesterapparat ist eine E-Mail-Adresse in Ihrem Bibliothekskonto erforderlich.");
	}
	
	if (!$titleid){
	    return $self->print_warning("Fehler bei der Übertragung der Datensatz-ID.");
	}

	if (!$articletitle && $numbering ){
	    return $self->print_warning("Bitte geben Sie den Titel des gewünschten Aufsatzes an.");
	}
	
	if (!$articleauthor && $numbering){
	    return $self->print_warning("Bitte geben Sie den Autor des gewünschten Aufsatzes an.");
	}
	
	if (!$volume && $numbering){
	    return $self->print_warning("Bitte geben Sie den Band an, in dem der gewünschte Aufsatz erschienen ist.");
	}

	if (!$issue && $numbering){
	    return $self->print_warning("Bitte geben Sie die Nummer des Heftes an, in dem der gewünschte Aufsatz erschienen ist.");
	}
	
	if (!$year && $numbering){
	    return $self->print_warning("Bitte geben Sie das Jahr an, in dem der gewünschte Aufsatz erschienen ist.");
	}
	
	if (!$label){
	    return $self->print_warning("Fehler bei der Übertragung der Signatur.");
	}
	
	if (!$title){
	    return $self->print_warning("Fehler bei der Übertragung des Titels.");
	}
		
	my $response_make_ilias_order_ref = $ils->make_ilias_order({ title => $title, titleid => $titleid, author => $author, coporation => $corporation, publisher => $publisher, year => $year, numbering => $numbering, label => $label, isbn => $isbn, issn => $issn, articleauthor => $articleauthor, articletitle => $articletitle, volume => $volume, issue => $issue, pages => $pages, refid => $refid, userid => $accountname, username => $accountname, receipt => $receipt, email => $email, remark => $remark, unit => $unit, location => $unit_desc, domain => $domain, subdomain => $subdomain });

	if ($logger->is_debug){
	    $logger->debug("Result make_order:".YAML::Dump($response_make_ilias_order_ref));	
	}
	
	if ($response_make_ilias_order_ref->{error}){
            return $self->print_warning($response_make_ilias_order_ref->{error_description});
	}
	elsif ($response_make_ilias_order_ref->{successful}){
	    # TT-Data erzeugen
	    my $ttdata={
		database      => $database,
		unit          => $unit,
		label         => $label,
		ilias_order   => $response_make_ilias_order_ref,
	    };
	    
	    return $self->print_page($config->{tt_users_circulations_make_ilias_order_tname},$ttdata);
	    
	}		
    }
}

sub get_input_definition {
    my $self=shift;
    
    return {
        database => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        titleid => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        label => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        unit_desc => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        email => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        unit => {
            default  => '',
            encoding => 'utf8',
            type     => 'integer',
        },
        receipt => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        remark => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        period => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        articleauthor => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        articletitle => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        volume => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        issue => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        pages => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        realname => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        numbering => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        domain => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        subdomain => {
            default  => '',
            encoding => 'utf8',
            type     => 'scalar',
        },
        confirm => {
            default  => 0,
            encoding => 'utf8',
            type     => 'scalar',
        },
    };
}

1;
__END__

=head1 NAME

OpenBib::Circulation - Benutzerkonto

=head1 DESCRIPTION

Das mod_perl-Modul OpenBib::UserPrefs bietet dem Benutzer des 
Suchportals einen Einblick in das jeweilige Benutzerkonto und gibt
eine Aufstellung der ausgeliehenen, vorgemerkten sowie ueberzogenen
Medien.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
