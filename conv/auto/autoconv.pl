#!/usr/bin/perl

#####################################################################
#
#  autoconv.pl
#
#  Automatische Konvertierung
#
#  Default: Sikis-Daten
#
#  Andere : Ueber Plugins/Filter realisierbar
#
#  Dieses File ist (C) 1997-2006 Oliver Flimm <flimm@openbib.org>
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
use Getopt::Long;

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

use vars qw(%config);

*config=\%OpenBib::Config::config;

&GetOptions("single-pool=s"   => \$singlepool,
	    "get-from-remote" => \$getfromremote,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$rootdir       = $config{'autoconv_dir'};
$pooldir       = $rootdir."/pools";

$wgetexe       = "/usr/bin/wget -nH --cut-dirs=3";
$meta2sqlexe   = "$config{'conv_dir'}/meta2sql.pl";
$meta2mexexe   = "$config{'conv_dir'}/meta2mex.pl";
$meta2waisexe  = "$config{'conv_dir'}/meta2wais.pl";
$wais2sqlexe   = "$config{'conv_dir'}/wais2searchSQL.pl";
$mysqlexe      = "/usr/bin/mysql -u $config{'dbuser'} --password=$config{'dbpasswd'} -f";
$mysqladminexe = "/usr/bin/mysqladmin -u $config{'dbuser'} --password=$config{'dbpasswd'} -f";

if (!$singlepool){
  print STDERR "Kein Pool mit --single-pool= ausgewaehlt\n";
  exit;
}

my $singlepooltmp=$singlepool."tmp";

my $sessiondbh = DBI->connect("DBI:$config{dbimodule}:dbname=$config{sessiondbname};host=$config{sessiondbhost};port=$config{sessiondbport}", $config{sessiondbuser}, $config{sessiondbpasswd}) or die "could not connect";

# Verweis: Datenbankname -> Sigel

my $dbinforesult=$sessiondbh->prepare("select sigel from dbinfo where dbname=?") or die "Error -- $DBI::errstr";
$dbinforesult->execute($singlepool);

my %poolsigel=();

my $result = $dbinforesult->fetchrow_hashref();
my $sigel  = $result->{'sigel'};

if ($sigel eq ""){
  print STDERR "Kein Sigel zu Pool $singlepool auffindbar\n";
  exit;
}

$dbinforesult=$sessiondbh->prepare("select * from dboptions where dbname=?") or die "Error -- $DBI::errstr";
$dbinforesult->execute($singlepool);
$result=$dbinforesult->fetchrow_hashref();

my $host          = $result->{'host'};
my $protocol      = $result->{'protocol'};
my $remotepath    = $result->{'remotepath'};
my $remoteuser    = $result->{'remoteuser'};
my $remotepasswd  = $result->{'remotepasswd'};
my $filename      = $result->{'filename'};
my $titfilename   = $result->{'titfilename'};
my $autfilename   = $result->{'autfilename'};
my $korfilename   = $result->{'korfilename'};
my $swtfilename   = $result->{'swtfilename'};
my $notfilename   = $result->{'notfilename'};
my $mexfilename   = $result->{'mexfilename'};
my $autoconvert   = $result->{'autoconvert'};

$dbinforesult->finish();

$sessiondbh->disconnect();

print "### POOL $singlepool\n";

if ($singlepool && -e "$config{autoconv_dir}/filter/$singlepool/pre_remote.pl"){
    print "### $singlepool: Verwende Plugin pre_remote.pl\n";
    system("$config{autoconv_dir}/filter/$singlepool/pre_remote.pl $singlepool");
}

if ($getfromremote){

    if ($singlepool && -e "$config{autoconv_dir}/filter/$singlepool/alt_remote.pl"){
        print "### $singlepool: Verwende Plugin alt_remote.pl\n";
        system("$config{autoconv_dir}/filter/$singlepool/alt_remote.pl $singlepool");
    }
    else {
        print "### $singlepool: Hole Exportdateien mit wget von $protocol://$host/$remotepath/\n";
        
        
        my $httpauthstring="";
        if ($protocol eq "http" && $remoteuser ne "" && $remotepasswd ne ""){
            $httpauthstring=" --http-user=$remoteuser --http-passwd=$remotepasswd";
        }
        
        system("cd $pooldir/$singlepool ; rm unload.*");
        system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $protocol://$host/$remotepath/$titfilename > /dev/null 2>&1 ");
        system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $protocol://$host/$remotepath/$autfilename > /dev/null 2>&1 ");
        system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $protocol://$host/$remotepath/$korfilename > /dev/null 2>&1 ");
        system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $protocol://$host/$remotepath/$swtfilename > /dev/null 2>&1 ");
        system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $protocol://$host/$remotepath/$notfilename > /dev/null 2>&1 ");
        system("$wgetexe $httpauthstring -P $pooldir/$singlepool/ $protocol://$host/$remotepath/$mexfilename > /dev/null 2>&1 ");
    }
}

if ($singlepool && -e "$config{autoconv_dir}/filter/$singlepool/post_remote.pl"){
    print "### $singlepool: Verwende Plugin post_remote.pl\n";
    system("$config{autoconv_dir}/filter/$singlepool/post_remote.pl $singlepool");
}

if (! -d "$rootdir/data/$singlepool"){
  system("mkdir $rootdir/data/$singlepool");
}

system("cd $pooldir/$singlepool/ ; zcat $titfilename | $meta2mexexe");

if ($singlepool && -e "$config{autoconv_dir}/filter/$singlepool/pre_move.pl"){
    print "### $singlepool: Verwende Plugin pre_move.pl\n";
    system("$config{autoconv_dir}/filter/$singlepool/pre_move.pl $singlepool");
}

system("rm $rootdir/data/$singlepool/*");
system("/bin/gzip -dc $pooldir/$singlepool/$titfilename > $rootdir/data/$singlepool/tit.exp");
system("/bin/gzip -dc $pooldir/$singlepool/$autfilename > $rootdir/data/$singlepool/aut.exp");
system("/bin/gzip -dc $pooldir/$singlepool/$swtfilename > $rootdir/data/$singlepool/swt.exp");
system("/bin/gzip -dc $pooldir/$singlepool/$notfilename > $rootdir/data/$singlepool/not.exp");
system("/bin/gzip -dc $pooldir/$singlepool/$korfilename > $rootdir/data/$singlepool/kor.exp");
system("/bin/gzip -dc $pooldir/$singlepool/$mexfilename > $rootdir/data/$singlepool/mex.exp");

# Konvertierung Exportdateien -> SQL
if ($singlepool && -e "$config{autoconv_dir}/filter/$singlepool/pre_conv.pl"){
    print "### $singlepool: Verwende Plugin pre_conv.pl\n";
    system("$config{autoconv_dir}/filter/$singlepool/pre_conv.pl $singlepool");
}

print "### $singlepool: Konvertierung Exportdateien -> SQL\n";

if ($singlepool && -e "$config{autoconv_dir}/filter/$singlepool/alt_conv.pl"){
    print "### $singlepool: Verwende Plugin alt_conv.pl\n";
    system("$config{autoconv_dir}/filter/$singlepool/alt_conv.pl $singlepool");
}
else {
    system("cd $rootdir/data/$singlepool ; $meta2sqlexe ");
}

if ($singlepool && -e "$config{autoconv_dir}/filter/$singlepool/post_conv.pl"){
    print "### $singlepool: Verwende Plugin post_conv.pl\n";
    system("$config{autoconv_dir}/filter/$singlepool/post_conv.pl $singlepool");
}

print "### $singlepool: Temporaere Datenbank erzeugen\n";

# Fuer das Einladen externer SQL-Daten mit 'load' wird das File_priv
# fuer den Benutzer dbuser benoetigt

system("$mysqladminexe drop   $singlepooltmp");
system("$mysqladminexe create $singlepooltmp");

print "### $singlepool: Datendefinition einlesen\n";

system("$mysqlexe $singlepooltmp < $config{'dbdesc_dir'}/mysql/pool.mysql");

# Index entfernen
print "### $singlepool: Index in temporaerer Datenbank entfernen\n";
system("$mysqlexe $singlepooltmp < $rootdir/data/$singlepool/control_index_off.mysql");

if ($singlepool && -e "$config{autoconv_dir}/filter/$singlepool/post_index_off.pl"){
    print "### $singlepool: Verwende Plugin post_index_off.pl\n";
    system("$config{autoconv_dir}/filter/$singlepool/post_index_off.pl $singlepooltmp");
}

# Einladen der Daten
print "### $singlepool: Einladen der Daten in temporaere Datenbank\n";
system("$mysqlexe $singlepooltmp < $rootdir/data/$singlepool/control.mysql");

if ($singlepool && -e "$config{autoconv_dir}/filter/$singlepool/post_dbload.pl"){
    print "### $singlepool: Verwende Plugin post_dbload.pl\n";
    system("$config{autoconv_dir}/filter/$singlepool/post_dbload.pl $singlepooltmp");
}

# Index setzen
print "### $singlepool: Index in temporaerer Datenbank aufbauen\n";
system("$mysqlexe $singlepooltmp < $rootdir/data/$singlepool/control_index_on.mysql");

if ($singlepool && -e "$config{autoconv_dir}/filter/$singlepool/post_index_on.pl"){
    print "### $singlepool: Verwende Plugin post_index_on.pl\n";
    system("$config{autoconv_dir}/filter/$singlepool/post_index_on.pl $singlepooltmp");
}

# Tabellen Packen
system("$config{autoconv_dir}/filter/common/pack_data.pl $singlepooltmp");

# Tabellen aus temporaerer Datenbank in finale Datenbank verschieben
print "### $singlepool: Tabellen aus temporaerer Datenbank in finale Datenbank verschieben\n";

system("$mysqladminexe drop $singlepool ");
system("$mysqladminexe create $singlepool ");
#system("mv /var/lib/mysql/$singlepooltmp /var/lib/mysql/$singlepool");


open(COPYIN, "echo \"show tables;\" | $mysqlexe -s $singlepooltmp |");
open(COPYOUT,"| $mysqlexe -s $singlepooltmp |");

while (<COPYIN>){
    chomp();
    print COPYOUT <<"ENDE";
rename table $singlepooltmp.$_ to $singlepool.$_ ;
ENDE
}

close(COPYIN);
close(COPYOUT);

system("$config{autoconv_dir}/filter/$singlepool/post_index_on.pl $singlepool");

print "### $singlepool: Updating Titcount\n";

system("$config{'base_dir'}/bin/updatetitcount.pl --single-pool=$singlepool");

print "### $singlepool: Cleanup\n";

#system("$mysqladminexe drop   $singlepooltmp");
#system("rm $rootdir/data/$singlepool/*");
  
sub print_help {
    print << "ENDHELP";
autoconv-sikis.pl - Automatische Konvertierung von SIKIS-Daten

   Optionen:
   -help                 : Diese Informationsseite
       
   -get-from-remote      : Hole Pool automatisch ueber das Netz
   --single-pool=...     : Angegebenen Datenpool verwenden

   Datenbankabhaengige Filter:

   pre_remote.pl
   alt_remote.pl
   post_remote.pl
   pre_move.pl
   pre_conv.pl
   post_conv.pl
   post_dbload.pl
   post_index_off.pl
   post_index_on.pl

ENDHELP
    exit;
}

