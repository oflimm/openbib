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
use OpenBib::Database::Catalog;

my $host=$ARGV[0];
my $passwd=$ARGV[1];

my $config        = new OpenBib::Config;

my $mysqlexe      = "/usr/bin/mysql -u $config->{'systemdbuser'} --password=$config->{'systemdbpasswd'} -f";
my $mysqladminexe = "/usr/bin/mysqladmin -u $config->{'systemdbuser'} --password=$config->{'systemdbpasswd'} -f";

if ($config->{systemdbimodule} eq "Pg"){
    system("echo \"*:*:*:$config->{'systemdbuser'}:$config->{'systemdbpasswd'}\" > ~/.pgpass ; chmod 0600 ~/.pgpass");
    system("/usr/bin/dropdb -U $config->{'systemdbuser'} $config->{'systemdbpasswd'} $config->{'systemdbname'}");
    system("/usr/bin/createdb -U $config->{'systemdbuser'} -E UTF-8 -O $config->{'systemdbuser'} $config->{'systemdbname'}");

    print STDERR "### Datendefinition einlesen\n";

    system("/usr/bin/psql -U $config->{'systemdbuser'} -f '$config->{'dbdesc_dir'}/postgresql/system.sql' $config->{'systemdbname'}");
    system("/usr/bin/psql -U $config->{'systemdbuser'} -f '$config->{'dbdesc_dir'}/postgresql/system_create_index.sql' $config->{'systemdbname'}");
}
elsif ($config->{systemdbimodule} eq "mysql"){
    system("$mysqladminexe drop   $config->{systemdbname}");
    system("$mysqladminexe create  $config->{systemdbname}");
    
    print STDERR "### Datendefinition einlesen\n";
    
    system("$mysqlexe  $config->{systemdbname} < $config->{'dbdesc_dir'}/mysql/system.mysql");
}
       
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
    if ($config->{systemdbimodule} eq "Pg"){
        $newschema = OpenBib::Database::System->connect("DBI:$config->{systemdbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd});
    }
    elsif ($config->{systemdbimodule} eq "mysql"){
        $newschema = OpenBib::Database::System->connect("DBI:$config->{systemdbimodule}:dbname=$config->{systemdbname};host=$config->{systemdbhost};port=$config->{systemdbport}", $config->{systemdbuser}, $config->{systemdbpasswd},,{'mysql_enable_utf8'    => 1, on_connect_do => [ q|SET NAMES 'utf8'| ,]})
    }
};
        
if ($@){
    print STDERR "Unable to connect schema to database openbib_system: $@";
    exit;
}

# Migration ConfigDB

# databaseinfo

my %dbid = ();

print STDERR "### databaseinfo\n";

my $dboptions_ref = {};

my $request = $oldconfigdbh->prepare("select * from dboptions");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    my $dbname = $result->{dbname};

    map { $dboptions_ref->{$dbname}{$_} = $result->{$_} } keys %{$result};
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

