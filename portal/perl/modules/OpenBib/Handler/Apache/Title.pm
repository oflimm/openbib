#####################################################################
#
#  OpenBib::Handler::Apache::Title.pm
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

package OpenBib::Handler::Apache::Title;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Log::Log4perl qw(get_logger :levels);

use OpenBib::Search::Local::Xapian;
use OpenBib::Record::Title;
use OpenBib::Template::Utilities;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('show_record');
    $self->run_modes(
        'show_collection_form'    => 'show_collection_form',
        'create_record'           => 'create_record',
        'update_record'           => 'update_record',
        'delete_record'           => 'delete_record',
        'show_record'             => 'show_record',
        'show_record_searchindex' => 'show_record_searchindex',
        'show_popular'            => 'show_popular',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_popular {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    
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
    
    my $statistics  = new OpenBib::Statistics();
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    my $utils       = new OpenBib::Template::Utilities;

    my $viewdesc      = $config->get_viewdesc_from_viewname($view);
    my $profile       = $config->get_viewinfo->search({ viewname => $view })->single()->profilename;
    
    # TT-Data erzeugen
    my $ttdata={
        database      => $database,
        profile       => $profile,
        viewdesc      => $viewdesc,
        dbinfo        => $dbinfotable,
        statistics    => $statistics,
        utils         => $utils,
    };

    my $templatename = "tt_title_popular".(($database)?'_by_database':'')."_tname";
    $self->print_page($config->{$templatename},$ttdata);

    return Apache2::Const::OK;
}

sub show_collection_form {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $database       = $self->param('database');

    # Shared Args
    my $config         = $self->param('config');

    if (!$self->is_authenticated('admin')){
        return;
    }

    my $ttdata={                #
        database => $database,
    };
    
    $self->print_page($config->{tt_title_collection_form_tname},$ttdata);

    return Apache2::Const::OK;
}

sub create_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $msg            = $self->param('msg');
    my $path_prefix    = $self->param('path_prefix');

    # CGI Args
    
    if (!$self->is_authenticated('admin')){
        return;
    }

    my $record = new OpenBib::Record::Title;
    $record->set_database($database);
    $record->set_from_apache_request($r);
    
    $self->query->method('GET');
    $self->query->headers_out->add(Location => "$path_prefix/$config->{title_loc}/$database/new.html");
    $self->query->status(Apache2::Const::REDIRECT);

    return;
}

