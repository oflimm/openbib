#!/usr/bin/perl

# Migrationsprogramm von UserDB-Inhalten aus v2.3 nach v2.4 (dann in
# vereinheitlichter System-DB

use warnings;
use strict;

use DBI;
use Encode qw/encode_utf8 decode_utf8/;
use JSON::XS qw(encode_json decode_json);
use YAML::Syck;

my $passwd=$ARGV[0];

my $olddbh = DBI->connect("DBI:mysql:dbname=user;host=localhost;port=3306", 'root', $passwd);
my $newdbh = DBI->connect("DBI:mysql:dbname=openbib_system;host=localhost;port=3306", 'root', $passwd);

$newdbh->do("truncate table subjectclassification");
$newdbh->do("truncate table litlist_subject");
$newdbh->do("truncate table subject");
$newdbh->do("truncate table litlistitem");
$newdbh->do("truncate table litlist");
$newdbh->do("truncate table reviewratings");
$newdbh->do("truncate table review");
$newdbh->do("truncate table tit_tag");
$newdbh->do("truncate table tag");
$newdbh->do("truncate table collection");
$newdbh->do("truncate table livesearch");
$newdbh->do("truncate table searchfield");
$newdbh->do("truncate table user_profile");
$newdbh->do("truncate table searchprofile");
$newdbh->do("truncate table user_session");
$newdbh->do("truncate table logintarget");
$newdbh->do("truncate table registration");
$newdbh->do("truncate table user_role");
$newdbh->do("truncate table role");
$newdbh->do("truncate table userinfo");

my %user_spelling = ();

$newdbh->do(qq{SET AUTOCOMMIT = 0});

# Spelling
{
    print STDERR "### spelling\n";

    my $request = $olddbh->prepare("select * from spelling");
    
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

    $newdbh->do(qq{ALTER TABLE userinfo DISABLE KEYS});
    
    my $request  = $olddbh->prepare("select * from user");
    my $request2 = $newdbh->prepare("insert into userinfo (id,lastlogin,loginname,pin,nachname,vorname,strasse,ort,plz,soll,gut,avanz,branz,bsanz,vmanz,maanz,vlanz,sperre,sperrdatum,gebdatum,email,masktype,autocompletiontype,spelling_as_you_type,spelling_resultlist,bibsonomy_user,bibsonomy_key,bibsonomy_sync) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");    

    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        my $userid    = $result->{userid};
        my $loginname = $result->{loginname};
        
        $request2->execute($userid,$result->{lastlogin},$loginname,$result->{pin},$result->{nachname},$result->{vorname},$result->{strasse},$result->{ort},$result->{plz},$result->{soll},$result->{gut},$result->{avanz},$result->{branz},$result->{bsanz},$result->{vmanz},$result->{maanz},$result->{vlanz},$result->{sperre},$result->{sperrdatum},$result->{gebdatum},$result->{email},$result->{masktype},$result->{autocompletiontype},$user_spelling{$result->{userid}}{as_you_type},$user_spelling{$result->{userid}}{resultlist},$result->{bibsonomy_user},$result->{bibsonomy_key},$result->{bibsonomy_sync});
        $loginname{$loginname} = $userid;
        $userid_exists{$userid} = 1 if ($loginname && $userid);
        
        print STDERR $userid," - ",$loginname,"\n";
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE userinfo ENABLE KEYS});
#    YAML::Syck::DumpFile("loginname.yml",\%loginname)
}


#START:

#my $loginname_ref = YAML::Syck::LoadFile("loginname.yml");
    
#%loginname = %{$loginname_ref};   

# role
{
    print STDERR "### role\n";
    
    my $request  = $olddbh->prepare("select * from role");
    my $request2 = $newdbh->prepare("insert into role (id,role) values (?,?)");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        $request2->execute($result->{id},$result->{role});
        
        print STDERR $result->{id}," - ",$result->{role},"\n";
    }
}

