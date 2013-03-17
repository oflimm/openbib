#!/usr/bin/perl

# Migrationsprogramm von Config/UserDB-Inhalten aus v2.3 nach v2.4 in
# vereinheitlichte System-DB

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

my $systemdbimodule = "Pg";
my $systemdbhost    = "peterhof.ub.uni-koeln.de";
my $systemdbname    = "openbib_system";
my $systemdbuser    = "root";
my $systemdbpasswd  = $passwd; # oder fest ala "StrengGeheim"
my $systemdbport    = "5432";

my $dbdesc_dir      = "/opt/openbib/db";

my $mysqlexe      = "/usr/bin/mysql -u $systemdbuser --password=$systemdbpasswd -f";
my $mysqladminexe = "/usr/bin/mysqladmin -u $systemdbuser --password=$systemdbpasswd -f";

system("echo \"*:*:*:$systemdbuser:$systemdbpasswd\" > ~/.pgpass ; chmod 0600 ~/.pgpass");
system("/usr/bin/dropdb -U $systemdbuser $systemdbname");
system("/usr/bin/createdb -U $systemdbuser -E UTF-8 -O $systemdbuser $systemdbname");

print STDERR "### Datendefinition einlesen\n";

system("/usr/bin/psql -U $systemdbuser -f '$dbdesc_dir/postgresql/system.sql' $systemdbname");
system("/usr/bin/psql -U $systemdbuser -f '$dbdesc_dir/postgresql/system_create_index.sql' $systemdbname");

my $old_orgunits_ref = [
    {
        desc  => 'Fakultätsungebunden',
        nr    => 0,
        short => '0ungeb',
    },
    {
        desc  => 'Wirtschafts- u. Sozialwissenschaftliche Fakultät',
        nr    => 1,
        short => '1wiso',
    },
    {
        desc  => 'Rechtswissenschaftliche Fakultät',
        nr    => 2,
        short => '2recht',
    },
    {
        desc  => 'Humanwissenschaftliche Fakultät',
        nr    => 3,
        short => '3human',
    },
    {
        desc  => 'Philosophische Fakultät',
        nr    => 4,
        short => '4phil',
    },
    {
        desc  => 'Mathematisch-Naturwissenschaftliche Fakultät',
        nr    => 5,
        short => '5matnat',
    },
    {
        desc  => 'Spezialkataloge',
        nr    => 6,
        short => '6spezial',
    },
    {
        desc  => 'Externe Kataloge',
        nr    => 7,
        short => '7extern',
    },
    
];

my $old_orgunits_by_key_ref = {};
foreach my $orgunit_ref (@{$old_orgunits_ref}){
    $old_orgunits_by_key_ref->{$orgunit_ref->{short}} = {
        desc => $orgunit_ref->{desc},
        nr   => $orgunit_ref->{nr},
    };
}

my $olduserdbh = DBI->connect("DBI:mysql:dbname=kuguser;host=$host;port=3306", 'root', $passwd);
my $oldconfigdbh = DBI->connect("DBI:mysql:dbname=config;host=$host;port=3306", 'root', $passwd);

my $newschema;
        
eval {
    $newschema = OpenBib::Schema::System->connect("DBI:$systemdbimodule:dbname=$systemdbname;host=$systemdbhost;port=$systemdbport", $systemdbuser, $systemdbpasswd);
};
        
if ($@){
    print STDERR "Unable to connect schema to database openbib_system: $@";
    exit;
}

# Migration ConfigDB

# databaseinfo

#goto USERINFO;

my %dbid = ();

print STDERR "### databaseinfo\n";

my $dboptions_ref = {};

