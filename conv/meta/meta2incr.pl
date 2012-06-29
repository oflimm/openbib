#!/usr/bin/perl

#####################################################################
#
#  meta2incr.pl
#
#  Generierung von Update-Dateien als Differenz des aktuellen
#  Datenabzugs zu den aktuellen Katalogdaten in OpenBib
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
use strict;
use warnings;

use DB_File;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use MLDBM qw(DB_File Storable);
use Storable ();
use YAML;

use OpenBib::Common::Util;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Conv::Config;
use OpenBib::Statistics;

my ($database,$logfile);

&GetOptions(
	    "database=s"    => \$database,
            "logfile=s"     => \$logfile,
	    );

my $config      = OpenBib::Config->instance;
my $conv_config = new OpenBib::Conv::Config({dbname => $database});

$logfile=($logfile)?$logfile:"/var/log/openbib/meta2incr-$database.log";

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

my %normdata_db_per              = ();
my %normdata_db_koe              = ();
my %normdata_db_sys              = ();
my %normdata_db_swd              = ();
my %normdata_db_tit              = ();
my %normdata_db_mex              = ();

my %normdata_file_per              = ();
my %normdata_file_koe              = ();
my %normdata_file_sys              = ();
my %normdata_file_swd              = ();
my %normdata_file_tit              = ();
my %normdata_file_mex              = ();

tie %normdata_db_per,                'MLDBM', "./normdata_db_per.db"
     or die "Could not tie normdata for current content in db_per.\n";

tie %normdata_db_koe,                'MLDBM', "./normdata_db_koe.db"
     or die "Could not tie normdata for current content in db_koe.\n";

tie %normdata_db_sys,                'MLDBM', "./normdata_db_sys.db"
     or die "Could not tie normdata for current content in db_sys.\n";

tie %normdata_db_swd,                'MLDBM', "./normdata_db_swd.db"
     or die "Could not tie normdata for current content in db_swd.\n";

tie %normdata_db_tit,                'MLDBM', "./normdata_db_tit.db"
     or die "Could not tie normdata for current content in db_tit.\n";

tie %normdata_db_mex,                'MLDBM', "./normdata_db_mex.db"
     or die "Could not tie normdata for current content in db_mex.\n";

# tie %normdata_file,              'MLDBM', "./normdata_file.db"
#     or die "Could not tie normdata for current file.\n";

my $dbh = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd}) or $logger->error_die($DBI::errstr);

######################################################################3
# Personen-Daten
######################################################################3

$logger->info("Einlesen der aktuellen Personen aus der DB");

my $request=$dbh->prepare("select * from aut where category=100 or category=101");

$request->execute;

my $maxdate=0;

my $i=1;
while (my $result=$request->fetchrow_hashref){
    my $id       = $result->{id};
    my $category = $result->{category};
    my ($day,$month,$year) = $result->{content} =~/(\d\d)\.(\d\d)\.(\d\d\d\d)/;

    my $thisdate = "$year$month$day";

    if ($thisdate > $maxdate){
        $maxdate=$thisdate;
    }

    if (!exists $normdata_db_per{$id}){
        $normdata_db_per{$id}={};
    }
    
    my $id_ref = $normdata_db_per{$id};
    
    $id_ref->{$category}= $thisdate;

    $normdata_db_per{$id}=$id_ref;
    
    if ($i % 10000 == 0){
        $logger->debug("$i done");
    }
    
    $i++;
}

$logger->info("Einlesen der aktuellen Datenlieferung aus Datei");

open(PER,   "gzip -dc unload.PER.gz|");
open(PEROUT,"|gzip > incr-unload.PER.gz");

binmode(PER,":utf8");
binmode(PEROUT,":utf8");

my ($id,$date_updated,$date_created);
my @buffer=();
my $is_newer=0;

while (<PER>){
    push @buffer, $_;

    if (/^0000:(\d+)/){        
        $id=$1;
        $normdata_file_per{$id}=1;
    }

    if (/^0100:(\d\d)\.(\d\d)\.(\d\d\d\d)/){
        $date_created="$3$2$1";

        if ($date_created > $maxdate){
            $is_newer=1;
        }
    }

    if (/^0101:(\d\d)\.(\d\d)\.(\d\d\d\d)/){
        $date_updated="$3$2$1";

        if ($date_updated > $maxdate){
            $is_newer=1;
        }
    }

    if (/^9999:/){
        if ($is_newer){
            $logger->info("Neue Person mit id $id gefunden");
            foreach my $category (@buffer){
                print PEROUT $category;
            }
        }

        @buffer=();
        $is_newer=0;
    }
}

