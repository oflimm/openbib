#!/usr/bin/perl

#####################################################################
#
#  meta2sql.pl
#
#  Generierung von SQL-Einladedateien aus dem Meta-Format
#
#  Dieses File ist (C) 1997-2006 Oliver Flimm <flimm@openbib.org>
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

use Getopt::Long;
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use Storable ();

use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;

# Importieren der Konfigurationsdaten als Globale Variablen
# in diesem Namespace
use vars qw(%config);

*config = \%OpenBib::Config::config;

&GetOptions("reduce-mem"    => \$reducemem,
	    "single-pool=s" => \$singlepool,
	    );

my $convtab_ref = (exists $config{convtab}{singlepool})?
  $config{convtab}{singlepool}:$config{convtab}{default};

my $dir=`pwd`;
chop $dir;

my %listitemdata_aut=();
my %listitemdata_kor=();
my %listitemdata_mex=();


if ($reducemem){
    tie %listitemdata_aut, 'MLDBM', "./listitemdata_aut.db"
        or die "Could not tie listitemdata_aut.\n";
    
    tie %listitemdata_kor, 'MLDBM', "./listitemdata_kor.db"
        or die "Could not tie listitemdata_kor.\n";
    
    tie %listitemdata_mex, 'MLDBM', "./listitemdata_mex.db"
        or die "Could not tie listitemdata_mex.\n";
}

my $stammdateien_ref = {
    aut => {
        type           => "aut",
        infile         => "aut.exp",
        outfile        => "aut.mysql",
        outfile_ft     => "aut_ft.mysql",
        outfile_string => "aut_string.mysql",
        inverted_ref   => $convtab_ref->{inverted_aut},
        blacklist_ref  => $convtab_ref->{blacklist_aut},
    },
    
    kor => {
        infile         => "kor.exp",
        outfile        => "kor.mysql",
        outfile_ft     => "kor_ft.mysql",
        outfile_string => "kor_string.mysql",
        inverted_ref   => $convtab_ref->{inverted_kor},
        blacklist_ref  => $convtab_ref->{blacklist_kor},
    },
    
    swt => {
        infile         => "swt.exp",
        outfile        => "swt.mysql",
        outfile_ft     => "swt_ft.mysql",
        outfile_string => "swt_string.mysql",
        inverted_ref   => $convtab_ref->{inverted_swt},
        blacklist_ref  => $convtab_ref->{blacklist_swt},
    },
    
    notation => {
        infile         => "not.exp",
        outfile        => "not.mysql",
        outfile_ft     => "not_ft.mysql",
        outfile_string => "not_string.mysql",
        inverted_ref   => $convtab_ref->{inverted_not},
        blacklist_ref  => $convtab_ref->{blacklist_not},
    },
};