my $request = $oldconfigdbh->prepare("select * from dboptions");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $dbname = $result->{dbname};

    map { $dboptions_ref->{$dbname}{$_} = $result->{$_} } keys %{$result};

    if ($dboptions_ref->{$dbname}{autfilename} eq "unload.PER.gz"){
        $dboptions_ref->{$dbname}{autfilename} = "meta.person.gz";
    }
    if ($dboptions_ref->{$dbname}{korfilename} eq "unload.KOE.gz"){
        $dboptions_ref->{$dbname}{korfilename} = "meta.corporatebody.gz";
    }
    if ($dboptions_ref->{$dbname}{swtfilename} eq "unload.SWD.gz"){
        $dboptions_ref->{$dbname}{swtfilename} = "meta.subject.gz";
    }
    if ($dboptions_ref->{$dbname}{notfilename} eq "unload.SYS.gz"){
        $dboptions_ref->{$dbname}{notfilename} = "meta.classification.gz";
    }
    if ($dboptions_ref->{$dbname}{titfilename} eq "unload.TIT.gz"){
        $dboptions_ref->{$dbname}{titfilename} = "meta.title.gz";
    }
    if ($dboptions_ref->{$dbname}{mexfilename} eq "unload.MEX.gz"){
        $dboptions_ref->{$dbname}{mexfilename} = "meta.holding.gz";
    }
}

my $titcount_ref      = {};
my $titcount_type_map = {
    1 => 'allcount',
    2 => 'journalcount',
    3 => 'articlecount',
    
};

$request = $oldconfigdbh->prepare("select * from titcount");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $dbname = $result->{dbname};
    my $type   = $titcount_type_map->{$result->{type}};
    my $count  = $result->{count};

    $titcount_ref->{$dbname}{$type}=$count;
}

$request = $oldconfigdbh->prepare("select * from dbinfo order by dbname");

$request->execute();

my $orgunit_db_ref = {};

my $libraryinfo_ref = [];

while (my $result=$request->fetchrow_hashref){
    my $active      = ($result->{active})?'true':'false';
    my $use_libinfo = ($result->{use_libinfo})?'true':'false';
    my $autoconvert = ($dboptions_ref->{$result->{dbname}}{autoconvert})?'true':'false';
    my $circ        = ($dboptions_ref->{$result->{dbname}}{circ})?'true':'false';

    my $new_databaseinfo = $newschema->resultset('Databaseinfo')->create(
        {
            description => $result->{description},
            shortdesc => $result->{shortdesc},
            system => $result->{system},
            dbname => $result->{dbname},
            sigel => $result->{sigel},
            url => $result->{url},
            active => $active,
            protocol => $dboptions_ref->{$result->{dbname}}{protocol},
            host => $dboptions_ref->{$result->{dbname}}{host},
            remotepath => $dboptions_ref->{$result->{dbname}}{remotepath},
            remoteuser => $dboptions_ref->{$result->{dbname}}{remoteuser},
            remotepassword =>$dboptions_ref->{$result->{dbname}}{remotepasswd}  ,
            titlefile => $dboptions_ref->{$result->{dbname}}{titfilename},
            personfile => $dboptions_ref->{$result->{dbname}}{autfilename},
            corporatebodyfile => $dboptions_ref->{$result->{dbname}}{korfilename},
            subjectfile => $dboptions_ref->{$result->{dbname}}{swtfilename},
            classificationfile => $dboptions_ref->{$result->{dbname}}{notfilename},
            holdingfile => $dboptions_ref->{$result->{dbname}}{mexfilename},
            autoconvert => $autoconvert,
            circ => $circ,
            circurl => $dboptions_ref->{$result->{dbname}}{circurl},
            circwsurl => $dboptions_ref->{$result->{dbname}}{circcheckurl},
            circdb => $dboptions_ref->{$result->{dbname}}{circdb},
            allcount => $titcount_ref->{$result->{dbname}}{allcount},
            journalcount => $titcount_ref->{$result->{dbname}}{journalcount},
            articlecount => $titcount_ref->{$result->{dbname}}{articlecount},
            digitalcount => 0,
            
        }
    );

    my $insertid   = $new_databaseinfo->id;

    $dbid{$dboptions_ref->{$result->{dbname}}{dbname}}=$insertid;

    push @{$orgunit_db_ref->{$result->{orgunit}}}, $insertid;
    
    print STDERR $result->{dbname},  " -> ID: ", $dbid{$result->{dbname}} ,"\n";

}


# profileinfo

my %profileid = ();

print STDERR "### profileinfo\n";

$request = $oldconfigdbh->prepare("select * from profileinfo");

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
$request = $oldconfigdbh->prepare("select * from profiledbs");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    $profiledbs_ref->{$profileid{$result->{profilename}}}{$dbid{$result->{dbname}}}=1;
}

