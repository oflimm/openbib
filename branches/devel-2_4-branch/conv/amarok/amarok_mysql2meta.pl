#!/usr/bin/perl

#####################################################################
#
#  amarok_mysql2meta.pl
#
#  Konverierung von Amarok-Daten aus dem MySQL-Backend in das Meta-Format
#
#  Dieses File ist (C) 2007-2011 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

my $config = new OpenBib::Config;

my $database=($ARGV[0])?$ARGV[0]:'audiosmlg';

my $dbinfo     = $config->get_databaseinfo->search_rs({ dbname => $database })->single;

my $dbuser    = $dbinfo->remoteuser;
my $dbpasswd  = $dbinfo->remotepassword;
my $dbhost    = $dbinfo->host;
my $dbname    = $dbinfo->remotepath;

my $dbh=DBI->connect("DBI:mysql:dbname=$dbname;host=$dbhost;port=$port", $dbuser, $dbpasswd) or die "could not connect";

#########################################################################
# Interpreten/Verfasser

{
    open(AUT,">:utf8", "unload.PER");

    my $sql_statement = "select * from artist";
    my $result=$dbh->prepare($sql_statement) or die "Error -- $DBI::errstr";
    
    $result->execute();
    
    while (my $res=$result->fetchrow_hashref){
        my $id    = $res->{'id'};
        my $name  = decode_utf8($res->{'name'});

        print AUT << "PERSET"
0000:$id
0001:$name
9999:

PERSET
    }
    
    close(AUT);
}

#########################################################################
# Albenname/Koerperschaft

{
    open(KOR,">:utf8", "unload.KOE");
    
    my $sql_statement = "select * from album";
    my $result=$dbh->prepare($sql_statement) or die "Error -- $DBI::errstr";
    
    $result->execute();
    
    while (my $res=$result->fetchrow_hashref){
        my $id    = $res->{'id'};
        my $name  = decode_utf8($res->{'name'});
        
        print KOR << "KOESET"
0000:$id
0001:$name
9999:

KOESET
    }
    
    close(KOR);
}

#########################################################################
# Genre/Notation

{
    open(NOTATION,">:utf8", "unload.SYS");
    
    my $sql_statement = "select * from genre";
    my $result=$dbh->prepare($sql_statement) or die "Error -- $DBI::errstr";
    
    $result->execute();

    while (my $res=$result->fetchrow_hashref){
        my $id    = $res->{'id'};
        my $name  = decode_utf8($res->{'name'});

        print NOTATION << "SYSSET"
0000:$id
0001:$name
9999:

SYSSET
    }

    close(NOTATION);
}

#########################################################################
# Titel

{
    my $titid=1;
    open(TIT,">:utf8", "unload.TIT");
    
    my $sql_statement = "select tags.*,year.name as thisyear from tags left join year on tags.year=year.id";
    my $result=$dbh->prepare($sql_statement) or die "Error -- $DBI::errstr";
    
    $result->execute();
    
    while (my $res=$result->fetchrow_hashref){
        my $artistid  = $res->{'artist'};
        my $albumid   = $res->{'album'};
        my $genreid   = $res->{'genre'};
        my $year      = $res->{'thisyear'};
        my $track     = $res->{'track'};
        my $length    = $res->{'length'};
        my $title     = decode_utf8($res->{'title'});


        my $sec = $length % 60;
        $length = ($length - $sec) / 60;
        my $minute = $length % 60;
#        $length = ($length - $minute) / 60;
#        my $hour = $length % 24;

        $length=sprintf "%d:%02d (min:sec)",$minute,$sec;
#        $length="$hour:$length" if ($hour);
        
        print TIT "0000:$titid\n";
        print TIT "0089:$track\n" if ($track);
        print TIT "0100:IDN: $artistid\n" if ($artistid);
        print TIT "0200:IDN: $albumid\n" if ($albumid);
        print TIT "0331:$title\n";
        print TIT "0425:$year\n" if ($year);
        print TIT "0433:$length\n" if ($length);
        print TIT "0700:IDN: $genreid\n" if ($genreid);
        print TIT "9999:\n\n";
        $titid++;
    }

    close(TIT);
}
