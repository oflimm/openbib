#####################################################################
#
#  OpenBib::Handler::PSGI::Users::Circulations::CampusOrders
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

package OpenBib::Handler::PSGI::Users::Circulations::CampusOrders;

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
use URI::Escape qw(uri_unescape);

use OpenBib::API::HTTP::JOP;
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
    my $userid         = $self->param('userid');
    
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
    my $validtarget    = $input_data_ref->{'validtarget'};
    my $titleid        = $input_data_ref->{'titleid'};
    my $label          = $input_data_ref->{'label'};
    my $unit_desc      = $input_data_ref->{'unit_desc'};
    my $domain         = $input_data_ref->{'domain'};
    my $subdomain      = $input_data_ref->{'subdomain'};
    my $receipt        = $input_data_ref->{'receipt'};
    my $unit           = $input_data_ref->{'unit'};
    my $volume         = $input_data_ref->{'volume'};
    my $articleauthor  = $input_data_ref->{'articleauthor'};
    my $articletitle   = $input_data_ref->{'artitletitle'};
    my $issue          = $input_data_ref->{'issue'};
    my $pages          = $input_data_ref->{'pages'};
    my $remark         = $input_data_ref->{'remark'};
    my $numbering      = $input_data_ref->{'numbering'};
    my $refid          = $input_data_ref->{'refid'};
    my $confirm        = $input_data_ref->{'confirm'};
   
    unless ($config->get('active_campusorder')){
	return $self->print_warning($msg->maketext("Der Campuslieferdienst ist aktuell systemweit deaktiviert."));	
    }

    if ($logger->is_debug){
	$logger->debug("Input: ".YAML::Dump($input_data_ref));
    }
    
    unless ($validtarget && $label && $unit >= 0 && $titleid){
	return $self->print_warning($msg->maketext("Notwendige Parameter nicht besetzt")." (validtarget: $validtarget, label:$label, unit:$unit)");
    }
    
    my $sessionauthenticator = $user->get_targetdb_of_session($session->{ID});
    my $sessionuserid        = $user->get_userid_of_session($session->{ID});

    $self->param('userid',$sessionuserid);
    
    if ($logger->debug){
	$logger->debug("Auth successful: ".$self->authorization_successful." - Authenticator: $sessionauthenticator");
    }
    
    if (!$self->authorization_successful || $userid ne $sessionuserid){
        if ($self->param('representation') eq "html"){
            return $self->tunnel_through_authenticator('POST');            
        }
        else  {
            return $self->print_warning($msg->maketext("Sie muessen sich authentifizieren"));
        }
    }

    my ($accountname,$password,$access_token) = $user->get_credentials();

    unless ($accountname =~ m/^(B|S)/){
	return $self->print_warning($msg->maketext("Sie gehören nicht zu den autorisierten Nutzergruppen für den Campuslieferdienst"));
    }
    
    my $database              = $sessionauthenticator;

    my $ils = OpenBib::ILS::Factory->create_ils({ database => $database });

    my $authenticator = $session->get_authenticator;

    my $userinfo_ref = $ils->get_userdata($accountname);

    my $record = new OpenBib::Record::Title({ database => $database, id => $titleid });
    $record->load_full_record;
    
    if ($confirm){
	$logger->debug("Showing campus orderform");
	
	# TT-Data erzeugen
	my $ttdata={
	    userinfo       => $userinfo_ref,
	    record         => $record,
	    database       => $database,
	    validtarget    => $validtarget,
	    titleid        => $titleid,
	    numbering      => $numbering,
	    label          => $label,
	    articleauthor  => $articleauthor,
	    articletitle   => $articletitle,
	    volume         => $volume,
	    issue          => $issue,
	    pages          => $pages,
	    refid          => $refid,
	    userid         => $userid,
	    receipt        => $receipt,
	    remark         => $remark,
	    unit           => $unit,
	    unit_desc      => $unit_desc,
	    domain         => $domain,
	    subdomain      => $subdomain	    
	};
	
	return $self->print_page($config->{tt_users_circulations_check_campus_order_tname},$ttdata);
    }
    else {
	$logger->debug("Making campus order");

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
	
	if (!$userinfo_ref->{email}){
	    return $self->print_warning("Zur Nutzung des Campuslieferdienstes ist eine E-Mail-Adresse in Ihrem Bibliothekskonto erforderlich.");
	}
	
	if (!$titleid){
	    return $self->print_warning("Fehler bei der Übertragung der Datensatz-ID.");
	}
	
	if (!$label){
	    return $self->print_warning("Fehler bei der Übertragung der Signatur.");
	}
	
	if (!$title){
	    return $self->print_warning("Fehler bei der Übertragung des Titels.");
	}
	
	# Ueberpruefen auf elektronische Verfuegbarkeit via JOP
	if ($issn){
	    my $jopquery = new OpenBib::SearchQuery;
	    
	    $jopquery->set_searchfield('issn',$issn) if ($issn);
	    $jopquery->set_searchfield('volume',$volume) if ($volume);
	    $jopquery->set_searchfield('issue',$issue) if ($issue);
	    $jopquery->set_searchfield('pages',$pages) if ($pages);
	    $jopquery->set_searchfield('date',$year) if ($year);
	    
	    if ($title){
		$jopquery->set_searchfield('genre','article');
	    }
	    elsif ($volume){
		$jopquery->set_searchfield('genre','article');
	    }
	    else {
		$jopquery->set_searchfield('genre','journal');
	    }
	    
	    # bibid set via portal.yml
	    my $api = OpenBib::API::HTTP::JOP->new({ searchquery => $jopquery });
	    
	    my $search = $api->search();
	    
	    my $result_ref = $search->get_search_resultlist;
	    
	    my $jop_online = 0;
	    
	    foreach my $item_ref (@$result_ref){
		if ($item_ref->{type} eq "online" && $item_ref->{state} =~m/^(0|2)$/){ # nur gruene und gelbe Titel beruecksichtigen, d.h. im Zweifelsfall wird die Bestellung durchgelassen
		    $jop_online = 1;
		}	    
	    }
	    
	    if ($jop_online){

		$logger->debug("Found for issn $issn in JOP");
		
		# TT-Data erzeugen
		my $ttdata={
		    database      => $database,
		    unit          => $unit,
		    label         => $label,
		    validtarget   => $validtarget,
		    jop_online    => $jop_online,
		    jop           => $result_ref,
		};
		
		return $self->print_page($config->{tt_users_circulations_make_campus_order_tname},$ttdata);
	    }
	}
	# Ueberpruefen auf elektronische Verfuegbarkeit an der UzK (KUG)	
	elsif ($isbn){
	    my $online_media = $self->check_online_media({ view => 'unikatalog', isbn => $isbn});

	    if ($online_media->get_size() > 0){

		$logger->debug("Got Online-Media for isbn $isbn");
		
		# TT-Data erzeugen
		my $ttdata={
		    database      => $database,
		    unit          => $unit,
		    label         => $label,
		    validtarget   => $validtarget,
		    uzk_online    => 1,
		    online_media  => $online_media,
		};
		
		return $self->print_page($config->{tt_users_circulations_make_campus_order_tname},$ttdata);
	    }

	}

	# Wesentliche Informationen zur Identitaet des Bestellers werden nicht per Webformular entgegen genommen,
	# sondern aus dem Bibliothekskonto des Nutzers via $userinfo_ref.
	
	# Production
	my $response_make_campus_order_ref = $ils->make_campus_order({ title => uri_unescape($title), titleid => $titleid, author => uri_unescape($author), coporation => uri_unescape($corporation), publisher => uri_unescape($publisher), year => $year, numbering => $numbering, label => uri_unescape($label), isbn => $isbn, issn => $issn, articleauthor => uri_unescape($articleauthor), articletitle => uri_unescape($articletitle), volume => $volume, issue => $issue, pages => $pages, refid => $refid, userid => uri_unescape($userinfo_ref->{username}), username => $userinfo_ref->{fullname}, receipt => $receipt, email => $userinfo_ref->{email}, remark => uri_unescape($remark), unit => $unit, location => $unit_desc, domain => $domain, subdomain => $subdomain });

	# Test
#	my $response_make_campus_order_ref = {
#	    successful => 1,
#	};
    	
	if ($logger->is_debug){
	    $logger->debug("Result make_order:".YAML::Dump($response_make_campus_order_ref));	
	}
	
	if ($response_make_campus_order_ref->{error}){
            return $self->print_warning($response_make_campus_order_ref->{error_description});
	}
	elsif ($response_make_campus_order_ref->{successful}){
	    # TT-Data erzeugen
	    my $ttdata={
		database      => $database,
		unit          => $unit,
		label         => $label,
		validtarget   => $validtarget,
		campus_order  => $response_make_campus_order_ref,
	    };
	    
	    return $self->print_page($config->{tt_users_circulations_make_campus_order_tname},$ttdata);
	    
	}		
    }
}

sub get_input_definition {
    my $self=shift;
    
    return {
        validtarget => {
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
            default  => 0,
            encoding => 'utf8',
            type     => 'scalar',
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