foreach my $type (keys %{$stammdateien_ref}){
  print STDERR "Bearbeite $stammdateien_ref->{$type}{infile} / $stammdateien_ref->{$type}{outfile}\n";

  open(IN ,       "<:utf8",$stammdateien_ref->{$type}{infile} )        || die "IN konnte nicht geoeffnet werden";
  open(OUT,       ">:utf8",$stammdateien_ref->{$type}{outfile})        || die "OUT konnte nicht geoeffnet werden";
  open(OUTFT,     ">:utf8",$stammdateien_ref->{$type}{outfile_ft})     || die "OUTFT konnte nicht geoeffnet werden";
  open(OUTSTRING, ">:utf8",$stammdateien_ref->{$type}{outfile_string}) || die "OUTSTRING konnte nicht geoeffnet werden";

  my $id;
 CATLINE:
  while (my $line=<IN>){
    my ($category,$indicator,$content);
    if ($line=~m/^0000:(\d+)$/){
      $id=$1;
      next CATLINE;
    }
    elsif ($line=~m/^9999:/){
      next CATLINE;
    }
    elsif ($line=~m/^(\d+)\.(\d+):(.*?)$/){
      ($category,$indicator,$content)=($1,$2,$3);
    }
    elsif ($line=~m/^(\d+):(.*?)$/){
      ($category,$content)=($1,$2);
    }

    chomp($content);
    
    next CATLINE if (exists $stammdateien_ref->{$type}{blacklist_ref}->{$category});

    # Ansetzungsformen fuer Kurztitelliste merken
    if ($category == 1){
        if ($type eq "aut"){
            $listitemdata_aut{$id}=$content;
        }
        elsif ($type eq "kor"){
            $listitemdata_kor{$id}=$content;
        }
    }
    
    my $contentnorm   = "";
    my $contentnormft = "";
    if (exists $stammdateien_ref->{$type}{inverted_ref}->{$category}){
       my $contentnormtmp = OpenBib::Common::Util::grundform({
           category => $category,
           content  => $content,
       });

       if ($stammdateien_ref->{$type}{inverted_ref}->{$category}->{string}){
           $contentnorm   = $contentnormtmp;
       }

       if ($stammdateien_ref->{$type}{inverted_ref}->{$category}->{ft}){
           $contentnormft = $contentnormtmp;
       }
       
       if ($stammdateien_ref->{$type}{inverted_ref}->{$category}->{init}){
           push @{$stammdateien_ref->{$type}{data}[$id]}, $contentnormtmp;
       }
   }

    if ($category && $content){
      print OUT       "$id$category$indicator$content\n";
    }
    if ($category && $contentnorm){
      print OUTSTRING "$id$category$contentnorm\n";
    }
    if ($category && $contentnormft){
      print OUTFT     "$id$category$contentnormft\n";
    }
  }
  close(OUT);
  close(OUTFT);
  close(OUTSTRING);
  close(IN);
}


#######################

$stammdateien_ref->{mex} = {
    infile         => "mex.exp",
    outfile        => "mex.mysql",
    outfile_ft     => "mex_ft.mysql",
    outfile_string => "mex_string.mysql",
    inverted_ref   => $convtab_ref->{inverted_mex},
};

print STDERR "Bearbeite mex.exp\n";

open(IN ,          "<:utf8","mex.exp"         ) || die "IN konnte nicht geoeffnet werden";
open(OUT,          ">:utf8","mex.mysql"       ) || die "OUT konnte nicht geoeffnet werden";
open(OUTFT,        ">:utf8","mex_ft.mysql"    ) || die "OUTFT konnte nicht geoeffnet werden";
open(OUTSTRING,    ">:utf8","mex_string.mysql") || die "OUTSTRING konnte nicht geoeffnet werden";
open(OUTCONNECTION,">:utf8","conn.mysql")       || die "OUTCONNECTION konnte nicht geoeffnet werden";

