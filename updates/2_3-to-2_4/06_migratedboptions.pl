#!/usr/bin/perl

use OpenBib::Config;

my $config = new OpenBib::Config;

my $request = $config->{dbh}->prepare("select * from dboptions");

$request->execute();

while (my $result=$request->fetchrow_hashref){
    $dboptions_ref = {
        dbname        => $result->{'dbname'},
        host          => $result->{'host'},
        protocol      => $result->{'protocol'},
        remotepath    => $result->{'remotepath'},
        remoteuser    => $result->{'remoteuser'},
        remotepasswd  => $result->{'remotepasswd'},
        filename      => $result->{'filename'},
        titfilename   => $result->{'titfilename'},
        autfilename   => $result->{'autfilename'},
        korfilename   => $result->{'korfilename'},
        swtfilename   => $result->{'swtfilename'},
        notfilename   => $result->{'notfilename'},
        mexfilename   => $result->{'mexfilename'},
        autoconvert   => $result->{'autoconvert'},
        circ          => $result->{'circ'},
        circurl       => $result->{'circurl'},
        circcheckurl  => $result->{'circcheckurl'},
        circdb        => $result->{'circdb'},
    };
    
    my $request2 = $config->{dbh}->prepare("update dbinfo set host = ?, protocol = ?, remotepath = ?, remoteuser = ?, remotepassword = ?, titlefile = ?, personfile = ?, corporatebodyfile = ?, subjectfile = ?, classificationfile = ?, holdingsfile = ?, autoconvert = ?, circ = ?, circurl = ?, circwsurl = ?, circdb = ? where dbname = ?");

    $request2->execute($dboptions_ref->{host},$dboptions_ref->{protocol},$dboptions_ref->{remotepath},$dboptions_ref->{remoteuser},$dboptions_ref->{remotepasswd},$dboptions_ref->{titfilename},$dboptions_ref->{autfilename},$dboptions_ref->{korfilename},$dboptions_ref->{swtfilename},$dboptions_ref->{notfilename},$dboptions_ref->{mexfilename},$dboptions_ref->{autoconvert},$dboptions_ref->{circ},$dboptions_ref->{circurl},$dboptions_ref->{circcheckurl},$dboptions_ref->{circdb},$dboptions_ref->{dbname});
}
