#!/usr/bin/perl

#####################################################################
#
#  meta2sql.pl
#
#  Generierung von SQL-Einladedateien aus dem Meta-Format
#
#  Dieses File ist (C) 1997-2008 Oliver Flimm <flimm@openbib.org>
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
#use strict;
#use warnings;

use Business::ISBN;
use DB_File;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML;

use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Statistics;

my ($database,$reducemem,$addsuperpers,$addmediatype,$logfile);

&GetOptions("reduce-mem"    => \$reducemem,
            "add-superpers" => \$addsuperpers,
            "add-mediatype" => \$addmediatype,
	    "database=s"    => \$database,
            "logfile=s"     => \$logfile,
	    );

my $config      = OpenBib::Config->instance;
my $conv_config = new OpenBib::Conv::Config({dbname => $database});

$logfile=($logfile)?$logfile:"/var/log/openbib/meta2sql-$database.log";

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

my $dir=`pwd`;
chop $dir;

my %listitemdata_aut        = ();
my %listitemdata_kor        = ();
my %listitemdata_not        = ();
my %listitemdata_swt        = ();
my %listitemdata_mex        = ();
my %listitemdata_superid    = ();
my %listitemdata_popularity = ();
my %normdata                = ();
my %enrichmntdata           = ();

# Verbindung zur SQL-Datenbank herstellen
my $statisticsdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{statisticsdbname};host=$config->{statisticsdbhost};port=$config->{statisticsdbport}", $config->{statisticsdbuser}, $config->{statisticsdbpasswd})
    or $logger->error($DBI::errstr);

my $request=$statisticsdbh->prepare("select katkey, count(katkey) as kcount from relevance where origin=2 and dbname=? group by katkey");
$request->execute($database);

open(OUTPOP,    ">:utf8","popularity.mysql")     || die "OUTPOP konnte nicht geoeffnet werden";
while (my $res    = $request->fetchrow_hashref){
    my $id      = $res->{katkey};
    my $idcount = $res->{kcount};
    $listitemdata_popularity{$id}=$idcount;
    print OUTPOP "$id$idcount\n";
}
$request->finish();
close(OUTPOP);

if ($reducemem){
    tie %listitemdata_aut,        'MLDBM', "./listitemdata_aut.db"
        or die "Could not tie listitemdata_aut.\n";
    
    tie %listitemdata_kor,        'MLDBM', "./listitemdata_kor.db"
        or die "Could not tie listitemdata_kor.\n";

    tie %listitemdata_not,        'MLDBM', "./listitemdata_not.db"
        or die "Could not tie listitemdata_not.\n";
 
    tie %listitemdata_swt,        'MLDBM', "./listitemdata_swt.db"
        or die "Could not tie listitemdata_swt.\n";

    tie %listitemdata_mex,        'MLDBM', "./listitemdata_mex.db"
        or die "Could not tie listitemdata_mex.\n";

    tie %listitemdata_superid,    "DB_File", "./listitemdata_superid.db"
        or die "Could not tie listitemdata_superid.\n";
}

tie %normdata,                'MLDBM', "./normdata.db"
    or die "Could not tie normdata.\n";

my $local_enrichmnt  = 0;
my $enrichmntdumpdir = $config->{autoconv_dir}."/data/enrichment";

if (exists $conv_config->{local_enrichmnt} && -e "$enrichmntdumpdir/enrichmntdata.db"){
    tie %enrichmntdata,           'MLDBM', "$enrichmntdumpdir/enrichmntdata.db"
        or die "Could not tie enrichment data.\n";

    $local_enrichmnt = 1;

    $logger->info("Lokale Einspielung mit zentralen Anreicherungsdaten aktiviert");
}