# rssinfo

print STDERR "### rssinfo\n";

my %rssid        = ();

$request = $oldconfigdbh->prepare("select * from rssfeeds");

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

$request = $oldconfigdbh->prepare("select * from viewinfo");

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

$request = $oldconfigdbh->prepare("select * from viewdbs");

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

$request = $oldconfigdbh->prepare("select * from viewrssfeeds");

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


#####################################
# Migration der UserDB

my %user_spelling = ();

# Spelling
{
    print STDERR "### spelling\n";

    my $request = $olduserdbh->prepare("select * from spelling");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        $user_spelling{$result->{userid}}{as_you_type} = $result->{as_you_type};
        $user_spelling{$result->{userid}}{resultlist}  = $result->{resultlist};
    }
}


USERINFO:
my %loginname = ();
my %userid_exists = ();
my %username_exists = ();

# userinfo
{
    print STDERR "### userinfo\n";
    
    my $userinfo_ref = [];

    my $request  = $olduserdbh->prepare("select * from user");
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        my $userid    = $result->{userid};
        my $loginname = $result->{loginname};
       
        next if ($userid_exists{$userid});
        next if ($username_exists{$loginname});

        push @$userinfo_ref, {
            id => $userid,
            username => $loginname,
            password => $result->{pin},
            nachname => $result->{nachname},
            vorname => $result->{vorname},
            strasse => $result->{strasse},
            ort => $result->{ort},
            plz => $result->{plz},
            soll => $result->{soll},
            gut => $result->{gut},
            avanz => $result->{avanz},
            branz => $result->{branz},
            bsanz => $result->{bsanz},
            vmanz => $result->{vmanz},
            maanz => $result->{maanz},
            vlanz => $result->{vlanz},
            sperre => $result->{sperre},
            sperrdatum => $result->{sperrdatum},
            gebdatum => $result->{gebdatum},
            email => $result->{email},
            masktype => $result->{masktype},
            autocompletiontype => $result->{autocompletiontype},
            spelling_as_you_type => $user_spelling{$result->{userid}}{as_you_type},
            spelling_resultlist => $user_spelling{$result->{userid}}{resultlist},
            bibsonomy_user => $result->{bibsonomy_user},
            bibsonomy_key => $result->{bibsonomy_key},
            bibsonomy_sync => $result->{bibsonomy_sync},
        };

        $loginname{$loginname} = $userid;
        $userid_exists{$userid} = 1 if ($loginname && $userid);
        $username_exists{$loginname} = 1 if ($loginname && $userid);
        
        print STDERR $userid," - ",$loginname,"\n";
    }

    $newschema->resultset('Userinfo')->populate($userinfo_ref);

#    YAML::Syck::DumpFile("loginname.yml",\%loginname)
}


#START:

#my $loginname_ref = YAML::Syck::LoadFile("loginname.yml");
    
#%loginname = %{$loginname_ref};   

# role
{
    print STDERR "### role\n";
    
    my $request  = $olduserdbh->prepare("select * from role");
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        my $new_role = $newschema->resultset('Role')->create(
            {
                id => $result->{id},
                name => $result->{role},
            }
        );
        
        print STDERR $result->{id}," - ",$result->{role},"\n";
    }
}

# user_role
{
    print STDERR "### role\n";
    
    my $request  = $olduserdbh->prepare("select * from userrole");
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        my $userid = $result->{userid};

        next unless ($userid_exists{$userid});

        my $new_userrole = $newschema->resultset('UserRole')->create(
            {
                userid => $result->{userid},
                roleid => $result->{roleid},
            }
        );
        
        print STDERR $result->{roleid}," - ",$result->{roleid},"\n";
    }
}

# registration
{
    print STDERR "### registration omitted\n";
}

# logintarget
{
    print STDERR "### logintarget\n";
    
    my $request  = $olduserdbh->prepare("select * from logintarget");
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        my $new_logintarget = $newschema->resultset('Authenticator')->create(
            {
                id => $result->{targetid},
                hostname => $result->{hostname},
                port => $result->{port},
                remoteuser => $result->{user},
                dbname => $result->{db},
                description => $result->{description},
                type => $result->{type},
            }
        );
        
        print STDERR $result->{targetid}," - ",$result->{description},"\n";
    }
}