close(PER);


$logger->info("Loeschsaetze erzeugen");

foreach my $db_id (keys %normdata_db_per){
    if (!exists $normdata_file_per{$db_id}){
       $logger->info("Person mit ID $db_id wurde geloescht");
       print PEROUT "0000:$db_id\n";
       print PEROUT "9999:\n";
    }
}

$logger->info("Stand in der DB fuer PER: $maxdate");

close(PEROUT);

######################################################################3
# Koerperschafts-Daten
######################################################################3

$logger->info("Einlesen der aktuellen Koerperschaftsdaten aus der DB");

$request=$dbh->prepare("select * from kor where category=100 or category=101");

$request->execute;

$maxdate=0;

$i=1;
while (my $result=$request->fetchrow_hashref){
    my $id       = $result->{id};
    my $category = $result->{category};
    my ($day,$month,$year) = $result->{content} =~/(\d\d)\.(\d\d)\.(\d\d\d\d)/;

    my $thisdate = "$year$month$day";

    if ($thisdate > $maxdate){
        $maxdate=$thisdate;
    }

    my $id_ref = $normdata_db_koe{$id};
    
    $id_ref->{$category}= $thisdate;

    $normdata_db_koe{$id}=$id_ref;
    
    if ($i % 10000 == 0){
        $logger->debug("$i done");
    }
    
    $i++;
}

$logger->info("Einlesen der aktuellen Datenlieferung aus Datei");

open(KOE,   "gzip -dc unload.KOE.gz|");
open(KOEOUT,"|gzip > incr-unload.KOE.gz");

binmode(KOE,":utf8");
binmode(KOEOUT,":utf8");

@buffer=();
$is_newer=0;

while (<KOE>){
    push @buffer, $_;

    if (/^0000:(\d+)/){        
        $id=$1;
        $normdata_file_koe{$id}=1;
    }

    if (/^0100:(\d\d)\.(\d\d)\.(\d\d\d\d)/){
        $date_created="$3$2$1";

        if ($date_created > $maxdate){
            $is_newer=1;
        }
    }

    if (/^0101:(\d\d)\.(\d\d)\.(\d\d\d\d)/){
        $date_updated="$3$2$1";

        if ($date_updated > $maxdate){
            $is_newer=1;
        }
    }

    if (/^9999:/){
        if ($is_newer){
            $logger->info("Neue Koerperschaft mit id $id gefunden");
            foreach my $category (@buffer){
                print KOEOUT $category;
            }
        }

        @buffer=();
        $is_newer=0;
    }
}

close(KOE);


$logger->info("Loeschsaetze erzeugen");

foreach my $db_id (keys %normdata_db_koe){
    if (!exists $normdata_file_koe{$db_id}){
       $logger->info("Koerperschaft mit ID $db_id wurde geloescht");
       print KOEOUT "0000:$db_id\n";
       print KOEOUT "9999:\n";
    }
}

$logger->info("Stand in der DB fuer KOE: $maxdate");

close(KOEOUT);

######################################################################3
# Systematik-Daten
######################################################################3

$logger->info("Einlesen der aktuellen Systematikdaten aus der DB");

$request=$dbh->prepare("select * from notation where category=100 or category=101");

$request->execute;

$maxdate=0;

$i=1;
while (my $result=$request->fetchrow_hashref){
    my $id       = $result->{id};
    my $category = $result->{category};
    my ($day,$month,$year) = $result->{content} =~/(\d\d)\.(\d\d)\.(\d\d\d\d)/;

    my $thisdate = "$year$month$day";

    if ($thisdate > $maxdate){
        $maxdate=$thisdate;
    }

    my $id_ref = $normdata_db_sys{$id};
    
    $id_ref->{$category}= $thisdate;

    $normdata_db_sys{$id}=$id_ref;
    
    if ($i % 10000 == 0){
        $logger->debug("$i done");
    }
    
    $i++;
}

$logger->info("Einlesen der aktuellen Datenlieferung aus Datei");

open(SYS,   "gzip -dc unload.SYS.gz|");
open(SYSOUT,"|gzip > incr-unload.SYS.gz");

binmode(SYS,":utf8");
binmode(SYSOUT,":utf8");

@buffer=();
$is_newer=0;

