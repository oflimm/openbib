#!/usr/bin/perl

use DBI;
use OpenBib::Config;
use OpenBib::User;
use YAML;

my $config = new OpenBib::Config;
my $user   = new OpenBib::User;

my $systemdbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd}) or die "could not connect";

my $request=$systemdbh->prepare("select id,username from userinfo where authenticatorid=15");
$request->execute();

my $userinfo_ref = {};

while (my $res=$request->fetchrow_hashref){
    my $username = $res->{username};
    my $id       = $res->{id};

    push @{$userinfo_ref->{$username}}, $id;
}

# Remove valid Accounts
foreach my $username (keys %{$userinfo_ref}){
    my $count = scalar @{$userinfo_ref->{$username}};
    if ($count <= 1){
	$userinfo_ref->{$username} = [];
	delete $userinfo_ref->{$username};
    }
}

print YAML::Dump($userinfo_ref),"\n";

foreach my $username (keys %{$userinfo_ref}){
    my @userids = sort { $a <=> $b } @{$userinfo_ref->{$username}};

    my $smallest_id =  shift @userids;

    foreach my $otherid (@userids){
	print "$username: Migrate $otherid -> $smallest_id\n";
	
	$user->migrate_ugc({
	    olduserid => $otherid,
	    newuserid => $smallest_id,
	    migrate_collections => 1,
	    migrate_litlists => 1,
	    migrate_tags => 1,
			   });
	$user->wipe_account($otherid);
    }    
}


