#!/usr/bin/perl

#####################################################################
#
#  wikisource2meta.pl
#
#  Konvertierung der Textdaten des Wikisource Formates in das OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2008-2012 Oliver Flimm <flimm@openbib.org>
#
#                      und
#
#                      2008      Jakob Voss <jakob.voss@gbv.de>
#                                (Ursprungscode der Verarbeitung von METS/MODS)
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
use JSON::XS;
use LWP::Simple;
use Log::Log4perl qw(get_logger :levels);
use XML::Twig;
use JSON::XS;
use YAML::Syck;

use OpenBib::Conv::Common::Util;

our (%metsbuf,$pers_templatename,$title_templatename,$index_prefix,$wiki_category,$gfdltext,$pdtext);
our ($baseurl,$commons_baseurl,$metsfile,$owner,$ownersiteurl,$ownerlogo);

my ($inputfile,$configfile,$logfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
	    "metsfile=s"           => \$metsfile,
            "configfile=s"         => \$configfile,
            "logfile=s"            => \$logfile,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
wikisource2meta.pl - Aufrufsyntax

    wikisource2meta.pl --inputfile=xxx
HELP
exit;
}

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

if ($metsfile){
  my $mets=LoadFile($metsfile);
  %metsbuf=%{$mets};
}

$baseurl            = $convconfig->{baseurl};
$commons_baseurl    = $convconfig->{commons_baseurl};

$pers_templatename  = $convconfig->{'pers_templatename'};
$title_templatename = $convconfig->{'title_templatename'};
$index_prefix       = $convconfig->{'index_prefix'};
$wiki_category      = $convconfig->{'wiki_category'};
$owner              = $convconfig->{'owner'};
$ownerlogo          = $convconfig->{'ownerLogo'};
$ownersiteurl       = $convconfig->{'ownerSiteURL'};

$gfdltext           = $convconfig->{'GFDL-Text'};
$pdtext             = $convconfig->{'PD-Text'};

$logfile=($logfile)?$logfile:"/var/log/openbib/wikisource2meta.log";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=DEBUG, LOGFILE, Screen
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

open (TIT,     ">:utf8","meta.title");
open (AUT,     ">:utf8","meta.person");
open (KOR,     ">:utf8","meta.corporatebody");
open (NOTATION,">:utf8","meta.classification");
open (SWT,     ">:utf8","meta.subject");
open (MEX,     ">:utf8","meta.holding");

my $twig1stpass= XML::Twig->new(
    TwigHandlers => {
        "/mediawiki/page" => \&parse_1stpass
    }
) if ($pers_templatename || $index_prefix);

my $twigtit= XML::Twig->new(
    TwigHandlers => {
        "/mediawiki/page" => \&parse_titset
    }
) if ($title_templatename);


if ($pers_templatename || $index_prefix){
    $logger->info("### Erster Durchgang Personendaten und/oder METS aus Index-Seiten generieren");
    $twig1stpass->parsefile($inputfile);
}

if ($title_templatename){
    $logger->info("### Bearbeite Titeldaten");
    $twigtit->parsefile($inputfile);
}

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);
close(MEX);

DumpFile("wikisource-mets-de.yml",\%metsbuf) unless ($metsfile);

sub parse_1stpass {
    my($t, $article)= @_;

    my $logger = get_logger();    

    my $id          = $article->first_child($convconfig->{uniqueidfield})->text();

    my $titel       = $article->first_child("title")->text();

    my ($text)      = $article->find_nodes("revision/text");

    my $textinhalt  = $text->text();

    if ($index_prefix && $titel=~/^$index_prefix/ && !$metsfile){
        generate_mets({ titel => $titel, article => $textinhalt});
    }
    elsif ($pers_templatename){
        generate_aut({ id => $id, titel => $titel, article => $textinhalt});
    }

    # Release memory of processed tree
    # up to here
    $t->purge();
}