while (<SYS>){
    push @buffer, $_;

    if (/^0000:(\d+)/){        
        $id=$1;
        $normdata_file_sys{$id}=1;
    }

    if (/^0100:(\d\d)\.(\d\d)\.(\d\d\d\d)/){
        $date_created="$3$2$1";

        if ($date_created > $maxdate){
            $is_newer=1;
        }
    }

    if (/^0101:(\d\d)\.(\d\d)\.(\d\d\d\d)/){
        $date_updated="$3$2$1";

        if ($date_updated > $maxdate){
            $is_newer=1;
        }
    }

    if (/^9999:/){
        if ($is_newer){
            $logger->info("Neue Systematik mit id $id gefunden");
            foreach my $category (@buffer){
                print SYSOUT $category;
            }
        }

        @buffer=();
        $is_newer=0;
    }
}

close(SYS);


$logger->info("Loeschsaetze erzeugen");

foreach my $db_id (keys %normdata_db_sys){
    if (!exists $normdata_file_sys{$db_id}){
       $logger->info("Systematik mit ID $db_id wurde geloescht");
       print SYSOUT "0000:$db_id\n";
       print SYSOUT "9999:\n";
    }
}

$logger->info("Stand in der DB fuer SYS: $maxdate");

close(SYSOUT);

######################################################################3
# Schlagwort-Daten
######################################################################3

$logger->info("Einlesen der aktuellen Schlagwortdaten aus der DB");

$request=$dbh->prepare("select * from swt where category=100 or category=101");

$request->execute;

$maxdate=0;

$i=1;
while (my $result=$request->fetchrow_hashref){
    my $id       = $result->{id};
    my $category = $result->{category};
    my ($day,$month,$year) = $result->{content} =~/(\d\d)\.(\d\d)\.(\d\d\d\d)/;

    my $thisdate = "$year$month$day";

    if ($thisdate > $maxdate){
        $maxdate=$thisdate;
    }

    my $id_ref = $normdata_db_swd{$id};
    
    $id_ref->{$category}= $thisdate;

    $normdata_db_swd{$id}=$id_ref;
    
    if ($i % 10000 == 0){
        $logger->debug("$i done");
    }
    
    $i++;
}

$logger->info("Einlesen der aktuellen Datenlieferung aus Datei");

open(SWD,   "gzip -dc unload.SWD.gz|");
open(SWDOUT,"|gzip > incr-unload.SWD.gz");

binmode(SWD,":utf8");
binmode(SWDOUT,":utf8");

@buffer=();
$is_newer=0;

while (<SWD>){
    push @buffer, $_;

    if (/^0000:(\d+)/){        
        $id=$1;
        $normdata_file_swd{$id}=1;
    }

    if (/^0100:(\d\d)\.(\d\d)\.(\d\d\d\d)/){
        $date_created="$3$2$1";

        if ($date_created > $maxdate){
            $is_newer=1;
        }
    }

    if (/^0101:(\d\d)\.(\d\d)\.(\d\d\d\d)/){
        $date_updated="$3$2$1";

        if ($date_updated > $maxdate){
            $is_newer=1;
        }
    }

    if (/^9999:/){
        if ($is_newer){
            $logger->info("Neues Schlagwort mit id $id gefunden");
            foreach my $category (@buffer){
                print SWDOUT $category;
            }
        }

        @buffer=();
        $is_newer=0;
    }
}

close(SWD);

$logger->info("Loeschsaetze erzeugen");

foreach my $db_id (keys %normdata_db_swd){
    if (!exists $normdata_file_swd{$db_id}){
       $logger->info("Schlagwort mit ID $db_id wurde geloescht");
       print SWDOUT "0000:$db_id\n";
       print SWDOUT "9999:\n";
    }
}

$logger->info("Stand in der DB fuer SWD: $maxdate");

close(SWDOUT);

######################################################################3
# Titel-Daten
######################################################################3

$logger->info("Einlesen der aktuellen Titeldaten aus der DB");

$request=$dbh->prepare("select * from tit where category=2 or category=3");

$request->execute;

$maxdate=0;

$i=1;
while (my $result=$request->fetchrow_hashref){
    my $id       = $result->{id};
    my $category = $result->{category};
    my ($day,$month,$year) = $result->{content} =~/(\d\d)\.(\d\d)\.(\d\d\d\d)/;

    my $thisdate = "$year$month$day";

    if ($thisdate > $maxdate){
        $maxdate=$thisdate;
    }

    my $id_ref = $normdata_db_tit{$id};
    
    $id_ref->{$category}= $thisdate;

    $normdata_db_tit{$id}=$id_ref;
    
    if ($i % 10000 == 0){
        $logger->debug("$i done");
    }
    
    $i++;
}

