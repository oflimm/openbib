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

use strict;
use warnings;

use Encode 'decode';
use Getopt::Long;
use XML::Twig;
use YAML::Syck;

use OpenBib::Config;

our (@autdubbuf,@kordubbuf,@swtdubbuf,@notdubbuf,$mexidn,$pers_templatename,$title_templatename,$wiki_category);
our ($autdublastidx,$kordublastidx,$notdublastidx,$swtdublastidx,$gfdltext,$pdtext);

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

$pers_templatename  = $convconfig->{'pers_templatename'};
$title_templatename = $convconfig->{'title_templatename'};
$wiki_category      = $convconfig->{'wiki_category'};

$gfdltext           = $convconfig->{'GFDL-Text'};
$pdtext             = $convconfig->{'PD-Text'};

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

my $twigaut= XML::Twig->new(
    TwigHandlers => {
        "/mediawiki/page" => \&parse_autset
    }
) if ($pers_templatename);

my $twigtit= XML::Twig->new(
    TwigHandlers => {
        "/mediawiki/page" => \&parse_titset
    }
) if ($title_templatename);


if ($pers_templatename){
    print STDERR "### Bearbeite Personendaten\n";
    $twigaut->parsefile($inputfile);
}

if ($title_templatename){
    print STDERR "### Bearbeite Titeldaten\n";
    $twigtit->parsefile($inputfile);
}

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);
close(MEX);

sub parse_autset {
    my($t, $autset)= @_;

    my $id          = $autset->first_child($convconfig->{uniqueidfield})->text();

    my $titel       = $autset->first_child("title")->text();

    my ($text)      = $autset->find_nodes("revision/text");

    my $textinhalt  = $text->text();

    # Doppeleintraege, wie z.B. Gebrueder Grimm koennen strukturell nicht verarbeitet werden.
    return if ($textinhalt =~m/\{\{$pers_templatename.*?\|\s*.*?\{\{$pers_templatename.*?\|/sm);
    
    my ($personendaten) = $textinhalt =~m/\{\{$pers_templatename.*?\|\s*(.*?)^}}/sm;

    return if (!$personendaten);

    my $baseurl         = $convconfig->{baseurl};
    my $commons_baseurl = $convconfig->{commons_baseurl};

    my $autidn=get_autidn($titel);

    $personendaten=~s/\n//sg;

    # Referenzen entfernen
    $personendaten=~s/<ref>.*?<\/ref>/$1/g;

    if ($autidn > 0){
        print AUT "0000:$autidn\n";
        print AUT "0001:$titel\n";

        # Bei internen Links nur Alternativbezeichner uebriglassen
        # zuerst Commons
        $personendaten=~s/\[\[:?commons:([^|\[\]]+?)\|(.+?)]]/<a href="$commons_baseurl$1" class="ext" target="_blank">$2<\/a>/gi;
        # dann den Rest
        $personendaten=~s/\[\[([^|\]]+?)\|(.+?)]]/<a href="$baseurl$1" class="ext" target="_blank">$2<\/a>/g;

        foreach my $item (split("\\|",$personendaten)){
            if ($item !~/=/){
                next;
            }

            my ($category,$content)=$item=~/^\s*(\w+)\s*=\s*(.*?)\s*$/;

            next if (!$content);
            next if ($content=~/^\s*off\s*$/i);
            
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
                    
                    if (!$convconfig->{no_wiki_filter}{$category}){
                        # Formatierungen entfernen der Form {{center|xxx}}
                        $part=~s/\{\{[^|}]+?\|(.+?)}}/$1/g;
                        
                        # Sonst bei internen Links nur den Linkbezeichner nehmen    
                        # zuerst Commons
                        $part=~s/\[\[:?commons:([^|\[\]]+?)]]/<a href="$commons_baseurl$1" class="ext" target="_blank">$1<\/a>/gi;
                        # dann den Rest
                        $part=~s/\[\[([^|\]]+?)]]/<a href="$baseurl$1" class="ext" target="_blank">$1<\/a>/g;
                        
                        # Externe Links werden in den Text via HTML integriert
                        $part=~s/\[(http\S+)\s+(.*?)\]/<a href="$1" class="ext" target="_blank">$2<\/a>/g;
                    }
                    
                    $part=konv($part);
                    
                    print AUT $convconfig->{pers}{$category}.$part."\n";
                }
            }
        }

        print AUT "9999:\n";
    }

    # Release memory of processed tree
    # up to here
    $t->purge();
}

