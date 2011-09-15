#!/usr/bin/perl

use warnings;
use strict;

use DBI;

my $passwd=$ARGV[0];

my $olddbh = DBI->connect("DBI:mysql:dbname=config;host=localhost;port=3306", 'root', $passwd);
my $newdbh = DBI->connect("DBI:mysql:dbname=openbib_config;host=localhost;port=3306", 'root', $passwd);

$newdbh->do("truncate table serverinfo");
$newdbh->do("truncate table rsscache");
$newdbh->do("truncate table view_rss");
$newdbh->do("truncate table view_db");
$newdbh->do("truncate table viewinfo");
$newdbh->do("truncate table orgunit_db");
$newdbh->do("truncate table orgunitinfo");
$newdbh->do("truncate table rssinfo");
$newdbh->do("truncate table profileinfo");
$newdbh->do("truncate table libraryinfo");
$newdbh->do("truncate table databaseinfo");


# databaseinfo

my %dbid = ();

print STDERR "### databaseinfo\n";


my $request = $olddbh->prepare("select * from databaseinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){

    my $request2 = $newdbh->prepare("insert into databaseinfo (description,shortdesc,system,dbname,sigel,url,use_libinfo,active,protocol,host,remotepath,remoteuser,remotepassword,titlefile,personfile,corporatebodyfile,subjectfile,classificationfile,holdingfile,autoconvert,circ,circurl,circwsurl,circdb,allcount,journalcount,articlecount,digitalcount) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
    $request2->execute($result->{description},$result->{shortdesc},$result->{system},$result->{dbname},$result->{sigel},$result->{url},$result->{use_libinfo},$result->{active},$result->{protocol},$result->{host},$result->{remotepath},$result->{remoteuser},$result->{remotepassword},$result->{titlefile},$result->{personfile},$result->{corporatebodyfile},$result->{subjectfile},$result->{classificationfile},$result->{holdingsfile},$result->{autoconvert},$result->{circ},$result->{circurl},$result->{circwsurl},$result->{circdb},$result->{allcount},$result->{journalcount},$result->{articlecount},$result->{digitalcount});
    my $insertid   = $newdbh->{'mysql_insertid'};

    $dbid{$result->{dbname}}=$insertid;

    print STDERR $result->{dbname},  " -> ID: ", $dbid{$result->{dbname}} ,"\n";
}

# libraryinfo

print STDERR "### libraryinfo\n";

$request = $olddbh->prepare("select * from libraryinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    if (!$result->{dbname} || ! $dbid{$result->{dbname}}){
        print STDERR "Ziel $result->{dbname} existiert nicht in databaseinfo\n"; 
        next;
    }

    my $request2 = $newdbh->prepare("insert into libraryinfo (dbid,category,indicator,content) values (?,?,?,?)");
    $request2->execute($dbid{$result->{dbname}},$result->{category},$result->{indicator},$result->{content});
}

# profileinfo

my %profileid = ();

print STDERR "### profileinfo\n";

$request = $olddbh->prepare("select * from profileinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    print STDERR $result->{profilename},  "\n";
    
    my $request2 = $newdbh->prepare("insert into profileinfo (profilename,description) values (?,?)");
    $request2->execute($result->{profilename},$result->{description});
    my $insertid   = $newdbh->{'mysql_insertid'};

    $profileid{$result->{profilename}}=$insertid;

    print STDERR $result->{profilename},  " -> ID: ", $profileid{$result->{profilename}} ,"\n";
}

# rssinfo

print STDERR "### rssinfo\n";

my %rssid        = ();

$request = $olddbh->prepare("select * from rssfeeds");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    if (!$result->{dbname} || ! $dbid{$result->{dbname}}){
        print STDERR "Ziel $result->{dbname} existiert nicht in databaseinfo\n"; 
        next;
    }

    print STDERR $result->{dbname},  "\n";
    
    my $request2 = $newdbh->prepare("insert into rssinfo (id,dbid,type,subtype,subtypedesc,active) values (?,?,?,?,?,?)");
    $request2->execute($result->{id},$dbid{$result->{dbname}},$result->{type},$result->{subtype},$result->{subtypedesc},$result->{active});
}

