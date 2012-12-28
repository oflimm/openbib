#!/usr/bin/perl

# Migrationsprogramm von EnrichmentDB-Inhalten aus v2.3 nach v3

use warnings;
use strict;
use utf8;

use DBI;
use Encode qw/encode_utf8 decode_utf8/;
use JSON::XS qw(encode_json decode_json);
use YAML::Syck;
use OpenBib::Config;
use OpenBib::Schema::Catalog;

my $host   = $ARGV[0];
my $passwd = $ARGV[1];

# Hier anpassen, denn:
# Das Config-Objekt kann nicht verwendet werden, da es selbst eine Verbindung zur System-DB
# oeffnet und damit eine Entfernung der DB nicht moeglich ist!!!

my $enrichmntdbimodule = "Pg";
my $enrichmntdbhost    = "localhost";
my $enrichmntdbname    = "openbib_enrichmnt";
my $enrichmntdbuser    = "root";
my $enrichmntdbpasswd  = $passwd; # oder fest ala "StrengGeheim"
my $enrichmntdbport    = "5432";

my $dbdesc_dir      = "/opt/openbib/db";

my $mysqlexe      = "/usr/bin/mysql -u $enrichmntdbuser --password=$enrichmntdbpasswd -f";
my $mysqladminexe = "/usr/bin/mysqladmin -u $enrichmntdbuser --password=$enrichmntdbpasswd -f";

system("echo \"*:*:*:$enrichmntdbuser:$enrichmntdbpasswd\" > ~/.pgpass ; chmod 0600 ~/.pgpass");
system("/usr/bin/dropdb -U $enrichmntdbuser $enrichmntdbname");
system("/usr/bin/createdb -U $enrichmntdbuser -E UTF-8 -O $enrichmntdbuser $enrichmntdbname");

print STDERR "### Datendefinition einlesen\n";

system("/usr/bin/psql -U $enrichmntdbuser -f '$dbdesc_dir/postgresql/enrichmnt.sql' $enrichmntdbname");
system("/usr/bin/psql -U $enrichmntdbuser -f '$dbdesc_dir/postgresql/enrichmnt_create_index.sql' $enrichmntdbname");

my $oldenrichmntdbh = DBI->connect("DBI:mysql:dbname=enrichmnt;host=$host;port=3306", 'root', $passwd);

my $newschema;
        
eval {
    $newschema = OpenBib::Schema::Enrichment->connect("DBI:$enrichmntdbimodule:dbname=$enrichmntdbname;host=$enrichmntdbhost;port=$enrichmntdbport", $enrichmntdbuser, $enrichmntdbpasswd);
};
        
if ($@){
    print STDERR "Unable to connect schema to database openbib_enrichmnt: $@";
    exit;
}

# Migration EnrichmntDB

# normdata

my $enriched_content_by_isbn_ref = [];
my $enriched_content_by_issn_ref = [];
my $enriched_content_by_bibkey_ref = [];

my $request = $oldenrichmntdbh->prepare("select * from normdata");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $isbn        = $result->{isbn};
    my $origin      = $result->{origin};
    my $field       = $result->{category};
    my $mult        = $result->{indicator};
    my $content      = $result->{content};

    push @$enriched_content_by_isbn_ref, {
        dbid     => $insertid,
        indicator => 1,
        category => $result2->{category},
        content  => $result2->{content},
    } if (length(isbn) == 13 );
    
    push @$enriched_content_by_issn_ref, {
        dbid     => $insertid,
        indicator => 1,
        category => $result2->{category},
        content  => $result2->{content},
    } if (length(isbn) == 8) ;
    
    push @$enriched_content_by_bibkey_ref, {
        dbid     => $insertid,
        indicator => 1,
        category => $result2->{category},
        content  => $result2->{content},
    } if (length(isbn) > 30) ;

}

$newschema->resultset('EnrichedContentByIsbn')->populate($enriched_content_by_isbn_ref);
$newschema->resultset('EnrichedContentByIssn')->populate($enriched_content_by_issn_ref);
$newschema->resultset('EnrichedContentByBibkey')->populate($enriched_content_by_bibkey_ref);

# similar_isbn

my $enriched_content_by_isbn_ref = [];
my $enriched_content_by_issn_ref = [];
my $enriched_content_by_bibkey_ref = [];

my $request = $oldenrichmntdbh->prepare("select * from normdata");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $isbn        = $result->{isbn};
    my $origin      = $result->{origin};
    my $field       = $result->{category};
    my $mult        = $result->{indicator};
    my $content      = $result->{content};

    push @$enriched_content_by_isbn_ref, {
        dbid     => $insertid,
        indicator => 1,
        category => $result2->{category},
        content  => $result2->{content},
    } if (length(isbn) == 13 );
}

print STDERR "### profileinfo\n";

$request = $oldenrichmntdbh->prepare("select * from profileinfo");

$request->execute();

my $profileinfos_ref = [];

while (my $result=$request->fetchrow_hashref){
    print STDERR $result->{profilename},  "\n";

    my $new_profileinfo = $newschema->resultset('Profileinfo')->create(
        {
            profilename => $result->{profilename},
            description => $result->{description},
        }
    );

    my $insertid   = $new_profileinfo->id;
    
    $profileid{$result->{profilename}}=$insertid;

    push @{$profileinfos_ref}, {
        profilename => $result->{profilename},
        description => $result->{description},
        id          => $insertid,
    };
    
    print STDERR $result->{profilename},  " -> ID: ", $profileid{$result->{profilename}} ,"\n";
}

