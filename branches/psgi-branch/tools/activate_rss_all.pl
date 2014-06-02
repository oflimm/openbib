#!/usr/bin/perl

#####################################################################
#
#  activate_rss_all.pl
#
#  Aktivierung aller Standard-RSS-Feeds in der Session-DB
#
#  Dieses File ist (C) 2006-2008 Oliver Flimm <flimm@openbib.org>
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

use DBI;

use OpenBib::Config;

my $config = OpenBib::Config->instance;

#####################################################################
# Verbindung zur SQL-Datenbank herstellen

my $sessiondbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{sessiondbname};host=$config->{sessiondbhost};port=$config->{sessiondbport}", $config->{sessiondbuser}, $config->{sessiondbpasswd}) or die "could not connect";

my $request=$sessiondbh->prepare("select dbname from dbinfo where active=1 order by orgunit,dbname");
$request->execute();

while (my $res=$request->fetchrow_hashref){
    my $dbname=$res->{dbname};

    print STDERR "Bearbeite Pool $dbname\n";

    # Feeds loeschen
    my $request2=$sessiondbh->prepare("delete from rssfeeds where dbname=?");
    $request2->execute($dbname);
    
    # Typ 1 - Feeds eintragen (letzte 50 von allen)
    $request2=$sessiondbh->prepare("insert into rssfeeds values (NULL,?,?,?,'',1)");
    $request2->execute($dbname,1,-1);

    $request2=$sessiondbh->prepare("select id from rssfeeds where dbname=? and type=? and subtype=?");
    $request2->execute($dbname,1,-1);

    my $res=$request2->fetchrow_hashref;
    my $type1id=$res->{id};

    # Typ 1 - Feed als Primaeren Feed fuer den View zur DB eintragen
    $request2=$sessiondbh->prepare("update viewinfo set rssfeed = ? where viewname=?");
    $request2->execute($type1id,$dbname);

    # Typ 1 - Feed aus den Feeds des Views loeschen
    $request2=$sessiondbh->prepare("delete from viewrssfeeds where rssfeed = ?");
    $request2->execute($type1id);
    
    # Typ 1 - Feed zu den Feeds des Views hinzufuegen
    $request2=$sessiondbh->prepare("insert into viewrssfeeds values (?,?)");
    $request2->execute($dbname,$type1id);

    #########################################

    my @types=(2,3,4,5);

    foreach my $type (@types){

        # Typ x - Feeds eintragen
        $request2=$sessiondbh->prepare("insert into rssfeeds values (NULL,?,?,?,'',1)");
        $request2->execute($dbname,$type,-1);
        
        $request2=$sessiondbh->prepare("select id from rssfeeds where dbname=? and type=? and subtype=?");
        $request2->execute($dbname,$type,-1);
        
        my $res=$request2->fetchrow_hashref;
        my $typeid=$res->{id};
        
        # Typ 1 - Feed aus den Feeds des Views loeschen
        $request2=$sessiondbh->prepare("delete from viewrssfeeds where rssfeed = ?");
        $request2->execute($typeid);
        
        # Typ 1 - Feed zu den Feeds des Views hinzufuegen
        $request2=$sessiondbh->prepare("insert into viewrssfeeds values (?,?)");
        $request2->execute($dbname,$typeid);
    }    
    
}

print "done\n";
