#!/usr/bin/perl

#####################################################################
#
#  fix-userdb.pl
#
#  Dieses File ist (C) 2005-2011 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Config;
use YAML::Syck;

my $config = OpenBib::Config->instance;

my $rootdir       = $config->{'autoconv_dir'};
my $pooldir       = $rootdir."/pools";
my $konvdir       = $config->{'conv_dir'};

my $pool          = $ARGV[0];

my $numericidmapping_ref = LoadFile("$rootdir/filter/$pool/$pool".".yml");

# Kein Spooling von DB-Handles!
my $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd});

my %reversemapping = ();
foreach my $newid (keys %{$numericidmapping_ref}){
    my $oldid=$numericidmapping_ref->{$newid};

    $reversemapping{$oldid}=$newid;
}
  
  
my $sql="select titid from litlistitem where dbname=?";
my $request=$dbh->prepare($sql);
$request->execute($pool);

while (my $result=$request->fetchrow_hashref){
    my $oldid=$result->{titleid};
    next unless ($oldid=~/^\d+$/);
    
    my $newid=$reversemapping{$oldid};

    next unless ($newid);
    
    my $sql="update litlistitem set titleid=? where titleid=? and dbname=?";

    print "REQUEST: $sql\n";
    print "NEW: $newid OLD: $oldid DB: $pool\n";
    my $request2=$dbh->prepare($sql);
    $request2->execute($newid,$oldid,$pool);
}

$sql="select titleid from collection where dbname=?";
$request=$dbh->prepare($sql);
$request->execute($pool);

while (my $result=$request->fetchrow_hashref){
    my $oldid=$result->{titleid};
    next unless ($oldid=~/^\d+$/);
    
    my $newid=$reversemapping{$oldid};

    next unless ($newid);
    
    my $sql="update collection set titleid=? where titleid=? and dbname=?";

    print "REQUEST: $sql\n";
    print "NEW: $newid OLD: $oldid DB: $pool\n";
    my $request2=$dbh->prepare($sql);
    $request2->execute($newid,$oldid,$pool);
}

$sql="select titid from tit_tag where dbname=?";
$request=$dbh->prepare($sql);
$request->execute($pool);

while (my $result=$request->fetchrow_hashref){
    my $oldid=$result->{titleid};
    next unless ($oldid=~/^\d+$/);
    
    my $newid=$reversemapping{$oldid};

    next unless ($newid);
    
    my $sql="update tit_tag set titleid=? where titleid=? and dbname=?";

    print "REQUEST: $sql\n";
    print "NEW: $newid OLD: $oldid DB: $pool\n";
    my $request2=$dbh->prepare($sql);
    $request2->execute($newid,$oldid,$pool);
}
