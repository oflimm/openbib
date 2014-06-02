#!/usr/bin/perl

#####################################################################
#
#  amarok_mysql2meta.pl
#
#  Konverierung von Amarok-Daten aus dem MySQL-Backend in das Meta-Format
#
#  Dieses File ist (C) 2007-2012 Oliver Flimm <flimm@openbib.org>
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

use utf8;

use DBI;
use Encode qw(decode_utf8 encode_utf8);
use JSON::XS;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

my $config = new OpenBib::Config;

my $database=($ARGV[0])?$ARGV[0]:'audio';

my $dbinfo     = $config->get_databaseinfo->search_rs({ dbname => $database })->single;

my $dbuser    = $dbinfo->remoteuser;
my $dbpasswd  = $dbinfo->remotepassword;
my $dbhost    = $dbinfo->host;
my $dbname    = $dbinfo->remotepath;

my $dbh=DBI->connect("DBI:mysql:dbname=$dbname;host=$dbhost;port=$port", $dbuser, $dbpasswd, {'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]}) or die "could not connect";

#########################################################################
# Interpreten/Verfasser

{
    open(PERSON,">:utf8", "meta.person");

    my $sql_statement = "select * from artists";
    my $result=$dbh->prepare($sql_statement) or die "Error -- $DBI::errstr";
    
    $result->execute();
    
    while (my $res=$result->fetchrow_hashref){
        my $id    = $res->{'id'};
        my $name  = decode_utf8($res->{'name'});

        my $item_ref = {};
        $item_ref->{id} = $id;
        push @{$item_ref->{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $name,
        };

        print PERSON encode_json $item_ref, "\n";
    }

    close(PERSON);
}

#########################################################################
# Albenname/Koerperschaft

{
    open(CORPORATEBODY,">:utf8", "meta.corporatebody");
    
    my $sql_statement = "select * from albums";
    my $result=$dbh->prepare($sql_statement) or die "Error -- $DBI::errstr";
    
    $result->execute();
    
    while (my $res=$result->fetchrow_hashref){
        my $id    = $res->{'id'};
        my $name  = decode_utf8($res->{'name'});

        my $item_ref = {};
        $item_ref->{id} = $id;
        push @{$item_ref->{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $name,
        };

        print CORPORATEBODY encode_json $item_ref, "\n";
    }

    close(CORPORATEBODY);
}

#########################################################################
# Genre/Notation

{
    open(CLASSIFICATION,">:utf8", "meta.classification");
    
    my $sql_statement = "select * from genres";
    my $result=$dbh->prepare($sql_statement) or die "Error -- $DBI::errstr";
    
    $result->execute();

    while (my $res=$result->fetchrow_hashref){
        my $id    = $res->{'id'};
        my $name  = decode_utf8($res->{'name'});

        my $item_ref = {};
        $item_ref->{id} = $id;
        push @{$item_ref->{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $name,
        };

        print CLASSIFICATION encode_json $item_ref, "\n";
    }

    close(CLASSIFICATION);
}

#########################################################################
# Titel

{
    open(TITLE,">:utf8", "meta.title");
    
    my $sql_statement = "select urls.uniqueid,urls.rpath,tracks.id,tracks.artist,tracks.album,tracks.genre,FROM_UNIXTIME(tracks.createdate) as createdate,FROM_UNIXTIME(tracks.modifydate) as modifydate,tracks.tracknumber,tracks.length,tracks.title,years.name as thisyear from tracks left join years on tracks.year=years.id left join urls on tracks.url=urls.id";
    my $result=$dbh->prepare($sql_statement) or die "Error -- $DBI::errstr";
    
    $result->execute();
    
    while (my $res=$result->fetchrow_hashref){
    	my $month;
    	my $day;
        my $id         = $res->{'id'};
        my $artistid   = $res->{'artist'};
        my $albumid    = $res->{'album'};
        my $genreid    = $res->{'genre'};
        my $year       = $res->{'thisyear'};
        my $track      = $res->{'tracknumber'};
        my $length     = $res->{'length'};
        my $title      = decode_utf8($res->{'title'});
        my $createdate = $res->{'createdate'};
        my $modifydate = $res->{'modifydate'};
        my $rpath      = $res->{'rpath'};
        my ($uniqueid) = $res->{'uniqueid'} =~m/\/\/(.+)$/;

        next unless ($rpath=~m/\/[es]c\d+\// || $rpath=~m/\/ia\d+\// || $rpath=~m/\/km\d+\// || $rpath=~m/\/em\d+\//);
        
        ($year,$month,$day) = $createdate =~m/^(\d\d\d\d)-(\d\d)-(\d\d)/;

        my $tstamp_create = "$day.$month.$year";

        ($year,$month,$day) = $modifydate =~m/^(\d\d\d\d)-(\d\d)-(\d\d)/;

        my $tstamp_update = "$day.$month.$year";
        
        my $item_ref = {};
        $item_ref->{id} = $uniqueid;

        my $sec = $length % 60;
        $length = ($length - $sec) / 60;
        my $minute = $length % 60;
#        $length = ($length - $minute) / 60;
#        my $hour = $length % 24;

        $length=sprintf "%d:%02d (min:sec)",$minute,$sec;
#        $length="$hour:$length" if ($hour);

        push @{$item_ref->{'0002'}}, {
            mult     => 1,
            subfield => '',
            content  => $tstamp_create,
        };

        push @{$item_ref->{'0003'}}, {
            mult     => 1,
            subfield => '',
            content  => $tstamp_update,
        };

        push @{$item_ref->{'0089'}}, {
            mult     => 1,
            subfield => '',
            content  => $track,
        } if ($track);

        push @{$item_ref->{'0100'}}, {
            mult       => 1,
            subfield   => '',
            id         => $artistid,
            supplement => '',
        } if ($artistid);

        push @{$item_ref->{'0200'}}, {
            mult       => 1,
            subfield   => '',
            id         => $albumid,
            supplement => '',
        } if ($albumid);

        push @{$item_ref->{'0331'}}, {
            mult     => 1,
            subfield => '',
            content  => $title,
        };
        
        push @{$item_ref->{'0425'}}, {
            mult     => 1,
            subfield => '',
            content  => $year,
        } if ($year);

        push @{$item_ref->{'0433'}}, {
            mult     => 1,
            subfield => '',
            content  => $length,
        } if ($length);

        push @{$item_ref->{'0700'}}, {
            mult       => 1,
            subfield   => '',
            id         => $genreid,
            supplement => '',
        } if ($genreid);

        print TITLE encode_json $item_ref, "\n";
    }

    close(TITLE);
}
