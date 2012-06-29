#!/usr/bin/perl

#####################################################################
#
#  filemaker2meta.pl
#
#  Konvertierung des FileMaker XML-Formates in des OpenBib Einlade-Metaformat
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
use YAML;

use vars qw(@autbuffer @autdubbuf);
use vars qw(@korbuffer @kordubbuf);
use vars qw(@swtbuffer @swtdubbuf);
use vars qw(@titbuffer @titdubbuf $titcount);

my $inputfile=$ARGV[0];

my $titcount=0;

$autdublastidx=1;
$autidx=0;

$kordublastidx=1;
$koridx=0;

$swtdublastidx=1;
$swtidx=0;

$titdublastidx=1;
$titidx=0;

$mexidn=1;
$mexidx=0;

@autbuffer=();
@autdubbuf=();
@korbuffer=();
@kordubbuf=();
@swtbuffer=();
@swtdubbuf=();
@titbuffer=();
@titdubbuf=();
@mexbuffer=();

%metadata=();
%metaidx=0;

# my $twig_meta= XML::Twig->new(
#    TwigHandlers => {
#      "/FMPXMLRESULT/METADATA/FIELD" => \&parse_metadata
#    },
#  );

# # Metadata einlesen
# $twig_meta->safe_parsefile($inputfile);

# print YAML::Dump(\%metadata);

# exit;


my $twig= XML::Twig->new(
   TwigHandlers => {
     "/FMPXMLRESULT/METADATA/FIELD" => \&parse_metadata,
     "/FMPXMLRESULT/RESULTSET/ROW" => \&parse_titset,
   },
 );


print STDERR "Daten werden eingelesen und geparsed\n";
$twig->safe_parsefile($inputfile);

print STDERR $@;

print STDERR "Verfasser werden ausgegeben\n";

ausgabeautfile();

print STDERR "Koerperschaften werden ausgegeben\n";

ausgabekorfile();

print STDERR "Schlagworte werden ausgegeben\n";

ausgabeswtfile();

print STDERR "Titel werden ausgegeben\n";

ausgabetitfile();

print STDERR "Exemplardaten werden ausgegeben\n";

ausgabemexfile();

print STDERR "Titelzahl: $titcount\n";

sub parse_metadata {
    my($t, $field)= @_;

    my $att=$field->{'att'}->{'NAME'};

    $metadata{$att}=int($metaidx);

    print "Mapping Category $att to index $metaidx - ".int($metaidx)."\n";
    
    $metaidx++;
    # Release memory of processed tree
    # up to here
    $t->purge();
}