$logger->info("Einlesen der aktuellen Datenlieferung aus Datei");

open(TIT,   "gzip -dc unload.TIT.gz|");
open(TITOUT,"|gzip > incr-unload.TIT.gz");

binmode(TIT,":utf8");
binmode(TITOUT,":utf8");

@buffer=();
$is_newer=0;

my %titid_to_add = ();

while (<TIT>){
    push @buffer, $_;

    if (/^0000:(\d+)/){        
        $id=$1;
        $normdata_file_tit{$id}=1;
    }

    if (/^0002:(\d\d)\.(\d\d)\.(\d\d\d\d)/){
        $date_created="$3$2$1";

        if ($date_created > $maxdate){
            $is_newer=1;
        }
    }

    if (/^0003:(\d\d)\.(\d\d)\.(\d\d\d\d)/){
        $date_updated="$3$2$1";

        if ($date_updated > $maxdate){
            $is_newer=1;
        }
    }

    if (/^9999:/){
        if ($is_newer){      
            $logger->info("Neuer Titel mit id $id gefunden");
            $titid_to_add{$id} = 1;
            foreach my $category (@buffer){
                print TITOUT $category;
            }
        }

        @buffer=();
        $is_newer=0;
    }
}

close(TIT);


$logger->info("Loeschsaetze erzeugen");

my %titid_to_remove = ();

foreach my $db_id (keys %normdata_db_tit){
    if (!exists $normdata_file_tit{$db_id}){
       $logger->info("Titel mit ID $db_id wurde geloescht");
       # Fuer Exemplardaten markieren
       $titid_to_remove{$db_id} =1 ;

       print TITOUT "0000:$db_id\n";
       print TITOUT "9999:\n";
    }
}

$logger->info("Stand in der DB fuer TIT: $maxdate");

close(TITOUT);


######################################################################3
# Exemplar-Daten
#
# Anders als die anderen Normdaten werden deren IDs dynamisch erzeugt und
# koennen daher differieren. Damit muss hier anders vorgegangen werden
#
# 1) Neue und geaenderte Saetze muessen hinten unter Generierung neuer
#    IDs angehaengt werden
# 2) Bestehende ID's zu geaenderten Saetzen muessen geloescht,
#    also entsprechende Loeschsaetze generiert werden. Zu loeschende Saetze
#    kennzeichnen sich dadurch, dass der zugehoeriger Titelsatz geloescht
#    oder geaendert wurde
######################################################################3

$logger->info("Einlesen der aktuellen Exemplardaten aus der DB");

# Hoechste ID bestimmen

my $maxid=0;

$request=$dbh->prepare("select max(id) as max_id from mex");

$request->execute;

while (my $result=$request->fetchrow_hashref){
    $maxid       = $result->{max_id};
}

$request=$dbh->prepare("select * from mex where category=4");

$request->execute;

$maxdate=0;

open(MEX,   "gzip -dc unload.MEX.gz|");
open(MEXOUT,"|gzip > incr-unload.MEX.gz");

binmode(MEX,":utf8");
binmode(MEXOUT,":utf8");

$i=1;
while (my $result=$request->fetchrow_hashref){
    my $id       = $result->{id};
    my $content  = $result->{content};

    if ($titid_to_remove{$content} || $titid_to_add{$content}){
       print MEXOUT "0000:$id\n";
       print MEXOUT "9999:\n";
    }

}

$logger->info("Einlesen der aktuellen Datenlieferung aus Datei");

@buffer=();
$is_newer=0;
my $titid;

while (<MEX>){
    push @buffer, $_;

    if (/^0004:(\d+)/){        
        $titid=$1;
        if ($titid_to_add{$titid}){
            $is_newer=1;
        }
    }

    if (/^9999:/){
        if ($is_newer){
            # IDs bei Mex sind dynamisch. Daher muessen neue Saetze
            # am Ende angehaengt werden.
            $maxid++;
            $buffer[0]="0000:$maxid\n";
            $logger->info("Neues Exemplar mit titid $titid als ID $maxid angehaengt");
            foreach my $category (@buffer){
                print MEXOUT $category;
            }
        }

        @buffer=();
        $is_newer=0;
    }
}

close(MEX);

close(MEXOUT)
