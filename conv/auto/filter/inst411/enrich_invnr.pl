#!/usr/bin/perl

use warnings;
use strict;
use utf8;

use DBI;
use JSON::XS qw/decode_json encode_json/;
use YAML;

# Einsammeln der Inventarnummern aus d01buch via DBI::Proxy

our $acq_config = YAML::LoadFile('/opt/openbib/conf/acq_inst411.yml');

my $dsn = sprintf "dbi:Proxy:%s;dsn=%s",$acq_config->{proxy}, $acq_config->{dsn_at_proxy};

our $dbh = DBI->connect($dsn, $acq_config->{dbuser}, $acq_config->{dbpasswd});

my $sql="select * from d01buch where d01invnr > 0  and d01invkreis != ''";

my $request=$dbh->prepare($sql);

$request->execute();

my $invnr_mapping_ref = {};

while (my $result=$request->fetchrow_hashref()){
    my $mnr      = $result->{'d01gsi'};
    my $invnr    = $result->{'d01invnr'};
    my $invkreis = $result->{'d01invkreis'};

    my $inventarnummer = "$invkreis/$invnr"; 

    $invnr_mapping_ref->{$mnr} = $inventarnummer; 
}

while (<>){
    my $holding_ref;

    eval {
       $holding_ref = decode_json $_;
    };

    if ($@){
        print STDERR $@,"\n";
        next;
    }

    if (defined $holding_ref->{fields}{'0010'}){
	my $mnr = $holding_ref->{fields}{'0010'}[0]{content};

	if (defined $invnr_mapping_ref->{$mnr}){
	    $holding_ref->{fields}{'0005'} = [
		{
		    mult     => 1,
		    subfield => '',
		    content  => $invnr_mapping_ref->{$mnr},
		},
		];
	}

    }

    print encode_json($holding_ref),"\n";

}