sub parse_titset {
    my($t, $titset)= @_;

    my $logger = get_logger();
    
    my $id          = $titset->first_child($convconfig->{uniqueidfield})->text();

    my $titel       = $titset->first_child("title")->text();

    my ($text)      = $titset->find_nodes("revision/text");

    my $textinhalt  = $text->text();
    
    my ($textdaten) = $textinhalt =~m/\{\{$title_templatename.*?\|\s*(.*?)^}}/sm;

    return if (!$textdaten);

    my $title_ref = {};

    $title_ref->{id} = $id;

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

    my $indexseite = "";
    
    foreach my $item (split("\\|",$textdaten)){
        if ($item !~/=/){
            next;
        }

        my ($category,$content)=$item=~/^\s*(\w+)\s*=\s*(.*?)\s*$/;

        next if (!$content);
        next if ($content=~/^\s*off\s*$/i);
        
        $category=~s/^\s+//;
        $category=~s/\s+$//;

        if ($category=~/INDEXSEITE/){
            $indexseite = $content;
        }        

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

            my $mult=1;
            foreach my $part (@parts){
                $part=~s/\[\[([^|\]]+?)]]/$1/g;

                $part=konv($part);

                my ($person_id,$new)=OpenBib::Conv::Common::Util::get_person_id($part);
                
                if ($new){
                    my $item_ref = {};
                    $item_ref->{id} = $person_id;
                    push @{$item_ref->{'0800'}}, {
                        mult     => 1,
                        subfield => '',
                        content  => $part,
                    };
                    
                    print AUT encode_json $item_ref, "\n";
                }

                my $new_category = $convconfig->{perstit}{$category};

                push @{$title_ref->{$new_category}}, {
                    mult       => $mult,
                    subfield   => '',
                    id         => $person_id,
                    supplement => '',
                };
                
                $mult++;
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

            my $mult=1;
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

                my $new_category = $convconfig->{title}{$category};

                push @{$title_ref->{$new_category}}, {
                    mult       => $mult,
                    subfield   => '',
                    content    => $part,
                };
                
                $mult++;
            }
        }

        
    }

    # Kategorien als Schlagworte abarbeiten Anfang
    my $mult=1;
    foreach my $schlagwort ( $textinhalt =~m/\[\[$wiki_category:(.+?)]]/g){
        $schlagwort=~s/\|.+?$//;
        $schlagwort=konv($schlagwort);

        my ($subject_id,$new)=OpenBib::Conv::Common::Util::get_subject_id($schlagwort);
        
        if ($new){
            my $item_ref = {};
            $item_ref->{id} = $subject_id;
            push @{$item_ref->{'0800'}}, {
                mult     => 1,
                subfield => '',
                content  => $schlagwort,
            };
            
            print SWT encode_json $item_ref, "\n";
        }

        push @{$title_ref->{'0710'}}, {
            mult       => $mult,
            subfield   => '',
            id         => $subject_id,
            supplement => '',
        };
        
        $mult++;
    }
    # Kategorien als Schlagworte abarbeiten Ende

    push @{$title_ref->{'0662'}}, {
        mult     => 1,
        subfield => '',
        content  => $convconfig->{baseurl}.$titel,
    };

    if ($indexseite){
        push @{$title_ref->{'4120'}}, {
            mult     => 1,
            subfield => '',
            content  => $convconfig->{baseurl}.$convconfig->{index_prefix}.$indexseite,
        };
    }
    
    my %mets = (exists $metsbuf{$indexseite})?%{$metsbuf{$indexseite}}:
        (exists $metsbuf{$titel})?%{$metsbuf{$titel}}:();

    if ($mets{autor}){
        push @{$title_ref->{'6000'}}, {
            mult     => 1,
            subfield => '',
            content  => $mets{author},
        };
    }
    if ($mets{titel}){
        push @{$title_ref->{'6001'}}, {
            mult     => 1,
            subfield => '',
            content  => $mets{titel},
        };
    }   
    if ($mets{year}){
        push @{$title_ref->{'6002'}}, {
            mult     => 1,
            subfield => '',
            content  => $mets{year},
        };
    }   
    if ($mets{location}){
        push @{$title_ref->{'6003'}}, {
            mult     => 1,
            subfield => '',
            content  => $mets{location},
        };
    }   

    if ($owner){
        push @{$title_ref->{'6040'}}, {
            mult     => 1,
            subfield => '',
            content  => $owner,
        };
    }   
    if ($ownerlogo){
        push @{$title_ref->{'6041'}}, {
            mult     => 1,
            subfield => '',
            content  => $ownerlogo,
        };
    }   
    if ($ownersiteurl){
        push @{$title_ref->{'6042'}}, {
            mult     => 1,
            subfield => '',
            content  => $ownersiteurl,
        };
    }

    my $i = 1;

    foreach my $item_ref (@{$mets{items}}){
        push @{$title_ref->{'6050'}}, {
            mult     => $i,
            subfield => '',
            content  => $item_ref->{label},
        } if (exists $item_ref->{label});

        push @{$title_ref->{'6051'}}, {
            mult     => $i,
            subfield => '',
            content  => $item_ref->{url},
        } if (exists $item_ref->{url});
        
        push @{$title_ref->{'6052'}}, {
            mult     => $i,
            subfield => '',
            content  => $item_ref->{thumburl},
        } if (exists $item_ref->{thumburl});
        
        push @{$title_ref->{'6053'}}, {
            mult     => $i,
            subfield => '',
            content  => $item_ref->{page},
        } if (exists $item_ref->{page});

        $i++;
    }   

    # Jeder Titel ist Digital
    push @{$title_ref->{'0800'}}, {
        mult     => 1,
        subfield => '',
        content  => 'Digital',
    };

    print TIT encode_json $title_ref, "\n";
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}

