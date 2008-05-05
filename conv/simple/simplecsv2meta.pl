#!/usr/bin/perl

#####################################################################
#
#  simplecsv2meta.pl
#
#  Konverierung der einfach aufgebauter CVS-Daten in das Meta-Format
#
#  Dieses File ist (C) 1999-2008 Oliver Flimm <flimm@openbib.org>
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
use DBI;

use OpenBib::Config;

my $config = OpenBib::Config->instance;

&GetOptions(
	    "filename=s"       => \$filename,
	    );

if (!$filename){
    print << "HELP";
simplecsv2meta.pl - Aufrufsyntax

    simplecsv2meta.pl --filename=xxx
HELP
exit;
}

$bufferidx=0;

# Kategorieflags

%autkonv=(
    'Autor'       => '0100:', # Verfasser
    'Herausgeber' => '0101:', # Person
);

%korkonv=(
);

%notkonv=(
    'Paket'                => '0700:',
    'Paket1'               => '0700:',
    'Paket2'               => '0700:',
    'Paket3'               => '0700:',
);

%swtkonv=(
    'Subject'               => '0710:',
    'Subject2'              => '0710:',
    'Subject3'              => '0710:',
);

# Kategoriemappings

%titelkonv=(
    'Titel'                => '0331:',
    'Serientitel'          => '0451:',
    'Untertitel'           => '0370:',
    'Auflage'              => '0403:',
    'PrintISBN'            => '0540:',
    'OEBISBN'              => '0540:',
    'EBookISBN'            => '0553:',
    'Erscheinungsjahr'     => '0425:',
#    'DOI'                  => '',
    'Hosting'              => '0508:',
    'Kurzbeschreibung'     => '0750:',
    'URL'                  => '0662:',
    'Verlag'               => '0412:',
    'Erscheinungsdatum'    => '0002:',
);

# Einlesen und Reorganisieren

my $dbh = DBI->connect("DBI:CSV:");
$dbh->{'csv_tables'}->{'data'} = {
    'eol' => "\n",
    'sep_char' => "\t",
    'quote_char' => "\"",
    'escape_char' => undef,
    'file' => "$filename",
};

my $request = $dbh->prepare("select * from data");
$request->execute();

#######################################################################
# Umwandeln

$titidn=1;
$titidx=0;

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

$tempidx=0;

$i=0;
$ti=0;

$autdublastidx=1;
$kordublastidx=1;
$notdublastidx=1;
$swtdublastidx=1;

while (my $result=$request->fetchrow_hashref){
    $titbuffer[$titidx++]=sprintf "0000:%d", $result->{'Nr'};

    foreach my $kateg (keys %titelkonv){
        my $content = $result->{$kateg};

	$content=~s/uhttp:/http:/;

        if ($result->{$kateg}){
            $titbuffer[$titidx++]=$titelkonv{$kateg}.$content;
        }
    }

    # Autoren abarbeiten Anfang
    foreach my $kateg (keys %autkonv){
        my $content = $result->{$kateg};
        
        if ($result->{$kateg}){
            my @authors = ();
            if ($content=~/; /){
                @authors = split('; ',$content);
            }
            else {
                push @authors, $content;
            }
            
            foreach my $singleauthor (@authors){
                $autidn=get_autidn($singleauthor);
                
                if ($autidn > 0){
                    $autbuffer[$autidx++]="0000:".$autidn;
                    $autbuffer[$autidx++]="0001:".$singleauthor;
                    $autbuffer[$autidx++]="9999:";
                    
                }
                else {
                    $autidn=(-1)*$autidn;
                }
                
                $titbuffer[$titidx++]=$autkonv{$kateg}."IDN: ".$autidn;
        }
        }
        # Autoren abarbeiten Ende
    }
    # Koerperschaften abarbeiten Anfang

    foreach my $kateg (keys %korkonv){
        my $content = $result->{$kateg};
        
        if ($result->{$kateg}){
            $koridn=get_koridn($content);
            
            if ($koridn > 0){
                $korbuffer[$koridx++]="0000:".$koridn;
                $korbuffer[$koridx++]="0001:".$content;
                $korbuffer[$koridx++]="9999:";
                
            }
            else {
                $koridn=(-1)*$koridn;
            }
            
            $titbuffer[$titidx++]=$korkonv{$kateg}."IDN: ".$koridn;
        }
    }
    # Koerperschaften abarbeiten Ende


    # Notationen abarbeiten Anfang
    foreach my $kateg (keys %notkonv){
        my $content = $result->{$kateg};
        
        if ($result->{$kateg}){
            $notidn=get_notidn($content);
            
            if ($notidn > 0){
                $notbuffer[$notidx++]="0000:".$notidn;
                $notbuffer[$notidx++]="0001:".$content;
                $notbuffer[$notidx++]="9999:";
                
            }
            else {
                $notidn=(-1)*$notidn;
            }
            
            $titbuffer[$titidx++]=$notkonv{$kateg}."IDN: ".$notidn;
        }
    }
    # Notationen abarbeiten Ende

    # Schlagworte abarbeiten Anfang
    foreach my $kateg (keys %swtkonv){
        my $content = $result->{$kateg};
        
        if ($result->{$kateg}){
            $swtidn=get_swtidn($content);
            
            if ($swtidn > 0){	  
                $swtbuffer[$swtidx++]="0000:".$swtidn;
                $tempbuffer[$ti]=~s/\*/\//g;
                $swtbuffer[$swtidx++]="0001:".$content;
                $swtbuffer[$swtidx++]="9999:";
            }
            else {
                $swtidn=(-1)*$swtidn;
            }
            $titbuffer[$titidx++]=$swtkonv{$kateg}."IDN: ".$swtidn;
        }
    }
    # Schlagworte abarbeiten Ende

    $titbuffer[$titidx++]="9999:";

    $titidn++;
}
  
$lasttitidx=$titidx;
$lastautidx=$autidx;
$lastnotidx=$notidx;
$lastmexidx=$mexidx;
$lastkoridx=$koridx;
$lastswtidx=$swtidx;

# Ausgabe der EXP-Dateien

ausgabetitfile();
ausgabeautfile();
ausgabekorfile();
ausgabenotfile();
ausgabeswtfile();

close(DAT);

sub ausgabetitfile {
  open (TIT,">:utf8","unload.TIT");
  $i=0;
  while ($i < $lasttitidx){
    print TIT $titbuffer[$i],"\n";
    $i++;
  }
  close(TIT);
}

sub ausgabeautfile {
  open(AUT,">:utf8","unload.PER");
  $i=0;
  while ($i < $lastautidx){
    print AUT $autbuffer[$i],"\n";
    $i++;
  }
  close(AUT);
}

sub ausgabekorfile {
  open(KOR,">:utf8","unload.KOE");
  $i=0;
  while ($i < $lastkoridx){
    print KOR $korbuffer[$i],"\n";
    $i++;
  }
  close(KOR);
}

sub ausgabenotfile {
  open(NOTATION,">:utf8","unload.SYS");
  $i=0;
  while ($i < $lastnotidx){
    print NOTATION $notbuffer[$i],"\n";
    $i++;
  }
  close(NOTATION);
}

sub ausgabeswtfile {
  open(SWT,">:utf8","unload.SWD");
  $i=0;
  while ($i < $lastswtidx) {
    print SWT $swtbuffer[$i],"\n";
    $i++;
  }
  close(SWT);
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

