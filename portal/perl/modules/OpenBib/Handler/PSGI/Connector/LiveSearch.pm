####################################################################
#
#  OpenBib::Handler::PSGI::Connector::LiveSearch.pm
#
#  Dieses File ist (C) 2008-2012 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::PSGI::Connector::LiveSearch;

use strict;
use warnings;
no warnings 'redefine';

use Benchmark;
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Template;
use Text::Aspell;

use OpenBib::Config;
use OpenBib::Common::Util;
use OpenBib::L10N;
use OpenBib::Search::Util;
use OpenBib::Session;
use OpenBib::Search::Factory;
use OpenBib::Search::Backend::Xapian;
use OpenBib::Search::Backend::ElasticSearch;
use OpenBib::Search::Backend::Z3950;
use OpenBib::Search::Backend::EZB;
use OpenBib::Search::Backend::DBIS;
use OpenBib::Search::Backend::BibSonomy;
use OpenBib::SearchQuery;

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
    my $lang           = $self->param('lang');
    my $msg            = $self->param('msg');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    my $word  = $query->param('q')     || '';
    my $type  = $query->param('type')  || '';
    my $exact = $query->param('exact') || '';
    
    if (!$word || $word=~/\d/){
        $self->header_add('Status',200); # ok
        return;
    }

    if (!$exact){
        $word = "$word*";
    }

    my @databases     = $config->get_viewdbs($view);
    my $searchprofile = $config->get_searchprofile_or_create(\@databases);
    

    my $searchquery = OpenBib::SearchQuery->new({ view => $view, config => $config});
    $searchquery->set_searchfield('freesearch',$word);
    $searchquery->set_searchprofile($searchprofile);

    $self->param('searchquery',$searchquery);
    
    my $search_args_ref = {};
    $search_args_ref->{authority}    = 1;
    $search_args_ref->{searchquery}  = $searchquery if (defined $searchquery);
    $search_args_ref->{config}       = $config if (defined $config);
    $search_args_ref->{queryoptions} = $queryoptions if (defined $queryoptions);

    my $searcher = OpenBib::Search::Factory->create_searcher($search_args_ref);

    $searcher->search;

    $searchquery->set_hits($searcher->get_resultcount);

    my $recordlist;

    if ($searcher->have_results) {
        $recordlist = $searcher->get_records();	
    }

    my $ttdata={        
        searchquery     => $searchquery,
        
        qopts           => $queryoptions->get_options,
        queryoptions    => $queryoptions,
        
        query           => $query,

        recordlist      => $recordlist,
    };
    
    $ttdata = $self->add_default_ttdata($ttdata);

    my $content = "";

    my $templatename = $config->get('tt_connector_livesearch_tname');
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => '',
        view         => $ttdata->{view},
        profile      => $ttdata->{sysprofile},
        templatename => $templatename,
    });
    
    # Start der Ausgabe mit korrektem Header
    # $r->content_type($ttdata->{content_type});
    
    # Es kann kein Datenbankabhaengiges Template geben
    
    my $itemtemplate = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
        #                INCLUDE_PATH   => $config->{tt_include_path},
        #                ABSOLUTE       => 1,
        RECURSION      => 1,
        OUTPUT         => \$content,
    });            

    $itemtemplate->process($templatename, $ttdata) || do {
        $logger->error("Process error for resultitem: ".$itemtemplate->error());
        $self->header_add('Status',400); # server error
        return;
    };

    $logger->debug("Printed: $content");
    
    return $content;
    
    my $viewdb_lookup_ref = {};
    foreach my $viewdb ($config->get_viewdbs($view)){
        $viewdb_lookup_ref->{$viewdb}=1;
    }

    my @livesearch_suggestions = ();

    # Verbindung zur SQL-Datenbank herstellen
    my $enrichdbh
        = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
            or $logger->error_die($DBI::errstr);

    my $in_select_string = join(',',map {'?'} keys %{$viewdb_lookup_ref});
    
    my $sql_request = "select distinct content,type from all_normdata where dbname in ($in_select_string) and match (fs) against (? in boolean mode)";
    
    my @sql_args = (keys %{$viewdb_lookup_ref},$word);
    
    if ($type){
        $sql_request.=" and type = ?";
        push @sql_args, $type;
    }

    if ($logger->is_debug){
        $logger->debug("Request: $sql_request / Args: ".YAML::Dump(\@sql_args));
    }
    
    my $request=$enrichdbh->prepare($sql_request);

    $request->execute(@sql_args);

    while (my $result=$request->fetchrow_hashref){
        my $suggestion      = $result->{content};
        my $suggestion_type = $result->{type};

        $suggestion =~s/&gt;//g;
        $suggestion =~s/&lt;//g;
        $suggestion =~s/<//g;
        $suggestion =~s/>//g;
        
        push @livesearch_suggestions, $suggestion;
    }

    $logger->debug("LiveSearch for word $word and type $type");
    
    $self->header_add('Content-Type',"text/plain");
    
    if (@livesearch_suggestions){
        return join("\n",map {decode_utf8($_)} @livesearch_suggestions);
    }
    else {
        $logger->debug("No suggestions");
    }

    return;
}

1;