sub parse_titset {
    my($t, $titset)= @_;

    $titcount++;

    my $id=$titset->{'att'}->{'RECORDID'};

    $titbuffer[$titidx++]="0000:".$id;

    my @cols=$titset->children('COL');
    
    # Verfasser/Personen
    # Autor
    my @verfasser=();
    if(exists $metadata{'Autor'} && $cols[$metadata{'Autor'}]->first_child('DATA')->text()) {
        for my $singleverf (split (";",$cols[$metadata{'Autor'}]->first_child('DATA')->text())){
            # Inhalt bereinigen
            $singleverf=~s/\s*:\s*$//;
            $singleverf=~s/. -$//;
            $singleverf=~s/^\s+//;
            $singleverf=~s/\s+$//;
            push @verfasser, $singleverf;
        }
    }

    # AutorJap
    if( exists $metadata{'AutorJap'} && $cols[$metadata{'AutorJap'}]->first_child('DATA')->text()) {
        for my $singleverf (split (";",$cols[$metadata{'AutorJap'}]->first_child('DATA')->text())){
            # Inhalt bereinigen
            $singleverf=~s/\s*:\s*$//;
            $singleverf=~s/. -$//;
            $singleverf=~s/^\s+//;
            $singleverf=~s/\s+$//;
            push @verfasser, $singleverf;
        }
    }

    # AV
    if( exists $metadata{'AV'} && $cols[$metadata{'AV'}]->first_child('DATA')->text()) {
        for my $singleverf (split (";",$cols[$metadata{'AV'}]->first_child('DATA')->text())){
            # Inhalt bereinigen
            $singleverf=~s/\s*:\s*$//;
            $singleverf=~s/. -$//;
            $singleverf=~s/^\s+//;
            $singleverf=~s/\s+$//;
            push @verfasser, $singleverf;
        }
    }

    my %seen_terms = ();
    my @unique_verfasser = grep { ! $seen_terms{$_} ++ } @verfasser;

    foreach my $singleverf (@unique_verfasser){        
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

    # Schlagworte
    if(exists $metadata{'Schlagwort'} && $cols[$metadata{'Schlagwort'}]->first_child('DATA')->text()) {
        my $swtans_all=$cols[$metadata{'Schlagwort'}]->text();

        if ($swtans_all){
            my @swts = split(" +",$swtans_all);

            foreach my $swtans (@swts){
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
    }

    # Titelkategorien

    # Titel
    my @titel=();
    if(exists $metadata{'Titel'} && $cols[$metadata{'Titel'}]->first_child('DATA')->text()) {
        push @titel, $cols[$metadata{'Titel'}]->first_child('DATA')->text();
    }
    # Titel Jap
    if(exists $metadata{'TitelJap'} && $cols[$metadata{'TitelJap'}]->first_child('DATA')->text()) {
        push @titel, $cols[$metadata{'TitelJap'}]->first_child('DATA')->text();
    }
    if (@titel){
        $titbuffer[$titidx++]="0331:".join(' / ',@titel);
    }
    
    # Ausgabe
    if(exists $metadata{'Ausgabe'} && $cols[$metadata{'Ausgabe'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0403:".$cols[$metadata{'Ausgabe'}]->first_child('DATA')->text();
    }

    # Verlag
    my @verlag=();
    if(exists $metadata{'Verlag'} && $cols[$metadata{'Verlag'}]->first_child('DATA')->text()){
        push @verlag, $cols[$metadata{'Verlag'}]->first_child('DATA')->text();
    }
    if(exists $metadata{'VerlJap'} && $cols[$metadata{'VerlJap'}]->first_child('DATA')->text()){
        push @verlag, $cols[$metadata{'VerlJap'}]->first_child('DATA')->text();
    }
    if (@verlag){
        $titbuffer[$titidx++]="0412:".join(' / ',@verlag);
    }
    
    # Verlagsort
    my @verlagsorte=();
    if(exists $metadata{'Ort'} && $cols[$metadata{'Ort'}]->first_child('DATA')->text()){
        push @verlagsorte, $cols[$metadata{'Ort'}]->first_child('DATA')->text();
    }
    if(exists $metadata{'OrtJap'} && $cols[$metadata{'OrtJap'}]->first_child('DATA')->text()){
        push @verlagsorte, $cols[$metadata{'OrtJap'}]->first_child('DATA')->text();
    }
    if (@verlagsorte){
        $titbuffer[$titidx++]="0410:".join(' / ',@verlagsorte);
    }

    # Umfang/Format
    if(exists $metadata{'Kollation'} && $cols[$metadata{'Kollation'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0433:".$cols[$metadata{'Kollation'}]->first_child('DATA')->text();
    }

    # Jahr
    if(exists $metadata{'Jahr'} && $cols[$metadata{'Jahr'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0425:".$cols[$metadata{'Jahr'}]->first_child('DATA')->text();
    }

    # Gesamttitel / Reihe
    my @gesamttitel=();
    if(exists $metadata{'Gesamttitel'} && $cols[$metadata{'Gesamttitel'}]->first_child('DATA')->text()){
        push @gesamttitel, $cols[$metadata{'Gesamttitel'}]->first_child('DATA')->text();
    }
    if(exists $metadata{'GesamtJap'} && $cols[$metadata{'GesamtJap'}]->first_child('DATA')->text()){
        push @gesamttitel, $cols[$metadata{'GesamtJap'}]->first_child('DATA')->text();
    }
    if(exists $metadata{'Reihe'} && $cols[$metadata{'Reihe'}]->first_child('DATA')->text()){
        push @gesamttitel, $cols[$metadata{'Reihe'}]->first_child('DATA')->text();
    }
    if(exists $metadata{'ReiheJap'} && $cols[$metadata{'ReiheJap'}]->first_child('DATA')->text()){
        push @gesamttitel, $cols[$metadata{'ReiheJap'}]->first_child('DATA')->text();
    }
    if (@gesamttitel){
        $titbuffer[$titidx++]="0451:".join(' / ',@gesamttitel);
    }
    
    if(exists $metadata{'Sprache'} && $cols[$metadata{'Sprache'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0015:".$cols[$metadata{'Sprache'}]->first_child('DATA')->text();
    }

    if(exists $metadata{'Nummer'} && $cols[$metadata{'Nummer'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0089:".$cols[$metadata{'Nummer'}]->first_child('DATA')->text();
    }

    if(exists $metadata{'Fußnote'} && $cols[$metadata{'Fußnote'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0501:".$cols[$metadata{'Fußnote'}]->first_child('DATA')->text();
    }

    if(exists $metadata{'Inventar'} && $cols[$metadata{'Inventar'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0005.001:".$cols[$metadata{'Inventar'}]->first_child('DATA')->text();
    }

    # Quelle
    if(exists $metadata{'Jg,Heft,Bd'} && $cols[$metadata{'Jg,Heft,Bd'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0590:".$cols[$metadata{'Jg,Heft,Bd'}]->first_child('DATA')->text();
    }

    # ISBN
    if(exists $metadata{'ISBN'} && $cols[$metadata{'ISBN'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0540:".$cols[$metadata{'ISBN'}]->first_child('DATA')->text();
    }

    # Datum
    if(exists $metadata{'Datum'} && $cols[$metadata{'Datum'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0002:".$cols[$metadata{'Datum'}]->first_child('DATA')->text();
    }

    if(exists $metadata{'Standort'} && $cols[$metadata{'Standort'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0016.001:".$cols[$metadata{'Standort'}]->first_child('DATA')->text();
    }
    
    if(exists $metadata{'Signatur_flach'} && $cols[$metadata{'Signatur_flach'}]->first_child('DATA')->text()){
        $titbuffer[$titidx++]="0014.001:".$cols[$metadata{'Signatur_flach'}]->first_child('DATA')->text();
    }

    $titbuffer[$titidx++]="9999:";

    # Exemplardaten
    if (exists $metadata{'Signatur'} && $cols[$metadata{'Signatur'}]->first_child('DATA')->text() || $cols[$metadata{'Standort'}]->first_child('DATA')->text()){

        $mexbuffer[$mexidx++]="0000:$mexidn";
        $mexbuffer[$mexidx++]="0004:$id";

        if(exists $metadata{'Standort'} && $cols[$metadata{'Standort'}]->first_child('DATA')->text()){
            $mexbuffer[$mexidx++]="0016.001:".$cols[$metadata{'Standort'}]->first_child('DATA')->text();
        }

        if(exists $metadata{'Signatur_flach'} && $cols[$metadata{'Signatur_flach'}]->first_child('DATA')->text()){
            $mexbuffer[$mexidx++]="0014.001:".$cols[$metadata{'Signatur_flach'}]->first_child('DATA')->text();
        }
        $mexbuffer[$mexidx++]="9999:";
        $mexidn++;
    }


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
    open(MEX,">:utf8","unload.MEX");
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

