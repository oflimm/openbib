#####################################################################
#
#  OpenBib::Handler::Apache::BibSonomy.pm
#
#  Copyright 2008-2011 Oliver Flimm <flimm@openbib.org>
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
use URI::Escape qw(uri_escape uri_escape_utf8);

use OpenBib::BibSonomy;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::QueryOptions;
use OpenBib::Session;
use OpenBib::User;

use base 'OpenBib::Handler::Apache';

# Run at startup
sub setup {
    my $self = shift;

    $self->start_mode('lookup');
    $self->run_modes(
        'show_tags'               => 'show_tags',
        'show_collection'         => 'show_collection',
        'show_collection_by_tag'  => 'show_collection_by_tag',
        'show_collection_by_user' => 'show_collection_by_user',
        'create_record'           => 'create_record',
    );

    # Use current path as template path,
    # i.e. the template is in the same directory as this script
#    $self->tmpl_path('./');
}

sub show_tags {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    

    # CGI Args
    my $tags   = $query->param('tags');
    my $bibkey = $query->param('bibkey');
    my $format = $query->param('format');

    my @local_tags=split('\s+', $tags);
    
    if (defined $bibkey || @local_tags){
        my @tags = ();
        @tags = OpenBib::BibSonomy->new()->get_tags({ bibkey => $bibkey, tags => \@local_tags}); # if ($bibkey=~/^1[0-9a-f]{32}$/);

        $logger->debug(YAML::Dump(\@tags));
            
        # TT-Data erzeugen
        my $ttdata={
            tags          => \@tags,
            format        => $format,
        };
        
        $self->print_page($config->{tt_bibsonomy_tags_tname},$ttdata);
        
        return Apache2::Const::OK;
    }

    return;
}

sub show_collection {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $type           = $self->strip_suffix($self->param('type'))           || 'publication';
    
    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    
    # CGI Args
    my $format = $query->param('format');
    my $start  = $query->param('start');
    my $end    = $query->param('end');
    my $method = $query->param('_method');

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    
    my $posts_ref = OpenBib::BibSonomy->new()->get_posts({ start => $start, end => $end , type => $type});
    
    if ($type eq "publication"){

        if ($method eq "POST"){
            $self->create_record;
            return;
        }
        
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
        type          => $type,
        format        => $format,
        dbinfo        => $dbinfotable,
    };
    
    $self->print_page($config->{tt_bibsonomy_collection_tname},$ttdata);
    
    return Apache2::Const::OK;
}

sub show_collection_by_tag {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatched Args
    my $view           = $self->param('view')           || '';
    my $type           = $self->param('type')           || 'publication';
    my $tag            = $self->strip_suffix($self->param('tagid'));
    
    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
    
    # CGI Args
    my $format = $query->param('format');
    my $start  = $query->param('start');
    my $end    = $query->param('end');

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    
    if ($tag){
        my $posts_ref = OpenBib::BibSonomy->new()->get_posts({ tag => encode_utf8($tag) ,start => $start, end => $end , type => $type});
        
        if ($type eq "publication"){
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
        };
        
        $self->print_page($config->{tt_bibsonomy_collection_by_tag_tname},$ttdata);
        
        return Apache2::Const::OK;
    }
    
    return;    
}

sub show_collection_by_user {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatches Args
    my $view           = $self->param('view')           || '';
    my $type           = $self->param('type')           || 'publication';
    my $bsuser         = $self->strip_suffix($self->param('userid'));

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');    
        
    # CGI Args
    my $format = $query->param('format');
    my $start  = $query->param('start');
    my $end    = $query->param('end');

    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;
    
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
            bsuser        => $bsuser,
            format        => $format,
            type          => $type,
            dbinfo        => $dbinfotable,
        };
        
        $self->print_page($config->{tt_bibsonomy_collection_by_user_tname},$ttdata);
        
        return Apache2::Const::OK;
    }
}

sub create_record {
    my $self = shift;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();
    
    # Dispatches Args
    my $view           = $self->param('view')           || '';

    # Shared Args
    my $query          = $self->query();
    my $config         = $self->param('config');
    my $path_prefix    = $self->param('path_prefix');
    my $servername     = $self->param('servername');

    # CGI Args
    my $id         = $query->param('id');
    my $database   = $query->param('db');
    
    my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

    if ($id && $database){
        my $title = OpenBib::Record::Title->new({id =>$id, database => $database})->load_full_record->to_bibtex({utf8 => 1});
#        $title=~s/\n/ /g;
        
        my $bibsonomy_uri = "$path_prefix/$config->{redirect_loc}/510/http://www.bibsonomy.org/BibtexHandler?requTask=upload&url=".uri_escape_utf8("http://$servername$path_prefix/$config->{home_loc}")."&description=".uri_escape_utf8($config->get_viewdesc_from_viewname($view))."&encoding=UTF-8&selection=".uri_escape_utf8($title);
#        my $bibsonomy_uri = "$path_prefix/$config->{redirect_loc}/510/http://www.bibsonomy.org/BibtexHandler?requTask=upload&encoding=UTF-8&url=http%3A%2F%2Fkug.ub.uni-koeln.de%2F&description=KUG Recherche-Portal&selection=".uri_escape_utf8($title);
        
        $logger->debug($bibsonomy_uri);

        $self->query->method('GET');
        $self->query->content_type('text/html; charset=UTF-8');
        $self->query->headers_out->add(Location => $bibsonomy_uri);
        $self->query->status(Apache2::Const::REDIRECT);
        
#        $self->header_type('redirect');
#        $self->header_props(-type => 'text/html', -url => $bibsonomy_uri);
        
    }

    return;
}

1;
