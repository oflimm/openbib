#!/usr/bin/perl

#####################################################################
#
#  econbiz2meta.pl
#
#  Konverierung von Econbiz-Daten in das Meta-Format
#  ueber die Zwischenstation des OAI-Formats
#
#  Dieses File ist (C) 2004-2006 Oliver Flimm <flimm@openbib.org>
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

use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

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

#######################################################################
# Umwandeln

$titidx=0;

$autidn=1;
$autidx=0;

$swtidn=1;
$swtidx=0;

$mexidn=1;
$mexidx=0;

$koridn=1;
$koridx=0;

$autdublastidx=1;
$kordublastidx=1;
$swtdublastidx=1;

my $dbh=DBI->connect("DBI:$dbimodule:dbname=$dbname;host=$dbhost;port=$port", $dbuser, $dbpasswd) or die "could not connect";

my $result=$dbh->prepare("select pid,cnt,lng from dc_tit") or die "Error -- $DBI::errstr";
$result->execute();

while (my $res=$result->fetchrow_hashref){
    my $pid  = $res->{'pid'};
    my $hst  = $res->{'cnt'};
    my $lang = $res->{'lng'};
    chomp($pid );
    chomp($hst );
    chomp($lang);

    $titbuffer[$titidx++]="0000:".$pid;


    my $cdateresult=$dbh->prepare("select cnt from dc_dat_cre where pid=?");
    $cdateresult->execute($pid);
    
    while (my $cdateres=$cdateresult->fetchrow_hashref){
        my $cdate=$cdateres->{'cnt'};
        chomp($cdate);
        $titbuffer[$titidx++]="0002:".$cdate;
    }
    
    my $urhresult=$dbh->prepare("select cnt from dc_cre_per_nam where pid=?");
    $urhresult->execute($pid);
    
    while (my $urhres=$urhresult->fetchrow_hashref){
        my $urh=$urhres->{'cnt'};
        chomp($urh);
        $urh=stripjunk($urh);
        
        $autidn=get_autidn($urh);
	
        if ($autidn > 0){
            $autbuffer[$autidx++]="0000:".$autidn;
            $autbuffer[$autidx++]="0001:".$urh;
            $autbuffer[$autidx++]="9999:";
        }
        else {
            $autidn=(-1)*$autidn;
        }
        $titbuffer[$titidx++]="0100:IDN: ".$autidn;
    }
    
    $urhresult=$dbh->prepare("select cnt from dc_pub_per_nam where pid=?");
    $urhresult->execute($pid);
    
    while (my $urhres=$urhresult->fetchrow_hashref){
        my $urh=$urhres->{'cnt'};
        chomp($urh);
        $urh=stripjunk($urh);
        
        $autidn=get_autidn($urh);
	
        if ($autidn > 0){
            $autbuffer[$autidx++]="0000:".$autidn;
            $autbuffer[$autidx++]="0001:".$urh;
            $autbuffer[$autidx++]="9999:";
            
        }
        else {
            $autidn=(-1)*$autidn;
        }
        
        $titbuffer[$titidx++]="0100:IDN: ".$autidn;
    } 
    
    $urhresult->finish();
    
    my $korresult=$dbh->prepare("select cnt from dc_cre_cor_nam where pid=?");
    $korresult->execute($pid);
    
    while (my $korres=$korresult->fetchrow_hashref){	    
        my $kor=$korres->{'cnt'};
        chomp($kor);
        $kor=stripjunk($kor);
        
        $koridn=get_koridn($kor);
	
        if ($koridn > 0){
            $korbuffer[$koridx++]="0000:".$koridn;
            $korbuffer[$koridx++]="0001:".$kor;
            $korbuffer[$koridx++]="9999:";
            
        }
        else {
            $koridn=(-1)*$koridn;
        }
        
        $titbuffer[$titidx++]="0201:IDN: ".$koridn;
    } 
    
    $korresult=$dbh->prepare("select cnt from dc_pub_cor_nam where pid=?");
    $korresult->execute($pid);
    
    while (my $korres=$korresult->fetchrow_hashref){	    
        my $kor=$korres->{'cnt'};
        chomp($kor);
        $kor=stripjunk($kor);
        
        $koridn=get_koridn($kor);
	
        if ($koridn > 0){
            $korbuffer[$koridx++]="0000:".$koridn;
            $korbuffer[$koridx++]="0001:".$kor;
            $korbuffer[$koridx++]="9999:";
            
        }
        else {
            $koridn=(-1)*$koridn;
        }
        
        $titbuffer[$titidx++]="0201:IDN: ".$koridn;
    } 
    
    $korresult->finish();
    
    $titbuffer[$titidx++]="0331:".stripjunk($hst);
    
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
            $swtidn=get_swtidn($swtg);
            
            if ($swtidn > 0){
                $swtbuffer[$swtidx++]="0000:".$swtidn;
                $swtbuffer[$swtidx++]="0001:".$swtg;
                $swtbuffer[$swtidx++]="9999:";
                
            }
            else {
                $swtidn=(-1)*$swtidn;
            }
            
            $titbuffer[$titidx++]="0710:IDN: ".$swtidn;
        }
        
        if ($swte){
            $swtidn=get_swtidn($swte);
            
            if ($swtidn > 0){
                $swtbuffer[$swtidx++]="0000:".$swtidn;
                $swtbuffer[$swtidx++]="0001:".$swte;
                $swtbuffer[$swtidx++]="9999:";
                
            }
            else {
                $swtidn=(-1)*$swtidn;
            }
            
            $titbuffer[$titidx++]="0710:IDN: ".$swtidn;
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
            $titbuffer[$titidx++]="0750:".$abs;
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
            $titbuffer[$titidx++]="0435:".$formattab{$content};
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
            $titbuffer[$titidx++]="0435:".$formattab{$content};
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
            $titbuffer[$titidx++]="0433:".$content." S.";
        }
    } 
    
    $result1->finish();

    
    
    $titbuffer[$titidx++]="0662:http://www.econbiz.de/admin/onteam/einzelansicht.shtml?pid=$pid";

    # Dokument-URL
    my $result1=$dbh->prepare("select cnt from dc_ide where pid=?");
    $result1->execute($pid);
    
    while (my $res1=$result1->fetchrow_hashref){	    
        my $content=$res1->{'cnt'};
        chomp($content);
        $content=stripjunk($content);

        if ($content){
            $titbuffer[$titidx++]="0662:".$content;
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
            $titbuffer[$titidx++]="0800:".$content;
        }
    } 
    
    $result1->finish();

    
    $titbuffer[$titidx++]="9999:";

}