my $id;
my $titid;
CATLINE:
while (my $line=<IN>){
    my ($category,$indicator,$content);
    if ($line=~m/^0000:(\d+)$/){
        $id=$1;
        $titid=0;
        next CATLINE;
    }
    elsif ($line=~m/^9999:/){
        next CATLINE;
    }
    elsif ($line=~m/^(\d+)\.(\d+):(.*?)$/){
        ($category,$indicator,$content)=($1,$2,$3);
    }
    elsif ($line=~m/^(\d+):(.*?)$/){
        ($category,$content)=($1,$2);
    }

    chomp($content);
    
    # Signatur fuer Kurztitelliste merken
    if ($category == 14 && $titid){
        my $array_ref=exists $listitemdata_mex{$titid}?$listitemdata_mex{$titid}:[];
        push @$array_ref, $content;
        $listitemdata_mex{$titid}=$array_ref;
    }
    
    my $contentnorm   = "";
    my $contentnormft = "";

    if ($category && $content){

        if (exists $stammdateien_ref->{mex}{inverted_ref}->{$category}){
            my $contentnormtmp = OpenBib::Common::Util::grundform({
                category => $category,
                content  => $content,
            });

            if ($stammdateien_ref->{mex}{inverted_ref}->{$category}->{string}){
                $contentnorm   = $contentnormtmp;
            }

            if ($stammdateien_ref->{mex}{inverted_ref}->{$category}->{ft}){
                $contentnormft = $contentnormtmp;
            }

            if ($stammdateien_ref->{mex}{inverted_ref}->{$category}->{init}){
                push @{$stammdateien_ref->{mex}{data}[$titid]}, $contentnormtmp;
            }
	}

        # Verknupefungen
        if ($category=~m/^0004/){
            my ($sourceid) = $content=~m/^(\d+)/;
            my $sourcetype = 1; # TIT
            my $targettype = 6; # MEX
            my $targetid   = $id;
            my $supplement = "";
            my $category   = "";
            $titid         = $sourceid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
    
        if ($category && $content){
            print OUT       "$id$category$indicator$content\n";
        }
        if ($category && $contentnorm){
            print OUTSTRING "$id$category$contentnorm\n";
        }
        if ($category && $contentnormft){
            print OUTFT     "$id$category$contentnormft\n";
        }
    }
}

close(OUT);
close(OUTFT);
close(OUTSTRING);
close(IN);

$stammdateien_ref->{tit} = {
    infile         => "tit.exp",
    outfile        => "tit.mysql",
    outfile_ft     => "tit_ft.mysql",
    outfile_string => "tit_string.mysql",
    inverted_ref   => $convtab_ref->{inverted_tit},
    blacklist_ref  => $convtab_ref->{blacklist_tit},
};

print STDERR "Bearbeite tit.exp\n";

open(IN ,           "<:utf8","tit.exp"          ) || die "IN konnte nicht geoeffnet werden";
open(OUT,           ">:utf8","tit.mysql"        ) || die "OUT konnte nicht geoeffnet werden";
open(OUTFT,         ">:utf8","tit_ft.mysql"     ) || die "OUTFT konnte nicht geoeffnet werden";
open(OUTSTRING,     ">:utf8","tit_string.mysql" ) || die "OUTSTRING konnte nicht geoeffnet werden";
open(OUTSEARCH,     ">:utf8","search.mysql"     ) || die "OUT konnte nicht geoeffnet werden";
open(TITLISTITEM,   ">"     ,"titlistitem.mysql") || die "TITLISTITEM konnte nicht goeffnet werden";

my @verf      = ();
my @kor       = ();
my @swt       = ();
my @notation  = ();
my @hst       = ();
my @sign      = ();
my @isbn      = ();
my @issn      = ();
my @artinh    = ();
my @ejahr     = ();
my @titverf   = ();
my @titkor    = ();
my @titswt    = ();
my @autkor    = ();

my $listitem_ref={};

CATLINE:
while (my $line=<IN>){
    my ($category,$indicator,$content);
    my ($ejahr,$sign,$isbn,$issn,$artinh);

    if ($line=~m/^0000:(\d+)$/){
        $id=$1;

        @verf      = ();
        @kor       = ();
        @swt       = ();
        @notation  = ();
        @hst       = ();
        @sign      = ();
        @isbn      = ();
        @issn      = ();
        @artinh    = ();
        @ejahr     = ();
        @titverf   = ();
        @titkor    = ();
        @titswt    = ();
        @autkor    = ();

        $listitem_ref={};

        $listitem_ref->{id}       = $id;
        $listitem_ref->{database} = $singlepool;

        next CATLINE;
    }
    elsif ($line=~m/^9999:/){

        my @temp=();
        foreach my $item (@verf){
            push @temp, join(" ",@{$stammdateien_ref->{aut}{data}[$item]});
        }
        push @temp, join(" ",@titverf);
        my $verf     = join(" ",@temp);

        @temp=();
        foreach my $item (@kor){
            push @temp, join(" ",@{$stammdateien_ref->{kor}{data}[$item]});
        }
        push @temp, join(" ",@titkor);
        my $kor      = join(" ",@temp);

        @temp=();
        foreach my $item (@swt){
            push @temp, join(" ",@{$stammdateien_ref->{swt}{data}[$item]});
        }
        push @temp, join(" ",@titswt);
        my $swt      = join(" ",@temp);

        @temp=();
        foreach my $item (@notation){
            push @temp, join(" ",@{$stammdateien_ref->{notation}{data}[$item]});
        }
        my $notation = join(" ",@temp);

        @temp=();
	push @temp, join(" ",@{$stammdateien_ref->{mex}{data}[$id]});
        my $mex = join(" ",@temp);
        
        my $hst       = join(" ",@hst);
        my $isbn      = join(" ",@isbn);
        my $issn      = join(" ",@issn);
        my $artinh    = join(" ",@artinh);
        my $ejahr     = join(" ",@ejahr);
        
        print OUTSEARCH "$id$verf$hst$kor$swt$notation$mex$ejahr$isbn$issn$artinh\n";

        # Listitem zusammensetzen

        # Konzeptionelle Vorgehensweise fuer die korrekte Anzeige eines Titel in
        # der Kurztitelliste:
        #
        # 1. Fall: Es existiert ein HST
        #
        # Dann:
        #
        # Unterfall 1.1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Setze diese Bandzahl vor den AST/HST
        #
        # Unterfall 1.2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Setze diese Bandzahl vor den AST/HST
        #
        # 2. Fall: Es existiert kein HST(331)
        #
        # Dann:
        #
        # Unterfall 2.1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Verwende diese Bandzahl
        #
        # Unterfall 2.3: Es existieren keine Bandzahlen, aber ein (erster)
        #                Gesamttitel(451)
        #
        # Dann: Verwende diesen GT
        #
        # Unterfall 2.4: Es existieren keine Bandzahlen, kein Gesamttitel(451),
        #                aber eine Zeitschriftensignatur(1203/USB-spezifisch)
        #
        # Dann: Verwende diese Zeitschriftensignatur
        #
        if (exists $listitem_ref->{T0331}){
            # UnterFall 1.1:
            if (exists $listitem_ref->{'T0089'}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0089}[0]{content}.". ".$listitem_ref->{T0331}[0]{content};
            }
            # Unterfall 1.2:
            elsif (exists $listitem_ref->{T0455}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0455}[0]{content}.". ".$listitem_ref->{T0331}[0]{content};
            }
        }
        else {
            # UnterFall 2.1:
            if (exists $listitem_ref->{'T0089'}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0089}[0]{content};
            }
            # Unterfall 2.2:
            elsif (exists $listitem_ref->{T0455}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0455}[0]{content};
            }
            # Unterfall 2.3:
            elsif (exists $listitem_ref->{T0451}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T0451}[0]{content};
            }
            # Unterfall 2.4:
            elsif (exists $listitem_ref->{T1203}){
                $listitem_ref->{T0331}[0]{content}=$listitem_ref->{T1203}[0]{content};
            }
            else {
                $listitem_ref->{T0331}[0]{content}="Kein HST/AST vorhanden";
            }
        }
        
        # Exemplardaten-Hash zu listitem-Hash hinzufuegen

        foreach my $content (@{$listitemdata_mex{$id}}){
            push @{$listitem_ref->{X0014}}, {
                content => $content,
            };
        }
        
        # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung
        push @{$listitem_ref->{'PC0001'}}, {
            content   => join(" ; ",@autkor),
        };
        # Hinweis: Weder das verpacken via pack "u" noch Base64 koennten
        # eventuell fuer die Recherche schnell genug sein. Allerdings
        # funktioniert es sehr gut.
        # Moegliche Alternativen
        # - Binaere Daten mit load data behandeln koennen
        # - Data::Dumper verwenden, da hier ASCII herauskommt
        # - in MLDB auslagern
        # - Kategorien als eigene Spalten

        
        my $listitem = Storable::freeze($listitem_ref);

        my $encoding_type="hex";
        
        if    ($encoding_type eq "base64"){
            $listitem = MIME::Base64::encode_base64($listitem,"");
        }
        elsif ($encoding_type eq "hex"){
            $listitem = unpack "H*",$listitem;
        }
        elsif ($encoding_type eq "uu"){
            $listitem =~s/\\/\\\\/g;
            $listitem =~s/\n/\\n/g;
            $listitem = pack "u",$tit;
        }

        print TITLISTITEM "$id$listitem\n";
        next CATLINE;
    }
    elsif ($line=~m/^(\d+)\.(\d+):(.*?)$/){
        ($category,$indicator,$content)=($1,$2,$3);
    }
    elsif ($line=~m/^(\d+):(.*?)$/){
        ($category,$content)=($1,$2);
    }

    chomp($content);
    
    if ($category && $content){
        
        next CATLINE if (exists $stammdateien_ref->{tit}{blacklist_ref}->{$category});

        if (exists $convtab_ref->{listitemcat}{$category}){
            push @{$listitem_ref->{"T".$category}}, {
                indicator => $indicator,
                content   => $content,
            };
    
        };
        
        my $contentnorm   = "";
        my $contentnormft = "";

        if (exists $stammdateien_ref->{tit}{inverted_ref}->{$category}){
            my $contentnormtmp = OpenBib::Common::Util::grundform({
                category => $category,
                content  => $content,
            });

            if ($stammdateien_ref->{tit}{inverted_ref}->{$category}->{string}){
                $contentnorm   = $contentnormtmp;
            }

            if ($stammdateien_ref->{tit}{inverted_ref}->{$category}->{ft}){
                $contentnormft = $contentnormtmp;
            }
        }

        # Verknupefungen
        if ($category=~m/^0004/){
            my ($targetid) = $content=~m/^(\d+)/;
            my $targettype = 1; # TIT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "";
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0100/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 2; # AUT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0100";

            push @verf, $targetid;

            my $content = $listitemdata_aut{$targetid};

            push @{$listitem_ref->{P0100}}, {
                id      => $targetid,
                type    => 'aut',
                content => $content,
            };

            push @autkor, $content;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0101/){
            my ($targetid)  = $content=~m/^IDN: (\d+)/;
            my $targettype  = 2; # AUT
            my $sourceid    = $id;
            my $sourcetype  = 1; # TIT
            my $supplement  = "";

            if ($content=~m/^IDN: \d+ ; (.+)/){
                $supplement = $1;
            }
            
            my $category="0101";

            push @verf, $targetid;

            my $content = $listitemdata_aut{$targetid};
            
            push @{$listitem_ref->{P0101}}, {
                id         => $targetid,
                type       => 'aut',
                content    => $content,
                supplement => $supplement,
            };

            push @autkor, $content;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0103/){
            my ($targetid)  = $content=~m/^IDN: (\d+)/;
            my $targettype  = 2; # AUT
            my $sourceid    = $id;
            my $sourcetype  = 1; # TIT
            my $supplement  = "";

            if ($content=~m/^IDN: \d+ ; (.+)/){
                $supplement = $1;
            }

            my $category="0103";

            push @verf, $targetid;

            my $content = $listitemdata_aut{$targetid};
            
            push @{$listitem_ref->{P0103}}, {
                id         => $targetid,
                type       => 'aut',
                content    => $content,
                supplement => $supplement,
            };

            push @autkor, $content;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0200/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 3; # KOR
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0200";

            push @kor, $targetid;

            my $content = $listitemdata_kor{$targetid};
            
            push @{$listitem_ref->{C0200}}, {
                id         => $targetid,
                type       => 'kor',
                content    => $content,
            };

            push @autkor, $content;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0201/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 3; # KOR
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0201";

            push @kor, $targetid;

            my $content = $listitemdata_kor{$targetid};

            push @{$listitem_ref->{C0201}}, {
                id         => $targetid,
                type       => 'kor',
                content    => $content,
            };

            push @autkor, $content;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0700/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 5; # NOTATION
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0700";

            push @notation, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0710/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0710";

            push @swt, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0902/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0902";

            push @swt, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0907/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0907";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0912/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0912";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0917/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0917";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0922/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0922";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0927/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0927";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0932/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0932";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0937/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0937";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0942/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0942";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0947/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0947";

            push @swt, $targetid;

            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        # Titeldaten
        else {
            if (   exists $convtab_ref->{search_category}{ejahr    }{$category}){
                push @ejahr, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $convtab_ref->{search_category}{hst      }{$category}){
                push @hst, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $convtab_ref->{search_category}{isbn     }{$category}){
                push @isbn,      OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $convtab_ref->{search_category}{issn     }{$category}){
                push @issn,      OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $convtab_ref->{search_category}{artinh   }{$category}){
                push @artinh, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $convtab_ref->{search_category}{verf     }{$category}){
                push @titverf, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $convtab_ref->{search_category}{kor      }{$category}){
                push @titkor, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $convtab_ref->{search_category}{swt      }{$category}){
                push @titswt, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }

            if ($category && $content){
                print OUT       "$id$category$indicator$content\n";
            }
            if ($category && $contentnorm){
                print OUTSTRING "$id$category$contentnorm\n";
            }
            if ($category && $contentnormft){
                print OUTFT     "$id$category$contentnormft\n";
            }
        }	
    }
}
close(OUT);
close(OUTFT);
close(OUTSTRING);
close(OUTCONNECTION);
close(OUTSEARCH);
close(TITLISTITEM);
close(IN);


