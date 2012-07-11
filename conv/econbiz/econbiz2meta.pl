#!/usr/bin/perl

#####################################################################
#
#  econbiz2meta.pl
#
#  Konverierung von Econbiz-Daten in das Meta-Format
#  ueber die Zwischenstation des OAI-Formats
#
#  Dieses File ist (C) 2004-2012 Oliver Flimm <flimm@openbib.org>
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

use utf8;

use DBI;
use Log::Log4perl qw(get_logger :levels);

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

my $logfile = '/var/log/openbib/econbiz2meta.log';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, LOGFILE, Screen
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$logfile
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=%d [%c]: %m%n
log4perl.appender.Screen=Log::Dispatch::Screen
log4perl.appender.Screen.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Screen.layout.ConversionPattern=%d [%c]: %m%n
L4PCONF

Log::Log4perl::init(\$log4Perl_config);

# Log4perl logger erzeugen
my $logger = get_logger();

my $config = new OpenBib::Config;

my $database=($ARGV[0])?$ARGV[0]:'econbiz';

my $dbimodule = "Pg";    # Pg (PostgreSQL)
my $port      = "5432";  # Pg:5432

my $dbinfo        = $config->get_databaseinfo->search_rs({ dbname => $database })->single;

my $dbuser    = $dbinfo->remoteuser;
my $dbpasswd  = $dbinfo->remotepassword;
my $dbhost    = $dbinfo->host;
my $dbname    = $dbinfo->remotepath;


my %formattab={
    'application/pdf'        => 'Portable Document Format [PDF]',
    'text/html'              => 'HTML',
    'application/msword'     => 'MS Word',
    'application/zip'        => 'Zip Archiv',
    'application/postscript' => 'Postscript-Datei',
};

my $dbh=DBI->connect("DBI:$dbimodule:dbname=$dbname;host=$dbhost;port=$port", $dbuser, $dbpasswd) or die "could not connect";

my $result=$dbh->prepare("select pid,cnt,lng from dc_tit") or die "Error -- $DBI::errstr";
$result->execute();

open (TIT,     ">:utf8","meta.title");
open (AUT,     ">:utf8","meta.person");
open (KOR,     ">:utf8","meta.corporatebody");
open (NOTATION,">:utf8","meta.classification");
open (SWT,     ">:utf8","meta.subject");

