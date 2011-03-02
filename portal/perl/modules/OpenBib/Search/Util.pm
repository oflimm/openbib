#####################################################################
#
#  OpenBib::Search::Util
#
#  Dieses File ist (C) 2004-2008 Oliver Flimm <flimm@openbib.org>
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

package OpenBib::Search::Util;

use strict;
use warnings;
no warnings 'redefine';
use utf8;

use Apache2::Reload;
use Apache2::Request ();
use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use JSON::XS qw(encode_json decode_json);
use List::MoreUtils qw(after before);
use Log::Log4perl qw(get_logger :levels);
use MIME::Base64 ();
use SOAP::Lite;
use Storable;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::CirculationInfoTable;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::QueryOptions;
use OpenBib::Record::Title;
use OpenBib::RecordList::Title;
use OpenBib::Session;
use OpenBib::VirtualSearch::Util;

sub get_result_navigation {
    my ($arg_ref) = @_;

    # Set defaults
    my $database              = exists $arg_ref->{database}
        ? $arg_ref->{database}              : undef;
    my $titidn                = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}                : undef;
    my $hitrange              = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}              : undef;
    my $sortorder             = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}             : undef;
    my $sorttype              = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}              : undef;
    my $view                  = exists $arg_ref->{view}
        ? $arg_ref->{view}                  : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;
    my $session = OpenBib::Session->instance;

    # Bestimmen des vorigen und naechsten Treffer einer
    # vorausgegangenen Kurztitelliste

    my $lastresultstring = $session->get_lastresultset();

    my $lasttiturl="";
    my $nexttiturl="";

    if ($lastresultstring){
        my $lastresult_ref = decode_json($lastresultstring);
        my @lastresult = @{$lastresult_ref};
        
        
        my @previous = before { $_->{database} eq $database && $_->{id} eq $titidn} @lastresult;
        
        my @last=(exists $previous[-1])?$previous[-1]:();
        
        my @after = after { $_->{database} eq $database && $_->{id} eq $titidn} @lastresult;
        my @next=(exists $after[0])?$after[0]:();
        
        if (@last) {
            $lasttiturl="$config->{base_loc}/$view/$config->{handler}{resource_title_loc}{name}/$last[0]->{database}/$last[0]->{id}/";
        }
        
        if (@next) {
            $nexttiturl="$config->{base_loc}/$view/$config->{handler}{resource_title_loc}{name}/$next[0]->{database}/$next[0]->{id}/";
        }
    }
    
    return ($lasttiturl,$nexttiturl);
}

sub get_index {
    my ($arg_ref) = @_;

    # Set defaults
    my $type              = exists $arg_ref->{type}
        ? $arg_ref->{type}              : undef;
    my $category          = exists $arg_ref->{category}
        ? $arg_ref->{category}          : undef;
    my $contentreq        = exists $arg_ref->{contentreq}
        ? $arg_ref->{contentreq}        : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    my $type_ref = {
        tit            => 1,
        aut            => 2,
        kor            => 3,
        swt            => 4,
        notation       => 5,
        mex            => 6,
    };
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }

    my @contents=();
    {
        my $sqlrequest;
        # Normdaten-String-Recherche
        if ($contentreq=~/^\^/){
            substr($contentreq,0,1)="";
            $contentreq=~s/\*$/\%/;
            $sqlrequest="select distinct ${type}.content as content from $type, ${type}_string where ${type}.category = ? and ${type}_string.category = ? and ${type}_string.content like ? and ${type}.id=${type}_string.id order by ${type}.content";
        }
        # Normdaten-Volltext-Recherche
        else {
            $sqlrequest="select distinct ${type}.content as content from $type, ${type}_ft where ${type}.category = ? and ${type}_ft.category = ? and match (${type}_ft.content) against (? IN BOOLEAN MODE) and ${type}.id=${type}_ft.id order by ${type}.content";
            $contentreq = OpenBib::VirtualSearch::Util::conv2autoplus($contentreq);
        }
        $logger->info($sqlrequest." - $category, $contentreq");
        my $request=$dbh->prepare($sqlrequest);
        $request->execute($category,$category,$contentreq);

        while (my $res=$request->fetchrow_hashref){
            push @contents, {
                content     => decode_utf8($res->{content}),
            };
        }
        $request->finish();

        $logger->debug("Index-Worte: ".YAML::Dump(\@contents))
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : ".($#contents+1)." Begriffe (Bestimmung): ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    $logger->debug("INDEX-Contents (".($#contents+1)." Begriffe): ".YAML::Dump(\@contents));


    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    my @index=();

    foreach my $content_ref (@contents){
        my ($atime,$btime,$timeall);

        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        my @ids=();
        {
            my $sqlrequest="select distinct id from ${type} where category = ? and content = ?";
            my $request=$dbh->prepare($sqlrequest);
            $request->execute($category,$content_ref->{content});

            while (my $res=$request->fetchrow_hashref){
                push @ids, $res->{id};
            }
            $request->finish();
        }

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : ".($#ids+1)." ID's (Art): ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }

        {
            my $sqlrequest="select count(distinct sourceid) as conncount from conn where targetid=? and sourcetype=1 and targettype=?";
            my $request=$dbh->prepare($sqlrequest);
            
            foreach my $id (@ids){
                $request->execute($id,$type_ref->{$type});
                my $res=$request->fetchrow_hashref;
                my $titcount=$res->{conncount};

                push @index, {
                    content   => $content_ref->{content},
                    id        => $id,
                    titcount  => $titcount,
                };
            }
            $request->finish();
        }

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : ".($#ids+1)." ID's (Anzahl): ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }

    }
    
    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : ".($#index+1)." Begriffe (Vollinformation): ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    return \@index;
}

sub print_index_by_swt {
    my ($arg_ref) = @_;

    # Set defaults
    my $swt               = exists $arg_ref->{swt}
        ? $arg_ref->{swt}               : undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}               : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $r                 = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}         : undef;
    my $stylesheet        = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}        : undef;
    my $view              = exists $arg_ref->{view}
        ? $arg_ref->{view}              : undef;
    my $msg                = exists $arg_ref->{msg}
        ? $arg_ref->{msg}                : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config       = OpenBib::Config->instance;
    my $session      = OpenBib::Session->instance;
    my $queryoptions = OpenBib::QueryOptions->instance;
    my $dbinfotable  = OpenBib::Config::DatabaseInfoTable->instance;
    
    my $swtindex=OpenBib::Search::Util::get_index({
        type       => 'swt',
        category   => '0001',
        contentreq => $swt,
        dbh        => $dbh,
    });

    my $poolname=$dbinfotable->{sigel}{$dbinfotable->{dbases}{$database}};

    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        database   => $database,
        poolname   => $poolname,
        qopts      => $queryoptions->get_options,
        sessionID  => $session->{ID},
        swt        => $swt,
        swtindex   => $swtindex,

        config     => $config,
        msg        => $msg,

    };
  
    OpenBib::Common::Util::print_page($config->{tt_search_showswtindex_tname},$ttdata,$r);

    return;
}

