#####################################################################
#
#  OpenBib::Search::Util
#
#  Dieses File ist (C) 2004-2007 Oliver Flimm <flimm@openbib.org>
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

use Apache::Reload;
use Apache::Request ();
use Benchmark ':hireswallclock';
use DBI;
use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use MIME::Base64 ();
use SOAP::Lite;
use Storable;
use YAML ();

use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::VirtualSearch::Util;

sub print_tit_list_by_idn {
    my ($arg_ref) = @_;

    # Set defaults
    my $itemlist_ref      = exists $arg_ref->{itemlist_ref}
        ? $arg_ref->{itemlist_ref}      : undef;
    my $targetdbinfo_ref  = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}  : undef;
    my $queryoptions_ref  = exists $arg_ref->{queryoptions_ref}
        ? $arg_ref->{queryoptions_ref}  : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;
    my $r                 = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}         : undef;
    my $stylesheet        = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}        : undef;
    my $hits              = exists $arg_ref->{hits}
        ? $arg_ref->{hits}              : -1;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}          : 50;
    my $offset            = exists $arg_ref->{offset}
        ? $arg_ref->{offset}            : undef;
    my $view              = exists $arg_ref->{view}
        ? $arg_ref->{view}              : undef;
    my $template          = exists $arg_ref->{template}
        ? $arg_ref->{template}          : 'tt_search_showtitlist_tname';
    my $location          = exists $arg_ref->{location}
        ? $arg_ref->{location}          : 'search_loc';
    my $lang              = exists $arg_ref->{lang}
        ? $arg_ref->{lang}              : undef;
    my $msg                = exists $arg_ref->{msg}
        ? $arg_ref->{msg}                : undef;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();

    my $query=Apache::Request->instance($r);

    my @itemlist=@$itemlist_ref;

    # Navigationselemente erzeugen
    my %args=$r->args;
    delete $args{offset};
    delete $args{hitrange};
    my @args=();
    while (my ($key,$value)=each %args) {
        push @args,"$key=$value";
    }

    my $baseurl="http://$config->{servername}$config->{$location}?".join(";",@args);

    my @nav=();

    if ($hitrange > 0) {
        for (my $i=0; $i <= $hits-1; $i+=$hitrange) {
            my $active=0;

            if ($i == $offset) {
                $active=1;
            }

            my $item={
		start  => $i+1,
		end    => ($i+$hitrange>$hits)?$hits:$i+$hitrange,
		url    => $baseurl.";hitrange=$hitrange;offset=$i",
		active => $active,
            };
            push @nav,$item;
        }
    }

    # TT-Data erzeugen
    my $ttdata={
        lang           => $lang,
        view           => $view,
        stylesheet     => $stylesheet,
        sessionID      => $sessionID,
	      
        database       => $database,

        hits           => $hits,
	      
        sessionID      => $sessionID,
	      
        targetdbinfo   => $targetdbinfo_ref,
        itemlist       => \@itemlist,

        baseurl        => $baseurl,

        qopts          => $queryoptions_ref,
        query          => $query,
        hitrange       => $hitrange,
        offset         => $offset,
        nav            => \@nav,

        config         => $config,
        msg            => $msg,
    };
  
    OpenBib::Common::Util::print_page($config->{$template},$ttdata,$r);
#    OpenBib::Common::Util::print_page($config->{tt_search_showtitlist_tname},$ttdata,$r);

    return;
}