my $titlecount = 1;
while (my $res=$result->fetchrow_hashref){
    my $pid  = $res->{'pid'};
    my $hst  = $res->{'cnt'};
    my $lang = $res->{'lng'};
    chomp($pid );
    chomp($hst );
    chomp($lang);

    $logger->debug("ID: $pid - HST: $hst - LANG: $lang");
    
    print TIT "0000:$pid\n";


    my $cdateresult=$dbh->prepare("select cnt from dc_dat_cre where pid=?");
    $cdateresult->execute($pid);
    
    while (my $cdateres=$cdateresult->fetchrow_hashref){
        my $cdate=$cdateres->{'cnt'};
        chomp($cdate);
        print TIT "0002:$cdate\n";
    }
    
    my $urhresult=$dbh->prepare("select cnt from dc_cre_per_nam where pid=?");
    $urhresult->execute($pid);
    
    while (my $urhres=$urhresult->fetchrow_hashref){
        my $urh=$urhres->{'cnt'};
        chomp($urh);
        $urh=stripjunk($urh);
        
        my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($urh);
	
        if ($new){
            print AUT "0000:$person_id\n";
            print AUT "0001:$urh\n";
            print AUT "9999:\n";
        }

        print TIT "0100:IDN: $person_id\n";
    }
    
    $urhresult=$dbh->prepare("select cnt from dc_pub_per_nam where pid=?");
    $urhresult->execute($pid);
    
    while (my $urhres=$urhresult->fetchrow_hashref){
        my $urh=$urhres->{'cnt'};
        chomp($urh);
        $urh=stripjunk($urh);

        my ($person_id,$new) = OpenBib::Conv::Common::Util::get_person_id($urh);
	
        if ($new){
            print AUT "0000:$person_id\n";
            print AUT "0001:$urh\n";
            print AUT "9999:\n";
        }
        
        print TIT "0100:IDN: $person_id\n";
    } 
    
    $urhresult->finish();
    
    my $korresult=$dbh->prepare("select cnt from dc_cre_cor_nam where pid=?");
    $korresult->execute($pid);
    
    while (my $korres=$korresult->fetchrow_hashref){
        my $kor=$korres->{'cnt'};
        chomp($kor);
        $kor=stripjunk($kor);

        my ($corporatebody_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($kor);
	
        if ($new){
            print KOR "0000:$corporatebody_id\n";
            print KOR "0001:$kor\n";
            print KOR "9999:\n";
        }
        
        print TIT "0201:IDN: $corporatebody_id\n";
    } 
    
    $korresult=$dbh->prepare("select cnt from dc_pub_cor_nam where pid=?");
    $korresult->execute($pid);
    
    while (my $korres=$korresult->fetchrow_hashref){	    
        my $kor=$korres->{'cnt'};
        chomp($kor);
        $kor=stripjunk($kor);

        my ($corporatebody_id,$new) = OpenBib::Conv::Common::Util::get_corporatebody_id($kor);
	
        if ($new){
            print KOR "0000:$corporatebody_id\n";
            print KOR "0001:$kor\n";
            print KOR "9999:\n";
        }
        
        print TIT "0201:IDN: $corporatebody_id\n";
    } 
    
    $korresult->finish();

    $hst=stripjunk($hst);
    print TIT "0331:$hst\n";
    
    my $swtresult=$dbh->prepare("select cntg,cnte from dc_sub_f where pid=?");
    $swtresult->execute($pid);
    
    while (my $swtres=$swtresult->fetchrow_hashref){
        my $swtg=$swtres->{'cntg'};
        my $swte=$swtres->{'cnte'};
        chomp($swtg);
        chomp($swte);
        $swtg=stripjunk($swtg);
        $swte=stripjunk($swte);
        
        if ($swtg){
            my ($subject_id,$new) = OpenBib::Conv::Common::Util::get_subject_id($swtg);
            
            if ($new){
                print SWT "0000:$subject_id\n";
                print SWT "0001:$swtg\n";
                print SWT "9999:\n";
            }

            print TIT "0710:IDN: $subject_id\n";
        }
        
        if ($swte){
            my ($subject_id,$new) = OpenBib::Conv::Common::Util::get_subject_id($swte);
            
            if ($new){
                print SWT "0000:$subject_id\n";
                print SWT "0001:$swte\n";
                print SWT "9999:\n";
            }
            
            print TIT "0710:IDN: $subject_id\n";
        }
    } 
    
    $swtresult->finish();
    
    # Abstract
    
    my $absresult=$dbh->prepare("select cnt from dc_des_abs where pid=?");
    $absresult->execute($pid);
    
    while (my $absres=$absresult->fetchrow_hashref){	    
        my $abs=$absres->{'cnt'};
        chomp($abs);
        $abs=stripjunk($abs);
        if ($abs){
            print TIT "0750:$abs\n";
        }
    } 
    
    $absresult->finish();


    # Format(type)
    
    my $result=$dbh->prepare("select cnt from dc_for_med where pid=?");
    $result->execute($pid);
    
    while (my $res=$result->fetchrow_hashref){	    
        my $content=$res->{'cnt'};
        chomp($content);
        $content=stripjunk($content);

        if ($formattab{$content}){
            print TIT "0435:$formattab{$content}\n";
        }
    } 
    
    $result->finish();

    # Format(type)
    
    my $result1=$dbh->prepare("select cnt from dc_for_med where pid=?");
    $result1->execute($pid);
    
    while (my $res1=$result1->fetchrow_hashref){	    
        my $content=$res1->{'cnt'};
        chomp($content);
        $content=stripjunk($content);

        if ($formattab{$content}){
            print TIT "0435:$formattab{$content}\n";
        }
    } 
    
    $result1->finish();

    # Kollation
    
    my $result1=$dbh->prepare("select cnt from dc_for_ext where pid=?");
    $result1->execute($pid);
    
    while (my $res1=$result1->fetchrow_hashref){	    
        my $content=$res1->{'cnt'};
        chomp($content);
        $content=stripjunk($content);

        if ($content){
            print TIT "0433:$content S.\n";
        }
    } 
    
    $result1->finish();

    
    
    print TIT "0662:http://www.econbiz.de/admin/onteam/einzelansicht.shtml?pid=$pid\n";

    # Dokument-URL
    my $result1=$dbh->prepare("select cnt from dc_ide where pid=?");
    $result1->execute($pid);
    
    while (my $res1=$result1->fetchrow_hashref){	    
        my $content=$res1->{'cnt'};
        chomp($content);
        $content=stripjunk($content);

        if ($content){
            print TIT "0662:$content\n";
        }
    } 
    
    $result1->finish();


    # Dokumententyp/Medienart
    my $result1=$dbh->prepare("select cntg from stlv, dc_typ where dc_typ.pid=? and dc_typ.cnt=stlv.nr");
    $result1->execute($pid);
    
    while (my $res1=$result1->fetchrow_hashref){	    
        my $content=$res1->{'cntg'};
        chomp($content);
        $content=stripjunk($content);

        if ($content){
            print TIT "0800:$content\n";
        }
    } 
    
    $result1->finish();

    
    print TIT "9999:\n";

    if ($titlecount % 1000 == 0){
        $logger->info("Processed $titlecount titles");
    }
    $titlecount++;
}

$result->finish();

$dbh->disconnect();

close(DAT);

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);

sub stripjunk {
    my ($item)=@_;
    $item=~s/ +$//;
    $item=~s/ *; .{5,11}$//;
    $item=~s/\n/<br>/g;
    $item=~s/\r//g;
#  $item=~s/\[/#093/g;
#  $item=~s/\]/#094/g;
#  $item=~s/�"/g;
#  $item=~s/�"/g;
    $item=~s/\x{93}/"/g;
    $item=~s/\x{94}/"/g;
    $item=~s/\x{96}/-/g;
    return $item;
}

