#!/usr/bin/perl

#####################################################################
#
#  gen-subset-mex.pl
#
#  Extrahieren einer Titeluntermenge eines Katalogs anhand der
#  mex-Daten fuer die Erzeugung eines separaten neuen Katalogs
#
#  Dieses File ist (C) 2005-2006 Oliver Flimm <flimm@openbib.org>
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
use OpenBib::Config;

use SOAP::Lite;
use DBI;

#if ($#ARGV < 0){
#    print_help();
#}

&GetOptions(
	    "help" => \$help
	    );

if ($help){
    print_help();
}

my $config = OpenBib::Config->instance;

$rootdir=$config->{'autoconv_dir'};
$pooldir=$rootdir."/pools";

$mysqlexe="/usr/bin/mysql -u $config->{'dbuser'} --password=$config->{'dbpasswd'} -f";

# IDN's der Titel via OLWS aus dem Ausleihsystem bestimmen

print "### edz: Bestimme Titelkatkeys fuer EDZ-Benutzerkonto\n";
my $soap = SOAP::Lite
  -> uri("urn:/Circulation")
  -> proxy("http://hardtberg.ub.uni-koeln.de:8888/olws");
my $result = $soap->get_idn_of_borrows(SOAP::Data->name(paramaters  =>\SOAP::Data->value(
          SOAP::Data->name(dept     => "98")->type(string),
          SOAP::Data->name(password => "")->type(string),
          SOAP::Data->name(database => "sisis")->type(string))));

my $circexlist=undef;

unless ($result->fault) {
  $circexlist=$result->result;
}
else {
  print "SOAP MediaStatus Error", join ', ', $result->faultcode,
    $result->faultstring, $result->faultdetail;
}

my @circexemplarliste=@$circexlist;

print "### edz: $#circexemplarliste Titel gefunden\n";

foreach my $singleex_ref (@circexemplarliste) {
  $titidns{$singleex_ref->{'Katkey'}}=1;
}

my $dbh=DBI->connect("DBI:$config->{dbimodule}:dbname=inst001;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);


# IDN's uebergeordneter Titel finden

print "### edz: Bestimme uebergeordnete/untergeordnete Titel\n";

foreach $titidn (keys %titidns){

  # Ueberordnungen
  $request=$dbh->prepare("select distinct sourceid from conn where targetid=? and sourcetype=1 and targettype=1") or $logger->error($DBI::errstr);
  $request->execute($titidn) or $logger->error($DBI::errstr);;
  
  while (my $result=$request->fetchrow_hashref()){
    $titidns{$result->{'sourceid'}}=1;
  }

  # Unterordnungen
  $request=$dbh->prepare("select distinct targetid from conn where sourceid=? and sourcetype=1 and targettype=1") or $logger->error($DBI::errstr);
  $request->execute($titidn) or $logger->error($DBI::errstr);;
  
  while (my $result=$request->fetchrow_hashref()){
    $titidns{$result->{'targetid'}}=1;
  }

}

# IDN's der Autoren, Koerperschaften, Schlagworte, Notationen bestimmen

print "### edz: Bestimme Normdaten\n";

foreach $titidn (keys %titidns){

    # Verfasser/Personen
    $request=$dbh->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=2") or $logger->error($DBI::errstr);
    $request->execute($titidn);
    
    while (my $result=$request->fetchrow_hashref()){
        $autidns{$result->{'targetid'}}=1;
    }

    # Urheber/Koerperschaften
    $request=$dbh->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=3") or $logger->error($DBI::errstr);
    $request->execute($titidn);
    
    while (my $result=$request->fetchrow_hashref()){
        $koridns{$result->{'targetid'}}=1;
    }

    # Notationen
    $request=$dbh->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=5") or $logger->error($DBI::errstr);
    $request->execute($titidn);
    
    while (my $result=$request->fetchrow_hashref()){
        $notidns{$result->{'targetid'}}=1;
    }

    # Schlagworte
    $request=$dbh->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=4") or $logger->error($DBI::errstr);
    $request->execute($titidn);
    
    while (my $result=$request->fetchrow_hashref()){
        $swtidns{$result->{'targetid'}}=1;
    }

    # Exemplardaten
    $request=$dbh->prepare("select targetid from conn where sourceid=? and sourcetype=1 and targettype=6") or $logger->error($DBI::errstr);
    $request->execute($titidn);
    
    while (my $result=$request->fetchrow_hashref()){
        $mexidns{$result->{'targetid'}}=1;
    }

}

print "### edz: Schreibe Meta-Daten\n";
# Autoren

open(AUT,"gzip -dc $pooldir/inst001/unload.PER.gz|");
open(AUTOUT,"| gzip > $pooldir/edz/unload.PER.gz");

while (<AUT>){

    if (/^0000:(\d+)/){
        $autidn=$1;
    }
    
    if ($autidns{$autidn} == 1){
        print AUTOUT $_;
    }
}

close(AUT);
close(AUTOUT);

# Koerperschaften

open(KOR,"gzip -dc $pooldir/inst001/unload.KOE.gz|");
open(KOROUT,"| gzip > $pooldir/edz/unload.KOE.gz");

while (<KOR>){
    
    if (/^0000:(\d+)/){
        $koridn=$1;
    }
    
    if ($koridns{$koridn} == 1){
        print KOROUT $_;
    }
}

close(KOR);
close(KOROUT);

# Notationen

open(NOTA,"gzip -dc $pooldir/inst001/unload.SYS.gz|");
open(NOTAOUT,"| gzip > $pooldir/edz/unload.SYS.gz");

while (<NOTA>){
    
    if (/^0000:(\d+)/){
        $notidn=$1;
    }
    
    if ($notidns{$notidn} == 1){
        print NOTAOUT $_;
    }
}

close(NOTA);
close(NOTAOUT);

# Schlagworte
open(SWT,"gzip -dc $pooldir/inst001/unload.SWD.gz|");
open(SWTOUT,"| gzip > $pooldir/edz/unload.SWD.gz");

while (<SWT>){
    
    if (/^0000:(\d+)/){
        $swtidn=$1;
    }
    
    if ($swtidns{$swtidn} == 1){
        print SWTOUT $_;
    }
}

close(SWT);
close(SWTOUT);

# Titeldaten

open(TIT,"gzip -dc $pooldir/inst001/unload.TIT.gz|");
open(TITOUT,"| gzip > $pooldir/edz/unload.TIT.gz");

while (<TIT>){

    if (/^0000:(\d+)/){
        $titidn=$1;
    }
    
    if ($titidns{$titidn} == 1){
        print TITOUT $_;
    }
}

close(TIT);
close(TITOUT);

# Exemplardaten

open(MEX,"gzip -dc $pooldir/inst001/unload.MEX.gz|");
open(MEXOUT,"| gzip > $pooldir/edz/unload.MEX.gz");

my $mexbuffer="";

while (<MEX>){
    if (/^0000:(\d+)/){
        $mexidn=$1;
    }
    
    if ($mexidns{$mexidn} == 1){
        print MEXOUT $_;
    }
}

close(MEX);
close(MEXOUT);


sub print_help {
    print "gen-subset-mex.pl - Erzeugen von Kataloguntermengen\n\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n\n";

    exit;
}