# user_session
{
    print STDERR "### user_session omitted\n";
}

my %searchprofileid = ();

# searchprofile
{
    print STDERR "### searchprofile / user_searchprofile \n";

    my $request  = $olduserdbh->prepare("select * from userdbprofile");
    my $request2 = $olduserdbh->prepare("select * from profildb where profilid = ? order by dbname");
    $request->execute();

    my $searchprofiledb_ref   = [];
    my $usersearchprofile_ref = [];
    while (my $result=$request->fetchrow_hashref){
        my $userid      = $result->{userid};
        my $profilename = $result->{profilename};

        next unless ($userid_exists{$userid});
                     
        $request2->execute($result->{profilid});
        
        my @profiledbs = ();
        while (my $result2=$request2->fetchrow_hashref){
            push @profiledbs, $result2->{dbname};
        }
        
        my $dbs_as_json = encode_json(\@profiledbs);
        
        unless ($searchprofileid{$dbs_as_json}){
            my $new_searchprofile = $newschema->resultset('Searchprofile')->create(
                {
                    databases_as_json => $dbs_as_json,
                    own_index => 'false',
                }
            );
            
            my $insertid   = $new_searchprofile->id;
            
            $searchprofileid{$dbs_as_json}=$insertid;

            foreach my $profiledb (@profiledbs){
                push @$searchprofiledb_ref, {
                    searchprofileid => $insertid,
                    dbid            => $dbid{$profiledb},
                } if ($insertid && $dbid{$profiledb});
            }
        }

        push @$usersearchprofile_ref, {
            searchprofileid => $searchprofileid{$dbs_as_json},
            userid          => $userid,
            profilename     => $profilename,
        };

        print STDERR "Profileid: $searchprofileid{$dbs_as_json} Userid: $userid - Name: $profilename\n";
    }

    $newschema->resultset('SearchprofileDb')->populate($searchprofiledb_ref);
    $newschema->resultset('UserSearchprofile')->populate($usersearchprofile_ref);
}

# searchfield
{
    print STDERR "### searchfield \n";

    my $request  = $olduserdbh->prepare("select * from fieldchoice");
    $request->execute();

    my %userid_done = ();

    my $searchfield_ref = [];
    while (my $result=$request->fetchrow_hashref){
        my $userid = $result->{userid};

        next if ($userid_done{$userid});
        
        $userid_done{$userid} = 1;

        next unless ($userid_exists{$userid});
                     
        my $fs = (defined $result->{fs} && $result->{fs} eq "1")?'true':'false';
        my $title = (defined $result->{hst} && $result->{hst} eq "1")?'true':'false';
        my $person = (defined $result->{verf} && $result->{verf} eq "1")?'true':'false';
        my $corporatebody = (defined $result->{kor} && $result->{kor} eq "1")?'true':'false';
        my $subject = (defined $result->{swt} && $result->{swt} eq "1")?'true':'false';
        my $classification = (defined $result->{notation} && $result->{notation} eq "1")?'true':'false';
        my $isbn = (defined $result->{isbn} && $result->{isbn} eq "1")?'true':'false';
        my $issn = (defined $result->{issn} && $result->{issn} eq "1")?'true':'false';
        my $mark = (defined $result->{sign} && $result->{sign} eq "1")?'true':'false';
        my $mediatype = (defined $result->{mart} && $result->{mart} eq "1")?'true':'false';
        my $titlestring = (defined $result->{hststring} && $result->{hststring} eq "1")?'true':'false';
        my $content = (defined $result->{inhalt} && $result->{inhalt} eq "1")?'true':'false';
        my $source = (defined $result->{gtquelle} && $result->{gtquelle} eq "1")?'true':'false';
        my $year = (defined $result->{ejahr} && $result->{ejahr} eq "1")?'true':'false';

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'freesearch',
            active => $fs,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'title',
            active => $title,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'titlestring',
            active => $titlestring,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'classification',
            active => $classification,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'corporatebody',
            active => $corporatebody,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'subject',
            active => $subject,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'source',
            active => $source,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'person',
            active => $person,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'year',
            active => $year,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'isbn',
            active => $isbn,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'issn',
            active => $issn,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'content',
            active => $content,
        };

        push @$searchfield_ref, {        
            userid => $userid,
            searchfield => 'mediatype',
            active => $mediatype,
        };

        push @$searchfield_ref, {
            userid => $userid,
            searchfield => 'mark',
            active => $mark,
        };
    }

    $newschema->resultset('Searchfield')->populate($searchfield_ref);
}

