#!/usr/bin/perl

#####################################################################
#
#  autoconv-sikis.pl
#
#  Automatische Konvertierung von SIKIS-Daten
#
#  Dieses File ist (C) 1997-2004 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;
use DBI;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

&GetOptions("single-pool=s" => \$singlepool,
	    "convert-only" => \$convertonly,
	    "wais-only" => \$waisonly,
	    "sql-only" => \$sqlonly,
	    "all-in-one" => \$allinone,
	    "get-via-wget" => \$getviawget,
	    "imxbaseurl=s" => \$imxbaseurl,
	    "fastload" => \$fastload,
	    "help" => \$help
	    );

if (!$waismode){
  $waismode=1;
}

if ($help){
    print_help();
}

$rootdir=$config{'autoconv_dir'};
$pooldir=$rootdir."/pools";

$wgetexe="/usr/bin/wget -nH --cut-dirs=3";
$meta2sqlexe="$config{'conv_dir'}/meta2sql.pl";
$meta2waisexe="$config{'conv_dir'}/meta2wais.pl";
$wais2sqlexe="$config{'conv_dir'}/wais2searchSQL.pl";
$mysqlexe="/usr/bin/mysql -u $config{'dbuser'} --password=$config{'dbpasswd'} -f";
$myisamchkexe="/usr/bin/myisamchk --tmpdir=$config{'base_dir'}/tmp";
$postgresqldir="/opt/postgresql/bin";

my $sessiondbh=DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";

# Verweis: Datenbankname -> Sigel
  
my $dbinforesult=$sessiondbh->prepare("select dbname,sigel from dbinfo") or die "Error -- $DBI::errstr";
$dbinforesult->execute();

my %poolsigel=();

while (my $result=$dbinforesult->fetchrow_hashref()){
    my $dbname=$result->{'dbname'};
    my $sigel=$result->{'sigel'};
    
    $poolsigel{"$dbname"}="$sigel";
}
  
$dbinforesult->finish();

$sessiondbh->disconnect();

if (!$singlepool){
   print STDERR "Kein Pool mit --single-pool= ausgewaehlt\n";
   exit;
}

print "### POOL $singlepool\n";

# Passworte fuer Pool erzeugen, damit diese per wget geholt werden koennen
# Interimsloesung bis Informationen aus der session-DB geholt werden

$pwdstring=$singlepool.$config{'web_seed'};
$password=`echo $pwdstring|md5sum|cut -c -8`;
chomp($password);

$sigel=$poolsigel{$singlepool};


