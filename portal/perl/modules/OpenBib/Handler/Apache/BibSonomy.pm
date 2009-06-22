#####################################################################
#
#  OpenBib::Handler::Apache::BibSonomy.pm
#
#  Copyright 2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Handler::Apache::BibSonomy;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Const -compile => qw(:common REDIRECT);
use Apache2::Reload;
use Apache2::RequestRec ();
use Apache2::Request ();
use Benchmark ':hireswallclock';
use Encode qw/decode_utf8 encode_utf8/;
use DBI;
use Log::Log4perl qw(get_logger :levels);
use POSIX;
use Template;
use URI::Escape qw(uri_escape);

use OpenBib::BibSonomy;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

sub handler {
    my $r=shift;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config      = OpenBib::Config->instance;
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    
    my $query  = Apache2::Request->new($r);

    my $status = $query->parse;

    if ($status) {
        $logger->error("Cannot parse Arguments");
    }

    my $session   = OpenBib::Session->instance({
        sessionID => $query->param('sessionID'),
    });

    my $stylesheet=OpenBib::Common::Util::get_css_by_browsertype($r);
  
    #####################################################################
    # Konfigurationsoptionen bei <FORM> mit Defaulteinstellungen
    #####################################################################

    my $offset         = $query->param('offset')           || 0;
    my $hitrange       = $query->param('hitrange')         || 50;
    my $sorttype       = $query->param('sorttype')         || "author";
    my $sortorder      = $query->param('sortorder')        || "up";
    my $titisbn        = $query->param('titisbn')          || '';
    my $bibkey         = $query->param('bibkey')           || '';
    my $isbn           = $query->param('isbn')             || '';
    my $start          = $query->param('start')            || '';
    my $end            = $query->param('end')              || '';
    my $id             = $query->param('id')               || '';
    my $database       = $query->param('database')         || '';
    my $format         = decode_utf8($query->param('format')) || '';
    my $tag            = decode_utf8($query->param('tag')) || '';
    my $tags           = decode_utf8($query->param('tags')) || '';
    my $type           = decode_utf8($query->param('type')) || 'bibtex';
    my $bsuser         = decode_utf8($query->param('bsuser')) || '';
    my $stid           = $query->param('stid')             || '';

    my $action         = decode_utf8($query->param('action')) || '';
    
    #####                                                          ######
    ####### E N D E  V A R I A B L E N D E K L A R A T I O N E N ########
    #####                                                          ######
  
    ###########                                               ###########
    ############## B E G I N N  P R O G R A M M F L U S S ###############
    ###########                                               ###########

    my $queryoptions = OpenBib::QueryOptions->instance($query);

    my $useragent=$r->subprocess_env('HTTP_USER_AGENT');

    # Message Katalog laden
    my $msg = OpenBib::L10N->get_handle($queryoptions->get_option('l')) || $logger->error("L10N-Fehler");
    $msg->fail_with( \&OpenBib::L10N::failure_handler );
    
    if (!$session->is_valid()){
        OpenBib::Common::Util::print_warning($msg->maketext("Ungültige Session"),$r,$msg);

        return Apache2::Const::OK;
    }
    
    my $view="";

    if ($query->param('view')) {
        $view=$query->param('view');
    }
    else {
        $view=$session->get_viewname();
    }

    if ($action eq "get_tags"){
        my @local_tags=split('\s+',$tags);
        if (defined $bibkey || @local_tags){
            my @tags = ();
            @tags = OpenBib::BibSonomy->new()->get_tags({ bibkey => $bibkey, tags => \@local_tags}) if ($bibkey=~/^1[0-9a-f]{32}$/);

            $logger->debug(YAML::Dump(\@tags));
            
            # TT-Data erzeugen
            my $ttdata={
                tags          => \@tags,
                view          => $view,
                format        => $format,
                stylesheet    => $stylesheet,
                sessionID     => $session->{ID},
                session       => $session,
                useragent     => $useragent,
                config        => $config,
                msg           => $msg,
            };
            
            $stid=~s/[^0-9]//g;
            
            my $templatename = ($stid)?"tt_bibsonomy_showtags_".$stid."_tname":"tt_bibsonomy_showtags_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
            return Apache2::Const::OK;
        }
    }
    elsif ($action eq "get_tit_of_tag"){
        if ($tag){
            my $posts_ref = OpenBib::BibSonomy->new()->get_posts({ tag => encode_utf8($tag) ,start => $start, end => $end , type => $type});
            
            if ($type eq "bibtex"){
                # Anreichern mit KUG-Verfuegbarkeit

                # Verbindung zur SQL-Datenbank herstellen
                my $enrichdbh
                = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                    or $logger->error_die($DBI::errstr);

                my $request = $enrichdbh->prepare("select distinct dbname from all_isbn where isbn=?");

                $logger->debug(YAML::Dump($posts_ref));
                foreach my $post_ref (@{$posts_ref->{recordlist}}){
                    my $bibkey = $post_ref->{bibkey};
                    $request->execute($bibkey);
                    $logger->debug("Single Post:".YAML::Dump($post_ref));
                    $logger->debug("Single Post-Bibkey:$bibkey");
                    my @local_dbs = ();
                    while (my $result=$request->fetchrow_hashref){
                        push @local_dbs,$result->{dbname};
                    }
                    if (@local_dbs){
                        $post_ref->{local_availability} = 1;
                        $post_ref->{local_dbs}          = \@local_dbs;
                    
                    }
                    else {
                        $post_ref->{local_availability} = 0;
                    }       
                }
                $enrichdbh->disconnect;
            }

            $logger->debug(YAML::Dump($posts_ref));
            
            # TT-Data erzeugen
            my $ttdata={
                posts         => $posts_ref,
                start         => $start,
                tag           => $tag,
                type          => $type,
                format        => $format,
                dbinfo        => $dbinfotable,
                view          => $view,
                stylesheet    => $stylesheet,
                sessionID     => $session->{ID},
                session       => $session,
                useragent     => $useragent,
                config        => $config,
                msg           => $msg,
            };
            
            $stid=~s/[^0-9]//g;
            
            my $templatename = ($stid)?"tt_bibsonomy_showtitlist_".$stid."_tname":"tt_bibsonomy_showtitlist_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
            return Apache2::Const::OK;
        }
    }
    elsif ($action eq "get_tit_of_user"){
        if ($bsuser){
            my $posts_ref = OpenBib::BibSonomy->new()->get_posts({ user => $bsuser ,start => $start, end => $end , type => $type});

            # Anreichern mit KUG-Verfuegbarkeit

            # Verbindung zur SQL-Datenbank herstellen
            my $enrichdbh
            = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
                or $logger->error_die($DBI::errstr);

            my $request = $enrichdbh->prepare("select distinct dbname from all_isbn where isbn=?");

            $logger->debug(YAML::Dump($posts_ref));
            foreach my $post_ref (@{$posts_ref->{recordlist}}){
                my $bibkey = $post_ref->{bibkey} || 'undefined';
                $request->execute($bibkey);
                $logger->debug("Single Post:".YAML::Dump($post_ref));
                $logger->debug("Single Post-Bibkey:$bibkey");
                my @local_dbs = ();
                while (my $result=$request->fetchrow_hashref){
                    push @local_dbs,$result->{dbname};
                }
                if (@local_dbs){
                    $post_ref->{local_availability} = 1;
                    $post_ref->{local_dbs}          = \@local_dbs;
                    
                }
                else {
                    $post_ref->{local_availability} = 0;
                }       
            }

            $enrichdbh->disconnect;
            
            $logger->debug(YAML::Dump($posts_ref));
            
            # TT-Data erzeugen
            my $ttdata={
                posts         => $posts_ref,
                tag           => $tag,
                bsuser        => $bsuser,
                format        => $format,
                type          => $type,
                dbinfo        => $dbinfotable,
                view          => $view,
                stylesheet    => $stylesheet,
                sessionID     => $session->{ID},
                session       => $session,
                useragent     => $useragent,
                config        => $config,
                msg           => $msg,
            };
            
            $stid=~s/[^0-9]//g;
            
            my $templatename = ($stid)?"tt_bibsonomy_showtitlist_".$stid."_tname":"tt_bibsonomy_showtitlist_tname";
            
            OpenBib::Common::Util::print_page($config->{$templatename},$ttdata,$r);
            
            return Apache2::Const::OK;
        }
    }
    elsif ($action eq "add_title"){
        if ($id && $database){
            my $title = uri_escape(OpenBib::Record::Title->new({id =>$id, database => $database})->load_full_record->to_bibtex);
            
            my $bibsonomy_uri = "$config->{redirect_loc}/$session->{ID}/510/http://www.bibsonomy.org/BibtexHandler?requTask=upload&url=http%3A%2F%2Fkug.ub.uni-koeln.de%2F&description=KUG%20Recherche-Portal&encoding=ISO-8859-1&selection=selection=$title";

            $logger->debug($bibsonomy_uri);
            
            $r->content_type('text/html');
            $r->headers_out->add("Location" => $bibsonomy_uri);
            
            return Apache2::Const::REDIRECT;
        }
    }
    
    OpenBib::Common::Util::print_warning($msg->maketext("Keine gültige Aktion"),$r,$msg);

    return Apache2::Const::OK;
}

1;
