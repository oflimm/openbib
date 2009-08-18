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
#                      2009      Jakob Voss <jakob.voss@gbv.de> (Ursprung: METS/MODS)
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
our ($baseurl,$commons_baseurl);

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

sub parse_1stpass {
    my($t, $article)= @_;

    my $logger = get_logger();    

    my $id          = $article->first_child($convconfig->{uniqueidfield})->text();

    my $titel       = $article->first_child("title")->text();

    my ($text)      = $article->find_nodes("revision/text");

    my $textinhalt  = $text->text();

    if ($index_prefix && $titel=~/^$index_prefix/){
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

    if (exists $metsbuf{$titel}){
        $logger->debug("METS-Daten: $metsbuf{$titel}");
        print TIT "6000:$metsbuf{$titel}\n";
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
    my $id         = exists $arg_ref->{id}
        ? $arg_ref->{id}             : undef;
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
        
    my $dmdsecid = "md123";
    my $logmapid = "log123";
    my $amdsecid = "amd123";
    my $physid   = "phys-123";
    my $rightsid = "rights123";

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
            $imgurls{ $p->{title} } =  $imageinfo{thumburl};
            $imagecounter++;
        }
        
        $logger->debug("Extracted " . (keys %imgurls) . " image URLs");
        
        
        sleep 1;
    }

    for(my $id=0; $id<@images; $id++) {
        my %img = %{ $images[$id] };
            
        my $title = "";
            
        if (exists $mapping{"Image:".$img{page}}){
            $title = $mapping{"Image:".$img{page}};
        }
        else {
            $title = "Bild:" . $img{page};
        }
            
        $logger->debug("Missing Title: $title") unless defined $imgurls{$title};
        $images[$id]->{url} = $imgurls{$title};
    }

    if (!$imagecounter){
        $logger->error("Keine Bilder vorhanden");
        return;
    }       
        
    my $mets = << "XMLDATA";
<mets:mets xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:mets="http://www.loc.gov/METS/" xsi:schemaLocation="http://www.loc.gov/METS/ http://www.loc.gov/mets/mets.xsd">
    <mets:dmdSec ID="$dmdsecid">
        <mets:mdWrap MIMETYPE="text/xml" MDTYPE="MODS">
            <mets:xmlData>
                <mods xmlns="http://www.loc.gov/mods/v3" version="3.0" xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-0.xsd">
                    <titleInfo>
                        <title>$title</title>
                    </titleInfo>
                    <name>
                        <displayForm>$author</displayForm>
                    </name>
                    <originInfo>
                        <place>
                            <placeTerm type="text">$location</placeTerm>
                        </place>
                        <dateIssued>$year</dateIssued>
                    </originInfo>
                </mods>
            </mets:xmlData>
        </mets:mdWrap>
    </mets:dmdSec>
    <mets:amdSec ID="$amdsecid">
        <mets:rightsMD ID="$rightsid">
            <mets:mdWrap MIMETYPE="text/xml" MDTYPE="OTHER" OTHERMDTYPE="DVRIGHTS">
                <mets:xmlData>
                    <dv:rights xmlns:dv="http://dfg-viewer.de/">
                        <dv:owner>Wikisource</dv:owner>
                        <dv:ownerLogo>http://upload.wikimedia.org/wikisource/de/b/bc/Wiki.png</dv:ownerLogo>
                        <dv:ownerSiteURL>http://de.wikisource.org/</dv:ownerSiteURL>
                    </dv:rights>
                </mets:xmlData>
            </mets:mdWrap>
        </mets:rightsMD>
        <!-- mets:digiprovMD ID="digiprov94775">
            <mets:mdWrap MIMETYPE="text/xml" MDTYPE="OTHER" OTHERMDTYPE="DVLINKS">
                <mets:xmlData>
                    <dv:links xmlns:dv="http://dfg-viewer.de/">
                        <dv:reference>http://gso.gbv.de/DB=1.28/CMD?ACT=SRCHA&amp;IKT=8002&amp;TRM=1:078985D</dv:reference>
                        <dv:presentation>http://digitale.bibliothek.uni-halle.de/vda/1:078985D</dv:presentation>
                    </dv:links>
                </mets:xmlData>
            </mets:mdWrap>
        </mets:digiprovMD -->
    </mets:amdSec>
XMLDATA
        
    $mets.="<mets:fileSec><mets:fileGrp USE='DEFAULT'>\n";
        
    for(my $id=0; $id<@images; $id++) {
        my %img = %{ $images[$id] };
            
        my $imgurl = $img{url};
        next unless ($imgurl);

        my $filetype = "image/jpeg";

        if ($imgurl =~/\.je?pg$/i){
            $filetype = "image/jpeg";
        }
        elsif ($imgurl =~/\.png$/i){
            $filetype = "image/png";
        }
        elsif ($imgurl =~/\.tiff?$/i){
            $filetype = "image/tiff";
        }
        
        $mets.= "  <mets:file ID=\"img$id\" MIMETYPE=\"$filetype\">\n"; # TODO: mime-type
        $mets.= "   <mets:FLocat LOCTYPE=\"URL\" xlink:href=\"$imgurl\"/>\n";
        $mets.= "  </mets:file>\n";
    }

    $mets.= "</mets:fileGrp></mets:fileSec>\n";


#    $mets.= "<mets:structMap TYPE='LOGICAL'>\n";
#    $mets.= "<mets:div ID='$logmapid' DMDID='$dmdsecid' ADMID='$amdsecid'>\n";
#    $mets.= "<mets:div ID='log0' ORDER='2' TYPE='section' LABEL='Inhalt'/>\n";
#    $mets.= "</mets:div></mets:structMap>\n";

    $mets.= "<mets:structMap TYPE='PHYSICAL'>\n";
    $mets.= " <mets:div ID='$physid' DMDID='$dmdsecid' ADMID='$amdsecid'>\n";
    for (my $id=0; $id<@images; $id++) {
        $mets.= " <mets:div ID=\"phys$id\" ORDER=\"$id\" >\n"
          . "  <mets:fptr FILEID=\"img$id\" /></mets:div>\n";
    }
    $mets.= "  </mets:div>\n";
    $mets.= " </mets:structMap>\n";

    $mets.= " <mets:structLink>\n";
    $mets.= "  <mets:smLink xlink:from='$logmapid' xlink:to='$physid'/>\n";
    $mets.= " </mets:structLink>\n";
    $mets.= "</mets:mets>\n";

    $logger->debug("METS: $mets");

    $mets=~s/\n//sg;
        
    $metsbuf{$ursprungstitel}=$mets;
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