# user_role
{
    print STDERR "### role\n";
    
    my $request  = $olddbh->prepare("select * from userrole");
    my $request2 = $newdbh->prepare("insert into user_role (userid,roleid) values (?,?)");
    
    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        my $userid = $result->{userid};

        next unless ($userid_exists{$userid});
        
        $request2->execute($result->{userid},$result->{roleid});
        
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
    
    my $request  = $olddbh->prepare("select * from logintarget");
    my $request2 = $newdbh->prepare("insert into logintarget (id,hostname,port,user,db,description,type) values (?,?,?,?,?,?,?)");    

    $request->execute();
    
    while (my $result=$request->fetchrow_hashref){
        $request2->execute($result->{targetid},$result->{hostname},$result->{port},$result->{user},$result->{db},$result->{description},$result->{type});
        
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
    print STDERR "### searchprofile / user_profile \n";

    $newdbh->do(qq{ALTER TABLE searchprofile DISABLE KEYS});
    $newdbh->do(qq{ALTER TABLE user_profile DISABLE KEYS});
         
    my $request  = $olddbh->prepare("select * from userdbprofile");
    my $request2 = $olddbh->prepare("select * from profildb where profilid = ? order by dbname");
    my $request3 = $newdbh->prepare("insert into searchprofile (databases_as_json) values (?)");
    my $request4 = $newdbh->prepare("insert into user_profile (profileid,userid,profilename) values (?,?,?)");
    
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
            $request3->execute($dbs_as_json);
            
            my $insertid   = $newdbh->{'mysql_insertid'};
            
            $searchprofileid{$dbs_as_json}=$insertid;
        }
        
        $request4->execute($searchprofileid{$dbs_as_json},$userid,$profilename);
        
        print STDERR "Profileid: $searchprofileid{$dbs_as_json} Userid: $userid - Name: $profilename\n";
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE searchprofile ENABLE KEYS});
    $newdbh->do(qq{ALTER TABLE user_profile ENABLE KEYS});
}

# searchfield
{
    print STDERR "### searchfield \n";

    $newdbh->do(qq{ALTER TABLE searchfield DISABLE KEYS});

    my $request  = $olddbh->prepare("select * from fieldchoice");
    my $request2 = $newdbh->prepare("insert into searchfield (userid,searchfield,active) values (?,?,?)");
    
    $request->execute();

    my %userid_done = ();
    
    while (my $result=$request->fetchrow_hashref){
        my $userid = $result->{userid};

        next if ($userid_done{$userid});
        
        $userid_done{$userid} = 1;

        next unless ($userid_exists{$userid});
                     
        my $fs = (defined $result->{fs} && $result->{fs} eq "1")?1:0;
        my $title = (defined $result->{hst} && $result->{hst} eq "1")?1:0;
        my $person = (defined $result->{verf} && $result->{verf} eq "1")?1:0;
        my $corporatebody = (defined $result->{kor} && $result->{kor} eq "1")?1:0;
        my $subject = (defined $result->{swt} && $result->{swt} eq "1")?1:0;
        my $classification = (defined $result->{notation} && $result->{notation} eq "1")?1:0;
        my $isbn = (defined $result->{isbn} && $result->{isbn} eq "1")?1:0;
        my $issn = (defined $result->{issn} && $result->{issn} eq "1")?1:0;
        my $mark = (defined $result->{sign} && $result->{sign} eq "1")?1:0;
        my $mediatype = (defined $result->{mart} && $result->{mart} eq "1")?1:0;
        my $titlestring = (defined $result->{hststring} && $result->{hststring} eq "1")?1:0;
        my $content = (defined $result->{inhalt} && $result->{inhalt} eq "1")?1:0;
        my $source = (defined $result->{gtquelle} && $result->{gtquelle} eq "1")?1:0;
        my $year = (defined $result->{ejahr} && $result->{ejahr} eq "1")?1:0;
        
        $request2->execute($userid,'freesearch',$fs);
        $request2->execute($userid,'title',$title);
        $request2->execute($userid,'titlestring',$titlestring);
        $request2->execute($userid,'classification',$classification);
        $request2->execute($userid,'corporatebody',$corporatebody);
        $request2->execute($userid,'subject',$subject);
        $request2->execute($userid,'source',$source);
        $request2->execute($userid,'person',$person);
        $request2->execute($userid,'year',$year);
        $request2->execute($userid,'isbn',$isbn);
        $request2->execute($userid,'issn',$issn);
        $request2->execute($userid,'content',$content);
        $request2->execute($userid,'mediatype',$mediatype);
        $request2->execute($userid,'mark',$mark);

        print STDERR $userid,"\n";
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE searchfield ENABLE KEYS});
}