# orgunitinfo

print STDERR "### orgunitinfo\n";

my %orgunitid        = ();
my %orgunitprofileid = ();

$request = $olddbh->prepare("select * from orgunitinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    if (!$result->{profilename} || ! $profileid{$result->{profilename}}){
        print STDERR "Ziel $result->{profilename} existiert nicht in profileinfo\n"; 
        next;
    }

    my $request2 = $newdbh->prepare("insert into orgunitinfo (profileid,orgunitname,description,nr) values (?,?,?,?)");
    $request2->execute($profileid{$result->{profilename}},$result->{orgunitname},$result->{description},$result->{nr});
    my $insertid   = $newdbh->{'mysql_insertid'};

    $orgunitid{$result->{orgunitname}}=$insertid;
    $orgunitprofileid{$result->{profilename}}{$result->{orgunitname}}=$insertid;

    print STDERR $result->{orgunitname},  " -> ID: ", $orgunitid{$result->{orgunitname}} ,"\n";

}

# orgunitdbs

print STDERR "### orgunit_db\n";

$request = $olddbh->prepare("select * from orgunitdbs");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    if (!$result->{profilename} || !$result->{orgunitname}|| ! $orgunitprofileid{$result->{profilename}}{$result->{orgunitname}}){
        print STDERR "Ziel $result->{profilename} existiert nicht in profileinfo\n"; 
        next;
    }

    my $request2 = $newdbh->prepare("insert into orgunit_db (orgunitid,dbid) values (?,?)");
    $request2->execute($orgunitprofileid{$result->{profilename}}{$result->{orgunitname}},$dbid{$result->{dbname}});

    print STDERR $result->{orgunitname},  " -> ID: ", $orgunitid{$result->{orgunitname}} ,"\n";

}

# viewinfo

print STDERR "### viewinfo\n";

my %viewid        = ();

$request = $olddbh->prepare("select * from viewinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){

    my $request2 = $newdbh->prepare("insert into viewinfo (viewname,description,rssid,start_loc,servername,profileid,stripuri,joinindex,active) values (?,?,?,?,?,?,?,?,?)");
    $request2->execute($result->{viewname},$result->{description},$result->{rssfeed},$result->{start_loc},$result->{servername},$profileid{$result->{profilename}},$result->{stripuri},$result->{joinindex},$result->{active});
    my $insertid   = $newdbh->{'mysql_insertid'};

    $viewid{$result->{viewname}}=$insertid;

    print STDERR $result->{viewname},  " -> ID: ", $viewid{$result->{viewname}} ,"\n";

}

# viewdbs

print STDERR "### viewdbs\n";

$request = $olddbh->prepare("select * from viewdbs");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    next unless ($result->{viewname} && $viewid{$result->{viewname}} && $result->{dbname} && $dbid{$result->{dbname}});
    my $request2 = $newdbh->prepare("insert into view_db (viewid,dbid) values (?,?)");
    $request2->execute($viewid{$result->{viewname}},$dbid{$result->{dbname}});
}

# viewrssfeeds

print STDERR "### view_rss\n";

$request = $olddbh->prepare("select * from viewrssfeeds");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    next unless ($result->{viewname} && $viewid{$result->{viewname}} && $result->{rssfeed} );
    my $request2 = $newdbh->prepare("insert into view_rss (viewid,rssid) values (?,?)");
    $request2->execute($viewid{$result->{viewname}},$result->{rssfeed});
}

# rsscache wird nicht migriert

print STDERR "### rsscache\n";

# serverinfo

print STDERR "### serverinfo\n";

$request = $olddbh->prepare("select * from loadbalancertargets");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $request2 = $newdbh->prepare("insert into serverinfo (id,host,active) values (?,?,?)");
    $request2->execute($result->{id},$result->{host},$result->{active});
}
