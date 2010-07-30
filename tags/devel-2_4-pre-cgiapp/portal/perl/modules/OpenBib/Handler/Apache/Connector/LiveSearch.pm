####################################################################
#
#  OpenBib::Handler::Apache::Connector::LiveSearch.pm
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::Connector::LiveSearch;

use strict;
use warnings;
no warnings 'redefine';

use Apache2::Const -compile => qw(:common);
use Apache2::Reload;
use Apache2::Request ();
use Apache2::RequestIO (); # print
use Apache2::RequestRec (); # headers_in, headers_out, args
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

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $query  = Apache2::Request->new($r);
    
#     my $status=$query->parse;
    
#     if ($status){
#         $logger->error("Cannot parse Arguments");
#     }

    my $lang = "de"; # TODO: Ausweitung auf andere Sprachen

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($lang) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    my $word  = $query->param('q')     || '';
    my $type  = $query->param('type')  || '';
    my $exact = $query->param('exact') || '';
    
    if (!$word || $word=~/\d/){
        return Apache2::Const::OK;
    }

    if (!$exact){
        $word = "$word*";
    }

    my $view=$r->subprocess_env('openbib_view') || $config->{defaultview};
    
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

    $logger->debug("Request: $sql_request / Args: ".YAML::Dump(\@sql_args));
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
    
    $r->content_type("text/plain");
    
    if (@livesearch_suggestions){
        $r->print(join("\n",map {decode_utf8($_)} @livesearch_suggestions));
    }
    else {
        $logger->debug("No suggestions");
    }


    return Apache2::Const::OK;
}

1;