# livesearch
{
    print STDERR "### livesearch \n";

    $newdbh->do(qq{ALTER TABLE livesearch DISABLE KEYS});

    my $request  = $olddbh->prepare("select * from livesearch");
    my $request2 = $newdbh->prepare("insert into livesearch (userid,searchfield,exact,active) values (?,?,?,?)");
    
    $request->execute();

    my %userid_done = ();
    while (my $result=$request->fetchrow_hashref){
        
        my $userid = $result->{userid};
        my $exact  = $result->{exact};

        next if ($userid_done{$userid});

        $userid_done{$userid} = 1;
        
        next unless ($userid && $userid_exists{$userid});
        
        my $fs = ($result->{fs} eq "1")?1:0;
        my $person = ($result->{verf} eq "1")?1:0;
        my $subject = ($result->{swt} eq "1")?1:0;
        
        $request2->execute($userid,'freesearch',$exact,$fs);
        $request2->execute($userid,'subject',$exact,$subject);
        $request2->execute($userid,'person',$exact,$person);

        print STDERR $userid,"\n";
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE livesearch ENABLE KEYS});
}

# collection    
{
    print STDERR "### collection \n";

    $newdbh->do(qq{ALTER TABLE collection DISABLE KEYS});
    
    my $request = $olddbh->prepare("select * from treffer");
    
    $request->execute();
    
    my $request2 = $newdbh->prepare("insert into collection (userid,dbname,titleid) values (?,?,?)");
    
    while (my $result=$request->fetchrow_hashref){        
        my $userid   = $result->{userid};
        my $dbname   = $result->{dbname};
        my $titleid  = $result->{singleidn};

        next unless ($userid_exists{$userid});
        
        $request2->execute($userid,$dbname,$titleid);
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE collection ENABLE KEYS});
}

# tag
{
    print STDERR "### tag \n";

    $newdbh->do(qq{ALTER TABLE tag DISABLE KEYS});
    
    my $request = $olddbh->prepare("select * from tags");
    
    $request->execute();
    
    my $request2 = $newdbh->prepare("insert into tag (id,name) values (?,?)");
    
    while (my $result=$request->fetchrow_hashref){        
        my $id       = $result->{id};
        my $name     = $result->{tag};
        
        $request2->execute($id,$name);
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE tag ENABLE KEYS});
}

# tit_tag
{
    print STDERR "### tit_tag \n";

    $newdbh->do(qq{ALTER TABLE tit_tag DISABLE KEYS});
    
    my $request = $olddbh->prepare("select * from tittag");
    
    $request->execute();
    
    my $request2 = $newdbh->prepare("insert into tit_tag (id,tagid,userid,dbname,titleid,titleisbn,type) values (?,?,?,?,?,?,?)");
    
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
        
        $request2->execute($id,$tagid,$userid,$dbname,$titleid,$titleisbn,$type);
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE tit_tag ENABLE KEYS});
}

# review
{
    print STDERR "### review \n";

    $newdbh->do(qq{ALTER TABLE review DISABLE KEYS});
    
    my $request = $olddbh->prepare("select * from reviews");
    
    $request->execute();
    
    my $request2 = $newdbh->prepare("insert into review (id,userid,nickname,title,reviewtext,rating,dbname,titleid,titleisbn) values (?,?,?,?,?,?,?,?,?)");
    
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
        
        $request2->execute($id,$userid,$nickname,$title,$reviewtext,$rating,$dbname,$titleid,$titleisbn);
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE review ENABLE KEYS});

}

