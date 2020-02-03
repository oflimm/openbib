####################################################################
#
#  OpenBib::Handler::PSGI::Connector::DAIA.pm
#
#  Dieses File ist (C) 2020- Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Connector::DAIA;

use strict;
use warnings;
no warnings 'redefine';

use URI;
use URI::Escape;

use Benchmark;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use Template;
use Encode 'decode_utf8';
use JSON::XS qw/encode_json/;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Enrichment;
use OpenBib::L10N;
use OpenBib::Record::Title;
use OpenBib::Search::Util;
use OpenBib::Session;

use base 'OpenBib::Handler::PSGI';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show');
    $self->run_modes(
        'show'       => 'show',
        'dispatch_to_representation'           => 'dispatch_to_representation',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show {
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
    my $lang           = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $id          = $query->param('id')        || '';
    my $format      = $query->param('format')    || '';
    my $callback    = $query->param('callback')  || '';
    my $patron      = $query->param('patron')    || '';
    my $patrontype  = $query->param('patron-type')    || '';
    my $accesstoken = $query->param('access_token')    || '';
    my $suppressresponsecodes = $query->param('suppress-response-codes')    || '';

    $self->header_add('X-DAIA-Version' => '1.0.0');
    $self->header_add('Content-Language' => $lang);

    if ($format && $format ne 'json'){
	my $response_ref = {
	    error => 'Missing or invalid query parameters',
	    code  => 422
	};
	
	if ($suppressresponsecodes){
	    $self->header_add('Status' => 200); # ok
	}
	else {
	    $self->header_add('Status' => 422); # invalid request
	    
	}

	return decode_utf8(encode_json $response_ref);
    }    

    my @request_ids = ();
    
    if ($id =~m/\\|/){ # multiple
	$logger->debug("Mutliple");
	@request_ids = split("\\|",$id);
    }
    else {
	push @request_ids, $id;
    }

    $logger->debug(YAML::Dump(\@request_ids));

    my $all_items_ref = [];

    foreach my $request_id (@request_ids){
	my ($thisdb,$thisid)=split(':',$request_id);

	
	my $record = new OpenBib::Record::Title({ database => $thisdb, id => $thisid})->load_circulation;
	my $circulation_ref = $record->get_circulation;
	
	my $item_ref = {
	    id => $thisid,
	    database => $thisdb,
	    circulation => $circulation_ref,
	};
	
	push @$all_items_ref,  $item_ref;
	
	$logger->debug("Circ: ".YAML::Dump($item_ref));
    }

    my $ttdata={
	timestamp => $self->get_timestamp,
	items     => $all_items_ref,
    };
    
    return $self->print_page($config->{tt_connector_daia_tname},$ttdata);
}

sub get_timestamp {
    my $self = shift;
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $timestamp = sprintf ( "%04d-%02d-%02dT%02d:%02d:%02dZ",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $timestamp;
}

1;
