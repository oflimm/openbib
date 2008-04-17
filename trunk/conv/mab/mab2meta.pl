#!/usr/bin/perl

#####################################################################
#
#  mab2meta.pl
#
#  Konvertierung von MAB2-Daten in das Meta-Format
#
#  Dieses File ist (C) 2007-2008 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;
use Encode::MAB2;
use MAB2::Record::Base;
use Tie::MAB2::Recno;
use Data::Dumper;
use YAML;

&GetOptions(
	    "filename=s"       => \$filename,
	    );

if (!$filename){
    print << "HELP";
mab2meta.pl - Aufrufsyntax

    mab2meta.pl --filename=xxx
HELP
exit;
}

$autidn=1;
$autidx=0;

$swtidn=1;
$swtidx=0;

$mexidn=1;
$mexidx=0;

$koridn=1;
$koridx=0;

$notidn=1;
$notidx=0;

$autdublastidx=1;
$kordublastidx=1;
$notdublastidx=1;
$swtdublastidx=1;


######################################################################
# Titel-Daten

my $titdefs_ref = {
    '001'  => {
        newcat => '0000', # ID
        mult   => 0,
    },    
    '002'  => {
        newcat => '0002', # SDN
        mut    => 0,
    },
    '010'  => {           # identifikationsnummer des direkt uebergeordneten datensatzes
        newcat => '0004', # Uebergeordn. Satz
        mut    => 1,
    },
    '089' => {            # bandangaben in vorlageform
        newcat => '0089', # bandangaben in vorlageform
        mult   => 1,
    },
    '331' => {            # hauptsachtitel in vorlageform oder mischform
        newcat => '0331', # hauptsachtitel in vorlageform oder mischform
        mult   => 1,
    },
    '403' => {            # ausgabebezeichnung in vorlageform
        newcat => '0403', # ausgabebezeichnung in vorlageform
        mult   => 1,
    },
    '425' => {            # erscheinungsjahr(e)
        newcat => '0425', # erscheinungsjahr(e)
        mult   => 1,
    },
    '433' => {            # umfangsangabe
        newcat => '0433', # umfangsangabe
        mult   => 1,
    },
    '540' => {            # internationale standardbuchnummer (isbn)
        newcat => '0540', # internationale standardbuchnummer (isbn)
        mult   => 1,
    },
    '335' => {            # zusaetze zum hauptsachtitel
        newcat => '0335', # zusaetze zum hauptsachtitel
        mult   => 1,
    },
    '359' => {            # verfasserangabe
        newcat => '0359', # verfasserangabe
        mult   => 1,
    },
    '410' => {            # ort(e) des 1. verlegers, druckers usw.
        newcat => '0410', # ort(e) des 1. verlegers, druckers usw.
        mult   => 1,
    },
    '412' => {            # name des 1. verlegers, druckers usw.
        newcat => '0412', # name des 1. verlegers, druckers usw.
        mult   => 1,
    },
    '655' => {            # E-Book URL
        newcat => '0662', # E-Book URL
        mult   => 1,
    },
    '659' => {            # E-Book Info
        newcat => '0663', # E-Book Info
        mult   => 1,
    },
    '700' => {            # Notationen/Systematik
        newcat => '0700', # Notationen/Systematik
        mult   => 1,
        ref    => 'not',
    },
    '710' => {            # schlagwoerter und schlagwortketten
        newcat => '0710', # schlagwoerter und schlagwortketten
        mult   => 1,
        ref    => 'swt',
    },
    '451' => {            # 1. gesamttitel in vorlageform
        newcat => '0451', # 1. gesamttitel in vorlageform
        mult   => 1,
    },
    '100' => {            # name der 1. person in ansetzungsform
        newcat => '0100', # verfasser
        mult   => 1,
        ref    => 'aut',
    },
    '104' => {            # name der 2. person in ansetzungsform
        newcat => '0100', # verfasser
        mult   => 1,
        ref    => 'aut',
    },
    '108' => {            # name der 3. person in ansetzungsform
        newcat => '0100', # verfasser
        mult   => 1,
        ref    => 'aut',
    },
    '200' => {            # name der 1. koerperschaft in ansetzungsform
        newcat => '0200', # koerperschaft
        mult   => 1,
        ref    => 'kor',
    },
    '204' => {            # name der 2. koerperschaft in ansetzungsform
        newcat => '0200', # koerperschaft
        mult   => 1,
        ref    => 'kor',
    },
    '208' => {            # name der 3. koerperschaft in ansetzungsform
        newcat => '0200', # koerperschaft
        mult   => 1,
        ref    => 'kor',
    },
};


open(PEROUT,'>:utf8','unload.PER');
open(KOEOUT,'>:utf8','unload.KOE');
open(SWDOUT,'>:utf8','unload.SWD');
open(SYSOUT,'>:utf8','unload.SYS');
open(TITOUT,'>:utf8','unload.TIT');

print "Bearbeite Titel\n";

tie @mab2titdata, 'Tie::MAB2::Recno', file => $filename;