# livesearch
{
    print STDERR "### livesearch \n";

    my $request  = $olduserdbh->prepare("select * from livesearch");
    $request->execute();

    my $livesearch_ref = [];

    my %userid_done = ();
    while (my $result=$request->fetchrow_hashref){
        
        my $userid = $result->{userid};
        my $exact  = $result->{exact};

        next if ($userid_done{$userid});

        $userid_done{$userid} = 1;
        
        next unless ($userid && $userid_exists{$userid});
        
        my $fs = ($result->{fs} eq "1")?'true':'false';
        my $person = ($result->{verf} eq "1")?'true':'false';
        my $subject = ($result->{swt} eq "1")?'true':'false';

        push @$livesearch_ref, {
            userid => $userid,
            searchfield => 'freesearch',
            exact => $exact,
            active => $fs,
        };

        push @$livesearch_ref, {
            userid => $userid,
            searchfield => 'subject',
            exact => $exact,
            active => $subject,
        };

        push @$livesearch_ref, {
            userid => $userid,
            searchfield => 'person',
            exact => $exact,
            active => $person,
        };
    }

    $newschema->resultset('Livesearch')->populate($livesearch_ref);
}

# collection -> cartitems
{
    print STDERR "### collection \n";

    my $request = $olduserdbh->prepare("select * from treffer");
    
    $request->execute();

    my $cartitems_ref = [];
    my $cartitems_idx = 1;
    my $user_cartitems_ref = [];
    while (my $result=$request->fetchrow_hashref){
        my $userid   = $result->{userid};
        my $dbname   = $result->{dbname};
        my $titleid  = $result->{singleidn};

        next unless ($userid_exists{$userid});

        push @$cartitems_ref, {
            id      => $cartitems_idx,
            dbname  => $dbname,
            titleid => $titleid,
        };
        
        push @$user_cartitems_ref, {
            userid  => $userid,
            cartitemid => $cartitems_idx,
        };

        $cartitems_idx++;
    }
    $newschema->resultset('Cartitem')->populate($cartitems_ref);
    $newschema->resultset('UserCartitem')->populate($user_cartitems_ref);

}

# tag
{
    print STDERR "### tag \n";

    my $request = $olduserdbh->prepare("select * from tags");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){        
        my $id       = $result->{id};
        my $name     = $result->{tag};

        $newschema->resultset('Tag')->create(
            {
                id => $id,
                name => $name,
            }
        );
    }

}

# tit_tag
{
    print STDERR "### tit_tag \n";

    my $request = $olduserdbh->prepare("select * from tittag");
    
    $request->execute();

    my $tittag_ref = [];
    while (my $result=$request->fetchrow_hashref){        
        my $id        = $result->{ttid};
        my $tagid     = $result->{tagid};
        my $titleid   = $result->{titid};
        my $titleisbn = $result->{titisbn};
        my $dbname    = $result->{titdb};
        my $loginname = $result->{loginname};
        my $type      = $result->{type};

        my $userid    = $loginname{$loginname};

        next unless ($userid && $userid_exists{$userid});

        push @$tittag_ref, {
            id => $id,
            tagid => $tagid,
            userid => $userid,
            dbname => $dbname,
            titleid => $titleid,
            titleisbn => $titleisbn,
            type => $type,
        } if ($dbname && $titleid);
    }
    
    $newschema->resultset('TitTag')->populate($tittag_ref);
}

# review
{
    print STDERR "### review \n";

    my $request = $olduserdbh->prepare("select * from reviews");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){        
        my $id         = $result->{id};
        my $tstamp     = $result->{tstamp};
        my $titleid    = $result->{titleid};
        my $titleisbn  = $result->{titisbn};
        my $dbname     = $result->{dbname};
        my $loginname  = $result->{loginname};
        my $nickname   = $result->{nickname};
        my $title      = $result->{title};
        my $reviewtext = $result->{review};
        my $rating     = $result->{rating};

        my $userid     = $loginname{$loginname};

        next unless ($userid_exists{$userid});
        
        $newschema->resultset('Review')->create(
            {
                id => $id,
                userid => $userid,
                nickname => $nickname,
                title => $title,
                reviewtext => $reviewtext,
                rating => $rating,
                dbname => $dbname,
                titleid => $titleid,
                titleisbn => $titleisbn,
            }
        ) if ($dbname && $titleid);
    }


}

