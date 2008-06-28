#!/usr/bin/perl

#####################################################################
#
#  cdm2meta.pl
#
#  Konvertierung des CDM XML-Formates in des OpenBib
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
     "/metadata/record" => \&parse_titset
   }
 );


$twig->parsefile($inputfile);

ausgabeautfile();
ausgabekorfile();
ausgabeswtfile();
ausgabetitfile();

sub parse_titset {
    my($t, $titset)= @_;
    
    $titbuffer[$titidx++]="0000:".$titset->first_child('cdmid')->text();
    
    # Verfasser/Personen
    if(defined $titset->first_child('creator') && $titset->first_child('creator')->text()){
        foreach my $ans (split('\s+;\s+',$titset->first_child('creator')->text())){
            if ($ans){
                $ans=~s/>/&gt;/g;
                $ans=~s/</&lt;/g;
                
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
    }

    # Titelkategorien

    # Erstellungsdatum
    if(defined $titset->first_child('cdmcreated') && $titset->first_child('cdmcreated')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmcreated')->text());
        $titbuffer[$titidx++]="0002:$day.$month.$year";
    }

    # Aenderungsdatum
    if(defined $titset->first_child('cdmmodified') && $titset->first_child('cdmcreated')->text()){
        my ($year,$month,$day)=split("-",$titset->first_child('cdmcreated')->text());
        $titbuffer[$titidx++]="0003:$day.$month.$year";
    }

    # Titel
    if(defined $titset->first_child('title') && $titset->first_child('title')->text()){
        $titbuffer[$titidx++]="0331:".$titset->first_child('title')->text();
    }

    # Verlag
    if(defined $titset->first_child('publisher') && $titset->first_child('publisher')->text()){
        $titbuffer[$titidx++]="0412:".$titset->first_child('publisher')->text();
    }

    # Beschreibung/Abstract
    if(defined $titset->first_child('description') && $titset->first_child('description')->text()){
        $titbuffer[$titidx++]="0750:".$titset->first_child('description')->text();
    }
    
    # Jahr
    if(defined $titset->first_child('date') && $titset->first_child('date')->text()){
        $titbuffer[$titidx++]="0425:".$titset->first_child('date')->text();
    }
    
    # Sprache
    if(defined $titset->first_child('language') && $titset->first_child('language')->text()){
        $titbuffer[$titidx++]="0005:".$titset->first_child('language')->text();
    }

    # Quelle
    if(defined $titset->first_child('relation') && $titset->first_child('relation')->text()){
        $titbuffer[$titidx++]="0508:".$titset->first_child('relation')->text();
    }

    # Signatur
    if(defined $titset->first_child('unmapped') && $titset->first_child('unmapped')->text()){
        $titbuffer[$titidx++]="0014.001:".$titset->first_child('unmapped')->text();
    }

    # CDM-Thumbnail URL
    if(defined $titset->first_child('thumbnailURL') && $titset->first_child('thumbnailURL')->text()){
        $titbuffer[$titidx++]="2662:".$titset->first_child('thumbnailURL')->text();
    }

    # CDM-URL
    if(defined $titset->first_child('viewerURL') && $titset->first_child('viewerURL')->text()){
        $titbuffer[$titidx++]="0662:".$titset->first_child('viewerURL')->text();
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