#######################


open(CONTROL,        ">control.mysql");
open(CONTROLINDEXOFF,">control_index_off.mysql");
open(CONTROLINDEXON, ">control_index_on.mysql");

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROLINDEXOFF << "DISABLEKEYS";
alter table $type        disable keys;
alter table ${type}_ft     disable keys;
alter table ${type}_string disable keys;
DISABLEKEYS
}

print CONTROLINDEXOFF "alter table conn        disable keys;\n";
print CONTROLINDEXOFF "alter table search      disable keys;\n";
print CONTROLINDEXOFF "alter table titlistitem disable keys;\n";

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROL << "ITEM";
truncate table $type;
load data infile '$dir/$stammdateien_ref->{$type}{outfile}'        into table $type        fields terminated by '' ;
truncate table ${type}_ft;
load data infile '$dir/$stammdateien_ref->{$type}{outfile_ft}'     into table ${type}_ft     fields terminated by '' ;
truncate table ${type}_string;
load data infile '$dir/$stammdateien_ref->{$type}{outfile_string}' into table ${type}_string fields terminated by '' ;
ITEM
}

print CONTROL << "TITITEM";
truncate table conn;
truncate table search;
truncate table titlistitem;
load data infile '$dir/conn.mysql'        into table conn   fields terminated by '' ;
load data infile '$dir/search.mysql'      into table search fields terminated by '' ;
load data infile '$dir/titlistitem.mysql' into table titlistitem fields terminated by '' ;
TITITEM

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROLINDEXON << "ENABLEKEYS";
alter table $type          enable keys;
alter table ${type}_ft     enable keys;
alter table ${type}_string enable keys;
ENABLEKEYS
}

