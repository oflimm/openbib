#####################################################################
#
#  OpenBib::Search::Util
#
#  Dieses File ist (C) 2004-2012 Oliver Flimm <flimm@openbib.org>
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

sub get_result_navigation {
    my ($arg_ref) = @_;

    # Set defaults
    my $database              = exists $arg_ref->{database}
        ? $arg_ref->{database}              : undef;
    my $titleid                = exists $arg_ref->{titleid}
        ? $arg_ref->{titleid}                : undef;
    my $hitrange              = exists $arg_ref->{hitrange}
        ? $arg_ref->{hitrange}              : undef;
    my $sortorder             = exists $arg_ref->{sortorder}
        ? $arg_ref->{sortorder}             : undef;
    my $sorttype              = exists $arg_ref->{sorttype}
        ? $arg_ref->{sorttype}              : undef;
    my $view                  = exists $arg_ref->{view}
        ? $arg_ref->{view}                  : undef;
    my $session               = exists $arg_ref->{session}
        ? $arg_ref->{session}               : OpenBib::Session->new;
    
    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $config  = OpenBib::Config->instance;

    # Bestimmen des vorigen und naechsten Treffer einer
    # vorausgegangenen Kurztitelliste

    my $lastresultstring = $session->get_lastresultset();

    my $lasttiturl="";
    my $nexttiturl="";

    if ($lastresultstring){
        my $lastresult_ref = decode_json($lastresultstring);
        my @lastresult = @{$lastresult_ref};
        
        
        my @previous = before { $_->{database} eq $database && $_->{id} eq $titleid} @lastresult;
        
        my @last=(exists $previous[-1])?$previous[-1]:();
        
        my @after = after { $_->{database} eq $database && $_->{id} eq $titleid} @lastresult;
        my @next=(exists $after[0])?$after[0]:();
        
        if (@last) {
            $lasttiturl="$config->{base_loc}/$view/$config->{titles_loc}/$last[0]->{database}/$last[0]->{id}/";
        }
        
        if (@next) {
            $nexttiturl="$config->{base_loc}/$view/$config->{titles_loc}/$next[0]->{database}/$next[0]->{id}/";
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
            $contentreq = conv2autoplus($contentreq);
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

        if ($logger->is_debug){
            $logger->debug("Index-Worte: ".YAML::Dump(\@contents))
        }
    }

    if ($config->{benchmark}) {
        $btime=new Benchmark;
        $timeall=timediff($btime,$atime);
        $logger->info("Zeit fuer : ".($#contents+1)." Begriffe (Bestimmung): ist ".timestr($timeall));
        undef $atime;
        undef $btime;
        undef $timeall;
    }

    if ($logger->is_debug){
        $logger->debug("INDEX-Contents (".($#contents+1)." Begriffe): ".YAML::Dump(\@contents));
    }


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

# Ehemals in VirtualSearch.pm

sub conv2autoplus {
    my ($eingabe)=@_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    $logger->debug("Original: $eingabe");

    my @phrasenbuf=();

    chomp($eingabe);

    # Token fuer Phrasensuche aussondern
    while ($eingabe=~/(".*?")/) {
        my $phrase=$1;

        # Merken
        push @phrasenbuf, $phrase;

        # Entfernen
        $eingabe=~s/$phrase//;
    }

    # Innenliegende - durch Leerzeichen ersetzen
    $eingabe=~s/(\w)-(\w)/$1 $2/gi;
    #  $eingabe=~s/\+(\w)/ $1/gi;
    $eingabe=~s/\+(\S)/ $1/gi;

    # Generell Plus vor Woertern durch Leerzeichen ersetzen
    #  $eingabe=~s/(\S+)/%2B$1/gi;
    $eingabe=~s/(\S+)/%2B$1/gi;

    # Kombination -+ wird nun eliminiert
    $eingabe=~s/-%2B/-/gi;

    # URL-Code fuer + in richtiges Plus umwandeln
    $eingabe=~s/%2B/+/g;

    push @phrasenbuf, $eingabe;

    # Gemerkte Phrase werden wieder hinzugefuegt
    if ($#phrasenbuf >= 0) {
        $eingabe=join(" ",@phrasenbuf);
    }

    $logger->debug("Gewandelt: $eingabe");

    return $eingabe;
}


1;