sub print_mult_tit_set_by_idn { 
    my ($arg_ref) = @_;

    # Set defaults
    my $titidns_ref        = exists $arg_ref->{titidns_ref}
        ? $arg_ref->{titidns_ref}        : undef;
    my $dbh                = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                : undef;
    my $sessiondbh         = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}         : undef;
    my $targetdbinfo_ref = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref} : undef;
    my $targetcircinfo_ref = exists $arg_ref->{targetcircinfo_ref}
        ? $arg_ref->{targetcircinfo_ref} : undef;
    my $queryoptions_ref   = exists $arg_ref->{queryoptions_ref}
        ? $arg_ref->{queryoptions_ref}  : undef;
    my $database           = exists $arg_ref->{database}
        ? $arg_ref->{database}           : undef;
    my $sessionID          = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}          : undef;
    my $r                  = exists $arg_ref->{apachereq}
        ? $arg_ref->{apachereq}          : undef;
    my $stylesheet         = exists $arg_ref->{stylesheet}
        ? $arg_ref->{stylesheet}         : undef;
    my $view               = exists $arg_ref->{view}
        ? $arg_ref->{view}               : undef;
    my $msg                = exists $arg_ref->{msg}
        ? $arg_ref->{msg}                : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my @titsets=();

    foreach my $titidn (@$titidns_ref) {
        my ($normset,$mexnormset,$circset)=OpenBib::Search::Util::get_tit_set_by_idn({
            titidn             => $titidn,
            dbh                => $dbh,
            targetdbinfo_ref   => $targetdbinfo_ref,
            targetcircinfo_ref => $targetcircinfo_ref,
            database           => $database,
        });
        
        my $thisset={
            titidn     => $titidn,
            normset    => $normset,
            mexnormset => $mexnormset,
            circset    => $circset,
        };
        push @titsets, $thisset;
    }

    my $poolname=$targetdbinfo_ref->{sigel}{
        $targetdbinfo_ref->{dbases}{$database}};

    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        database   => $database,
        poolname   => $poolname,
        qopts      => $queryoptions_ref,
        sessionID  => $sessionID,
        titsets    => \@titsets,

        config     => $config,
        msg        => $msg,
    };
  
    OpenBib::Common::Util::print_page($config->{tt_search_showmulttitset_tname},$ttdata,$r);

    return;
}