print CONTROLINDEXON "alter table conn        enable keys;\n";
print CONTROLINDEXON "alter table search      enable keys;\n";
print CONTROLINDEXON "alter table titlistitem enable keys;\n";

close(CONTROL);
close(CONTROLINDEXOFF);
close(CONTROLINDEXON);

if ($reducemem){
    untie %listitemdata_aut;
    untie %listitemdata_kor;
    untie %listitemdata_mex;
}

1;

__END__

=head1 NAME

 meta2sql.pl - Generierung von SQL-Einladedateien aus dem Meta-Format

=head1 DESCRIPTION

 Mit dem Programm meta2sql.pl werden Daten, die im MAB2-orientierten
 Meta-Format vorliegen, in Einlade-Dateien fuer das MySQL-Datenbank-
 system umgewandelt. Bei dieser Umwandlung kann durch geeignete
 Aenderung in diesem Programm lenkend eingegriffen werden.

=head1 SYNOPSIS

 In $stammdateien_ref werden die verschiedenen Normdatentypen, ihre
 zugehoerigen Namen der Ein- und Ausgabe-Dateien, sowie die zu
 invertierenden Kategorien.

 Folgende Normdatentypen existieren:

 Titel                 (tit)      -> numerische Typentsprechung: 1
 Verfasser/Person      (aut)      -> numerische Typentsprechung: 2
 Koerperschaft/Urheber (kor)      -> numerische Typentsprechung: 3
 Schlagwort            (swt)      -> numerische Typentsprechung: 4
 Notation/Systematik   (notation) -> numerische Typentsprechung: 5
 Exemplardaten         (mex)      -> numerische Typentsprechung: 6


 Die numerische Entsprechung wird bei der Verknuepfung einzelner Saetze
 zwischen den Normdaten in der Tabelle conn verwendet.

 Der Speicherverbrauch kann ueber die Option -reduce-mem durch
 Auslagerung der fuer den Aufbau der Kurztitel-Tabelle benoetigten
 Informationen reduziert werden.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