sub parse_titset {
    my($t, $titset)= @_;

    my $id          = $titset->first_child($convconfig->{uniqueidfield})->text();

    my $titel       = $titset->first_child("title")->text();

    my ($text)      = $titset->find_nodes("revision/text");

    my $textinhalt  = $text->text();
    
    my ($textdaten) = $textinhalt =~m/\{\{$title_templatename.*?\|\s*(.*?)^}}/sm;

    return if (!$textdaten);

    my $baseurl         = $convconfig->{baseurl};
    my $commons_baseurl = $convconfig->{commons_baseurl};
    
    print TIT "0000:$id\n";

    # Zuerst zeilenweise bereinigen zum besseren Matchen und einfacherer Regexp
    my @textdatenset = split ("\n",$textdaten);

    foreach my $line (@textdatenset){
        # Bei internen Links nur (Alternativ-)bezeichner uebriglassen, wenn die entsprechenden Kategorien vom Filtern ausgeschlossen sind
        foreach my $category (keys %{$convconfig->{'no_wiki_filter'}}){
            if ($line=~/$category\s*=/){
                $line=~s/\[\[([^|\]]+?)\|(.+?)]]/$2/g;
                $line=~s/\[\[([^|\]]+?)]]/$1/g;
            }            
        }
    }

    $textdaten = join("\n",@textdatenset);
    
    $textdaten=~s/\n//sg;

    # Referenzen entfernen
    $textdaten=~s/<ref>.*?<\/ref>/$1/g;

    # GBS-Links einfuegen
    $textdaten=~s/\{\{GBS\|([^|]+)\|US\|([^|]+)}}/<a href="http:\/\/books.google.com\/books?id=$1&pg=$2" class="ext" target="_blank">Google Books USA<\/a>/gi;
    $textdaten=~s/\{\{GBS\|([^|]+)}}/<a href="http:\/\/books.google.com\/books?id=$1" class="ext" target="_blank">Google Books<\/a>/gi;
    # Sonst Formatierungen entfernen der Form {{center|xxx}}
    $textdaten=~s/\{\{[^|}]+?\|(.+?)}}/$1/g;

    # Bei internen Links den noch nicht bereinigten Rest absolut verlinken
    # zuerst Commons
    $textdaten=~s/\[\[:?commons:([^|\[\]]+?)\|(.+?)]]/<a href="$commons_baseurl$1" class="ext" target="_blank">$2<\/a>/gi;
    # dann den Rest
    $textdaten=~s/\[\[([^|\]]+?)\|(.+?)]]/<a href="$baseurl$1" class="ext" target="_blank">$2<\/a>/g;

    foreach my $item (split("\\|",$textdaten)){
        if ($item !~/=/){
            next;
        }

        my ($category,$content)=$item=~/^\s*(\w+)\s*=\s*(.*?)\s*$/;

        next if (!$content);
        next if ($content=~/^\s*off\s*$/i);
        
        $category=~s/^\s+//;
        $category=~s/\s+$//;

        # Autoren abarbeiten Anfang
        if (exists $convconfig->{perstit}{$category} && $content){
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
                
                print TIT $convconfig->{perstit}{$category}."IDN: $autidn\n";
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

                if (!$convconfig->{no_wiki_filter}{$category}){
                    # Sonst bei internen Links nur den Linkbezeichner nehmen    
                    # zuerst Commons
                    $part=~s/\[\[:?commons:([^|\[\]]+?)]]/<a href="$commons_baseurl$1" class="ext" target="_blank">$1<\/a>/gi;
                    # dann den Rest
                    $part=~s/\[\[([^|\]]+?)]]/<a href="$baseurl$1" class="ext" target="_blank">$1<\/a>/g;
                    
                    # Externe Links werden in den Text via HTML integriert
                    $part=~s/\[(http\S+)\s+(.*?)\]/<a href="$1" class="ext" target="_blank">$2<\/a>/g;
                }

                # Wenn im Titel nichts vernuenftiges steht, dann nehmen den Titel des Artikels (wg. engl. Wikisource mit [[../]])                
                if ($convconfig->{title}{$category} =~/^0331/ && $part !~ /\w+/){
                    $part=$titel;
                }

                $part=konv($part);

                print TIT $convconfig->{title}{$category}.$part."\n";
            }
        }


    }

    # Kategorien als Schlagworte abarbeiten Anfang
    foreach my $schlagwort ( $textinhalt =~m/\[\[$wiki_category:(.+?)]]/g){
        $schlagwort=~s/\|.+?$//;
        $schlagwort=konv($schlagwort);

        my $swtidn=get_swtidn($schlagwort);
        
        if ($swtidn > 0){
            print SWT "0000:$swtidn\n";
            print SWT "0001:$schlagwort\n";
            print SWT "9999:\n";
        }
        else {
            $swtidn=(-1)*$swtidn;
        }
        
        print TIT "0710:IDN: $swtidn\n";
    }
    # Kategorien als Schlagworte abarbeiten Ende

    print TIT "0662:".$convconfig->{baseurl}."$titel\n";
    
    print TIT "9999:\n";
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}
                                   
sub get_autidn {
    my ($autans)=@_;
    
    my $autdubidx=1;
    my $autdubidn=0;
                                   
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
    my ($swtans)=@_;
    
    my $swtdubidx=1;
    my $swtdubidn=0;
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
    my ($korans)=@_;
    
    my $kordubidx=1;
    my $kordubidn=0;
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

    # Text-Makros ersetzen
    $content=~s/\{\{GFDL-Text}}/$gfdltext/g;
    $content=~s/\{\{PD-Text}}/$pdtext/g;

    $content=~s/\{\{[^|}]+?}}//g;

#    $content=~s/\&/&amp;/g;
    
#    $content=~s/>/&gt;/g;
#    $content=~s/</&lt;/g;
#    $content=~s/\[\[//g;
#    $content=~s/]]//g;


    return $content;
}