sub get_result_navigation {
    my ($arg_ref) = @_;

    # Set defaults
    my $sessiondbh            = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}            : undef;
    my $database              = exists $arg_ref->{database}
        ? $arg_ref->{database}              : undef;
    my $titidn                = exists $arg_ref->{titidn}
        ? $arg_ref->{titidn}                : undef;
    my $sessionID             = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}             : undef;
    my $hitrange              = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}              : undef;
    my $sortorder             = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}             : undef;
    my $sorttype              = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}              : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    # Bestimmen des vorigen und naechsten Treffer einer
    # vorausgegangenen Kurztitelliste
    my $sessionresult=$sessiondbh->prepare("select lastresultset from session where sessionid = ?") or $logger->error($DBI::errstr);
    $sessionresult->execute($sessionID) or $logger->error($DBI::errstr);
  
    my $result=$sessionresult->fetchrow_hashref();
    my $lastresultstring="";
  
    if ($result->{'lastresultset'}) {
        $lastresultstring = decode_utf8($result->{'lastresultset'});
    }
  
    $sessionresult->finish();
  
    my $lasttiturl="";
    my $nexttiturl="";
  
    if ($lastresultstring=~m/(\w+:\d+)\|$database:$titidn/) {
        $lasttiturl=$1;
        my ($lastdatabase,$lastkatkey)=split(":",$lasttiturl);
        $lasttiturl="$config->{search_loc}?sessionID=$sessionID;database=$lastdatabase;searchsingletit=$lastkatkey";
    }
    
    if ($lastresultstring=~m/$database:$titidn\|(\w+:\d+)/) {
        $nexttiturl=$1;
        my ($nextdatabase,$nextkatkey)=split(":",$nexttiturl);

	$logger->debug("NextDB: $nextdatabase - NextKatkey: $nextkatkey");

        $nexttiturl="$config->{search_loc}?sessionID=$sessionID;database=$nextdatabase;searchsingletit=$nextkatkey";
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

    my $config = new OpenBib::Config();
    
    my $type_ref = {
        tit      => 1,
        aut      => 2,
        kor      => 3,
        swt      => 4,
        notation => 5,
        mex      => 6,
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
    my $sessiondbh        = exists $arg_ref->{sessiondbh}
        ? $arg_ref->{sessiondbh}        : undef;
    my $database          = exists $arg_ref->{database}
        ? $arg_ref->{database}          : undef;
    my $targetdbinfo_ref   = exists $arg_ref->{targetdbinfo_ref}
        ? $arg_ref->{targetdbinfo_ref}  : undef;
    my $queryoptions_ref   = exists $arg_ref->{queryoptions_ref}
        ? $arg_ref->{queryoptions_ref}  : undef;
    my $sessionID         = exists $arg_ref->{sessionID}
        ? $arg_ref->{sessionID}         : undef;
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

    my $config = new OpenBib::Config();
    
    my $swtindex=OpenBib::Search::Util::get_index({
        type       => 'swt',
        category   => '0001',
        contentreq => $swt,
        dbh        => $dbh,
    });

    my $poolname=$targetdbinfo_ref->{sigel}{$targetdbinfo_ref->{dbases}{$database}};

    # TT-Data erzeugen
    my $ttdata={
        view       => $view,
        stylesheet => $stylesheet,
        database   => $database,
        poolname   => $poolname,
        qopts      => $queryoptions_ref,
        sessionID  => $sessionID,
        swt        => $swt,
        swtindex   => $swtindex,

        config     => $config,
        msg        => $msg,

    };
  
    OpenBib::Common::Util::print_page($config->{tt_search_showswtindex_tname},$ttdata,$r);

    return;
}

sub initial_search_for_titidns {
    my ($arg_ref) = @_;

    # Set defaults
    my $searchquery_ref   = exists $arg_ref->{searchquery_ref}
        ? $arg_ref->{searchquery_ref} : undef;
    my $serien            = exists $arg_ref->{serien}
        ? $arg_ref->{serien}        : undef;
    my $enrich            = exists $arg_ref->{enrich}
        ? $arg_ref->{enrich}        : undef;
    my $enrichkeys_ref    = exists $arg_ref->{enrichkeys_ref}
        ? $arg_ref->{enrichkeys_ref}: undef;
    my $dbh               = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}           : undef;
    my $hitrange          = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}      : 50;
    my $offset            = exists $arg_ref->{offset}
        ? $arg_ref->{offset}        : 0;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my ($atime,$btime,$timeall);
  
    if ($config->{benchmark}) {
        $atime=new Benchmark;
    }
    
    # Aufbau des sqlquerystrings
    my $sqlselect = "";
    my $sqlfrom   = "";
    my $sqlwhere  = "";

    my @sqlwhere = ();
    my @sqlfrom  = ('search');
    my @sqlargs  = ();

    my $notfirstsql=0;
    
    if ($searchquery_ref->{fs}{norm}) {	
        push @sqlwhere, $searchquery_ref->{fs}{bool}." match (verf,hst,kor,swt,notation,sign,inhalt,isbn,issn,ejahrft) against (? IN BOOLEAN MODE)";
        push @sqlargs, $searchquery_ref->{fs}{norm};
    }
   
    if ($searchquery_ref->{verf}{norm}) {	
        push @sqlwhere, $searchquery_ref->{verf}{bool}." match (verf) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{verf}{norm};
    }
  
    if ($searchquery_ref->{hst}{norm}) {
        push @sqlwhere, $searchquery_ref->{hst}{bool}." match (hst) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{hst}{norm};
    }
  
    if ($searchquery_ref->{swt}{norm}) {
        push @sqlwhere, $searchquery_ref->{swt}{bool}." match (swt) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{swt}{norm};
    }
  
    if ($searchquery_ref->{kor}{norm}) {
        push @sqlwhere, $searchquery_ref->{kor}{bool}." match (kor) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{kor}{norm};
    }
  
    my $notfrom="";
  
    if ($searchquery_ref->{notation}{norm}) {
        # Spezielle Trunkierung
        $searchquery_ref->{notation}{norm} =~ s/\*$/%/;

        push @sqlfrom,  "notation_string";
        push @sqlfrom,  "conn";
        push @sqlwhere, $searchquery_ref->{notation}{bool}." (notation_string.content like ? and conn.sourcetype=1 and conn.targettype=5 and conn.targetid=notation_string.id and search.verwidn=conn.sourceid)";
        push @sqlargs,  $searchquery_ref->{notation}{norm};
    }
  
    my $signfrom="";
  
    if ($searchquery_ref->{sign}{norm}) {
        # Spezielle Trunkierung
        $searchquery_ref->{sign}{norm} =~ s/\*$/%/;

        push @sqlfrom,  "mex_string";
        push @sqlfrom,  "conn";
        push @sqlwhere, $searchquery_ref->{sign}{bool}." (mex_string.content like ? and mex_string.category=0014 and conn.sourcetype=1 and conn.targettype=6 and conn.targetid=mex_string.id and search.verwidn=conn.sourceid)";
        push @sqlargs,  $searchquery_ref->{sign}{norm};
    }
  
    if ($searchquery_ref->{isbn}{norm}) {
        push @sqlwhere, $searchquery_ref->{isbn}{bool}." match (isbn) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{isbn}{norm};
    }
  
    if ($searchquery_ref->{issn}{norm}) {
        push @sqlwhere, $searchquery_ref->{issn}{bool}." match (issn) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{issn}{norm};
    }
  
    if ($searchquery_ref->{mart}{norm}) {
        push @sqlwhere, $searchquery_ref->{mart}{bool}."  match (artinh) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{mart}{norm};
    }
  
    if ($searchquery_ref->{hststring}{norm}) {
        # Spezielle Trunkierung
        $searchquery_ref->{hststring}{norm} =~ s/\*$/%/;

        push @sqlfrom,  "tit_string";
        push @sqlwhere, $searchquery_ref->{hststring}{bool}." (tit_string.content like ? and tit_string.category in (0331,0310,0304,0370,0341) and search.verwidn=tit_string.id)";
        push @sqlargs,  $searchquery_ref->{hststring}{norm};
    }

    if ($searchquery_ref->{inhalt}{norm}) {
        push @sqlwhere, $searchquery_ref->{inhalt}{bool}."  match (inhalt) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{inhalt}{norm};
    }
    
    if ($searchquery_ref->{gtquelle}{norm}) {
        push @sqlwhere, $searchquery_ref->{gtquelle}{bool}."  match (gtquelle) against (? IN BOOLEAN MODE)";
        push @sqlargs,  $searchquery_ref->{gtquelle}{norm};
    }
  
    if ($searchquery_ref->{ejahr}{norm}) {
        push @sqlwhere, $searchquery_ref->{ejahr}{bool}." ejahr ".$searchquery_ref->{ejahr}{arg}." ?";
        push @sqlargs,  $searchquery_ref->{ejahr}{norm};
    }

    if ($serien){
        push @sqlfrom,  "conn";
        push @sqlwhere, "and (conn.targetid=search.verwidn and conn.targettype=1 and conn.sourcetype=1)";
    }

    my @tempidns=();
    
    my $sqlwherestring  = join(" ",@sqlwhere);
    $sqlwherestring     =~s/^(?:AND|OR|NOT) //;
    my $sqlfromstring   = join(", ",@sqlfrom);

    if ($offset >= 0){
        $offset=$offset.",";
    }
    
    my $sqlquerystring  = "select distinct verwidn from $sqlfromstring where $sqlwherestring limit $offset$hitrange";

    $logger->debug("QueryString: ".$sqlquerystring);
    my $request         = $dbh->prepare($sqlquerystring);

    $request->execute(@sqlargs);

    while (my $res=$request->fetchrow_arrayref){
        push @tempidns, $res->[0];
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : initital_search_for_titidns / $sqlquerystring -> ".($#tempidns+1)." : ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    if ($enrich){
        my ($atime,$btime,$timeall);
        
        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        my $request=$dbh->prepare("select id as verwidn from tit_string where tit_string.content = ?");
        foreach my $enrichkey (@$enrichkeys_ref){
            $request->execute($enrichkey);
            while(my $res=$request->fetchrow_arrayref){
                push @tempidns, $res->[0];
            }
        }

        $request->finish();

        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : enrich -> ".($#tempidns+1)."/".(scalar @$enrichkeys_ref)." : ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }

    }

    # Entfernen mehrfacher verwidn's unter Beruecksichtigung von $hitrange
    my %schon_da=();
    my $count=0;
    my @tidns=grep {! $schon_da{$_}++ } @tempidns;
    @tidns=splice(@tidns,0,$hitrange);
    
    
    my $fullresultcount=$#tidns+1;
    
    $logger->info("Fulltext-Query: $sqlquerystring");
  
    $logger->info("Treffer: ".($#tidns+1)." von ".$fullresultcount);

    # Wenn hitrange Treffer gefunden wurden, ist es wahrscheinlich, dass
    # die wirkliche Trefferzahl groesser ist.
    # Diese wird daher getrennt bestimmt, damit sie dem Benutzer als
    # Hilfestellung fuer eine Praezisierung seiner Suchanfrage
    # ausgegeben werden kann
    if ($#tidns+1 > $hitrange){ # ueberspringen
    #    if ($#tidns+1 == $hitrange){

        if ($config->{benchmark}) {
            $atime=new Benchmark;
        }
        
        my $sqlresultcount = "select count(verwidn) as resultcount from $sqlfromstring where $sqlwherestring";
#        my $sqlresultcount = "select verwidn from $sqlfromstring where $sqlwherestring";
        $request         = $dbh->prepare($sqlresultcount);
        
        $request->execute(@sqlargs);
        
        my $fullres         = $request->fetchrow_hashref;
        $fullresultcount = $fullres->{resultcount};

#        $fullresultcount = 0;

#        while ($request->fetchrow_array){
#            $fullresultcount++;
#        }
        
        if ($config->{benchmark}) {
            $btime=new Benchmark;
            $timeall=timediff($btime,$atime);
            $logger->info("Zeit fuer : initital_search_for_titidns / $sqlresultcount -> $fullresultcount : ist ".timestr($timeall));
            undef $atime;
            undef $btime;
            undef $timeall;
        }
        
    }

    $request->finish();
    
    return {
        fullresultcount => $fullresultcount,
        titidns_ref     => \@tidns
    };
}

sub get_recent_titids {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $request=$dbh->prepare("select id,content from tit_string where category=2 order by content desc limit $limit");
    $request->execute();

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

sub get_recent_titids_by_aut {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $request=$dbh->prepare("select tit_string.id as id,tit_string.content as content from tit_string,conn where conn.targetid = ? and tit_string.category=2 and tit_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 2 order by content desc limit $limit");
    $request->execute($id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

sub get_recent_titids_by_kor {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $request=$dbh->prepare("select tit_string.id as id,tit_string.content as content from tit_string,conn where conn.targetid = ? and tit_string.category=2 and tit_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 3 order by content desc limit $limit");
    $request->execute($id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

sub get_recent_titids_by_swt {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $request=$dbh->prepare("select tit_string.id as id,tit_string.content as content from tit_string,conn where conn.targetid = ? and tit_string.category=2 and tit_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 4 order by content desc limit $limit");
    $request->execute($id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

sub get_recent_titids_by_not {
    my ($arg_ref) = @_;

    # Set defaults
    my $dbh                    = exists $arg_ref->{dbh}
        ? $arg_ref->{dbh}                 : undef;
    my $id                     = exists $arg_ref->{id}
        ? $arg_ref->{id}                  : undef;
    my $limit                  = exists $arg_ref->{limit}
        ? $arg_ref->{limit}               : undef;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config = new OpenBib::Config();
    
    my $request=$dbh->prepare("select tit_string.id as id,tit_string.content as content from tit_string,conn where conn.targetid = ? and tit_string.category=2 and tit_string.id=conn.sourceid and conn.sourcetype = 1 and conn.targettype = 5 order by content desc limit $limit");
    $request->execute($id);

    my @titlist=();
    
    while (my $res=$request->fetchrow_hashref()){
        push @titlist, {
            id   => $res->{id},
            date => $res->{content},
        };
    }
    
    $dbh->disconnect;

    return \@titlist;
}

1;

