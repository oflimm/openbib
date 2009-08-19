#!/usr/bin/perl

#####################################################################
#
#  wikisource2meta.pl
#
#  Konvertierung der Textdaten des Wikisource Formates in das OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2008-2009 Oliver Flimm <flimm@openbib.org>
#
#                      und
#
#                      2009      Jakob Voss <jakob.voss@gbv.de>
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
use YAML::Syck;

our (%autbuf,%korbuf,%swtbuf,%notbuf,%metsbuf,$nextautidn,$nextkoridn,$nextnotidn,$nextswtidn);
our ($pers_templatename,$title_templatename,$index_prefix,$wiki_category,$gfdltext,$pdtext);
our ($baseurl,$commons_baseurl,$metsfile);

%autbuf = ();
%korbuf = ();
%swtbuf = ();
%notbuf = ();

$nextautidn=1;
$nextkoridn=1;
$nextnotidn=1;
$nextswtidn=1;

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

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

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
        generate_mets({ id => $id, titel => $titel, article => $textinhalt});
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

        if ($category eq "INDEXSEITE"){
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

            foreach my $part (@parts){
                $part=~s/\[\[([^|\]]+?)]]/$1/g;

                $part=konv($part);

                my $autidn=get_id($part,"aut");
                
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

        my $swtidn=get_id($schlagwort,"swt");        
        
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

    my %mets = (exists $metsbuf{$indexseite})?%{$metsbuf{$indexseite}}:
        (exists $metsbuf{$titel})?%{$metsbuf{$titel}}:();

    if ($mets{autor}){
        print TIT "6000:$mets{author}\n";
    }
    if ($mets{titel}){
        print TIT "6001:$mets{titel}\n";
    }   
    if ($mets{year}){
        print TIT "6002:$mets{year}\n";
    }   
    if ($mets{location}){
        print TIT "6003:$mets{location}\n";
    }   

    my $i = 1;

    foreach my $item_ref (@{$mets{items}}){
        printf TIT "6050.%03d:%s\n",$i,$item_ref->{label} if (exists $item_ref->{label});
        printf TIT "6051.%03d:%s\n",$i,$item_ref->{url} if (exists $item_ref->{url});
        printf TIT "6052.%03d:%s\n",$i,$item_ref->{thumburl} if (exists $item_ref->{thumburl});
        printf TIT "6053.%03d:%s\n",$i,$item_ref->{page} if (exists $item_ref->{page});
        $i++;
    }   

    print TIT "9999:\n";
    
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
    
    my $autidn=get_id($titel,"aut");
    
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

    my ($author, $title, $location, $year);

    my $pagemode = 0;
    my @pagelines = ();

    foreach my $l (split("\n",$textinhalt)) {
        $l =~ s/^\s*//;
        last if $l =~ /^\}\}/;
        
        $pagemode = 0 if ($l =~ /^\|[A-Z]/);
        
        if ($pagemode) {
            push @pagelines, $l;
        }
        elsif ($l =~ /^\|AUTOR=(.*)/) {
            $author = $1;
            $author =~ s/['[\]]//g;
        }
        elsif ($l =~ /^\|TITEL=(.*)/) {
            $title = $1;
            $title =~ s/['[\]]//g;
        }
        elsif ($l =~ /^\|JAHR=(.*)/) {
            $year = $1;
        }
        elsif ($l =~ /^\|ORT=(.*)/) {
            $location = $1;
        }
        elsif ($l =~ /^\|SEITEN=/) {
            $pagemode = 1;
        } else {
            # print "$l\n";
        }
    }
    
    my @images = ();

    foreach my $l (@pagelines) {
        # TODO: Struktur auslesen (Titel, Vorwort, Gliederung...)
        next unless ($l =~ /^\[\[Seite:([^|]+)\|(.*)\]\]/ );
        my ($page, $label) = ($1, $2);
        
        if ($page=~/djvu/i){
            $logger->debug("Ignoring DJVU-File");
            return;
        }
        
        $label =~ s/<\/?[^>]+>//g; # HTML-tags entfernen
        # $page =~ s/ /_/g;

        push @images, {
            label => $label,
            page => $page
        };
    }

    my $iiurlwidth = 1000;
    
    my @titles = ();
    for (my $id=0; $id<@images; $id++) {
        my $title = "Image:" . $images[$id]->{page};
        if ($title=~/djvu/i){
            $logger->debug("Ignoring DJVU-File");
            return;
        }
        
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
        author   => $author,
        title    => $title,
        year     => $year,
        location => $location,
        items    => \@images,
    };

    $logger->debug(Dump($thisitem_ref));
    
    $metsbuf{$ursprungstitel} = $thisitem_ref;

    return;
}

sub get_id {
    my ($content,$type)=@_;

    my $buffer_ref;
    my $nextid_ref;
    
    if    ($type eq "aut"){
        $buffer_ref=\%autbuf;
        $nextid_ref=\$nextautidn;
    }
    elsif ($type eq "kor"){
        $buffer_ref=\%korbuf;
        $nextid_ref=\$nextkoridn;
    }
    elsif ($type eq "swt"){
        $buffer_ref=\%swtbuf;
        $nextid_ref=\$nextswtidn;
    }
    elsif ($type eq "not"){
        $buffer_ref=\%notbuf;
        $nextid_ref=\$nextnotidn;
    }
    
    if (exists $buffer_ref->{$content}){
        return (-1)*$buffer_ref->{$content};
    }
    else {
        $buffer_ref->{$content}=$$nextid_ref;
        $$nextid_ref++;
        return $buffer_ref->{$content};
    }
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
