#!/usr/bin/perl

#####################################################################
#
#  lidos2meta.pl
#
#  Konvertierung des LIDOS XML-Formates in des OpenBib Einlade-Metaformat
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

use 5.008001;

use utf8;
use Encode;

use XML::Twig;

use vars qw(@autbuffer @autdubbuf);
use vars qw(@korbuffer @kordubbuf);
use vars qw(@swtbuffer @swtdubbuf);
use vars qw(@titbuffer @titdubbuf);

my $inputfile=$ARGV[0];

$autdublastidx=1;
$autidx=0;

$kordublastidx=1;
$koridx=0;

$swtdublastidx=1;
$swtidx=0;

$titdublastidx=1;
$titidx=0;

@autbuffer=();
@autdubbuf=();
@korbuffer=();
@kordubbuf=();
@swtbuffer=();
@swtdubbuf=();
@titbuffer=();
@titdubbuf=();

my $twig= XML::Twig->new(
   TwigHandlers => {
     "/BIBLIO/LIDOS-Dokument" => \&parse_titset
   }
 );


$twig->parsefile($inputfile);

ausgabeautfile();
ausgabekorfile();
ausgabeswtfile();
ausgabetitfile();

sub parse_titset {
    my($t, $titset)= @_;
    
    my $id=-1;
    if($titset->first_child( 'Dok-Nummer')->text()) {
        $id=$titset->first_child( 'Dok-Nummer')->text();
        $id=~s/^0+//g;
    }

    $titbuffer[$titidx++]="0000:".$id;
    

    # Verfasser/Personen
    if($titset->first_child( 'Verfasser')->text()) {
        my @verfasser=split ("; ",$titset->first_child( 'Verfasser')->text());
        foreach my $singleverf (@verfasser){
            my $autidn=get_autidn($singleverf);
            if ($autidn > 0){
                $autbuffer[$autidx++]="0000:".$autidn;
                $autbuffer[$autidx++]="0001:".$singleverf;
                $autbuffer[$autidx++]="9999:";
            }
            else {
                $autidn=(-1)*$autidn;
            }

            $titbuffer[$titidx++]="0100:IDN: ".$autidn;
        }
    }
    
    if($titset->first_child( 'beteiligte_Personen')->text()) {
        my @verfasser=split ("; ",$titset->first_child( 'beteiligte_Personen')->text());
        foreach my $singleverf (@verfasser){
            my $autidn=get_autidn($singleverf);
            if ($autidn > 0){
                $autbuffer[$autidx++]="0000:".$autidn;
                $autbuffer[$autidx++]="0001:".$singleverf;
                $autbuffer[$autidx++]="9999:";
            }
            else {
                $autidn=(-1)*$autidn;
            }

            $titbuffer[$titidx++]="0101:IDN: ".$autidn;
        }
    }

    # Koerperschaften
    if($titset->first_child('Körperschaft')->text()) {
        my @koerperschaften=split ("; ",$titset->first_child('Körperschaft')->text());
        foreach my $singlekor (@koerperschaften){
            my $koridn=get_koridn($singlekor);
            if ($koridn > 0){
                $korbuffer[$koridx++]="0000:".$koridn;
                $korbuffer[$koridx++]="0001:".$singlekor;
                $korbuffer[$koridx++]="9999:";
            }
            else {
                $koridn=(-1)*$koridn;
            }

            $titbuffer[$titidx++]="0201:IDN: ".$koridn;
        }
    }

    # Sonst.Koerperschaften
    if($titset->first_child('beteiligte_Körperschaften')->text()) {
        my @koerperschaften=split ("; ",$titset->first_child('beteiligte_Körperschaften')->text());
        foreach my $singlekor (@koerperschaften){
            my $koridn=get_koridn($singlekor);
            if ($koridn > 0){
                $korbuffer[$koridx++]="0000:".$koridn;
                $korbuffer[$koridx++]="0001:".$singlekor;
                $korbuffer[$koridx++]="9999:";
                
            }
            else {
                $koridn=(-1)*$koridn;
            }

            $titbuffer[$titidx++]="0201:IDN: ".$koridn;
        }
    }
    

    # Schlagworte
    foreach my $desk ($titset->children('Deskriptoren')){
        my $swtans=$desk->text();
        if ($swtans){
            my $swtidn=get_swtidn($swtans);
            if ($swtidn > 0){
                $swtbuffer[$swtidx++]="0000:".$swtidn;
                $swtbuffer[$swtidx++]="0001:".$swtans;
                $swtbuffer[$swtidx++]="9999:";
            }
            else {
                $swtidn=(-1)*$swtidn;
            }

            $titbuffer[$titidx++]="0710:IDN: ".$swtidn;
        }
    }
    
    # Titelkategorien

    # Titel
    if($titset->first_child('Titel')->text()){
        $titbuffer[$titidx++]="0331:".$titset->first_child('Titel')->text();
    }

    # Titelzusatz
    if($titset->first_child('Zusatz_zum_Titel')->text()){
        $titbuffer[$titidx++]="0335:".$titset->first_child('Zusatz_zum_Titel')->text();
    }

    # Ausgabe
    if($titset->first_child('Ausgabe')->text()){
        $titbuffer[$titidx++]="0403:".$titset->first_child('Ausgabe')->text();
    }

    # Verlag
    if($titset->first_child('Verlag')->text()){
        $titbuffer[$titidx++]="0412:".$titset->first_child('Verlag')->text();
    }

    # Verlagsort
    if($titset->first_child('Ort')->text()){
        $titbuffer[$titidx++]="0410:".$titset->first_child('Ort')->text();
    }

    # Umfang/Format
    if($titset->first_child('Umfang_-_Format')->text()){
        $titbuffer[$titidx++]="0433:".$titset->first_child('Umfang_-_Format')->text();
    }

    # Jahr
    if($titset->first_child('Jahr')->text()){
        $titbuffer[$titidx++]="0425:".$titset->first_child('Jahr')->text();
    }

    $titbuffer[$titidx++]="9999:";
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}
                                   
                                   
sub get_autidn {
    ($autans)=@_;
    
    $autdubidx=1;
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
    
    $swtdubidx=1;
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
    
    $kordubidx=1;
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

sub ausgabeautfile {
    open(AUT,">:utf8","unload.PER");
    $i=0;
    while ($i < $autidx){
        print AUT $autbuffer[$i],"\n";
        $i++;
    }
    close(AUT);
}

sub ausgabetitfile
{
    open (TIT,">:utf8","unload.TIT");
    $i=0;
    while ($i < $titidx){
        print TIT $titbuffer[$i],"\n";
        $i++;
    }
    close(TIT);
}

sub ausgabemexfile {
    open(MEX,">:utf8","mex.exp");
    $i=0;
    while ($i < $mexidx){
	print MEX $mexbuffer[$i],"\n";
	$i++;
    }
    close(MEX);
}

sub ausgabeswtfile {
  open(SWT,">:utf8","unload.SWD");
  $i=0;
  while ($i < $swtidx) {
      print SWT $swtbuffer[$i],"\n";
      $i++;
  }
  close(SWT);
}

sub ausgabekorfile {
    open(KOR,">:utf8","unload.KOE");
    $i=0;
    while ($i < $koridx){
	print KOR $korbuffer[$i],"\n";
	$i++;
    }
    close(KOR);
}