foreach my $rawrec (@mab2titdata){
    my $rec = MAB2::Record::Base->new($rawrec);
    #print $rec->readable."\n----------------------\n";    
    my $multcount_ref = {};
    
    foreach my $category_ref (@{$rec->_struct->[1]}){
        my $category  = $category_ref->[0];
        my $indicator = $category_ref->[1];
        my $content   = konv($category_ref->[2]);

        my $newcategory = "";
        
        if (!exists $titdefs_ref->{$category}){
            next;
        }
        
        # Vorabfilterung

        # Titel-ID sowie Ueberordnungs-ID
        if ($category =~ /^001$/ || $category =~ /^010$/){
            $content=~s/\D//g;
        }

        if ($category =~ /^002$/){
            $content=~s/(\d\d\d\d)(\d\d)(\d\d)/$3.$2.$1/;
        }

        # Standard-Konvertierung mit perkonv

        if (!$titdefs_ref->{$category}{mult}){
            $indicator="";
        }

        if (exists $titdefs_ref->{$category}{newcat}){
            $newcategory = $titdefs_ref->{$category}{newcat};
        }

        if (exists $titdefs_ref->{$category}{ref}){
            if    ($titdefs_ref->{$category}{ref} eq 'aut'){
                my $supplement="";
                if ($content =~/^(.+?)( ; \[.*?$)/){
                    $content    = $1;
                    $supplement = $2;
                }

                $autidn=get_autidn($content);
                
                if ($autidn > 0){
                    print PEROUT "0000:$autidn\n";
                    print PEROUT "0001:$content\n;
                    print PEROUT "9999:\n";
                }
                else {
                    $autidn=(-1)*$autidn;
                }

                $content="IDN: $autidn".$supplement;
            }
            elsif ($titdefs_ref->{$category}{ref} eq 'kor'){
                $koridn=get_koridn($content);
                
                if ($koridn > 0){
                    print KOEOUT "0000:$koridn\n";
                    print KOEOUT "0001:$content\n;
                    print KOEOUT "9999:\n";
                }
                else {
                    $koridn=(-1)*$koridn;
                }

                $content="IDN: $koridn";
            }
            elsif ($titdefs_ref->{$category}{ref} eq 'swt'){
                $swtidn=get_swtidn($content);
                
                if ($swtidn > 0){
                    print SWDOUT "0000:$swtidn\n";
                    print SWDOUT "0001:$content\n;
                    print SWDOUT "9999:\n";
                }
                else {
                    $swtidn=(-1)*$swtidn;
                }

                $content="IDN: $swtidn";
            }
            elsif ($titdefs_ref->{$category}{ref} eq 'not'){
                $notidn=get_notidn($content);
                
                if ($notidn > 0){
                    print SYSOUT "0000:$notidn\n";
                    print SYSOUT "0001:$content\n;
                    print SYSOUT "9999:\n";
                }
                else {
                    $notidn=(-1)*$notidn;
                }

                $content="IDN: $notidn";
            }
        }

        if ($newcategory && $titdefs_ref->{$category}{mult} && $content){
            my $multcount=sprintf "%03d",++$multcount_ref->{$newcategory};
            print TITOUT "$newcategory.$multcount:$content\n";
        }
        elsif ($newcategory && $content){
            print TITOUT "$newcategory:$content\n";
        }
    }
    print TITOUT "9999:\n\n";
}

close(TITOUT);
close(PEROUT);
close(KOEOUT);
close(SWDOUT);
close(SYSOUT);

sub konv {
  my ($line)=@_;

  $line=~s/\&/&amp;/g;
  $line=~s/>/&gt;/g;
  $line=~s/</&lt;/g;
  $line=~s/\x{0088}//g;
  $line=~s/\x{0089}//g;

  return $line;
}

sub get_autidn {
  ($autans)=@_;
  
  $autdubidx=$startautidn;
  $autdubidn=0;
  #  print "Autans: $autans\n";
  
  while ($autdubidx < $autdublastidx){
    if ($autans eq $autdubbuf[$autdubidx]){
      $autdubidn=(-1)*$autdubidx;      
      
      #      print "AutIDN schon vorhanden: $autdubidn\n";
    }
    $autdubidx++;
  }
  if (!$autdubidn){
    $autdubbuf[$autdublastidx]=$autans;
    $autdubidn=$autdublastidx;
    #    print "AutIDN noch nicht vorhanden: $autdubidn\n";
    $autdublastidx++;
    
  }
  return $autdubidn;
}

sub get_swtidn {
  ($swtans)=@_;
  
  $swtdubidx=$startswtidn;
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
  
  $kordubidx=$startkoridn;
  $kordubidn=0;
  #  print "Korans: $korans\n";
  
  while ($kordubidx < $kordublastidx){
    if ($korans eq $kordubbuf[$kordubidx]){
      $kordubidn=(-1)*$kordubidx;      
      
      #      print "KorIDN schon vorhanden: $kordubidn\n";
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
  ($notans)=@_;
  
  $notdubidx=$startnotidn;
  $notdubidn=0;
  #  print "Notans: $notans\n";
  
  while ($notdubidx < $notdublastidx){
    if ($notans eq $notdubbuf[$notdubidx]){
      $notdubidn=(-1)*$notdubidx;      
      
      #      print "NotIDN schon vorhanden: $notdubidn\n";
    }
    $notdubidx++;
  }
  if (!$notdubidn){
    $notdubbuf[$notdublastidx]=$notans;
    $notdubidn=$notdublastidx;
    #    print "NotIDN noch nicht vorhanden: $notdubidn\n";
    $notdublastidx++;
    
  }
  return $notdubidn;
}

