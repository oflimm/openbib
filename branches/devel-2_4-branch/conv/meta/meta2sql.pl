#!/usr/bin/perl

#####################################################################
#
#  meta2sql.pl
#
#  Generierung von SQL-Einladedateien aus dem Meta-Format
#
#  Dieses File ist (C) 1997-2010 Oliver Flimm <flimm@openbib.org>
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
use Encode qw/decode_utf8/;
use Getopt::Long;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use MIME::Base64 ();
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML;

use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Record::Classification;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Person;
use OpenBib::Record::Subject;
use OpenBib::Record::Title;
use OpenBib::Statistics;

my ($database,$reducemem,$addsuperpers,$addmediatype,$incremental,$logfile,$loglevel,$count);

&GetOptions("reduce-mem"    => \$reducemem,
            "add-superpers" => \$addsuperpers,
            "add-mediatype" => \$addmediatype,
            "incremental"   => \$incremental,
	    "database=s"    => \$database,
            "logfile=s"     => \$logfile,
            "loglevel=s"    => \$loglevel,
	    );

my $config      = OpenBib::Config->instance;
my $conv_config = new OpenBib::Conv::Config({dbname => $database});

$logfile=($logfile)?$logfile:"/var/log/openbib/meta2sql-$database.log";
$loglevel=($loglevel)?$loglevel:"INFO";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=$loglevel, LOGFILE, Screen
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

my %listitemdata_person        = ();
my %listitemdata_corporatebody        = ();
my %listitemdata_classification        = ();
my %listitemdata_subject        = ();
my %listitemdata_holding        = ();
my %listitemdata_superid    = ();
my %listitemdata_popularity = ();
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
    tie %listitemdata_person,        'MLDBM', "./listitemdata_person.db"
        or die "Could not tie listitemdata_person.\n";
    
    tie %listitemdata_corporatebody,        'MLDBM', "./listitemdata_corporatebody.db"
        or die "Could not tie listitemdata_corporatebody.\n";

    tie %listitemdata_classification,        'MLDBM', "./listitemdata_classification.db"
        or die "Could not tie listitemdata_classification.\n";
 
    tie %listitemdata_subject,        'MLDBM', "./listitemdata_subject.db"
        or die "Could not tie listitemdata_subject.\n";

    tie %listitemdata_holding,        'MLDBM', "./listitemdata_holding.db"
        or die "Could not tie listitemdata_holding.\n";

    tie %listitemdata_superid,    "DB_File", "./listitemdata_superid.db"
        or die "Could not tie listitemdata_superid.\n";
}

my $local_enrichmnt  = 0;
my $enrichmntdumpdir = $config->{autoconv_dir}."/data/enrichment";

if (exists $conv_config->{local_enrichmnt} && -e "$enrichmntdumpdir/enrichmntdata.db"){
    tie %enrichmntdata,           'MLDBM', "$enrichmntdumpdir/enrichmntdata.db"
        or die "Could not tie enrichment data.\n";

    $local_enrichmnt = 1;

    $logger->info("Lokale Einspielung mit zentralen Anreicherungsdaten aktiviert");
}

if ($incremental){
    open(OUTDELETE, ">:utf8","delete.mysql") || die "OUTDELETE konnte nicht geoeffnet werden";
}

