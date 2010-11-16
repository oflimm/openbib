#!/usr/bin/perl

#####################################################################
#
#  lidos32meta.pl
#
#  Konvertierung von Lidos 3 Daten in das Meta-Format
#
#  Dieses File ist (C) 1999-2007 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module
#####################################################################

use Encode;
use Getopt::Long;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace

&GetOptions(
	    "filename=s"       => \$filename,
	    );

if (!$filename){
    print << "HELP";
lidos32meta.pl - Aufrufsyntax

    lidos32meta.pl --filename=xxx
HELP
exit;
}

$mergecat_ref = {
	       '0100' => 1,
	       '0331' => 1,
	       '0509' => 1,
	       '0590' => 1,
};

# Kategoriemappings

$titcat_ref = {
	       '0089' => 1,
	       '0331' => 1,
	       '0410' => 1,
	       '0412' => 1,
	       '0425' => 1,
	       '0433' => 1,
	       '0434' => 1,
	       '0451' => 1,
	       '0501' => 1,
	       '0509' => 1,
	       '0525' => 1,
	       '0590' => 1,
	       '0800' => 1,
	      };

$autcat_ref = {
	       '0100' => 1,
	       '0101' => 1,
	      };

$korcat_ref = {
	       '0200' => 1,
	       '0201' => 1,
	      };

$notcat_ref = {
	      };

$swtcat_ref = {
	       '0710' => 1,
	      };

$mexcat_ref = {
	       '0014' => 1,
	       '0016' => 1,
               '0005' => 1,               
	      };

$konvtab_ref = {
    'Dokumentennummer:'                        => '0000',
    'Autor:'                                   => '0100', 
    'Band, H.(Zs.) / Tag, Monat (Ztg.):'       => '0089', 
    'Beh�rden, Betriebe, Institutionen:'    => '0200', 
    'Co-Autor:'                                => '0101', 
    'Deskriptoren:'                            => '0710', 
    'Freie Stichworte:'                        => '0710', 
    'Gimm-Standorte:'                          => '0434', 
    'Herausgebende Institution:'               => '0201', 
    'In (Sammelband/Zeitschrift/Zeitung):'     => '0590', 
    'Inventarnummer:'                          => '0005', 
    'Jahr:'                                    => '0425', 
    'Kommentar:'                               => '', 
    'Markierung:'                              => '', 
    'Ort:'                                     => '0410', 
    'Ortsnamen:'                               => '0525', 
    'Personennamen:'                           => '0509', 
    'Reihe:'                                   => '0451', 
    'Seiten:'                                  => '0433', 
    'Signatur-Kommentar:'                      => '0016', 
    'Sprache (D/E/C/F/J/R):'                   => '0015', 
    'Standort/Signatur:'                       => '0014', 
    'Tagesdatum:'                              => '', 
    'Titel:'                                   => '0331', 
    'Typ (M-ono.,A-rtik.,P-eriodik.,Z-eitg.):' => '0800', 
    'Verlag:'                                  => '0412', 
    'Werke:'                                   => '0501', 
    'Zeichen:'                                 => '',
};

# Einlesen und Reorganisieren

print "### Schritt 1: Einlesen und kategorisieren der Ursprungs-Daten\n";

open(DAT,"$filename");

my $encoding = q{ # 
		 [\x00-\xA0]                                  # ASCII
		 | [\xA1-\xF7][\xA1-\xFE]                     # GB2312/EUC-CN
		};

my ($title_ref,$titlelist_ref)=({},[]);

while (<DAT>){
  s/
//;
  if (/^\d+/){ # Neuer-Titel
    push @$titlelist_ref, $title_ref if (exists $title_ref->{'0000'});
    $title_ref = {};
    $category_dst = "";
  }
  elsif (/^\+(.+)$/){
    my $category_src = $1;

    if (exists $konvtab_ref->{$category_src}){
       $category_dst = $konvtab_ref->{$category_src};
    }
  }
  elsif (/^-(.+)/){
    my $content = $1;
    if ($category_dst){

      my $newcontent = "";

      my @chars = $content =~ /$encoding/gosx;  # Pro 1 oder 2-byte Zeichen ein Char
 
      foreach my $char (@chars) {
	if (length($char) == 2) { # 2-byte Zeichen
	  $newcontent .= Encode::decode("euc-cn",$char)." ";
	} 
	else {  # 1-byte Zeichen
	  $newcontent .= Encode::decode("cp437",$char);
	}
      }
    
      if (exists $title_ref->{$category_dst} && exists $mergecat_ref->{$category_dst}){
	$title_ref->{$category_dst}[0].=" $newcontent";
      }
      else {
	push @{$title_ref->{$category_dst}}, $newcontent; 
      }
    }
  }
}

