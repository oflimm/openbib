#!/usr/bin/perl

use DBI;

use OpenBib::Config;

my $config = OpenBib::Config->instance;

my $pool = $ARGV[0];

my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=$pool;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or die "$DBI::errstr";

open(ASKSAM,"gzip -dc /opt/openbib/autoconv/pools/edz/asksamedz.csv.gz |");

# Erste Beschreibungszeile ueberlesen
my $dummy=<ASKSAM>;

while (<ASKSAM>){
  ($signatur,$sachgruppe)=split("\",\"",$_);

  # Anfangs-" entfernen
  $signatur=~s/^\"//;

  # Leerzeichen entfernen
  $signatur=~s/ //g;

  my $result=$dbh->prepare("select distinct id from mex where category=14 and content=? ");
  $result->execute($signatur);

  while (my $res=$result->fetchrow_hashref()){
      my $mexidn=$res->{id};
      if ($mexidn){
          my $result2=$dbh->prepare("update mex set content='<a href=\"http://www.ub.uni-koeln.de/edz/content/edzallgemein/index_ger.html#e2321\" target=\"_blank\"><span style=\"color:red\">EDZ-Sachgruppe $sachgruppe</span></a>' where category='0016' and id = ? ");
          $result2->execute($mexidn);
          $result2->finish();
      }
  }
  $result->finish();
}

close(ASKSAM);

