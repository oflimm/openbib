#!/usr/bin/perl

#####################################################################
#
#  wikisource_de2meta.pl
#
#  Konvertierung der Textdaten des Wikisource Formates in das OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode';
use Getopt::Long;
use XML::Twig;
use YAML::Syck;

use OpenBib::Config;

our (@autdubbuf,@kordubbuf,@swtdubbuf,@notdubbuf,$mexidn);

@autdubbuf = ();
@kordubbuf = ();
@swtdubbuf = ();
@notdubbuf = ();
$mexidn  =  1;

$autdublastidx=1;
$kordublastidx=1;
$notdublastidx=1;
$swtdublastidx=1;


my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
wikisource_de2meta.pl - Aufrufsyntax

    wikisource_de2meta.pl --inputfile=xxx
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

my $twig= XML::Twig->new(
   TwigHandlers => {
     "/mediawiki/page" => \&parse_titset
   }
 );


$twig->parsefile($inputfile);

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);
close(MEX);

sub parse_titset {
    my($t, $titset)= @_;

    my $id          = $titset->first_child($convconfig->{uniqueidfield})->text();

    my $titel       = $titset->first_child("title")->text();

    my ($text)      = $titset->find_nodes("revision/text");

    my $textinhalt  = $text->text();
    
    my ($textdaten) = $textinhalt =~m/^\{\{Textdaten.*?\|\s*(AUTOR=.*?TITEL.*?SUBTITEL.*?)^}}/sm;


    return if (!$textdaten);

    my $baseurl         = $convconfig->{baseurl};
    my $commons_baseurl = $convconfig->{commons_baseurl};
    
    print TIT "0000:$id\n";
    
    $textdaten=~s/\n//sg;

    # Bei internen Links nur Alternativbezeichner uebriglassen
    # zuerst Commons
    $textdaten=~s/\[\[:?commons:([^|\[\]]+?)\|(.+?)]]/<a href="$commons_baseurl$1" class="ext" target="_blank">$2<\/a>/gi;
    # dann den Rest
    $textdaten=~s/\[\[([^|\]]+?)\|(.+?)]]/<a href="$baseurl$1" class="ext" target="_blank">$2<\/a>/g;

    foreach my $item (split("\\|",$textdaten)){
        if ($item !~/=/){
            next;
        }

        my ($category,$content)=$item=~/^(\w+)=(.*?)$/;

        next if ($content=~/^off$/);
        
        $category=~s/^\s+//;
        $category=~s/\s+$//;
        
        if (exists $convconfig->{pers}{$category} && $content){
            my $split_regexp=$convconfig->{category_split_chars}{$category};

            my @parts = ();
            if ($split_regexp){
                @parts = split(/$split_regexp/,$content);
            }
            else {
                push @parts, $content;
            }

            foreach my $part (@parts){
                $part=~s/\[\[([^|\]]+?)]]/$1/g;

                $part=konv($part);

                my $autidn=get_autidn($part);
                
                if ($autidn > 0){
                    print AUT "0000:$autidn\n";
                    print AUT "0001:$part\n";
                    print AUT "9999:\n";
                }
                else {
                    $autidn=(-1)*$autidn;
                }
                
                print TIT $convconfig->{pers}{$category}."IDN: $autidn\n";
            }
        }
        # Autoren abarbeiten Ende

        if (exists $convconfig->{title}{$category} && $content){
            my $split_regexp=$convconfig->{category_split_chars}{$category};
            
            my @parts = ();
            if ($split_regexp){
                @parts = split(/$split_regexp/,$content);
            }
            else {
                push @parts, $content;
            }
            
            foreach my $part (@parts){
                # Formatierungen entfernen der Form {{center|xxx}}
                $part=~s/\{\{[^|}]+?\|(.+?)}}/$1/g;
                
                # Sonst bei internen Links nur den Linkbezeichner nehmen    
                # zuerst Commons
                $part=~s/\[\[:?commons:([^|\[\]]+?)]]/<a href="$commons_baseurl$1" class="ext" target="_blank">$1<\/a>/gi;
                # dann den Rest
                $part=~s/\[\[([^|\]]+?)]]/<a href="$baseurl$1" class="ext" target="_blank">$1<\/a>/g;

                # Externe Links werden in den Text via HTML integriert
                $part=~s/\[(http\S+)\s+(.*?)\]/<a href="$1" class="ext" target="_blank">$2<\/a>/g;

                $part=konv($part);

                print TIT $convconfig->{title}{$category}.$part."\n";
            }
        }


    }

    print TIT "0662:".$convconfig->{baseurl}."$titel\n";
    
    print TIT "9999:\n";
    
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

sub get_notidn {
    my ($notans)=@_;
    
    my $notdubidx=1;
    my $notdubidn=0;
    
    while ($notdubidx <= $#notdubbuf){
        if ($notans eq $notdubbuf[$notdubidx]){
            $notdubidn=(-1)*$notdubidx;      
        }
        $notdubidx++;
    }
    if (!$notdubidn){
        $notdubbuf[$notdubidx]=$notans;
        $notdubidn=$notdubidx;
    }
    return $notdubidn;
}

sub konv {
    my ($content)=@_;

    $content=~s/^\s+//;
    $content=~s/\s+$//;


#    $content=~s/\&/&amp;/g;
    
#    $content=~s/>/&gt;/g;
#    $content=~s/</&lt;/g;
#    $content=~s/\[\[//g;
#    $content=~s/]]//g;


    return $content;
}