# reviewrating
{
    print STDERR "### reviewrating \n";

    $newdbh->do(qq{ALTER TABLE reviewratings DISABLE KEYS});
    
    my $request = $olddbh->prepare("select * from reviewratings");
    
    $request->execute();
    
    my $request2 = $newdbh->prepare("insert into reviewrating (id,userid,reviewid,tstamp,rating) values (?,?,?,?,?)");
    
    while (my $result=$request->fetchrow_hashref){        
        my $id         = $result->{id};
        my $tstamp     = $result->{tstamp};
        my $reviewid   = $result->{reviewid};
        my $loginname  = $result->{loginname};
        my $rating     = $result->{rating};

        my $userid     = $loginname{$loginname};

        next unless ($userid_exists{$userid});
        
        $request2->execute($id,$userid,$reviewid,$tstamp,$rating);
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE reviewratings ENABLE KEYS});
}

# litlist
{
    print STDERR "### litlist \n";

    $newdbh->do(qq{ALTER TABLE litlist DISABLE KEYS});
    
    my $request = $olddbh->prepare("select * from litlists");
    
    $request->execute();
    
    my $request2 = $newdbh->prepare("insert into litlist (id,userid,tstamp,title,type,lecture) values (?,?,?,?,?,?)");
    
    while (my $result=$request->fetchrow_hashref){        
        my $id         = $result->{id};
        my $tstamp     = $result->{tstamp};
        my $userid     = $result->{userid};
        my $title      = $result->{title};
        my $type       = $result->{type};
        my $lecture    = $result->{lecture};

        next unless ($userid_exists{$userid});
        
        $request2->execute($id,$userid,$tstamp,$title,$type,$lecture);
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE litlist ENABLE KEYS});
}

# litlistitem
{
    print STDERR "### litlistitem \n";

    $newdbh->do(qq{ALTER TABLE litlistitem DISABLE KEYS});
    
    my $request = $olddbh->prepare("select * from litlistitems");
    
    $request->execute();
    
    my $request2 = $newdbh->prepare("insert into litlistitem (litlistid,tstamp,dbname,titleid,titleisbn) values (?,?,?,?,?)");
    
    while (my $result=$request->fetchrow_hashref){        
        my $litlistid  = $result->{litlistid};
        my $tstamp     = $result->{tstamp};
        my $titleid    = $result->{titid};
        my $titleisbn  = $result->{titisbn};
        my $dbname     = $result->{titdb};
        
        $request2->execute($litlistid,$tstamp,$dbname,$titleid,$titleisbn);
    }

    $newdbh->do(qq{COMMIT});
    $newdbh->do(qq{ALTER TABLE litlistitem ENABLE KEYS});
}

# subject
{
    print STDERR "### subject \n";
    
    my $request = $olddbh->prepare("select * from subjects");
    
    $request->execute();
    
    my $request2 = $newdbh->prepare("insert into subject (id,name,description) values (?,?,?)");
    
    while (my $result=$request->fetchrow_hashref){        
        my $id          = $result->{id};
        my $name        = $result->{name};
        my $description = $result->{description};
        
        $request2->execute($id,$name,$description);
    }
}

# litlist_subject
{
    print STDERR "### litlist_subject \n";
    
    my $request = $olddbh->prepare("select * from litlist2subject");
    
    $request->execute();
    
    my $request2 = $newdbh->prepare("insert into litlist_subject (litlistid,subjectid) values (?,?)");
    
    while (my $result=$request->fetchrow_hashref){        
        my $litlistid   = $result->{litlistid};
        my $subjectid   = $result->{subjectid};
        
        $request2->execute($litlistid,$subjectid);
    }
}

# subjectclassification
{
    print STDERR "### subjectclassification \n";
    
    my $request = $olddbh->prepare("select * from subject2classification");
    
    $request->execute();
    
    my $request2 = $newdbh->prepare("insert into subjectclassification (subjectid,classification,type) values (?,?,?)");
    
    while (my $result=$request->fetchrow_hashref){        
        my $subjectid        = $result->{subjectid};
        my $classification   = $result->{classification};
        my $type             = $result->{type};
        
        $request2->execute($subjectid,$classification,$type);
    }
}

print STDERR "### ENDE der Migration \n";