# reviewrating
{
    print STDERR "### reviewrating \n";

    my $request = $olduserdbh->prepare("select * from reviewratings");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){        
        my $id         = $result->{id};
        my $tstamp     = $result->{tstamp};
        my $reviewid   = $result->{reviewid};
        my $loginname  = $result->{loginname};
        my $rating     = $result->{rating};

        my $userid     = $loginname{$loginname};

        next unless ($userid_exists{$userid});

        $newschema->resultset('Reviewrating')->create(
            {
                id => $id,
                userid => $userid,
                reviewid => $reviewid,
                tstamp => $tstamp,
                rating => $rating,
            }
        );
    }

}

# litlist
my %litlistid_exists = ();

{
    print STDERR "### litlist \n";
    
    my $request = $olduserdbh->prepare("select * from litlists");
    
    $request->execute();

    my $litlist_ref = [];
    
    while (my $result=$request->fetchrow_hashref){        
        my $id         = $result->{id};
        my $tstamp     = $result->{tstamp};
        my $userid     = $result->{userid};
        my $title      = $result->{title};
        my $type       = $result->{type};
        my $lecture    = ($result->{lecture})?'true':'false';

        next unless ($userid_exists{$userid});

        $litlistid_exists{$id} = 1;
        
        push @$litlist_ref, {
            id => $id,
            userid => $userid,
            tstamp => $tstamp,
            title => $title,
            type => $type,
            lecture => $lecture,
        };
    }
    
    $newschema->resultset('Litlist')->populate($litlist_ref);
}

# litlistitem
{
    print STDERR "### litlistitem \n";

    my $request = $olduserdbh->prepare("select * from litlistitems");
    
    $request->execute();

    my $litlistitem_ref = [];
    
    while (my $result=$request->fetchrow_hashref){
        my $litlistid  = $result->{litlistid};
        my $tstamp     = $result->{tstamp};
        my $titleid    = $result->{titid};
        my $titleisbn  = $result->{titisbn};
        my $dbname     = $result->{titdb};

        next unless ($litlistid_exists{$litlistid});

        push @$litlistitem_ref, {
            litlistid => $litlistid,
            tstamp => $tstamp,
            dbname => $dbname,
            titleid => $titleid,
            titleisbn => $titleisbn,
        } if ($dbname && $titleid);
    }

    $newschema->resultset('Litlistitem')->populate($litlistitem_ref);

}

# subject
{
    print STDERR "### subject \n";
    
    my $request = $olduserdbh->prepare("select * from subjects");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){        
        my $id          = $result->{id};
        my $name        = $result->{name};
        my $description = $result->{description};

        print STDERR "$id - $name - $description\n";
        
        $newschema->resultset('Topic')->create(
            {
                id => $id,
                name => $name,
                description => $description,
            }
        );
    }

}

# litlist_subject
{
    print STDERR "### litlist_subject \n";
    
    my $request = $olduserdbh->prepare("select * from litlist2subject");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){        
        my $litlistid   = $result->{litlistid};
        my $subjectid   = $result->{subjectid};

        next unless ($litlistid_exists{$litlistid});

        $newschema->resultset('LitlistTopic')->create(
            {
                litlistid => $litlistid,
                topicid => $subjectid,
                }
        );
    }

}

# subjectclassification
{
    print STDERR "### subjectclassification \n";
    
    my $request = $olduserdbh->prepare("select * from subject2classification");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){        
        my $subjectid        = $result->{subjectid};
        my $classification   = $result->{classification};
        my $type             = $result->{type};
        
        $newschema->resultset('Topicclassification')->create(
            {
                topicid        => $subjectid,
                classification => $classification,
                type           => $type,
            }
        );
    }

}

print STDERR "### ENDE der Migration \n";