sub generate_aut {
    my ($arg_ref)=@_;

    # Set defaults
    my $id         = exists $arg_ref->{id}
        ? $arg_ref->{id}             : undef;
    my $titel      = exists $arg_ref->{titel}
        ? $arg_ref->{titel}          : undef;
    my $textinhalt = exists $arg_ref->{article}
        ? $arg_ref->{article}        : undef;

    my $logger = get_logger();
    
    # Doppeleintraege, wie z.B. Gebrueder Grimm koennen strukturell nicht verarbeitet werden.
    return if ($textinhalt =~m/\{\{$pers_templatename.*?\|\s*.*?\{\{$pers_templatename.*?\|/sm);
    
    my ($personendaten) = $textinhalt =~m/\{\{$pers_templatename.*?\|\s*(.*?)^}}/sm;
    
    return if (!$personendaten);
    
    my ($person_id,$new)=OpenBib::Conv::Common::Util::get_person_id($titel);
    
    $personendaten=~s/\n//sg;
    
    # Referenzen entfernen
    $personendaten=~s/<ref>.*?<\/ref>/$1/g;
    
    if ($new){
        my $item_ref = {};
        $item_ref->{id} = $person_id;
        push @{$item_ref->{'0800'}}, {
            mult     => 1,
            subfield => '',
            content  => $titel,
        };
        
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

                my $mult=1;
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

                    push @{$item_ref->{$convconfig->{pers}{$category}}}, {
                        mult     => $mult,
                        subfield => '',
                        content  => $part,
                    };
                }
            }
        }

        print AUT encode_json $item_ref, "\n";
    }    
}

sub generate_mets {
    my ($arg_ref)=@_;

    my $logger = get_logger();
    
    # Set defaults
    my $titel      = exists $arg_ref->{titel}
        ? $arg_ref->{titel}          : undef;
    my $textinhalt = exists $arg_ref->{article}
        ? $arg_ref->{article}        : undef;

    my ($ursprungstitel) = $titel =~ /^$index_prefix(.+)$/;

    $logger->debug("Bearbeite Index-Seite zu: $ursprungstitel");

    my ($author)     = $textinhalt =~/^\|AUTOR=(.*?)$/ms;
    my ($title)      = $textinhalt =~/^\|TITEL=(.*?)$/ms;
    my ($year)       = $textinhalt =~/^\|JAHR=(.*?)$/ms;
    my ($location)   = $textinhalt =~/^\|LOCATION=(.*?)$/ms;

    $logger->debug("A:$author;T:$title;Y:$year;L:$location");
    
    my @pageinfos  = $textinhalt =~/\[\[Seite:([^|]+?\|.*?)]]/sg;

    $logger->debug("Textinhalt: ".$textinhalt);
    $logger->debug("Pageinfos: ".join(";",@pageinfos));

    my @images = ();

    foreach my $pageinfo (@pageinfos){
        my ($page,$label) = $pageinfo =~/^(.+?)\|(.*?)$/;

        if ($page=~/djvu/i){
            $logger->debug("Ignoring DJVU-File");
            return;
        }

        push @images, {
            label => $label,
            page  => $page
        };

    }

    my $iiurlwidth = 1000;
    
    my @titles = ();
    for (my $id=0; $id<@images; $id++) {
        my $title = "Image:" . $images[$id]->{page};
        
        push @titles, $title;
    }
    
    return unless (@titles);
    
    my $apibaseurl = 'http://de.wikisource.org/w/api.php?format=json&action=query&prop=imageinfo&iiprop=url&iiurlwidth=' . $iiurlwidth
        . '&titles=';
    
    my %imgurls = ();
    my %mapping = ();
    
    my $imagecounter = 0;
    # get around Wikipedia API restrictions
    while (@titles){
        my @parts = splice(@titles,0,50);
        my $url = $apibaseurl.join('|',@parts);
        $logger->debug("Getting JSON from $url");
        
        my $json = get($url);
        
        return unless ($json);
        
        $logger->debug("JSON: $json");
        
        my $obj = decode_json $json; 
        
        foreach my $n (@{ $obj->{query}->{normalized} }) {
            $mapping{$n->{from}}=$n->{to};
        }
        
        my %pages = %{ $obj->{query}->{pages} };
        foreach my $p (values %pages) {
            next unless (exists $p->{imageinfo}); # djvu-Files haben keine imageinfo
            my %imageinfo = %{ shift @{ $p->{imageinfo} } };
            $imgurls{ $p->{title} }{thumburl} =  $imageinfo{thumburl};
            $imgurls{ $p->{title} }{url}      =  $imageinfo{url};
            $imagecounter++;
        }
        
        $logger->debug("Extracted " . (keys %imgurls) . " image URLs");
        
        
        sleep 1;
    }

    # Anreicherung mit den gefundenen Bild-URLs
    for(my $id=0; $id<@images; $id++) {
        my %img = %{ $images[$id] };
            
        my $title = "";
            
        if (exists $mapping{"Image:".$img{page}}){
            $title = $mapping{"Image:".$img{page}};
        }
        else {
            $title = "Bild:" . $img{page};
        }
            
        $images[$id]->{thumburl} = $imgurls{$title}{thumburl};
        $images[$id]->{url}      = $imgurls{$title}{url};

        $logger->debug("Missing Title: $title") unless defined $imgurls{$title}{thumburl};

    }

    if (!$imagecounter){
        $logger->error("Keine Bilder vorhanden");
        return;
    }       

    my $thisitem_ref = {
        author   => konv_index($author),
        title    => konv_index($title),
        year     => konv_index($year),
        location => konv_index($location),
        items    => \@images,
    };

    $logger->debug(Dump($thisitem_ref));
    
    $metsbuf{$ursprungstitel} = $thisitem_ref;

    return;
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

sub konv_index {
    my ($content)=@_;

    # Referenzen entfernen
    $content=~s/<ref>.*?<\/ref>/$1/g;

    # GBS-Links einfuegen
    $content=~s/\{\{GBS\|([^|]+)\|US\|([^|]+)}}/<a href="http:\/\/books.google.com\/books?id=$1&pg=$2" class="ext" target="_blank">Google Books USA<\/a>/gi;
    $content=~s/\{\{GBS\|([^|]+)}}/<a href="http:\/\/books.google.com\/books?id=$1" class="ext" target="_blank">Google Books<\/a>/gi;
    # Sonst Formatierungen entfernen der Form {{center|xxx}}
    $content=~s/\{\{[^|}]+?\|(.+?)}}/$1/g;

    # Bei internen Links den noch nicht bereinigten Rest absolut verlinken
    # zuerst Commons
    $content=~s/\[\[:?commons:([^|\[\]]+?)\|(.+?)]]/<a href="$commons_baseurl$1" class="ext" target="_blank">$2<\/a>/gi;
    # dann den Rest
    $content=~s/\[\[([^|\]]+?)\|(.+?)]]/<a href="$baseurl$1" class="ext" target="_blank">$2<\/a>/g;

    # Externe Links werden in den Text via HTML integriert
    $content=~s/\[(http\S+)\s+(.*?)\]/<a href="$1" class="ext" target="_blank">$2<\/a>/g;
    $content=~s/\[\[(.+?)]]/$1/g;

    return $content;
}