my $stammdateien_ref = {
    aut => {
        type           => "aut",
        infile         => "aut.exp",
        outfile        => "aut.mysql",
        outfile_ft     => "aut_ft.mysql",
        outfile_string => "aut_string.mysql",
        inverted_ref   => $conv_config->{inverted_aut},
        blacklist_ref  => $conv_config->{blacklist_aut},
    },
    
    kor => {
        infile         => "kor.exp",
        outfile        => "kor.mysql",
        outfile_ft     => "kor_ft.mysql",
        outfile_string => "kor_string.mysql",
        inverted_ref   => $conv_config->{inverted_kor},
        blacklist_ref  => $conv_config->{blacklist_kor},
    },
    
    swt => {
        infile         => "swt.exp",
        outfile        => "swt.mysql",
        outfile_ft     => "swt_ft.mysql",
        outfile_string => "swt_string.mysql",
        inverted_ref   => $conv_config->{inverted_swt},
        blacklist_ref  => $conv_config->{blacklist_swt},
    },
    
    notation => {
        infile         => "not.exp",
        outfile        => "not.mysql",
        outfile_ft     => "not_ft.mysql",
        outfile_string => "not_string.mysql",
        inverted_ref   => $conv_config->{inverted_not},
        blacklist_ref  => $conv_config->{blacklist_not},
    },
};


foreach my $type (keys %{$stammdateien_ref}){
  $logger->info("Bearbeite $stammdateien_ref->{$type}{infile} / $stammdateien_ref->{$type}{outfile}");

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
        elsif ($type eq "notation"){
            $listitemdata_not{$id}=$content;
        }
        elsif ($type eq "swt"){
           $listitemdata_swt{$id}= {
               content     => $content,
                contentnorm => OpenBib::Common::Util::grundform({
                    category => 'T0710',
                    content  => $content,
                }),
           };
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
           push @{$stammdateien_ref->{$type}{data}{$id}}, $contentnormtmp;
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
    inverted_ref   => $conv_config->{inverted_mex},
};

$logger->info("Bearbeite mex.exp");

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
                push @{$stammdateien_ref->{mex}{data}{$titid}}, $contentnormtmp;
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
    inverted_ref   => $conv_config->{inverted_tit},
    blacklist_ref  => $conv_config->{blacklist_tit},
};

if ($addsuperpers){
    $logger->info("Option addsuperpers ist aktiviert");
    $logger->info("1. Durchgang: Uebergeordnete Titel-ID's finden");
    open(IN ,           "<:utf8","tit.exp"          ) || die "IN konnte nicht geoeffnet werden";

    while (my $line=<IN>){
        if ($line=~m/^0004.*?:(\d+)/){
            my $superid=$1;
            $listitemdata_superid{$superid}=1;
        }
    }
    close(IN);

    $logger->info("2. Durchgang: Verfasser-ID's in uebergeordneten Titeln finden");
    open(IN ,           "<:utf8","tit.exp"          ) || die "IN konnte nicht geoeffnet werden";

    my ($id,@persids);

    while (my $line=<IN>){
        if ($line=~m/^0000:(\d+)$/){            
            $id=$1;
            @persids=();
        }
        elsif ($line=~m/^9999:/){
            if ($#persids >= 0){
                $listitemdata_superid{$id}=join(":",@persids);
            }
        }
        elsif ($line=~m/^010[0123].*?:IDN: (\d+)/){
            my $persid=$1;
            if (exists $listitemdata_superid{$id}){
                push @persids, $persid;
            }
        }
    }

    close(IN);
}

$logger->info("Bearbeite tit.exp");

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
my @ejahrft   = ();
my @gtquelle  = ();
my @titverf   = ();
my @titkor    = ();
my @titswt    = ();
my @autkor    = ();
my @inhalt    = ();
my @superids  = ();

my $listitem_ref={};
my $thisitem_ref={};