# profiledb

my $profiledbs_ref = {};
$request = $oldenrichmntdbh->prepare("select * from profiledbs");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    $profiledbs_ref->{$profileid{$result->{profilename}}}{$dbid{$result->{dbname}}}=1;
}

# rssinfo

print STDERR "### rssinfo\n";

my %rssid        = ();

$request = $oldenrichmntdbh->prepare("select * from rssfeeds");

$request->execute();

my $rssinfo_ref = [];

while (my $result=$request->fetchrow_hashref){
    if (!$result->{dbname} || ! $dbid{$result->{dbname}}){
        print STDERR "Ziel $result->{dbname} existiert nicht in databaseinfo\n"; 
        next;
    }

    my $active = ($result->{active})?'true':'false';

    push @$rssinfo_ref, {
        id          => $result->{id},
        dbid        => $dbid{$result->{dbname}},
        type        => $result->{type},
        subtype     => $result->{subtype},
        subtypedesc => $result->{subtypedesc},
        active      => $active,
    };
}

$newschema->resultset('Rssinfo')->populate($rssinfo_ref);

# orgunitinfo

print STDERR "### orgunitinfo fuer jedes Profil\n";

my %orgunitid        = ();
my %orgunitprofileid = ();

foreach my $profileinfo_ref (@{$profileinfos_ref}){
    if (!$profileinfo_ref->{profilename} || ! $profileinfo_ref->{id}){
        print STDERR "Ziel $profileinfo_ref->{profilename} existiert nicht in profileinfo\n"; 
        next;
    }

    foreach my $old_orgunit_ref (@{$old_orgunits_ref}){
        my $new_orgunitinfo = $newschema->resultset('Orgunitinfo')->create(
            {
                profileid => $profileinfo_ref->{id},
                orgunitname => $old_orgunit_ref->{short},
                description => $old_orgunit_ref->{desc},
                nr => $old_orgunit_ref->{nr},
            }
        ); 

        my $insertid   = $new_orgunitinfo->id;
        
        $orgunitid{$old_orgunit_ref->{short}}=$insertid;
        $orgunitprofileid{$profileinfo_ref->{profilename}}{$old_orgunit_ref->{short}}=$insertid;
        
        print STDERR $old_orgunit_ref->{short},  " -> ID: ", $orgunitid{$old_orgunit_ref->{short}} ,"\n";


        my $orgunitdbs_ref = [];
        foreach my $dbid (@{$orgunit_db_ref->{$old_orgunit_ref->{short}}}){
            push @$orgunitdbs_ref, {
                orgunitid     => $insertid,
                dbid          => $dbid,
            } if ($profiledbs_ref->{$profileinfo_ref->{id}}{$dbid});
        }

        print STDERR (encode_json $orgunitdbs_ref), "\n";
        if (@$orgunitdbs_ref){
            $newschema->resultset('OrgunitDb')->populate($orgunitdbs_ref);
        }
    }
}

# viewinfo

print STDERR "### viewinfo\n";

my %viewid        = ();

$request = $oldenrichmntdbh->prepare("select * from viewinfo");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $active = ($result->{active})?'true':'false';
    
    my $new_viewinfo = $newschema->resultset('Viewinfo')->create(
            {
                viewname => $result->{viewname},
                description => $result->{description},
                rssid => $result->{rssfeed},
                start_loc => $result->{start_loc},
                servername => "",
                profileid => $profileid{$result->{profilename}},
                stripuri => 'false',
                active => $active,
            }
        ); 

    my $insertid   = $new_viewinfo->id;

    $viewid{$result->{viewname}}=$insertid;

    print STDERR $result->{viewname},  " -> ID: ", $viewid{$result->{viewname}} ,"\n";

}

# viewdbs

print STDERR "### viewdbs\n";

$request = $oldenrichmntdbh->prepare("select * from viewdbs");

$request->execute();

my $viewdb_ref = [];

while (my $result=$request->fetchrow_hashref){
    next unless ($result->{viewname} && $viewid{$result->{viewname}} && $result->{dbname} && $dbid{$result->{dbname}});

    push @$viewdb_ref, {
        dbid   => $dbid{$result->{dbname}},
        viewid => $viewid{$result->{viewname}},
    };
}

$newschema->resultset('ViewDb')->populate($viewdb_ref);

# viewrssfeeds

print STDERR "### view_rss\n";

$request = $oldenrichmntdbh->prepare("select * from viewrssfeeds");

$request->execute();

my $viewrss_ref = [];
while (my $result=$request->fetchrow_hashref){
    next unless ($result->{viewname} && $viewid{$result->{viewname}} && $result->{rssfeed} );

    push @$viewrss_ref, {
        rssid   => $result->{rssfeed},
        viewid  => $viewid{$result->{viewname}},
    };

}

$newschema->resultset('ViewRss')->populate($viewrss_ref);

# serverinfo

print STDERR "### serverinfo\n";

$request = $oldenrichmntdbh->prepare("select * from loadbalancertargets");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $active = ($result->{active})?'true':'false';
    
    my $new_serverinfo = $newschema->resultset('Serverinfo')->create(
        {
            id     => $result->{id},
            host   => $result->{host},
            active => $active,
        }
    );
}

print STDERR "### ENDE der Migration \n";