if ($getviawget){
    print "### $singlepool: Hole Exportdateien mit wget von $imxbaseurl/$singlepool\n";
    
    system("cd $pooldir/$singlepool ; rm *.exp.gz");
    system("$wgetexe --http-user=$singlepool --http-passwd=$password -P $pooldir/$singlepool/ $imxbaseurl/$singlepool/tit.exp.gz > /dev/null 2>&1 ");
    system("$wgetexe --http-user=$singlepool --http-passwd=$password -P $pooldir/$singlepool/ $imxbaseurl/$singlepool/aut.exp.gz > /dev/null 2>&1 ");
    system("$wgetexe --http-user=$singlepool --http-passwd=$password -P $pooldir/$singlepool/ $imxbaseurl/$singlepool/swt.exp.gz > /dev/null 2>&1 ");
    system("$wgetexe --http-user=$singlepool --http-passwd=$password -P $pooldir/$singlepool/ $imxbaseurl/$singlepool/not.exp.gz > /dev/null 2>&1 ");
    system("$wgetexe --http-user=$singlepool --http-passwd=$password -P $pooldir/$singlepool/ $imxbaseurl/$singlepool/kor.exp.gz > /dev/null 2>&1 ");
    system("$wgetexe --http-user=$singlepool --http-passwd=$password -P $pooldir/$singlepool/ $imxbaseurl/$singlepool/mex.exp.gz > /dev/null 2>&1 ");

  }

  if (! -d "$rootdir/data/$singlepool"){
    system("mkdir $rootdir/data/$singlepool");
  }

  system("rm $rootdir/data/$singlepool/*");
  system("/bin/gzip -dc $pooldir/$singlepool/tit.exp.gz > $rootdir/data/$singlepool/tit.exp");
  system("/bin/gzip -dc $pooldir/$singlepool/aut.exp.gz > $rootdir/data/$singlepool/aut.exp");
  system("/bin/gzip -dc $pooldir/$singlepool/swt.exp.gz > $rootdir/data/$singlepool/swt.exp");
  system("/bin/gzip -dc $pooldir/$singlepool/not.exp.gz > $rootdir/data/$singlepool/not.exp");
  system("/bin/gzip -dc $pooldir/$singlepool/kor.exp.gz > $rootdir/data/$singlepool/kor.exp");
  system("/bin/gzip -dc $pooldir/$singlepool/mex.exp.gz > $rootdir/data/$singlepool/mex.exp");

  
  if (($sqlonly) || (!$waisonly)){         
    
    # Konvertierung Exportdateien -> SQL
    
    print "### $singlepool: Konvertierung Exportdateien -> SQL\n";

    if ($config{'dbms'} eq "mysql"){
	system("cd $rootdir/data/$singlepool ; $meta2sqlexe -all -mysql");
    }
    elsif ($config{'dbms'} eq "pg"){
	system("cd $rootdir/data/$singlepool ; $meta2sqlexe -all -pg --idn-mode=sigel --sigel=".$poolsigel{$singlepool}."");
    }
  }
  
  if (($waisonly) || (!$sqlonly)){ 
    
      if (($waismode == 1)||($waismode == 3)){
	  # Konvertierung Exportdateien -> WAIS
	  
	  print "### $singlepool: Konvertierung Exportdateien -> WAIS\n";
	  system("cd $rootdir/data/$singlepool ; $meta2waisexe -combined ; $wais2sqlexe < data.wais ");
      }
  }

  if ($convertonly){
    exit;
  }
  
  if (($sqlonly) || (!$waisonly)){ 
    
    # L"oschen der Daten in Biblio
    
    print "### $singlepool: Loeschen der Daten in Biblio\n";

    if ($config{'dbms'} eq "mysql"){
	system("$mysqlexe $singlepool < $config{'dbdesc_dir'}/mysql/poolflush.mysql");
	system("$mysqlexe $singlepool < $config{'dbdesc_dir'}/mysql/pool.mysql");
	
	# Einladen der Daten nach Biblio
    
	print "### $singlepool: Einladen der Daten nach Biblio\n";
	system("$mysqlexe $singlepool < $rootdir/data/$singlepool/control.mysql");
	print "### $singlepool: Fixen der Sigel\n";
	if ($singlepool ne "instzs"){

	  my $thispoolsigel=$poolsigel{"$singlepool"};
	  $thispoolsigel=~s/^99/00/;
	  system("$mysqlexe -e \"update mex set sigel=\\\"".$thispoolsigel."\\\" where idn < 99999999 \" ".$singlepool."");
	}

    }
    elsif ($config{'dbms'} eq "pg"){


	system("$postgresqldir/destroydb $singlepool");
	system("$postgresqldir/createdb $singlepool");
	system("$postgresqldir/psql -f $config{'dbdesc_dir'}/postgresql/biblio.pg $singlepool");
	system("$postgresqldir/psql -f $config{'dbdesc_dir'}/postgresql/index.pg $singlepool");
	# Einladen der Daten nach Biblio
	
	print "### $singlepool: Einladen der Daten nach Biblio\n";
	system("$postgresqldir/psql -f $rootdir/data/$singlepool/control.pg $singlepool");

	print "### $singlepool: Fixen der Sigel\n";

	$insert=$poolsigel{"$singlepool"};
	$dbhpg=DBI->connect("DBI:Pg:$singlepool:$config{'dbhost'}:$config{'dbport'}", $config{'dbuser'}, $config{'dbpasswd'}) or die "could not connect";
	$request="update mex set sigel=".$poolsigel{"$singlepool"}." where idn < 999999999 ;";
	$result=$dbhpg->prepare("$request") or die "Error -- $DBI::errstr";
	$result->execute();
	$result->finish();
	$dbhpg->disconnect();

    }

  }
  
  if (($waisonly) || (!$sqlonly)){ 
    
    # Kopieren der WAIS-Daten
    
    print "### $singlepool: Einladen der Search-Daten\n";

    if ($fastload){
      system("$mysqlexe $singlepool -e \"truncate table search\"");
      system("$mysqladminexe flush-tables");
      system("$myisamchkexe --keys-used=0 -rq /var/lib/mysql/$singlepool/search");
      system("$mysqlexe $singlepool -e \"load data infile '$rootdir/data/$singlepool/search.sql' into table search fields terminated by '|' \" ");
      system("$myisamchkexe -r -q /var/lib/mysql/$singlepool/search");
      system("$mysqladminexe flush-tables");
    }
    else {
      system("cd $rootdir/data/$singlepool ; $mysqlexe $singlepool -e \"load data infile '$rootdir/data/$singlepool/search.sql' into table search fields terminated by '|'\" ");
    }
      
  }
  
  if ($allinone){

          if ($config{'dbms'} eq "mysql"){
	  # Datenbereich im Gesamtpool loeschen
	  print "### $singlepool: Entsprechende Datenbereich im Gesamtpool loeschen";
	  system("$mysqlexe -e \"delete from aut where idn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from autverw where autidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from kor where idn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from korverw where koridn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from korfrueh where koridn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from korspaet where koridn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from swt where idn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from swtverw where swtidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from swtfrueh where swtidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from swtspaet where swtidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from swtassoz where swtidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from swtueber where swtidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from tit where idn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titpsthst where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titgtunv where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titisbn where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titissn where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titner where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titteiluw where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titstichw where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titnr where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titartinh where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titphysform where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titgtm where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titgtf where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titinverkn where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titswtlok where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titswtreg where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titverf where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titpers where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titurh where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titkor where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from titnot where titidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from mex where idn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from mexsign where mexidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from notation where idn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from notverw where notidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "."; 
	  system("$mysqlexe -e \"delete from notbenverw where notidn like \\\"".$poolsigel{$singlepool}."%\\\" \" institute");
	  print "\n"; 
	  # Einladen der Daten in den Gesamtpool
	  print "### $singlepool: Einladen der Daten in den Gesamtpool\n";
	  system("$mysqlexe institute < $rootdir/data/$singlepool/control.mysql");	
      }   
      elsif ($config{'dbms'} eq "pg"){

	  @instloesch=(
		       "delete from aut where idn like \"XXX%\"; ",
		       "delete from autverw where autidn like \"XXX%\"; ",
		       "delete from kor where idn like \"XXX%\"; ",
		       "delete from korverw where koridn like \"XXX%\"; ",
		       "delete from korfrueh where koridn like \"XXX%\"; ",
		       "delete from korfrueh where koridn like \"XXX%\"; ",
		       "delete from swt where idn like \"XXX%\"; ",
		       "delete from swtverw where swtidn like \"XXX%\"; ",
		       "delete from swtfrueh where swtidn like \"XXX%\"; ",
		       "delete from swtspaet where swtidn like \"XXX%\"; ",
		       "delete from swtassoz where swtidn like \"XXX%\"; ",
		       "delete from swtueber where swtidn like \"XXX%\"; ",
		       "delete from tit where idn like \"XXX%\"; ",
		       "delete from titpsthst where titidn like \"XXX%\"; ",
		       "delete from titgtunv where titidn like \"XXX%\"; ",
		       "delete from titisbn where titidn like \"XXX%\"; ",
		       "delete from titissn where titidn like \"XXX%\"; ",
		       "delete from titner where titidn like \"XXX%\"; ",
		       "delete from titteiluw where titidn like \"XXX%\"; ",
		       "delete from titstichw where titidn like \"XXX%\"; ",
		       "delete from titnr where titidn like \"XXX%\"; ",
		       "delete from titartinh where titidn like \"XXX%\"; ",
		       "delete from titphysform where titidn like \"XXX%\"; ",
		       "delete from titgtm where titidn like \"XXX%\"; ",
		       "delete from titgtf where titidn like \"XXX%\"; ",
		       "delete from titinverkn where titidn like \"XXX%\"; ",
		       "delete from titswtlok where titidn like \"XXX%\"; ",
		       "delete from titswtreg where titidn like \"XXX%\"; ",
		       "delete from titverf where titidn like \"XXX%\"; ",
		       "delete from titpers where titidn like \"XXX%\"; ",
		       "delete from titurh where titidn like \"XXX%\"; ",
		       "delete from titkor where titidn like \"XXX%\"; ",
		       "delete from titnot where titidn like \"XXX%\"; ",
		       "delete from mex where idn like \"XXX%\"; ",
		       "delete from mexsign where mexidn like \"XXX%\"; ",
		       "delete from notation where idn like \"XXX%\"; ",
		       "delete from notverw where notidn like \"XXX%\"; ",
		       "delete from notbenverw where notidn like \"XXX%\"; ",
		       "delete from tit where titidn like \"XXX%\"; ",
		       "delete from tit where titidn like \"XXX%\"; "
		       );

	  $dbh=DBI->connect("DBI:Pg:institute:$config{'dbhost'}:$config{'dbport'}", undef, undef) or die "could not connect";
	  
	  # Datenbereich im Gesamtpool loeschen
	  print "### $singlepool: Entsprechende Datenbereich im Gesamtpool loeschen";
	  $insert=$poolsigel{"$singlepool"};
	  foreach $request (@instloesch){
	      $request=~s/XXX/$insert/;
	      print "$request\n";
	      $result=$dbh->prepare("$request") or die "Error -- $DBI::errstr";
	      $result->execute();
	      $result->finish();
	  }

	  $dbh->disconnect();

	  print "\n"; 

	  # Einladen der Daten in den Gesamtpool
	  print "### $singlepool: Einladen der Daten in den Gesamtpool\n";
	  system("$postgresqldir/psql -f $rootdir/data/$singlepool/control.pg institute");	      }           
  }  

  print "### $singlepool: Updating Titcount\n";
  
  system("$config{'base_dir'}/bin/updatetitcount.pl --single-pool=$singlepool");


print "### $singlepool: Cleanup\n";
  
sub print_help {
    print "autoconv-sikis.pl - Automatische Konvertierung von SIKIS-Daten\n\n";
    print "Optionen: \n";
    print "  -help                 : Diese Informationsseite\n\n";
    print "  -convert-only         : Nur Konvertieren, NICHT einladen\n";
    print "  -wais-only            : Nur WAIS\n";
    print "  -sql-only             : Nur SQL\n";
    print "  -all-in-one           : Auch Aufbau des Instituts-Semi-GKs\n";
    print "  -get-via-wget         : Hole Pool automatisch mit wget\n";
    print "  -fastload             : Beschleunigtes Einladen via myisamchk\n";
    print "  --single-pool=...     : Angegebenen Datenpool verwenden\n";
    print "  --imxbaseurl=...      : Basis-URL fuer wget\n";
    exit;
}