my $normdata_ref={};

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
        @ejahrft   = ();
        @gtquelle  = ();
        @inhalt    = ();
        @titverf   = ();
        @titkor    = ();
        @titswt    = ();
        @autkor    = ();
        @superids  = ();

        $listitem_ref={};
        $thisitem_ref={};

        $normdata_ref={};

        $listitem_ref->{id}       = $id;
        $listitem_ref->{database} = $database;

        if (exists $listitemdata_popularity{$id}){
            $listitem_ref->{popularity} = $listitemdata_popularity{$id};
        }
        
        next CATLINE;
    }
    elsif ($line=~m/^9999:/){

        # Personen der Ueberordnung anreichern (Schiller-Raeuber)
        if ($addsuperpers){
            foreach my $superid (@superids){
                if (exists $listitemdata_superid{$superid}){
                    my @superpersids = split (":",$listitemdata_superid{$superid}); 
                    push @verf, @superpersids;
                }
            }
        }

        # Medientypen erkennen und anreichern
        if ($addmediatype){

            # Zeitschriften/Serien:
            # ISSN und/oder ZDB-ID besetzt
            if (exists $thisitem_ref->{'T0572'} || exists $thisitem_ref->{'T0543'}) {
                # Steht Medientyp schon auf Zeitschrift?
                my $have_journal=0;
                my $type_indicator = 1;
                foreach my $item (@{$thisitem_ref->{'T0800'}}){
                    $have_journal = 1 if ($item->{content} eq "Zeitschrift/Serie");
                    $type_indicator++;
                }

                if (!$have_journal){
                    push @{$normdata_ref->{mart}}, "Zeitschrift/Serie";

                    print OUT       "$id800$type_indicatorZeitschrift/Serie\n";
                    my $contentnormtmp = OpenBib::Common::Util::grundform({
                        category => '800',
                        content  => 'Zeitschrift/Serie',
                    });
                    print OUTSTRING "$id800$contentnormtmp\n";
                }
            }   


            # Aufsatz
            # HSTQuelle besetzt
            if (exists $thisitem_ref->{'T0590'}) {
                # Steht Medientyp schon auf Aufsatz?
                my $have_article=0;
                my $type_indicator = 1;
                foreach my $item (@{$thisitem_ref->{'T0800'}}){
                    $have_article = 1 if ($item->{content} eq "Aufsatz");
                    $type_indicator++;
                }

                if (!$have_journal){
                    push @{$normdata_ref->{mart}}, "Aufsatz";

                    print OUT       "$id800$type_indicatorAufsatz\n";
                    my $contentnormtmp = OpenBib::Common::Util::grundform({
                        category => '800',
                        content  => 'Aufsatz',
                    });
                    print OUTSTRING "$id800$contentnormtmp\n";
                }
            }   

        }
        
        # Zentrale Anreicherungsdaten lokal einspielen
        if ($local_enrichmnt && exists $normdata_ref->{isbn13}){
            foreach my $category (keys %{$conv_config->{local_enrichmnt}}){
                if (exists $enrichmntdata{$normdata_ref->{isbn13}}{$category}){
                    my $indicator = 1;
                    foreach my $content (@{$enrichmntdata{$normdata_ref->{isbn13}}{$category}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });

                        $logger->debug("Id: $id - Adding $category -> $content");
                        print OUT       "$id$category$indicator$content\n";
                        $indicator++;
                        # Normierung (String/Fulltext) der als invertierbar definierten Kategorien
                        if (exists $stammdateien_ref->{tit}{inverted_ref}->{$category}){
                            if ($stammdateien_ref->{tit}{inverted_ref}->{$category}->{string}){
                                print OUTSTRING "$id$category$contentnormtmp\n";
                            }
                            
                            if ($stammdateien_ref->{tit}{inverted_ref}->{$category}->{ft}){
                                print OUTFT     "$id$category$contentnormtmp\n";
                            }
                        }
                        if (exists $conv_config->{'search_hst'}{$category}){
                            push @hst, $contentnormtmp;
                        }
                        if (exists $conv_config->{'search_ejahr'}{$category}){
                            push @ejahr, $contentnormtmp;
                        }
                        if (exists $conv_config->{'search_ejahrft'}{$category}){
                            push @ejahrft, $contentnormtmp;
                        }
                        if (exists $conv_config->{'search_gtquelle'}{$category}){
                            push @gtquelle, $contentnormtmp;
                        }
                        if (exists $conv_config->{'search_inhalt'}{$category}){
                            push @inhalt, $contentnormtmp;
                        }
                        if (exists $conv_config->{'search_artinh'}{$category}){
                            push @artinh, $contentnormtmp;
                        }
                        if (exists $conv_config->{'search_verf'}{$category}){
                            push @titverf, $contentnormtmp;
                        }
                        if (exists $conv_config->{'search_kor'}{$category}){
                            push @titkor, $contentnormtmp;
                        }
                        if (exists $conv_config->{'search_swt'}{$category}){
                            push @titswt, $contentnormtmp;
                        }
                    }
                }
            }
        }
        
        my @temp=();

        # Im Falle einer Personenanreicherung durch Ueberordnungen mit
        # -add-superpers sollen Dubletten entfernt werden.
        my %seen_verf=();
        foreach my $item (@verf){
            next if (exists $seen_verf{$item});
            push @temp, join(" ",@{$stammdateien_ref->{aut}{data}{$item}});
            $seen_verf{$item}=1;
        }
        push @temp, join(" ",@titverf);
        my $verf     = join(" ",@temp);

        @temp=();
        foreach my $item (@kor){
            push @temp, join(" ",@{$stammdateien_ref->{kor}{data}{$item}});
        }
        push @temp, join(" ",@titkor);
        my $kor      = join(" ",@temp);

        @temp=();
        foreach my $item (@swt){
            push @temp, join(" ",@{$stammdateien_ref->{swt}{data}{$item}});
        }
        push @temp, join(" ",@titswt);
        my $swt      = join(" ",@temp);

        @temp=();
        foreach my $item (@notation){
            push @temp, join(" ",@{$stammdateien_ref->{notation}{data}{$item}});
        }
        my $notation = join(" ",@temp);

        @temp=();
	push @temp, join(" ",@{$stammdateien_ref->{mex}{data}{$id}});
        my $mex = join(" ",@temp);
        
        my $hst       = join(" ",@hst);
        my $isbn      = join(" ",@isbn);
        my $issn      = join(" ",@issn);
        my $artinh    = join(" ",@artinh);
        my $ejahr     = join(" ",@ejahr);
        my $ejahrft   = join(" ",@ejahrft);
        my $gtquelle  = join(" ",@gtquelle);
        my $inhalt    = join(" ",@inhalt);
        
        print OUTSEARCH "$id$verf$hst$kor$swt$notation$mex$ejahr$ejahrft$gtquelle$inhalt$isbn$issn$artinh\n";

        # Listitem zusammensetzen

        # Konzeptionelle Vorgehensweise fuer die korrekte Anzeige eines Titel in
        # der Kurztitelliste:
        #
        # 1. Fall: Es existiert ein HST
        #
        # Dann:
        #
        # Ist nichts zu tun
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
        if (!exists $listitem_ref->{T0331}) {
            # UnterFall 2.1:
            if (exists $thisitem_ref->{'T0089'}) {
                $listitem_ref->{T0331}[0]{content}=$thisitem_ref->{T0089}[0]{content};
            }
            # Unterfall 2.2:
            elsif (exists $thisitem_ref->{T0455}) {
                $listitem_ref->{T0331}[0]{content}=$thisitem_ref->{T0455}[0]{content};
            }
            # Unterfall 2.3:
            elsif (exists $thisitem_ref->{T0451}) {
                $listitem_ref->{T0331}[0]{content}=$thisitem_ref->{T0451}[0]{content};
            }
            # Unterfall 2.4:
            elsif (exists $thisitem_ref->{T1203}) {
                $listitem_ref->{T0331}[0]{content}=$thisitem_ref->{T1203}[0]{content};
            }
            else {
                $listitem_ref->{T0331}[0]{content}="Kein HST/AST vorhanden";
            }
        }

        # Bestimmung der Zaehlung

        # Fall 1: Es existiert eine (erste) Bandzahl(089)
        #
        # Dann: Setze diese Bandzahl
        #
        # Fall 2: Es existiert keine Bandzahl(089), aber eine (erste)
        #                Bandzahl(455)
        #
        # Dann: Setze diese Bandzahl

        # Fall 1:
        if (exists $thisitem_ref->{'T0089'}) {
            $listitem_ref->{T5100}= [
                {
                    content => $thisitem_ref->{T0089}[0]{content}
                }
            ];
        }
        # Fall 2:
        elsif (exists $thisitem_ref->{T0455}) {
            $listitem_ref->{T5100}= [
                {
                    content => $thisitem_ref->{T0455}[0]{content}
                }
            ];
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
            $listitem = pack "u",$listitem;
        }

        print TITLISTITEM "$id$listitem\n";

	$normdata{$id} = $normdata_ref; 

        # Kategorie 5050 wird *immer* angereichert. Die Invertierung ist konfigurabel
        my $bibkey_base = OpenBib::Common::Util::gen_bibkey_base({ normdata => $thisitem_ref});
        my $bibkey      = OpenBib::Common::Util::gen_bibkey({ bibkey_base => $bibkey_base });
        
        if ($bibkey){
            print OUT       "$id50501$bibkey\n";            
            print OUTSTRING "$id5050$bibkey\n" if (exists $stammdateien_ref->{tit}{inverted_ref}->{'5050'}{string});
            print OUTSTRING "$id5051$bibkey_base\n" if (exists $stammdateien_ref->{tit}{inverted_ref}->{'5051'}{string});
        }
        
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
        
        # Kategorien in der Blacklist werden generell nicht uebernommen
        next CATLINE if (exists $stammdateien_ref->{tit}{blacklist_ref}->{$category});

        # Kategorien in listitemcat werden fuer die Kurztitelliste verwendet
        if (exists $conv_config->{listitemcat}{$category}){
            push @{$listitem_ref->{"T".$category}}, {
                indicator => $indicator,
                content   => $content,
            };
        };

        my $contentnorm   = "";
        my $contentnormft = "";

        # Normierung (String/Fulltext) der als invertierbar definierten Kategorien
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
        
        # Verknuepfungen
        if ($category=~m/^0004/){
            my ($targetid) = $content=~m/^(\d+)/;
            my $targettype = 1; # TIT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "";

            push @superids, $targetid;
            
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0100/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 2; # AUT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0100";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_aut{$targetid}){
                push @verf, $targetid;
                
                my $content = $listitemdata_aut{$targetid};
                
                push @{$thisitem_ref->{"T".$category}}, {
                    indicator => $indicator,
                    content   => $content,
                };

                push @{$listitem_ref->{P0100}}, {
                    id      => $targetid,
                    type    => 'aut',
                    content => $content,
                } if (exists $conv_config->{listitemcat}{'0100'});
                
                push @{$normdata_ref->{verf}}, $content;
                
                push @autkor, $content;
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("PER ID $targetid doesn't exist in TIT ID $id");
            }
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

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_aut{$targetid}){
                push @verf, $targetid;
                
                my $content = $listitemdata_aut{$targetid};
                
                push @{$thisitem_ref->{"T".$category}}, {
                    indicator  => $indicator,
                    content    => $content,
                    supplement => $supplement,
                };

                push @{$listitem_ref->{P0101}}, {
                    id         => $targetid,
                    type       => 'aut',
                    content    => $content,
                    supplement => $supplement,
                } if (exists $conv_config->{listitemcat}{'0101'});
                
                push @{$normdata_ref->{verf}}, $content;
                
                push @autkor, $content;
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("PER ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0102/){
            my ($targetid)  = $content=~m/^IDN: (\d+)/;
            my $targettype  = 2; # AUT
            my $sourceid    = $id;
            my $sourcetype  = 1; # TIT
            my $supplement  = "";

            if ($content=~m/^IDN: \d+ ; (.+)/){
                $supplement = $1;
            }
            
            my $category="0102";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_aut{$targetid}){
                push @verf, $targetid;
                
                my $content = $listitemdata_aut{$targetid};
                
                push @{$listitem_ref->{P0102}}, {
                    id         => $targetid,
                    type       => 'aut',
                    content    => $content,
                    supplement => $supplement,
                } if (exists $conv_config->{listitemcat}{'0102'});
                
                push @{$normdata_ref->{verf}}, $content;
                
                push @autkor, $content;
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("PER ID $targetid doesn't exist in TIT ID $id");
            }
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

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_aut{$targetid}){
                push @verf, $targetid;
                
                my $content = $listitemdata_aut{$targetid};
                
                push @{$listitem_ref->{P0103}}, {
                    id         => $targetid,
                    type       => 'aut',
                    content    => $content,
                    supplement => $supplement,
                } if (exists $conv_config->{listitemcat}{'0103'});
                
                push @{$normdata_ref->{verf}}, $content;
                
                push @autkor, $content;
            
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("PER ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0200/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 3; # KOR
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0200";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_kor{$targetid}){
                push @kor, $targetid;
                
                my $content = $listitemdata_kor{$targetid};
                
                push @{$listitem_ref->{C0200}}, {
                    id         => $targetid,
                    type       => 'kor',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0200'});

                push @{$normdata_ref->{kor}}, $content;

                push @autkor, $content;
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("KOR ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0201/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 3; # KOR
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0201";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_kor{$targetid}){
                push @kor, $targetid;
                
                my $content = $listitemdata_kor{$targetid};
                
                push @{$listitem_ref->{C0201}}, {
                    id         => $targetid,
                    type       => 'kor',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0201'});

                push @{$normdata_ref->{kor}}, $content;

                push @autkor, $content;
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("KOR ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0700/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 5; # NOTATION
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0700";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_not{$targetid}){
                push @notation, $targetid;
                
                my $content = $listitemdata_not{$targetid};

                push @{$listitem_ref->{N0700}}, {
                    id         => $targetid,
                    type       => 'notation',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0700'});

                push @{$normdata_ref->{notation}}, $content;
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SYS ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0710/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0710";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;
                
                my $content = $listitemdata_swt{$targetid}->{content};
                
                push @{$listitem_ref->{S0710}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0710'});

                push @{$normdata_ref->{swt}}, $content;
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0902/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0902";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;

                my $content = $listitemdata_swt{$targetid}->{content};

                push @{$listitem_ref->{S0902}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0902'});

                push @{$normdata_ref->{swt}}, $content;

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0907/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0907";
            
            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;

                my $content = $listitemdata_swt{$targetid}->{content};

                push @{$listitem_ref->{S0907}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0907'});

                push @{$normdata_ref->{swt}}, $content;
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0912/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0912";
            
            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;

                my $content = $listitemdata_swt{$targetid}->{content};

                push @{$listitem_ref->{S0912}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0912'});

                push @{$normdata_ref->{swt}}, $content;

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0917/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0917";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;

                my $content = $listitemdata_swt{$targetid}->{content};

                push @{$listitem_ref->{S0917}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0917'});

                push @{$normdata_ref->{swt}}, $content;
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0922/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0922";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;

                my $content = $listitemdata_swt{$targetid}->{content};

                push @{$listitem_ref->{S0922}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0922'});

                push @{$normdata_ref->{swt}}, $content;

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0927/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0927";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;

                my $content = $listitemdata_swt{$targetid}->{content};

                push @{$listitem_ref->{S0927}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0927'});

                push @{$normdata_ref->{swt}}, $content;

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0932/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0932";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;

                my $content = $listitemdata_swt{$targetid}->{content};

                push @{$listitem_ref->{S0932}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0932'});

                push @{$normdata_ref->{swt}}, $content;

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0937/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0937";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;

                my $content = $listitemdata_swt{$targetid}->{content};

                push @{$listitem_ref->{S0937}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0937'});

                push @{$normdata_ref->{swt}}, $content;

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0942/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0942";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;

                my $content = $listitemdata_swt{$targetid}->{content};

                push @{$listitem_ref->{S0942}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0942'});

                push @{$normdata_ref->{swt}}, $content;

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        elsif ($category=~m/^0947/){
            my ($targetid) = $content=~m/^IDN: (\d+)/;
            my $targettype = 4; # SWT
            my $sourceid   = $id;
            my $sourcetype = 1; # TIT
            my $supplement = "";
            my $category   = "0947";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_swt{$targetid}){
                push @swt, $targetid;

                my $content = $listitemdata_swt{$targetid}->{content};

                push @{$listitem_ref->{S0947}}, {
                    id         => $targetid,
                    type       => 'swt',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0947'});

                push @{$normdata_ref->{swt}}, $content;

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SWT ID $targetid doesn't exist in TIT ID $id");
            }
        }
        # Titeldaten
        else {
            # Alle Kategorien werden gemerkt
            push @{$thisitem_ref->{"T".$category}}, {
                indicator => $indicator,
                content   => $content,
            };

            if (   exists $conv_config->{search_ejahr    }{$category}){
                push @ejahr, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            if (   exists $conv_config->{search_ejahrft  }{$category}){
                push @ejahrft, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            if (   exists $conv_config->{search_gtquelle }{$category}){
                push @gtquelle, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $conv_config->{search_hst      }{$category}){
                push @hst, OpenBib::Common::Util::grundform({
                    # Keine Uebergabe der Kategorie, da erstes Stopwort hier nicht entfernt werden soll
                    content  => $content,
                });
            }
            if (   exists $conv_config->{search_inhalt   }{$category}){
                push @inhalt, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $conv_config->{search_isbn     }{$category}){

                my $isbnnorm = OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
                
                push @isbn, $isbnnorm;

                # Alternative ISBN zur Rechercheanreicherung erzeugen
                my $isbn = Business::ISBN->new($isbnnorm);

                if (defined $isbn && $isbn->is_valid){
                    my $isbnXX;
                    if (length($isbnnorm) == 10){
                        $isbnXX = $isbn->as_isbn13;
                    }
                    else {
                        $isbnXX = $isbn->as_isbn10;
                    }

                    if (defined $isbnXX){
                        if (!exists $normdata_ref->{isbn13}){
                            $normdata_ref->{isbn13} = OpenBib::Common::Util::grundform({
                                category => $category,
                                content  => $isbnXX->as_isbn13->as_string,
                            });
                        }

                        push @isbn,      OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $isbnXX->as_string,
                        });
                    }
                }

            }
            elsif (exists $conv_config->{search_issn     }{$category}){
                push @issn,      OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $conv_config->{search_artinh   }{$category}){
                push @artinh, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $conv_config->{search_verf     }{$category}){
                push @titverf, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $conv_config->{search_kor      }{$category}){
                push @titkor, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }
            elsif (exists $conv_config->{search_swt      }{$category}){
                push @titswt, OpenBib::Common::Util::grundform({
                    category => $category,
                    content  => $content,
                });
            }

            if ($category && $content){
                print OUT       "$id$category$indicator$content\n";

		if ($category eq "0800"){ # Medienart
		  push @{$normdata_ref->{mart}}, $content;
		}

		if ($category eq "0015"){ # Sprache
		  push @{$normdata_ref->{spr}}, $content;
		}

                if ($category eq "0425" || $category eq "0424"){ # Jahr
		  push @{$normdata_ref->{year}}, $content;
		}

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
truncate table popularity;
truncate table search;
truncate table titlistitem;
load data infile '$dir/conn.mysql'        into table conn   fields terminated by '' ;
load data infile '$dir/popularity.mysql'  into table popularity fields terminated by '' ;
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
    untie %listitemdata_not;
    untie %listitemdata_swt;
    untie %listitemdata_mex;
    untie %listitemdata_superid;
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