sub show_record {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->strip_suffix($self->param('titleid'));

    # Shared Args
    my $query          = $self->query();
    my $r              = $self->param('r');
    my $config         = $self->param('config');
    my $session        = $self->param('session');
    my $user           = $self->param('user');
    my $msg            = $self->param('msg');
    my $lang            = $self->param('lang');
    my $queryoptions   = $self->param('qopts');
    my $stylesheet     = $self->param('stylesheet');
    my $useragent      = $self->param('useragent');

    # CGI Args
    my $stid          = $query->param('stid')              || '';
    my $callback      = $query->param('callback')  || '';
    my $queryid       = $query->param('queryid')   || '';
    my $format        = $query->param('format')    || 'full';
    my $no_log        = $query->param('no_log')    || '';

    my $dbinfotable   = OpenBib::Config::DatabaseInfoTable->instance;
    my $circinfotable = OpenBib::Config::CirculationInfoTable->instance;
    my $searchquery   = OpenBib::SearchQuery->instance;
    my $logintargetdb = $user->get_targetdb_of_session($session->{ID});

    if ($database && $titleid ){ # Valide Informationen etc.
        $logger->debug("ID: $titleid - DB: $database");
        
        my $record = OpenBib::Record::Title->new({database => $database, id => $titleid})->load_full_record;

        my $poolname=$dbinfotable->{dbnames}{$database};

        if ($queryid){
            $searchquery->load({sessionID => $session->{ID}, queryid => $queryid});
        }

        my ($prevurl,$nexturl)=OpenBib::Search::Util::get_result_navigation({
            session    => $session,
            database   => $database,
            titidn     => $titleid,
            view       => $view,
        });

        # Literaturlisten finden

        my $litlists_ref = $user->get_litlists_of_tit({titid => $titleid, titdb => $database});

        # Anreicherung mit OLWS-Daten
        if (defined $query->param('olws') && $query->param('olws') eq "Viewer"){
            if (exists $circinfotable->{$database} && exists $circinfotable->{$database}{circcheckurl}){
                $logger->debug("Endpoint: ".$circinfotable->{$database}{circcheckurl});
                my $soapresult;
                eval {
                    my $soap = SOAP::Lite
                        -> uri("urn:/Viewer")
                            -> proxy($circinfotable->{$database}{circcheckurl});
                
                    my $result = $soap->get_item_info(
                        SOAP::Data->name(parameter  =>\SOAP::Data->value(
                            SOAP::Data->name(collection => $circinfotable->{$database}{circdb})->type('string'),
                            SOAP::Data->name(item       => $titleid)->type('string'))));
                    
                    unless ($result->fault) {
                        $soapresult=$result->result;
                    }
                    else {
                        $logger->error("SOAP Viewer Error", join ', ', $result->faultcode, $result->faultstring, $result->faultdetail);
                    }
                };
                
                if ($@){
                    $logger->error("SOAP-Target konnte nicht erreicht werden :".$@);
                }
                
                $record->{olws}=$soapresult;
            }
        }

        # TT-Data erzeugen
        my $ttdata={
            database    => $database, # Zwingend wegen common/subtemplate
            dbinfo      => $dbinfotable,
            poolname    => $poolname,
            prevurl     => $prevurl,
            nexturl     => $nexturl,
            qopts       => $queryoptions->get_options,
            queryid     => $searchquery->get_id,
            record      => $record,
            titidn      => $titleid,

            format      => $format,

            searchquery => $searchquery,
            activefeed  => $config->get_activefeeds_of_db($self->{database}),
            
            logintargetdb => $logintargetdb,
            
            litlists          => $litlists_ref,
            highlightquery    => \&highlightquery,
        };

        $stid=~s/[^0-9]//g;
        my $templatename = ($stid)?"tt_title_".$stid."_tname":"tt_title_tname";
        
        $self->print_page($config->{$templatename},$ttdata);

        # Log Event

        my $isbn;
        
        if (exists $record->get_normdata->{T0540}[0]{content}){
            $isbn = $record->get_normdata->{T0540}[0]{content};
            $isbn =~s/ //g;
            $isbn =~s/-//g;
            $isbn =~s/X/x/g;
        }
        
        if (!$no_log){
            $session->log_event({
                type      => 10,
                content   => {
                    id       => $titleid,
                    database => $database,
                    isbn     => $isbn,
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

sub show_record_searchindex {
    my $self = shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    # Dispatched Args
    my $view           = $self->param('view');
    my $database       = $self->param('database');
    my $titleid        = $self->strip_suffix($self->param('titleid'));

    # Shared Args
    my $r              = $self->param('r');
    my $config         = $self->param('config');

    my $terms_ref  = OpenBib::Search::Local::Xapian->get_indexterms({ database => $database, id => $titleid });
    my $values_ref = OpenBib::Search::Local::Xapian->get_values({ database => $database, id => $titleid });

    my $ttdata = {
        terms  => $terms_ref,
        values => $values_ref,
    };
    
    $self->print_page($config->{'tt_title_searchindex_tname'},$ttdata);

    return Apache2::Const::OK;
}

sub highlightquery {
    my ($searchquery,$content) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Highlight Query

    my $term_ref = $searchquery->get_searchterms();

    return $content if (scalar(@$term_ref) <= 0);

    $logger->debug("Terms: ".YAML::Dump($term_ref));

    my $terms = join("|", grep /^\w{3,}/ ,@$term_ref);

    return $content if (!$terms);
    
    $logger->debug("Term_ref: ".YAML::Dump($term_ref)."\nTerms: $terms");
    $logger->debug("Content vor: ".$content);
    
    $content=~s/\b($terms)/<span class="queryhighlight">$1<\/span>/ig unless ($content=~/http/);

    $logger->debug("Content nach: ".$content);

    return $content;
}

1;
