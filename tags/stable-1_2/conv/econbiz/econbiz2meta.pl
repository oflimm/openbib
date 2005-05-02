#!/usr/bin/perl

#####################################################################
#
#  econbiz2meta.pl
#
#  Konverierung von Econbiz-Daten in das Meta-Format
#  ueber die Zwischenstation des OAI-Formats
#
#  Dieses File ist (C) 2004 Oliver Flimm <flimm@openbib.org>
#
#  Dieses Programm ist freie Software. Sie koennen es unter
#  den Bedingungen der GNU General Public License, wie von der
#  Free Software Foundation herausgegeben, weitergeben und/oder
#  modifizieren, entweder unter Version 2 der Lizenz oder (wenn
#  Sie es wuenschen) jeder spaeteren Version.
#
#  Die Veroeffentlichung dieses Programms erfolgt in der
#  Hoffnung, dass es Ihnen von Nutzen sein wird, aber OHNE JEDE
#  GEWAEHRLEISTUNG - sogar ohne die implizite Gewaehrleistung
#  der MARKTREIFE oder der EIGNUNG FUER EINEN BESTIMMTEN ZWECK.
#  Details finden Sie in der GNU General Public License.
#
#  Sie sollten eine Kopie der GNU General Public License zusammen
#  mit diesem Programm erhalten haben. Falls nicht, schreiben Sie
#  an die Free Software Foundation, Inc., 675 Mass Ave, Cambridge,
#  MA 02139, USA.
#
#####################################################################

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

use DBI;

my $dbimodule="Pg";    # Pg (PostgreSQL)
my $port="5432";       # Pg:5432

my $dbuser="Der Econbiz DB-User";
my $dbpasswd="Das Econbiz DB-Passwort";
my $dbname="Der Econbiz DB-Name";
my $dbhost="Der Econbiz DB-Host";

my $dbh=DBI->connect("DBI:$dbimodule:dbname=$dbname;host=$dbhost;port=$port", $dbuser, $dbpasswd) or die "could not connect";

my $result=$dbh->prepare("select pid,cnt,lng from dc_tit;") or die "Error -- $DBI::errstr";
$result->execute();

while (my $res=$result->fetchrow_hashref){	    
   my $pid=$res->{'pid'};
   my $hst=$res->{'cnt'};
   my $lang=$res->{'lng'};
   chomp($pid);
   chomp($hst);
   chomp($lang);

   my $urhresult=$dbh->prepare("select cnt from dc_cre_per_nam where pid=$pid");
   $urhresult->execute();

   while (my $urhres=$urhresult->fetchrow_hashref){	    
     my $urh=$urhres->{'cnt'};
     chomp($urh);
     $urh=stripjunk($urh);
     print "AU==$urh\n";
   } 

   $urhresult=$dbh->prepare("select cnt from dc_pub_per_nam where pid=$pid");
   $urhresult->execute();

   while (my $urhres=$urhresult->fetchrow_hashref){	    
     my $urh=$urhres->{'cnt'};
     chomp($urh);
     $urh=stripjunk($urh);
     print "AU==$urh\n";
   } 

   $urhresult->finish();

   my $korresult=$dbh->prepare("select cnt from dc_cre_cor_nam where pid=$pid");
   $korresult->execute();

   while (my $korres=$korresult->fetchrow_hashref){	    
     my $kor=$korres->{'cnt'};
     chomp($kor);
     $kor=stripjunk($kor);
     print "KO==$kor\n";
   } 

   $korresult=$dbh->prepare("select cnt from dc_pub_cor_nam where pid=$pid");
   $korresult->execute();

   while (my $korres=$korresult->fetchrow_hashref){	    
     my $kor=$korres->{'cnt'};
     chomp($kor);
     $kor=stripjunk($kor);
     print "KO==$kor\n";
   } 

   $korresult->finish();

   print "TI==$hst\n";
   
   my $swtresult=$dbh->prepare("select cntg,cnte from dc_sub_f where pid=$pid;");
   $swtresult->execute();

   while (my $swtres=$swtresult->fetchrow_hashref){	    
     my $swtg=$swtres->{'cntg'};
     my $swte=$swtres->{'cnte'};
     chomp($swtg);
     chomp($swte);
     $swtg=stripjunk($swtg);
     $swte=stripjunk($swte);
     print "SW==$swtg\n" if ($swtg);
     print "SW==$swte\n" if ($swte);
   } 

   $swtresult->finish();

   # Abstract

   my $absresult=$dbh->prepare("select cnt from dc_des_abs where pid=$pid;");
   $absresult->execute();

   while (my $absres=$absresult->fetchrow_hashref){	    
     my $abs=$absres->{'cnt'};
     chomp($abs);
     $abs=stripjunk($abs);
     print "AB==$abs\n" if ($abs);
   } 

   $absresult->finish();

   print "UR==http://www.econbiz.de/admin/onteam/einzelansicht.shtml?pid=$pid\n";
   print "\n";
   
}

$result->finish();

$dbh->disconnect();

sub stripjunk {
  my ($item)=@_;
  $item=~s/ +$//;
  $item=~s/ *; .{5,11}$//;
  $item=~s/\n/<br>/g;
#  $item=~s/\[/#093/g;
#  $item=~s/\]/#094/g;
  $item=~s/“/"/g;
  $item=~s/”/"/g;

  return $item;
}
