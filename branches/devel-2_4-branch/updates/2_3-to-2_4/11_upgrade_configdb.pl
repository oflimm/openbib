#!/usr/bin/perl

use warnings;
use strict;

use DBI;

my $passwd=$ARGV[0];

my $olddbh = DBI->connect("DBI:mysql:dbname=config;host=localhost;port=3306", 'root', $passwd);
my $newdbh = DBI->connect("DBI:mysql:dbname=openbib_config;host=localhost;port=3306", 'root', $passwd);

# databaseinfo

my %dbid = ();

$newdbh->do("truncate table databaseinfo");

my $request = $olddbh->prepare("select * from databaseinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){

    my $request2 = $newdbh->prepare("insert into databaseinfo (description,shortdesc,system,dbname,sigel,url,use_libinfo,active,protocol,host,remotepath,remoteuser,remotepassword,titlefile,personfile,corporatebodyfile,subjectfile,classificationfile,holdingfile,autoconvert,circ,circurl,circwsurl,circdb,allcount,journalcount,articlecount,digitalcount) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
    $request2->execute($result->{description},$result->{shortdesc},$result->{system},$result->{dbname},$result->{sigel},$result->{url},$result->{use_libinfo},$result->{active},$result->{protocol},$result->{host},$result->{remotepath},$result->{remoteuser},$result->{remotepassword},$result->{titlefile},$result->{personfile},$result->{corporatebodyfile},$result->{subjectfile},$result->{classificationfile},$result->{holdingsfile},$result->{autoconvert},$result->{circ},$result->{circurl},$result->{circwsurl},$result->{circdb},$result->{allcount},$result->{journalcount},$result->{articlecount},$result->{digitalcount});
    my $insertid   = $newdbh->{'mysql_insertid'};

    $dbid{$result->{dbname}}=$insertid;
}

# libraryinfo

$newdbh->do("truncate table libraryinfo");

$request = $olddbh->prepare("select * from libraryinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    next unless ($result->{dbname} && $dbid{$result->{dbname}});
    my $request2 = $newdbh->prepare("insert into libraryinfo (dbid,category,indicator,content) values (?,?,?,?)");
    $request2->execute($dbid{$result->{dbname}},$result->{category},$result->{indicator},$result->{content});
}

# profileinfo

my %profileid = ();

$newdbh->do("truncate table profileinfo");

$request = $olddbh->prepare("select * from profileinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){

    my $request2 = $newdbh->prepare("insert into profileinfo (profilename,description) values (?,?)");
    $request2->execute($result->{profilename},$result->{description});
    my $insertid   = $newdbh->{'mysql_insertid'};

    $profileid{$result->{profilename}}=$insertid;

}

# rssinfo

my %rssid        = ();

$newdbh->do("truncate table rssinfo");

$request = $olddbh->prepare("select * from rssfeeds");

$request->execute();

while (my $result=$request->fetchrow_hashref){

    my $request2 = $newdbh->prepare("insert into rssinfo (id,dbid,type,subtype,subtypedesc,active) values (?,?,?,?,?,?)");
    $request2->execute($result->{id},$dbid{$result->{dbname}},$result->{type},$result->{subtype},$result->{subtypedesc},$result->{active});
}

# orgunitinfo

my %orgunitid        = ();
my %orgunitprofileid = ();

$newdbh->do("truncate table orgunitinfo");

$request = $olddbh->prepare("select * from orgunitinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){

    my $request2 = $newdbh->prepare("insert into orgunitinfo (profileid,orgunitname,description,nr) values (?,?,?,?)");
    $request2->execute($profileid{$result->{profilename}},$result->{orgunitname},$result->{description},$result->{nr});
    my $insertid   = $newdbh->{'mysql_insertid'};

    $orgunitid{$result->{orgunitname}}=$insertid;
    $orgunitprofileid{$result->{profilename}}{$result->{orgunitname}}=$insertid;
}

# orgunitdbs

$newdbh->do("truncate table orgunit_db");

$request = $olddbh->prepare("select * from orgunitdbs");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $request2 = $newdbh->prepare("insert into orgunit_db (orgunitid,dbid) values (?,?)");
    $request2->execute($orgunitprofileid{$result->{profilename}}{$result->{orgunitname}},$dbid{$result->{dbname}});
}

# viewinfo

my %viewid        = ();

$newdbh->do("truncate table viewinfo");

$request = $olddbh->prepare("select * from viewinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){

    my $request2 = $newdbh->prepare("insert into viewinfo (viewname,description,rssid,start_loc,servername,profileid,stripuri,joinindex,active) values (?,?,?,?,?,?,?,?,?)");
    $request2->execute($result->{viewname},$result->{description},$result->{rssfeed},$result->{start_loc},$result->{servername},$profileid{$result->{profilename}},$result->{stripuri},$result->{joinindex},$result->{active});
    my $insertid   = $newdbh->{'mysql_insertid'};

    $viewid{$result->{viewname}}=$insertid;
}

# viewdbs

$newdbh->do("truncate table view_db");

$request = $olddbh->prepare("select * from viewdbs");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    next unless ($result->{viewname} && $viewid{$result->{viewname}} && $result->{dbname} && $dbid{$result->{dbname}});
    my $request2 = $newdbh->prepare("insert into view_db (viewid,dbid) values (?,?)");
    $request2->execute($viewid{$result->{viewname}},$dbid{$result->{dbname}});
}

# viewrssfeeds

$newdbh->do("truncate table view_rss");

$request = $olddbh->prepare("select * from viewrssfeeds");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    next unless ($result->{viewname} && $viewid{$result->{viewname}} && $result->{rssfeed} );
    my $request2 = $newdbh->prepare("insert into view_rss (viewid,rssid) values (?,?)");
    $request2->execute($viewid{$result->{viewname}},$result->{rssfeed});
}

# rsscache wird nicht migriert

$newdbh->do("truncate table rsscache");

# serverinfo

$newdbh->do("truncate table serverinfo");

$request = $olddbh->prepare("select * from loadbalancertargets");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $request2 = $newdbh->prepare("insert into serverinfo (id,host,active) values (?,?,?)");
    $request2->execute($result->{id},$result->{host},$result->{active});
}
