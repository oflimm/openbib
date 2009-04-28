#!/usr/bin/perl

#####################################################################
#
#  gutenberg2meta.pl
#
#  Konvertierung des Gutenberg RDF-Formates in das OpenBib
#  Einlade-Metaformat
#
#  Dieses File ist (C) 2009 Oliver Flimm <flimm@openbib.org>
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
use XML::LibXML;
use YAML::Syck;

use OpenBib::Config;

our (@autdubbuf,@kordubbuf,@swtdubbuf,@notdubbuf,$mexidn);
our ($autdublastidx,$kordublastidx,$swtdublastidx)=(1,1,1);

@autdubbuf = ();
@kordubbuf = ();
@swtdubbuf = ();
@notdubbuf = ();
$mexidn  =  1;

my ($inputfile,$configfile);

&GetOptions(
	    "inputfile=s"          => \$inputfile,
            "configfile=s"         => \$configfile,
	    );

if (!$inputfile && !$configfile){
    print << "HELP";
gutenberg2meta.pl - Aufrufsyntax

    gutenberg2meta.pl --inputfile=xxx
HELP
exit;
}

open (TIT,     ">:utf8","unload.TIT");
open (AUT,     ">:utf8","unload.PER");
open (KOR,     ">:utf8","unload.KOE");
open (NOTATION,">:utf8","unload.SYS");
open (SWT,     ">:utf8","unload.SWD");
open (MEX,     ">:utf8","unload.MEX");

my $parser = XML::LibXML->new();
$parser->keep_blanks(0);

my $tree = $parser->parse_file($inputfile);
my $root = $tree->getDocumentElement;

foreach my $etext_node ($root->findnodes('/rdf:RDF/pgterms:etext')){
 my $etext_number = $etext_node->getAttribute ('ID');
   $etext_number =~ s/^etext//;

   print TIT "0000:$etext_number\n";

   # Neuaufnahmedatum
   foreach my $item ($etext_node->findnodes ('dc:created//text()')) {
        my ($year,$month,$day)=split("-",$item->textContent);
        print TIT "0002:$day.$month.$year\n";
   }

   # Sprache
   foreach my $item ($etext_node->findnodes ('dc:language//text()')) {
       print TIT "0015:".Encode::encode_utf8($item->textContent)."\n";
   }

   # Verfasser, Personen
   # Einzelner Verfasser
   foreach my $item ($etext_node->findnodes ('dc:creator//text()')) {
       my $content = $item->textContent;
       my $autidn  = get_autidn($content);
                    
       if ($autidn > 0){
           print AUT "0000:$autidn\n";
           print AUT "0001:$content\n";
           print AUT "9999:\n";
       }
       else {
           $autidn=(-1)*$autidn;
       }
                    
       print TIT "0100:IDN: $autidn\n";
   }

   # Verfasser, Personen
   foreach my $item ($etext_node->findnodes ('dc:contributor//text()')) {
       my $content = $item->textContent;
       my $autidn  = get_autidn($content);
                    
       if ($autidn > 0){
           print AUT "0000:$autidn\n";
           print AUT "0001:$content\n";
           print AUT "9999:\n";
       }
       else {
           $autidn=(-1)*$autidn;
       }

       print TIT "0101:IDN: $autidn\n";
   }

   # Titel
   foreach my $item ($etext_node->findnodes ('dc:title//text()')) {
       my $content = Encode::encode_utf8($item->textContent);
       if (my ($hst,$zusatz)=$content=~m/^(.+?)\n(.*)/ms){
           $zusatz=~s/\n/ /msg;
           print TIT "0331:$hst\n";
           print TIT "0335:$zusatz\n";
       }
       else {
           print TIT "0331:$content\n";
       }

   }

   # Verlag
   print TIT "0412:Project Gutenberg\n";

   # E-Text-URL
   print TIT "0662:http://www.gutenberg.org/etext/$etext_number\n";

   # Beschreibung
   foreach my $item ($etext_node->findnodes ('dc:description//text()')) {
       my $content = Encode::encode_utf8($item->textContent);
       print TIT "0501:$content\n";
   }

   # Schlagworte
   foreach my $item ($etext_node->findnodes ('dc:subject/dcterms:LCSH//text()')) {
       my $content = $item->textContent;
       my $swtidn  = get_swtidn($content);
                    
       if ($swtidn > 0){
           print SWT "0000:$swtidn\n";
           print SWT "0001:$content\n";
           print SWT "9999:\n";
       }
       else {
           $swtidn=(-1)*$swtidn;
       }

       print TIT "0710:IDN: $swtidn\n";
   }

   print TIT "9999:\n";
}

close(TIT);
close(AUT);
close(KOR);
close(NOTATION);
close(SWT);
close(MEX);
                                   
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

#    $content=~s/\&/&amp;/g;
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    return $content;
}