my $stammdateien_ref = {
    person => {
        type           => "person",
        infile         => "person.meta",
        outfile        => "person.mysql",
        outfile_ft     => "person_ft.mysql",
        outfile_string => "person_string.mysql",
        inverted_ref   => $conv_config->{inverted_person},
        blacklist_ref  => $conv_config->{blacklist_person},
    },
    
    corporatebody => {
        infile         => "corporatebody.meta",
        outfile        => "corporatebody.mysql",
        outfile_ft     => "corporatebody_ft.mysql",
        outfile_string => "corporatebody_string.mysql",
        inverted_ref   => $conv_config->{inverted_corporatebody},
        blacklist_ref  => $conv_config->{blacklist_corporatebody},
    },
    
    subject => {
        infile         => "subject.meta",
        outfile        => "subject.mysql",
        outfile_ft     => "subject_ft.mysql",
        outfile_string => "subject_string.mysql",
        inverted_ref   => $conv_config->{inverted_subject},
        blacklist_ref  => $conv_config->{blacklist_subject},
    },
    
    classification => {
        infile         => "classification.meta",
        outfile        => "classification.mysql",
        outfile_ft     => "classification_ft.mysql",
        outfile_string => "classification_string.mysql",
        inverted_ref   => $conv_config->{inverted_classification},
        blacklist_ref  => $conv_config->{blacklist_classification},
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
    if ($line=~m/^0000:(.+)$/){
      $id=$1;
      if ($incremental){
          print OUTDELETE "delete from ".$type." where id=$id;\n";
          print OUTDELETE "delete from ".$type."_string where id=$id;\n";
          print OUTDELETE "delete from ".$type."_ft where id=$id;\n";
      }
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
        if ($type eq "person"){
            $listitemdata_person{$id}=$content;
        }
        elsif ($type eq "corporatebody"){
            $listitemdata_corporatebody{$id}=$content;
        }
        elsif ($type eq "classification"){
            $listitemdata_classification{$id}=$content;
        }
        elsif ($type eq "subject"){
           $listitemdata_subject{$id}=$content;
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

       if (exists $stammdateien_ref->{$type}{inverted_ref}{$category}->{index}){
           foreach my $searchfield (keys %{$stammdateien_ref->{$type}{inverted_ref}{$category}->{index}}){
               push @{$stammdateien_ref->{$type}{data}{$id}{$searchfield}}, $contentnormtmp;               
           }
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

$stammdateien_ref->{holding} = {
    infile         => "holding.meta",
    outfile        => "holding.mysql",
    outfile_ft     => "holding_ft.mysql",
    outfile_string => "holding_string.mysql",
    inverted_ref   => $conv_config->{inverted_holding},
};

$logger->info("Bearbeite holding.meta");

open(IN ,          "<:utf8","holding.meta"         ) || die "IN konnte nicht geoeffnet werden";
open(OUT,          ">:utf8","holding.mysql"       ) || die "OUT konnte nicht geoeffnet werden";
open(OUTFT,        ">:utf8","holding_ft.mysql"    ) || die "OUTFT konnte nicht geoeffnet werden";
open(OUTSTRING,    ">:utf8","holding_string.mysql") || die "OUTSTRING konnte nicht geoeffnet werden";
open(OUTCONNECTION,">:utf8","conn.mysql")       || die "OUTCONNECTION konnte nicht geoeffnet werden";

my $id;
my $titleid;
CATLINE:
while (my $line=<IN>){
    my ($category,$indicator,$content);
    if ($line=~m/^0000:(.+)$/){
        $id=$1;
        $titleid=0;
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
    if ($category == 14 && $titleid){
        my $array_ref=exists $listitemdata_holding{$titleid}?$listitemdata_holding{$titleid}:[];
        push @$array_ref, $content;
        $listitemdata_holding{$titleid}=$array_ref;
    }
    
    my $contentnorm   = "";
    my $contentnormft = "";

    if ($category && $content){

        if (exists $stammdateien_ref->{holding}{inverted_ref}->{$category}){
            my $contentnormtmp = OpenBib::Common::Util::grundform({
                category => $category,
                content  => $content,
            });

            if ($stammdateien_ref->{holding}{inverted_ref}->{$category}->{string}){
                $contentnorm   = $contentnormtmp;
            }

            if ($stammdateien_ref->{holding}{inverted_ref}->{$category}->{ft}){
                $contentnormft = $contentnormtmp;
            }

            if (exists $stammdateien_ref->{holding}{inverted_ref}{$category}->{index}){
                foreach my $searchfield (keys %{$stammdateien_ref->{holding}{inverted_ref}{$category}->{index}}){
                    push @{$stammdateien_ref->{holding}{data}{$titleid}{$searchfield}}, $contentnormtmp;               
                }
            }
	}

        # Verknupefungen
        if ($category=~m/^0004/){
            my ($sourceid) = $content=~m/^(.+)/;
            my $sourcetype = 1; # TITLE
            my $targettype = 6; # HOLDING
            my $targetid   = $id;
            my $supplement = "";
            my $category   = "";
            $titleid         = $sourceid;

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

$stammdateien_ref->{title} = {
    infile         => "title.meta",
    outfile        => "title.mysql",
    outfile_ft     => "title_ft.mysql",
    outfile_string => "title_string.mysql",
    inverted_ref   => $conv_config->{inverted_title},
    blacklist_ref  => $conv_config->{blacklist_title},
};

if ($addsuperpers){
    $logger->info("Option addsuperpers ist aktiviert");
    $logger->info("1. Durchgang: Uebergeordnete Titel-ID's finden");
    open(IN ,           "<:utf8","title.meta"          ) || die "IN konnte nicht geoeffnet werden";

    while (my $line=<IN>){
        if ($line=~m/^0004.*?:(.+)/){
            my $superid=$1;
            $listitemdata_superid{$superid}=1;
        }
    }
    close(IN);

    $logger->info("2. Durchgang: Verfasser-ID's in uebergeordneten Titeln finden");
    open(IN ,           "<:utf8","title.meta"          ) || die "IN konnte nicht geoeffnet werden";

    my ($id,@persids);

    while (my $line=<IN>){
        if ($line=~m/^0000:(.+)$/){            
            $id=$1;
            @persids=();
        }
        elsif ($line=~m/^9999:/){
            if ($#persids >= 0){
                $listitemdata_superid{$id}=join(":",@persids);
            }
        }
        elsif ($line=~m/^010[0123].*?:IDN: (\S+)/){
            my $persid=$1;
            if (exists $listitemdata_superid{$id}){
                push @persids, $persid;
            }
        }
    }

    close(IN);
}

$logger->info("Bearbeite title.meta");

open(IN ,           "<:utf8","title.meta"          ) || die "IN konnte nicht geoeffnet werden";
open(OUT,           ">:utf8","title.mysql"        ) || die "OUT konnte nicht geoeffnet werden";
open(OUTFT,         ">:utf8","title_ft.mysql"     ) || die "OUTFT konnte nicht geoeffnet werden";
open(OUTSTRING,     ">:utf8","title_string.mysql" ) || die "OUTSTRING konnte nicht geoeffnet werden";
open(TITLELISTITEM, ">:utf8","title_listitem.mysql") || die "TITLELISTITEM konnte nicht goeffnet werden";
open(SEARCHENGINE,  ">:utf8","searchengine.csv" ) || die "SEARCHENGINE konnte nicht goeffnet werden";

my @person      = ();
my @corporatebody       = ();
my @subject       = ();
my @classification  = ();
my @hststring = ();
my @sign      = ();
my @isbn      = ();
my @issn      = ();
my @artinh    = ();
my @gtquelle  = ();
my @titleperson   = ();
my @titlecorporatebody    = ();
my @titlesubject    = ();
my @personcorporatebody    = ();
my @inhalt    = ();

my $listitem_ref={};
my $thisitem_ref={};

my $normdata_ref={};
$count=0;

CATLINE:
while (my $line=<IN>){
    my $searchfield_ref = {};
    my ($category,$indicator,$content);
    my ($sign,$isbn,$issn,$artinh);
    
    if ($line=~m/^0000:(.+)$/){
        $count++;
        $id=$1;
        
        if ($incremental){
            print OUTDELETE "delete from title where id=$id;\n";
            print OUTDELETE "delete from title_string where id=$id;\n";
            print OUTDELETE "delete from title_ft where id=$id;\n";
            print OUTDELETE "delete from title_listitem where id=$id;\n";
            print OUTDELETE "delete from popularity where id=$id;\n";
            print OUTDELETE "delete holding from holding inner join conn where conn.sourcetype=1 and conn.targettype=6 and conn.targetid=holding.id and conn.sourceid=$id;\n";
            print OUTDELETE "delete holding_string from holding inner join conn where conn.sourcetype=1 and conn.targettype=6 and conn.targetid=holding.id and conn.sourceid=$id;\n";
            print OUTDELETE "delete holding_ft from holding inner join conn where conn.sourcetype=1 and conn.targettype=6 and conn.targetid=holding.id and conn.sourceid=$id;\n";
            print OUTDELETE "delete from conn where sourceid=$id;\n";
        }

        $searchfield_ref = {};
        @person      = ();
        @corporatebody       = ();
        @subject       = ();
        @classification  = ();
        @hststrring= ();
        @sign      = ();
        @isbn      = ();
        @issn      = ();
        @artinh    = ();
        @gtquelle  = ();
        @inhalt    = ();
        @titleperson   = ();
        @titlecorporatebody    = ();
        @titlesubject    = ();
        @personcorporatebody    = ();

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
            foreach my $superid (@{$searchfield_ref->{subid}}){
                if (exists $listitemdata_superid{$superid}){
                    my @superpersids = split (":",$listitemdata_superid{$superid}); 
                    push @person, @superpersids;
                }
            }
        }
        
        # Zentrale Anreicherungsdaten lokal einspielen
        if ($local_enrichmnt && (exists $normdata_ref->{isbn13} || exists $normdata_ref->{issn})){
            foreach my $category (keys %{$conv_config->{local_enrichmnt}}){
                my $enrichmnt_data_ref = (exists $enrichmntdata{$normdata_ref->{isbn13}}{$category})?$enrichmntdata{$normdata_ref->{isbn13}}{$category}:
                    ($enrichmntdata{$normdata_ref->{issn}}{$category})?$enrichmntdata{$normdata_ref->{issn}}{$category}:undef;
                if ($enrichmnt_data_ref){
                    my $indicator = 1;
                    foreach my $content (@{$enrichmnt_data_ref}){
                        $content = decode_utf8($content);
                        
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });

                        # ToDo: Parametrisierbarkeit in convert.yml im Bereich search fuer
                        #       die Recherchierbarkeit via Suchmaschine
                        
                        $logger->debug("Id: $id - Adding $category -> $content");
                        print OUT       "$id$category$indicator$content\n";

                        # In aktuellem Satz merken
                        push @{$thisitem_ref->{"T".$category}}, {
                            indicator => $indicator,
                            content   => $content,
                        };

                        $indicator++;
                        # Normierung (String/Fulltext) der als invertierbar definierten Kategorien
                        if (exists $stammdateien_ref->{title}{inverted_ref}->{$category}){
                            if (exists $stammdateien_ref->{title}{inverted_ref}->{$category}->{string}){
                                print OUTSTRING "$id$category$contentnormtmp\n";
                            }
                            
                            if (exists $stammdateien_ref->{title}{inverted_ref}->{$category}->{ft}){
                                print OUTFT     "$id$category$contentnormtmp\n";
                            }
                            
                            if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                                foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                                    push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                                }
                            }

                            if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                                foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                                    push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                                }
                            }
                        }
                        
                        if (exists $conv_config->{'listitemcat'}{$category}){
                            push @{$listitem_ref->{"T".$category}}, {
                                content => $content,
                            };
                        }
                    }
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
                    if ($item->{content} eq "Aufsatz"){
                        $have_article = 1 ;
                    }
                    $type_indicator++;
                }

                if (!$have_article){
                    push @{$normdata_ref->{mart}}, "Aufsatz";

                    print OUT       "$id800$type_indicatorAufsatz\n";
                    my $contentnormtmp = OpenBib::Common::Util::grundform({
                        category => '800',
                        content  => 'Aufsatz',
                    });
                    print OUTSTRING "$id800$contentnormtmp\n";
                }
            }   

            # Elektronisches Medium mit Online-Zugriff
            # Besetzung der folgenden Kategorien
            # [02]807:g
            # 0334:Elektronische Ressource
            # 0652:Online-Ressource
            #
            # Lizensiert:
            # [02]663.001:Info: Zugriff nur im Hochschulnetz der Universitaet Koeln bzw.
            #          fuer autorisierte Benutzer moeglich
            
            if (((exists $thisitem_ref->{'T0807'} && $thisitem_ref->{'T0807'}[0]{content} eq "g") || (exists $thisitem_ref->{'T2807'} && $thisitem_ref->{'T2807'}[0]{content} eq "g"))
                && exists $thisitem_ref->{'T0334'} && $thisitem_ref->{'T0334'}[0]{content} eq "Elektronische Ressource"
                    && exists $thisitem_ref->{'T0652'} && $thisitem_ref->{'T0652'}[0]{content} eq "Online-Ressource"){
                # Steht Medientyp schon auf Online-Zugriff?
                my $have_ebook=0;
                my $type_indicator = 1;
                foreach my $item (@{$thisitem_ref->{'T0800'}}){
                    if ($item->{content} eq "E-Medium mit Online-Zugriff"){
                        $have_ebook = 1 ;
                    }
                    $type_indicator++;
                }

                if (!$have_ebook){
                    push @{$normdata_ref->{mart}}, "E-Medium mit Online-Zugriff";

                    print OUT       "$id800$type_indicatorE-Medium mit Online-Zugriff\n";
                    my $contentnormtmp = OpenBib::Common::Util::grundform({
                        category => '800',
                        content  => 'E-Medium mit Online-Zugriff',
                    });
                    print OUTSTRING "$id800$contentnormtmp\n";
                }
            }   
            
            # mit Inhaltsverzeichnis
            # Anreicherungskategorie 4110
            if (exists $thisitem_ref->{'T4110'}) {
                my $have_toc=0;
                my $type_indicator = 1;
                foreach my $item (@{$thisitem_ref->{'T0800'}}){
                    $have_toc = 1 if ($item->{content} eq "mit Inhaltsverzeichnis");
                    $type_indicator++;
                }

                if (!$have_toc){
                    push @{$normdata_ref->{mart}}, "mit Inhaltsverzeichnis";

                    print OUT       "$id800$type_indicatormit Inhaltsverzeichnis\n";
                    my $contentnormtmp = OpenBib::Common::Util::grundform({
                        category => '800',
                        content  => 'mit Inhaltsverzeichnis',
                    });
                    print OUTSTRING "$id800$contentnormtmp\n";
                }
            }   
            
	  }
        
        my @temp=();

        # Im Falle einer Personenanreicherung durch Ueberordnungen mit
        # -add-superpers sollen Dubletten entfernt werden.
        my %seen_person=();
        foreach my $item (@person){
            next if (exists $seen_person{$item});

            # ID-Merken fuer Recherche ueber Suchmaschine
            push @{$normdata_ref->{'personid'}}, $item;

            foreach my $searchfield (keys %{$stammdateien_ref->{person}{data}{$item}}){
                push @{$normdata_ref->{$searchfield}}, @{$stammdateien_ref->{person}{data}{$item}{$searchfield}};
            }

            $seen_person{$item}=1;
        }

        foreach my $item (@corporatebody){
            # ID-Merken fuer Recherche ueber Suchmaschine
            push @{$normdata_ref->{'corporatebodyid'}}, $item;

            foreach my $searchfield (keys %{$stammdateien_ref->{corporatebody}{data}{$item}}){
                push @{$normdata_ref->{$searchfield}}, @{$stammdateien_ref->{corporatebody}{data}{$item}{$searchfield}};
            }
        }

        foreach my $item (@subject){
            # ID-Merken fuer Recherche ueber Suchmaschine
            push @{$normdata_ref->{'subjectid'}}, $item;

            foreach my $searchfield (keys %{$stammdateien_ref->{subject}{data}{$item}}){
                push @{$normdata_ref->{$searchfield}}, @{$stammdateien_ref->{subject}{data}{$item}{$searchfield}};
            }
        }

        foreach my $item (@classification){
            # ID-Merken fuer Recherche ueber Suchmaschine
            push @{$normdata_ref->{'classificationid'}}, $item;

            foreach my $searchfield (keys %{$stammdateien_ref->{classification}{data}{$item}}){
                push @{$normdata_ref->{$searchfield}}, @{$stammdateien_ref->{classification}{data}{$item}{$searchfield}};
            }
        }

        foreach my $searchfield (keys %{$stammdateien_ref->{holding}{data}{$id}}){
            push @{$normdata_ref->{$searchfield}}, @{$stammdateien_ref->{holding}{data}{$item}{$searchfield}};
        }

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

        foreach my $content (@{$listitemdata_holding{$id}}){
            push @{$listitem_ref->{X0014}}, {
                content => $content,
            };
        }
        
        # Kombinierte Verfasser/Koerperschaft hinzufuegen fuer Sortierung
        push @{$listitem_ref->{'PC0001'}}, {
            content   => join(" ; ",@personcorporatebody),
        };
        
        # Kategorie 5050 wird *immer* angereichert. Die Invertierung ist konfigurabel
        my $bibkey_base = OpenBib::Common::Util::gen_bibkey_base({ normdata => $thisitem_ref});
        my $bibkey      = OpenBib::Common::Util::gen_bibkey({ bibkey_base => $bibkey_base });
        
        if ($bibkey){
            print OUT       "$id50501$bibkey\n";            
            print OUTSTRING "$id5050$bibkey\n" if (exists $stammdateien_ref->{title}{inverted_ref}->{'5050'}{string});
            print OUTSTRING "$id5051$bibkey_base\n" if (exists $stammdateien_ref->{title}{inverted_ref}->{'5051'}{string});

            # Bibkey merken fuer Recherche ueber Suchmaschine
            push @{$normdata_ref->{'bkey'}}, $bibkey;
        }

        # Hinweis: Weder das verpacken via pack "u" noch Base64 koennten
        # eventuell fuer die Recherche schnell genug sein. Allerdings
        # funktioniert es sehr gut.
        # Moegliche Alternativen
        # - Binaere Daten mit load data behandeln koennen
        # - Data::Dumper verwenden, da hier ASCII herauskommt
        # - in MLDB auslagern
        # - Kategorien als eigene Spalten

        my $listitem = "";

        if ($config->{internal_serialize_type} eq "packed_storable"){
            $listitem = unpack "H*",Storable::freeze($listitem_ref);
        }
        elsif ($config->{internal_serialize_type} eq "json"){
            $listitem = encode_json $listitem_ref;
        }
        else {
            $listitem = unpack "H*",Storable::freeze($listitem_ref);
        }

        print TITLELISTITEM "$id$listitem\n";
        
        my $normdatastring = encode_json $normdata_ref;
        print SEARCHENGINE "$id$normdatastring\n";


        if ($count % 1000 == 0) {
	     $logger->debug("$count Titelsaetze bearbeitet");
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
        next CATLINE if (exists $stammdateien_ref->{title}{blacklist_ref}->{$category});

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
        if (exists $stammdateien_ref->{title}{inverted_ref}->{$category}){
            my $contentnormtmp = OpenBib::Common::Util::grundform({
                category => $category,
                content  => $content,
            });

            if ($stammdateien_ref->{title}{inverted_ref}->{$category}->{string} || $stammdateien_ref->{title}{inverted_ref}->{$category}->{index}){
                $contentnorm   = $contentnormtmp;
            }

            if ($stammdateien_ref->{title}{inverted_ref}->{$category}->{ft}){
                $contentnormft = $contentnormtmp;
            }
        }

        # Parametrisierung fuer die Suchmaschine

        
        # Verknuepfungen
        if ($category=~m/^0004/){
            my ($targetid) = $content=~m/^(.+)/;
            my $targettype = 1; # TITLE
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";

            if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                    push @{$normdata_ref->{$searchfield}}, $targetid;
                }
            }
            
            if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                    push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                }
            }

            print OUT           "$id$category$indicator$content\n";
            print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
        }
        elsif ($category=~m/^0100/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 2; # PERSON
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0100";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # da schon vorhande -> dann aus DB holen
            if ($incremental && !exists $listitemdata_person{$targetid}){
                $listitemdata_person{$targetid} = OpenBib::Record::Person
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }
            
            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_person{$targetid}){
                push @person, $targetid;
                
                my $content = $listitemdata_person{$targetid};
                
                push @{$thisitem_ref->{"T".$category}}, {
                    indicator => $indicator,
                    content   => $content,
                };

                push @{$listitem_ref->{P0100}}, {
                    id      => $targetid,
                    type    => 'person',
                    content => $content,
                } if (exists $conv_config->{listitemcat}{'0100'});

                push @personcorporatebody, $content;

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){                    
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("PER ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0101/){
            my ($targetid)  = $content=~m/^IDN: (\S+)/;
            my $targettype  = 2; # PERSON
            my $sourceid    = $id;
            my $sourcetype  = 1; # TITLE
            my $supplement  = "";

            if ($content=~m/^IDN: \S+ ; (.+)/){
                $supplement = $1;
            }
            
            my $category="0101";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_person{$targetid}){
                $listitemdata_person{$targetid} = OpenBib::Record::Person
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_person{$targetid}){
                push @person, $targetid;
                
                my $content = $listitemdata_person{$targetid};
                
                push @{$thisitem_ref->{"T".$category}}, {
                    indicator  => $indicator,
                    content    => $content,
                    supplement => $supplement,
                };

                push @{$listitem_ref->{P0101}}, {
                    id         => $targetid,
                    type       => 'person',
                    content    => $content,
                    supplement => $supplement,
                } if (exists $conv_config->{listitemcat}{'0101'});

                push @personcorporatebody, $content;

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("PER ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0102/){
            my ($targetid)  = $content=~m/^IDN: (\S+)/;
            my $targettype  = 2; # PERSON
            my $sourceid    = $id;
            my $sourcetype  = 1; # TITLE
            my $supplement  = "";

            if ($content=~m/^IDN: \S+ ; (.+)/){
                $supplement = $1;
            }
            
            my $category="0102";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_person{$targetid}){
                $listitemdata_person{$targetid} = OpenBib::Record::Person
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_person{$targetid}){
                push @person, $targetid;
                
                my $content = $listitemdata_person{$targetid};
                
                push @{$listitem_ref->{P0102}}, {
                    id         => $targetid,
                    type       => 'person',
                    content    => $content,
                    supplement => $supplement,
                } if (exists $conv_config->{listitemcat}{'0102'});

                push @personcorporatebody, $content;
                
                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("PER ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0103/){
            my ($targetid)  = $content=~m/^IDN: (\S+)/;
            my $targettype  = 2; # PERSON
            my $sourceid    = $id;
            my $sourcetype  = 1; # TITLE
            my $supplement  = "";

            if ($content=~m/^IDN: \S+ ; (.+)/){
                $supplement = $1;
            }

            my $category="0103";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_person{$targetid}){
                $listitemdata_person{$targetid} = OpenBib::Record::Person
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_person{$targetid}){
                push @person, $targetid;
                
                my $content = $listitemdata_person{$targetid};
                
                push @{$listitem_ref->{P0103}}, {
                    id         => $targetid,
                    type       => 'person',
                    content    => $content,
                    supplement => $supplement,
                } if (exists $conv_config->{listitemcat}{'0103'});

                push @personcorporatebody, $content;

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("PER ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0200/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 3; # CORPORATEBODY
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0200";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_corporatebody{$targetid}){
                $listitemdata_corporatebody{$targetid} = OpenBib::Record::CorporateBody
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_corporatebody{$targetid}){
                push @corporatebody, $targetid;

                # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
                # dann aus DB holen
                if ($incremental && !exists $listitemdata_corporatebody{$targetid}){
                    $listitemdata_corporatebody{$targetid} = OpenBib::Record::CorporateBody
                        ->new({id => $targetid, database => $database})
                            ->load_name
                                ->name_as_string;
                }

                my $content = $listitemdata_corporatebody{$targetid};
                
                push @{$listitem_ref->{C0200}}, {
                    id         => $targetid,
                    type       => 'corporatebody',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0200'});

                push @personcorporatebody, $content;

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("CORPORATEBODY ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0201/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 3; # CORPORATEBODY
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0201";

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_corporatebody{$targetid}){
                push @corporatebody, $targetid;

                # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
                # dann aus DB holen
                if ($incremental && !exists $listitemdata_corporatebody{$targetid}){
                    $listitemdata_corporatebody{$targetid} = OpenBib::Record::CorporateBody
                        ->new({id => $targetid, database => $database})
                            ->load_name
                                ->name_as_string;
                }

                my $content = $listitemdata_corporatebody{$targetid};
                
                push @{$listitem_ref->{C0201}}, {
                    id         => $targetid,
                    type       => 'corporatebody',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0201'});

                push @personcorporatebody, $content;

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("CORPORATEBODY ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0700/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 5; # CLASSIFICATION
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0700";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_classification{$targetid}){
                $listitemdata_classification{$targetid} = OpenBib::Record::Classification
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_classification{$targetid}){
                push @classification, $targetid;
                
                my $content = $listitemdata_classification{$targetid};

                push @{$listitem_ref->{N0700}}, {
                    id         => $targetid,
                    type       => 'classification',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0700'});

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }                

                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SYS ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0710/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0710";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;
                 
                my $content = $listitemdata_subject{$targetid};
                
                push @{$listitem_ref->{S0710}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0710'});

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0902/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0902";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }
            
            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;

                my $content = $listitemdata_subject{$targetid};

                push @{$listitem_ref->{S0902}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0902'});
                
                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0907/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0907";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;

                my $content = $listitemdata_subject{$targetid};

                push @{$listitem_ref->{S0907}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0907'});
                
                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0912/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0912";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;
                
                my $content = $listitemdata_subject{$targetid};

                push @{$listitem_ref->{S0912}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0912'});

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0917/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0917";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }
            
            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;

                my $content = $listitemdata_subject{$targetid};

                push @{$listitem_ref->{S0917}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0917'});

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0922/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0922";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }
            
            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;

                my $content = $listitemdata_subject{$targetid};

                push @{$listitem_ref->{S0922}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0922'});

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0927/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0927";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }
            
            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;

                my $content = $listitemdata_subject{$targetid};

                push @{$listitem_ref->{S0927}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0927'});

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0932/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0932";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }
            
            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;

                my $content = $listitemdata_subject{$targetid};

                push @{$listitem_ref->{S0932}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0932'});

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0937/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0937";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }
            
            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;

                my $content = $listitemdata_subject{$targetid};

                push @{$listitem_ref->{S0937}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0937'});

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0942/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0942";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }

            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;

                my $content = $listitemdata_subject{$targetid};

                push @{$listitem_ref->{S0942}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0942'});

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        elsif ($category=~m/^0947/){
            my ($targetid) = $content=~m/^IDN: (\S+)/;
            my $targettype = 4; # SUBJECT
            my $sourceid   = $id;
            my $sourcetype = 1; # TITLE
            my $supplement = "";
            my $category   = "0947";

            # Ansetzungsform potentiell nicht in inkrementellen Daten dabei,
            # dann aus DB holen
            if ($incremental && !exists $listitemdata_subject{$targetid}){
                $listitemdata_subject{$targetid} = OpenBib::Record::Subject
                    ->new({id => $targetid, database => $database})
                        ->load_name
                            ->name_as_string;
            }
            
            # Es ist nicht selbstverstaendlich, dass ein verknuepfter Titel
            # auch wirklich existiert -> schlechte Katalogisate
            if (exists $listitemdata_subject{$targetid}){
                push @subject, $targetid;

                my $content = $listitemdata_subject{$targetid};

                push @{$listitem_ref->{S0947}}, {
                    id         => $targetid,
                    type       => 'subject',
                    content    => $content,
                } if (exists $conv_config->{listitemcat}{'0947'});

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                        my $contentnormtmp = OpenBib::Common::Util::grundform({
                            category => $category,
                            content  => $content,
                        });
                        push @{$normdata_ref->{$searchfield}}, $contentnormtmp;
                    }
                }

                if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                    foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                        push @{$normdata_ref->{"facet_".$searchfield}}, $content;
                    }
                }
                
                print OUTCONNECTION "$category$sourceid$sourcetype$targetid$targettype$supplement\n";
            }
            else {
                $logger->error("SUBJECT ID $targetid doesn't exist in TITLE ID $id");
            }
        }
        # Titeldaten
        else {
            # Alle Kategorien werden gemerkt
            push @{$thisitem_ref->{"T".$category}}, {
                indicator => $indicator,
                content   => $content,
            };

            if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{index}){
                foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{index}}){
                    if ($searchfield eq "isbn"){
                        # Alternative ISBN zur Rechercheanreicherung erzeugen
                        my $isbn = Business::ISBN->new($contentnorm);
                        
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
                                    my $isbn13 = OpenBib::Common::Util::grundform({
                                        category => $category,
                                        content  => $isbnXX->as_isbn13->as_string,
                                    });
                                    $normdata_ref->{isbn13} = $isbn13;
                                    push @{$normdata_ref->{fs}}, $contentnorm;
                                }
                            }
                        }
                    }
                    push @{$normdata_ref->{$searchfield}}, $contentnorm;
                }
            }

            if (exists $stammdateien_ref->{title}{inverted_ref}{$category}->{facet}){
                foreach my $searchfield (keys %{$stammdateien_ref->{title}{inverted_ref}{$category}->{facet}}){
                    push @{$normdata_ref->{"facet_".$searchfield}}, $content;
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
    }
}

if ($incremental){
    close(OUTDELETE);
}

close(OUT);
close(OUTFT);
close(OUTSTRING);
close(OUTCONNECTION);
close(SEARCHENGINE);
close(TITLELISTITEM);
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
print CONTROLINDEXOFF "alter table title_listitem disable keys;\n";

foreach my $type (keys %{$stammdateien_ref}){
    if (!$incremental){
        print CONTROL << "ITEMTRUNC";
truncate table $type;
truncate table ${type}_ft;
truncate table ${type}_string;
ITEMTRUNC
    }

    print CONTROL << "ITEM";
load data local infile '$dir/$stammdateien_ref->{$type}{outfile}'        into table $type        fields terminated by '' ;
load data local infile '$dir/$stammdateien_ref->{$type}{outfile_ft}'     into table ${type}_ft     fields terminated by '' ;
load data local infile '$dir/$stammdateien_ref->{$type}{outfile_string}' into table ${type}_string fields terminated by '' ;
ITEM
}

if (!$incremental){
    print CONTROL << "TITLEITEMTRUNC";
truncate table conn;
truncate table popularity;
truncate table title_listitem;
TITLEITEMTRUNC
}
    
print CONTROL << "TITLEITEM";
load data local infile '$dir/conn.mysql'        into table conn   fields terminated by '' ;
load data local infile '$dir/popularity.mysql'  into table popularity fields terminated by '' ;
load data local infile '$dir/title_listitem.mysql' into table title_listitem fields terminated by '' escaped by '';
TITLEITEM

foreach my $type (keys %{$stammdateien_ref}){
    print CONTROLINDEXON << "ENABLEKEYS";
alter table $type          enable keys;
alter table ${type}_ft     enable keys;
alter table ${type}_string enable keys;
ENABLEKEYS
}

print CONTROLINDEXON "alter table conn           enable keys;\n";
print CONTROLINDEXON "alter table title_listitem enable keys;\n";

close(CONTROL);
close(CONTROLINDEXOFF);
close(CONTROLINDEXON);

if ($reducemem){
    untie %listitemdata_person;
    untie %listitemdata_corporatebody;
    untie %listitemdata_classification;
    untie %listitemdata_subject;
    untie %listitemdata_holding;
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

 Titel                 (title)      -> numerische Typentsprechung: 1
 Verfasser/Person      (person)      -> numerische Typentsprechung: 2
 Koerperschaft/Urheber (corporatebody)      -> numerische Typentsprechung: 3
 Schlagwort            (subject)      -> numerische Typentsprechung: 4
 Notation/Systematik   (classification) -> numerische Typentsprechung: 5
 Exemplardaten         (holding)      -> numerische Typentsprechung: 6


 Die numerische Entsprechung wird bei der Verknuepfung einzelner Saetze
 zwischen den Normdaten in der Tabelle conn verwendet.

 Der Speicherverbrauch kann ueber die Option -reduce-mem durch
 Auslagerung der fuer den Aufbau der Kurztitel-Tabelle benoetigten
 Informationen reduziert werden.

=head1 AUTHOR

 Oliver Flimm <flimm@openbib.org>

=cut