$result->finish();

$dbh->disconnect();

$lasttitidx=$titidx;
$lastautidx=$autidx;
$lastmexidx=$mexidx;
$lastkoridx=$koridx;
$lastswtidx=$swtidx;

# Ausgabe der EXP-Dateien

ausgabetitfile();
ausgabeautfile();
ausgabekorfile();
ausgabeswtfile();

close(DAT);

sub ausgabetitfile {
    open (TIT,">:utf8","unload.TIT");
    $i=0;
    while ($i < $lasttitidx){
        print TIT $titbuffer[$i],"\n";
        $i++;
    }
    close(TIT);
}

sub ausgabeautfile {
    open(AUT,">:utf8","unload.PER");
    $i=0;
    while ($i < $lastautidx){
        print AUT $autbuffer[$i],"\n";
        $i++;
    }
    close(AUT);
}

sub ausgabekorfile {
    open(KOR,">:utf8","unload.KOE");
    $i=0;
    while ($i < $lastkoridx){
        print KOR $korbuffer[$i],"\n";
        $i++;
    }
    close(KOR);
}

sub ausgabeswtfile {
    open(SWT,">:utf8","unload.SWD");
    $i=0;
    while ($i < $lastswtidx) {
        print SWT $swtbuffer[$i],"\n";
        $i++;
    }
    close(SWT);
}

sub get_autidn {
    ($autans)=@_;
    
    $autdubidx=$startautidn;
    $autdubidn=0;
    
    while ($autdubidx < $autdublastidx){
        if ($autans eq $autdubbuf[$autdubidx]){
            $autdubidn=(-1)*$autdubidx;
        }
        $autdubidx++;
    }
    if (!$autdubidn){
        $autdubbuf[$autdublastidx]=$autans;
        $autdubidn=$autdublastidx;
        $autdublastidx++;
    }
    return $autdubidn;
}

sub get_swtidn {
    ($swtans)=@_;
    
    $swtdubidx=$startswtidn;
    $swtdubidn=0;
    
    while ($swtdubidx < $swtdublastidx){
        if ($swtans eq $swtdubbuf[$swtdubidx]){
            $swtdubidn=(-1)*$swtdubidx;
        }
        $swtdubidx++;
    }
    if (!$swtdubidn){
        $swtdubbuf[$swtdublastidx]=$swtans;
        $swtdubidn=$swtdublastidx;
        $swtdublastidx++;
    }
    return $swtdubidn;
}

sub get_koridn {
    ($korans)=@_;
    
    $kordubidx=$startkoridn;
    $kordubidn=0;
    
    while ($kordubidx < $kordublastidx){
        if ($korans eq $kordubbuf[$kordubidx]){
            $kordubidn=(-1)*$kordubidx;
        }
        $kordubidx++;
    }
    if (!$kordubidn){
        $kordubbuf[$kordublastidx]=$korans;
        $kordubidn=$kordublastidx;
        $kordublastidx++;
    }
    return $kordubidn;
}

sub stripjunk {
    my ($item)=@_;
    $item=~s/ +$//;
    $item=~s/ *; .{5,11}$//;
    $item=~s/\n/<br>/g;
    $item=~s/
//g;
#  $item=~s/\[/#093/g;
#  $item=~s/\]/#094/g;
#  $item=~s/�"/g;
#  $item=~s/�"/g;
    $item=~s/\x{93}/"/g;
    $item=~s/\x{94}/"/g;
    $item=~s/\x{96}/-/g;
    return $item;
}