while (my $result=$request->fetchrow_hashref){
    my $active = ($result->{active})?'true':'false';
    my $new_databaseinfo = $newschema->resultset('Databaseinfo')->create(
        {
            description => $result->{description},
            shortdesc => $result->{shortdesc},
            system => $result->{system},
            dbname => $result->{dbname},
            sigel => $result->{sigel},
            url => $result->{url},
            use_libinfo => $result->{use_libinfo},
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
            autoconvert => $dboptions_ref->{$result->{dbname}}{autoconvert},
            circ => $dboptions_ref->{$result->{dbname}}{circ},
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

    # libraryinfo
    
    print STDERR "### libraryinfo\n";
    
    my $request2 = $oldconfigdbh->prepare("select * from libraryinfo where dbname=?");
    
    $request2->execute($result->{dbname});

    my $category_contents_ref = [];
    while (my $result2=$request2->fetchrow_hashref){
        next unless ($result2->{category} && $result2->{content});
        push @$category_contents_ref, {
            dbid     => $insertid,
            indicator => 1,
            category => $result2->{category},
            content  => $result2->{content},
        };
    }
    
    $newschema->resultset('Libraryinfo')->populate($category_contents_ref);
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

while (my $result=$request->fetchrow_hashref){
    if (!$result->{dbname} || ! $dbid{$result->{dbname}}){
        print STDERR "Ziel $result->{dbname} existiert nicht in databaseinfo\n"; 
        next;
    }

    print STDERR $result->{dbname},  "\n";

    my $active = ($result->{active})?'true':'false';
    
    my $new_rssinfo = $newschema->resultset('Rssinfo')->create(
        {
            id => $result->{id},
            dbid => $dbid{$result->{dbname}},
            type => $result->{type},
            subtype => $result->{subtype},
            subtypedesc => $result->{subtypedesc},
            active => $active,
        }
    ); 
}

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

        $newschema->resultset('OrgunitDb')->populate($orgunitdbs_ref);
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
                stripuri => 0,
                joinindex => 0,
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

while (my $result=$request->fetchrow_hashref){
    next unless ($result->{viewname} && $viewid{$result->{viewname}} && $result->{dbname} && $dbid{$result->{dbname}});

    my $new_viewinfo = $newschema->resultset('Viewinfo')->create(
        {
            dbid   => $dbid{$result->{dbname}},
            viewid => $viewid{$result->{viewname}},
        }
    );
}

# viewrssfeeds

print STDERR "### view_rss\n";

$request = $oldconfigdbh->prepare("select * from viewrssfeeds");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    next unless ($result->{viewname} && $viewid{$result->{viewname}} && $result->{rssfeed} );

    my $new_viewrss = $newschema->resultset('ViewRss')->create(
        {
            rssid   => $result->{rssfeed},
            viewid  => $viewid{$result->{viewname}},
        }
    );
}

# serverinfo

print STDERR "### serverinfo\n";

$request = $oldconfigdbh->prepare("select * from loadbalancertargets");

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

#goto START;

my %loginname = ();
my %userid_exists = ();

# userinfo
{
    print STDERR "### userinfo\n";

    my $request  = $olduserdbh->prepare("select * from user");
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        my $userid    = $result->{userid};
        my $loginname = $result->{loginname};

        my $new_userinfo = $newschema->resultset('Userinfo')->create(
            {
                id => $userid,
                lastlogin => $result->{lastlogin},
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
            }
        );
        
        $loginname{$loginname} = $userid;
        $userid_exists{$userid} = 1 if ($loginname && $userid);
        
        print STDERR $userid," - ",$loginname,"\n";
    }

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
        my $new_logintarget = $newschema->resultset('Logintarget')->create(
            {
                id => $result->{targetid},
                hostname => $result->{hostname},
                port => $result->{port},
                user => $result->{user},
                db => $result->{db},
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
                }
            );
            
            my $insertid   = $new_searchprofile->id;
            
            $searchprofileid{$dbs_as_json}=$insertid;

            foreach my $profiledb (@profiledbs){
                my $new_searchprofiledbs = $newschema->resultset('SearchprofileDb')->create(
                    {
                        searchprofileid => $insertid,
                        dbid => $dbid{$profiledb},
                    }
                );
            }
        }

        my $new_usersearchprofile = $newschema->resultset('UserSearchprofile')->create(
            {
                searchprofileid => $searchprofileid{$dbs_as_json},
                userid => $userid,
                profilename => $profilename,
            }
        );

        print STDERR "Profileid: $searchprofileid{$dbs_as_json} Userid: $userid - Name: $profilename\n";
    }

}