push @$titlelist_ref, $title_ref if (exists $title_ref->{'0000'});

close(DAT);

print "### Schritt 2: Umwandeln und ausgeben in das Meta-Format\n";

my ($autidn,$koridn,$notidn,$swtidn,$mexidn)                     = (1,1,1,1);
my ($autdublastidx,$kordublastidx,$notdublastidx,$swtdublastidx) = (1,1,1,1);

open (TIT,">:utf8","unload.TIT");
open (PER,">:utf8","unload.PER");
open (KOR,">:utf8","unload.KOE");
open (SYS,">:utf8","unload.SYS");
open (SWD,">:utf8","unload.SWD");
open (MEX,">:utf8","unload.MEX");

foreach my $title_ref (@$titlelist_ref){
   print TIT "0000:".$title_ref->{'0000'}[0]."\n";

   foreach my $category (sort keys %$title_ref){
      if (exists $titcat_ref->{$category}){
         my $mult = 1;
         foreach my $content (@{$title_ref->{$category}}){       
                printf TIT "%04d.%03d:%s\n",$category,$mult,$content;
                $mult++;
         }
      }
      elsif (exists $autcat_ref->{$category}){
         my $mult = 1;
         foreach my $content (@{$title_ref->{$category}}){       
                my $supplement="";
                if ($content =~/^(.+?) *\/? *(\(.*?$)/){
                   $content    = $1;
                   $supplement = " ; $2";
                }

                $autidn=OpenBib::Conv::Common::Util::get_autidn($content);
                
                if ($autidn > 0){
                    print PER "0000:$autidn\n";
                    print PER "0001:$content\n";
                    print PER "9999:\n";
                }
                else {
                    $autidn=(-1)*$autidn;
                }
                
                printf TIT "%04d.%03d:IDN: %d%s\n",$category,$mult,$autidn,$supplement;
                $mult++;
         }
      }
      elsif (exists $korcat_ref->{$category}){
         my $mult = 1;
         foreach my $content (@{$title_ref->{$category}}){       

                $koridn=OpenBib::Conv::Common::Util::get_koridn($content);
                
                if ($koridn > 0){
                    print KOR "0000:$koridn\n";
                    print KOR "0001:$content\n";
                    print KOR "9999:\n";
                }
                else {
                    $koridn=(-1)*$koridn;
                }
                
                printf TIT "%04d.%03d:IDN: %d\n",$category,$mult,$koridn;
                $mult++;
         }
      }
      elsif (exists $swtcat_ref->{$category}){
         my $mult = 1;
         foreach my $content (@{$title_ref->{$category}}){       

                $swtidn=OpenBib::Conv::Common::Util::get_swtidn($content);
                
                if ($swtidn > 0){
                    print SWD "0000:$swtidn\n";
                    print SWD "0001:$content\n";
                    print SWD "9999:\n";
                }
                else {
                    $swtidn=(-1)*$swtidn;
                }
                
                printf TIT "%04d.%03d:IDN: %d\n",$category,$mult,$swtidn;
                $mult++;
         }
      }
      elsif (exists $notcat_ref->{$category}){
         my $mult = 1;
         foreach my $content (@{$title_ref->{$category}}){       

                $notidn=OpenBib::Conv::Common::Util::get_notidn($content);
                
                if ($notidn > 0){
                    print SYS "0000:$notidn\n";
                    print SYS "0001:$content\n";
                    print SYS "9999:\n";
                }
                else {
                    $notidn=(-1)*$notidn;
                }
                
                printf TIT "%04d.%03d:IDN: %d\n",$category,$mult,$notidn;
                $mult++;
         }
      }
   } 

   print TIT "9999:\n\n";

   my $has_mex = 0;
   foreach my $category (sort keys %{$mexcat_ref}){
     if (exists $title_ref->{$category}){
        $has_mex = 1;
     }
   }
  
   if ($has_mex){
     print MEX "0000:$mexidn\n";
     print MEX "0004:".$title_ref->{'0000'}[0]."\n";
     foreach my $category (sort keys %{$mexcat_ref}){
       if (exists $title_ref->{$category}){
         foreach my $content (@{$title_ref->{$category}}){       
                printf MEX "%04d:%s\n",$category,$content;
         }
       }
     }
     print MEX "9999:\n\n";
     $mexidn++;
   }
}

close(TIT);
close(PER);
close(KOR);
close(SWD);
close(MEX);

