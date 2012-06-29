#!/usr/bin/perl

#####################################################################
#
#  tellico_music2meta.pl
#
#  Konvertierung des Tellico XML-Formates (Musik) in des OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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

use XML::Twig;

use vars qw(@autbuffer @autdubbuf);
use vars qw(@korbuffer @kordubbuf);
use vars qw(@swtbuffer @swtdubbuf);
use vars qw(@titbuffer @titdubbuf);
use vars qw($id);
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
     "/tellico/collection/entry" => \&parse_titset
   }
 );


$twig->parsefile($inputfile);

ausgabeautfile();
ausgabekorfile();
ausgabeswtfile();
ausgabetitfile();

sub parse_titset {
    my($t, $titset)= @_;

    #  Beispiel:
    #
    #  <entry id="1" >
    #   <title>Autour de Lucie</title>
    #   <artists>
    #    <artist>Autour de Lucie</artist>
    #   </artists>
    #   <year>2001</year>
    #   <anzahl-titel>11</anzahl-titel>
    #   <besitzer>Oliver Flimm</besitzer>
    #  </entry>

    my $id = int($titset->{'att'}->{'id'});
        
    $titbuffer[$titidx++]="0000:".$id;
               
    # Verfasser/Personen
    foreach my $desk ($titset->children('artists')){
        my $ans=$desk->text();
        if ($ans){
            my $idn=get_autidn($ans);
            if ($idn > 0){
                $autbuffer[$autidx++]="0000:".$idn;
                $autbuffer[$autidx++]="0001:".$ans;
                $autbuffer[$autidx++]="9999:";
            }
            else {
                $idn=(-1)*$idn;
            }

            $titbuffer[$titidx++]="0100:IDN: ".$idn;
        }
    }

    # Titelkategorien

    # Titel
    if(defined $titset->first_child('title')){
        $titbuffer[$titidx++]="0331:".$titset->first_child('title')->text();
    }


    # Anzahl Titel
    if(defined $titset->first_child('anzahl-titel')){
        $titbuffer[$titidx++]="0433:".$titset->first_child('anzahl-titel')->text();
    }

    # Anzahl Medien
    if(defined $titset->first_child('anzahl-medien')){
        $titbuffer[$titidx++]="0512:".$titset->first_child('anzahl-medien')->text()." Medien";
    }

    # Medienart
    if(defined $titset->first_child('medium')){
        $titbuffer[$titidx++]="0800:".$titset->first_child('medium')->text();
    }
    
    # Jahr
    if(defined $titset->first_child('year')){
        $titbuffer[$titidx++]="0425:".$titset->first_child('year')->text();
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
            
            # print STDERR "AutIDN schon vorhanden: $autdubidn\n";
        }
        $autdubidx++;
    }
    if (!$autdubidn){
        $autdubbuf[$autdublastidx]=$autans;
        $autdubidn=$autdublastidx;
        #print STDERR "AutIDN noch nicht vorhanden: $autdubidn\n";
        $autdublastidx++;
        
    }
    return $autdubidn;
}
                                   
sub get_swtidn {
    ($swtans)=@_;
    
    $swtdubidx=1;
    $swtdubidn=0;
    #  print "Swtans: $swtans\n";
    
    while ($swtdubidx < $swtdublastidx){
        if ($swtans eq $swtdubbuf[$swtdubidx]){
            $swtdubidn=(-1)*$swtdubidx;      
            
            #            print "SwtIDN schon vorhanden: $swtdubidn, $swtdublastidx\n";
        }
        $swtdubidx++;
    }
    if (!$swtdubidn){
        $swtdubbuf[$swtdublastidx]=$swtans;
        $swtdubidn=$swtdublastidx;
        #        print "SwtIDN noch nicht vorhanden: $swtdubidn, $swtdubidx, $swtdublastidx\n";
        $swtdublastidx++;
        
    }
    return $swtdubidn;
}
                                   
sub get_koridn {
    ($korans)=@_;
    
    $kordubidx=1;
    $kordubidn=0;
    #  print "Korans: $korans\n";
    
    while ($kordubidx < $kordublastidx){
        if ($korans eq $kordubbuf[$kordubidx]){
            $kordubidn=(-1)*$kordubidx;
        }
        $kordubidx++;
    }
    if (!$kordubidn){
        $kordubbuf[$kordublastidx]=$korans;
        $kordubidn=$kordublastidx;
        #    print "KorIDN noch nicht vorhanden: $kordubidn\n";
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