# searchfield
{
    print STDERR "### searchfield \n";

    my $request  = $olduserdbh->prepare("select * from fieldchoice");
    $request->execute();

    my %userid_done = ();
    
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

        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'freesearch',
                active => $fs,
            }
        );

        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'title',
                active => $title,
            }
        );
        
        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'titlestring',
                active => $titlestring,
            }
        );

        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'classification',
                active => $classification,
            }
        );
        
        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'corporatebody',
                active => $corporatebody,
            }
        );
        
        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'subject',
                active => $subject,
            }
        );

        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'source',
                active => $source,
            }
        );

        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'person',
                active => $person,
            }
        );

        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'year',
                active => $year,
            }
        );

        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'isbn',
                active => $isbn,
            }
        );

        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'issn',
                active => $issn,
            }
        );

        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'content',
                active => $content,
            }
        );
        
        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'mediatype',
                active => $mediatype,
            }
        );

        $newschema->resultset('Searchfield')->create(
            {
                userid => $userid,
                searchfield => 'mark',
                active => $mark,
            }
        );
        
        print STDERR $userid,"\n";
    }

}

# livesearch
{
    print STDERR "### livesearch \n";

    my $request  = $olduserdbh->prepare("select * from livesearch");
    $request->execute();

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

        $newschema->resultset('Livesearch')->create(
            {
                userid => $userid,
                searchfield => 'freesearch',
                exact => $exact,
                active => $fs,
            }
        );

        $newschema->resultset('Livesearch')->create(
            {
                userid => $userid,
                searchfield => 'subject',
                exact => $exact,
                active => $subject,
            }
        );

        $newschema->resultset('Livesearch')->create(
            {
                userid => $userid,
                searchfield => 'person',
                exact => $exact,
                active => $person,
            }
        );

        print STDERR $userid,"\n";
    }

}

# collection    
{
    print STDERR "### collection \n";

    my $request = $olduserdbh->prepare("select * from treffer");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){        
        my $userid   = $result->{userid};
        my $dbname   = $result->{dbname};
        my $titleid  = $result->{singleidn};

        next unless ($userid_exists{$userid});

        $newschema->resultset('Collection')->create(
            {
                userid  => $userid,
                dbname  => $dbname,
                titleid => $titleid,
            }
        );
    }

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

        $newschema->resultset('TitTag')->create(
            {
                id => $id,
                tagid => $tagid,
                userid => $userid,
                dbname => $dbname,
                titleid => $titleid,
                titleisbn => $titleisbn,
                type => $type,
            }
        );
    }

}

# review
{
    print STDERR "### review \n";

    my $request = $olduserdbh->prepare("select * from reviews");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){        
        my $id         = $result->{id};
        my $tstamp     = $result->{tstamp};
        my $titleid    = $result->{titid};
        my $titleisbn  = $result->{titisbn};
        my $dbname     = $result->{titdb};
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
        );
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
{
    print STDERR "### litlist \n";

    my $request = $olduserdbh->prepare("select * from litlists");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){        
        my $id         = $result->{id};
        my $tstamp     = $result->{tstamp};
        my $userid     = $result->{userid};
        my $title      = $result->{title};
        my $type       = $result->{type};
        my $lecture    = $result->{lecture};

        next unless ($userid_exists{$userid});

        $newschema->resultset('Litlist')->create(
            {
                id => $id,
                userid => $userid,
                tstamp => $tstamp,
                title => $title,
                type => $type,
                lecture => $lecture,
            }
        );
    }

}

# litlistitem
{
    print STDERR "### litlistitem \n";

    my $request = $olduserdbh->prepare("select * from litlistitems");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){        
        my $litlistid  = $result->{litlistid};
        my $tstamp     = $result->{tstamp};
        my $titleid    = $result->{titid};
        my $titleisbn  = $result->{titisbn};
        my $dbname     = $result->{titdb};

        $newschema->resultset('Litlistitem')->create(
            {
                litlistid => $litlistid,
                tstamp => $tstamp,
                dbname => $dbname,
                titleid => $titleid,
                titleisbn => $titleisbn,
            }
        );
    }

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
        
        $newschema->resultset('Subject')->create(
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

        $newschema->resultset('LitlistSubject')->create(
            {
                litlistid => $litlistid,
                subjectid => $subjectid,
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
        
        $newschema->resultset('LitlistSubject')->create(
            {
                subjectid => $subjectid,
                classification => $classification,
                type => $type,
            }
        );
    }

}

print STDERR "### ENDE der Migration \n";