sub get_recent_titids {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $database               = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;

    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
    }

    my $request=$dbh->prepare("select id,content from title_string where category=2 order by content desc limit $limit");
    $request->execute();

    my $recordlist = new OpenBib::RecordList::Title();

    while (my $res=$request->fetchrow_hashref()){
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}, date => $res->{content}}));
    }
    
    $dbh->disconnect;

    return $recordlist;
}

sub get_recent_titids_by_aut {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $database               = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
    }

    my $request=$dbh->prepare("select title_string.id as id,title_string.content as content from title_string,conn where conn.targetid = ? and title_string.category=2 and title_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 2 order by content desc limit $limit");
    $request->execute($id);

    my $recordlist = new OpenBib::RecordList::Title();

    while (my $res=$request->fetchrow_hashref()){
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}, date => $res->{content}}));
    }
    
    $dbh->disconnect;

    return $recordlist;
}

sub get_recent_titids_by_kor {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $database               = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
    }

    my $request=$dbh->prepare("select title_string.id as id,title_string.content as content from title_string,conn where conn.targetid = ? and title_string.category=2 and title_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 3 order by content desc limit $limit");
    $request->execute($id);

    my $recordlist = new OpenBib::RecordList::Title();
    
    while (my $res=$request->fetchrow_hashref()){
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}, date => $res->{content}}));
    }
    
    $dbh->disconnect;

    return $recordlist;
}

sub get_recent_titids_by_swt {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $database               = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
    }

    my $request=$dbh->prepare("select title_string.id as id,title_string.content as content from title_string,conn where conn.targetid = ? and title_string.category=2 and title_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 4 order by content desc limit $limit");
    $request->execute($id);

    my $recordlist = new OpenBib::RecordList::Title();
    
    while (my $res=$request->fetchrow_hashref()){
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}, date => $res->{content}}));
    }
    
    $dbh->disconnect;

    return $recordlist;
}

sub get_recent_titids_by_not {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $database               = exists $arg_ref->{database}
        ? $arg_ref->{database}            : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = OpenBib::Config->instance;
    
    if (!defined $dbh){
        # Kein Spooling von DB-Handles!
        $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
            or $logger->error_die($DBI::errstr);
    }

    my $request=$dbh->prepare("select title_string.id as id,title_string.content as content from title_string,conn where conn.targetid = ? and title_string.category=2 and title_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 5 order by content desc limit $limit");
    $request->execute($id);

    my $recordlist = new OpenBib::RecordList::Title();

    while (my $res=$request->fetchrow_hashref()){
        $recordlist->add(new OpenBib::Record::Title({ database => $database , id => $res->{id}, date => $res->{content}}));
    }
    
    $dbh->disconnect;

    return $recordlist;
}

1;

