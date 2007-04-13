#!/usr/bin/perl

#####################################################################
#
#  file2xapian.pl
#
#  Dieses File ist (C) 2007 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;
use utf8;

BEGIN {
    $ENV{XAPIAN_PREFER_FLINT}    = '1';
    $ENV{XAPIAN_FLUSH_THRESHOLD} = '200000';
}

use Benchmark ':hireswallclock';
use DB_File;
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian;
use String::Tokenizer;

use OpenBib::Config;
use OpenBib::Common::Util;

my ($database,$help,$logfile,$withfields);

&GetOptions("single-pool=s"   => \$database,
            "logfile=s"       => \$logfile,
            "with-fields"     => \$withfields,
	    "help"            => \$help
	    );

if ($help){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/db2xapian.log';

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

my $config = new OpenBib::Config();

if (!$database){
  $logger->fatal("Kein Pool mit --single-pool= ausgewaehlt");
  exit;
}

$logger->info("### POOL $database");

my %xapian_idmapping;

tie %xapian_idmapping, 'DB_File', $config->{'autoconv_dir'}."/pools/$database/xapian_idmapping.db";

open(SEARCH,      "<:utf8","search.mysql"      ) || die "SEARCH konnte nicht geoeffnet werden";
open(TITLISTITEM, "<:utf8","titlistitem.mysql" ) || die "TITLISTITEM konnte nicht geoeffnet werden";

my $dbbasedir=$config->{xapian_index_base_path};

my $thisdbpath="$dbbasedir/$database";
if (! -d "$thisdbpath"){
    mkdir "$thisdbpath";
}

$logger->info("Loeschung des alten Index fuer Datenbank $database");

system("rm -f $thisdbpath/*");

$logger->info("Aufbau eines neuen  Index fuer Datenbank $database");

my $db = Search::Xapian::WritableDatabase->new( $thisdbpath, Search::Xapian::DB_CREATE_OR_OVERWRITE ) || die "Couldn't open/create Xapian DB $!\n";

my $stopword_ref={};

if (exists $config->{stopword_filename}){
    open(SW,$config->{stopword_filename});
    while (my $stopword=<SW>){
        chomp $stopword ;
        $stopword = OpenBib::Common::Util::grundform({
            content  => $stopword,
        });
        
        $stopword_ref->{$stopword}=1;
    }
    close(SW);
}

my $tokenizer = String::Tokenizer->new();

$logger->info("Migration der Titelsaetze");

my $atime = new Benchmark;
my $count = 1;
{
    my $atime = new Benchmark;
    while (my $search=<SEARCH>, my $titlistitem=<TITLISTITEM>) {
        my ($s_id,$verf,$hst,$kor,$swt,$notation,$sign,$ejahrint,$ejahr,$gtquelle,$isbn,$issn,$artinh)=split("",$search);
        my ($t_id,$listitem)=split ("",$titlistitem);
        if ($s_id != $t_id) {
            $logger->fatal("Id's stimmen nicht ueberein ($s_id != $t_id)!");
            next;
        }

        my $tokinfos_ref=[
            {
                prefix  => "X1",
                content => $verf,
            },
            {
                prefix  => "X2",
                content => $hst,
            },
            {
                prefix  => "X3",
                content => $kor,
            },
            {
                prefix  => "X4",
                content => $swt,
            },
            {
                prefix  => "X5",
                content => $notation,
            },
            {
                prefix  => "X6",
                content => $sign,
            },
            {
                prefix  => "X7",
                content => $ejahr,
            },
            {
                prefix  => "X8",
                content => $isbn,
            },
            {
                prefix  => "X9",
                content => $issn,
            },
        
        ];

        my $seen_token_ref = {};
        
        my $doc=Search::Xapian::Document->new();

        foreach my $tokinfo_ref (@$tokinfos_ref) {
            # Tokenize
            next if (! $tokinfo_ref->{content});
            
            $tokenizer->tokenize($tokinfo_ref->{content});
        
            my $i = $tokenizer->iterator();

            my @saved_tokens=();
            while ($i->hasNextToken()) {
                my $next = $i->nextToken();

                # Naechstes, wenn kein Token
                next if (!$next);
                # Naechstes, wenn keine Zahl oder einstellig
                # next if (length($next) < 2 && $next !~ /\d/);
                # Naechstes, wenn schon gesehen 
                next if (exists $seen_token_ref->{$next});
                # Naechstes, wenn Stopwort
                next if (exists $config->{stopword_filename} && exists $stopword_ref->{$next});

                $seen_token_ref->{$next}=1;
                
                # Token generell einfuegen
                $doc->add_term($next);

                push @saved_tokens, $next;
            }

            if ($withfields) {
                foreach my $token (@saved_tokens) {
                    # Token in Feld einfuegen            
                    my $fieldtoken=$tokinfo_ref->{prefix}.$token;
                    $doc->add_term($fieldtoken);
                }
            }
        }
    
        $doc->set_data(encode_utf8($listitem));
    
        my $docid=$db->add_document($doc);

        # Abspeichern des Mappings der SQL-ID zur Xapian-Doc-ID
        $xapian_idmapping{$s_id} = $docid;

        if ($count % 1000 == 0) {
            my $btime      = new Benchmark;
            my $timeall    = timediff($btime,$atime);
            my $resulttime = timestr($timeall,"nop");
            $resulttime    =~s/(\d+\.\d+) .*/$1/;
            $atime         = new Benchmark;
            $logger->info("$count Saetze indexiert in $resulttime Sekunden");
        }
    
        $count++;
    }
}

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");

untie(%xapian_idmapping);

sub print_help {
    print << "ENDHELP";
db2xapian.pl - Datenbank-Konnektor zum Aufbau eines Xapian-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   -with-fields          : Aufbau von einzelnen Suchfeldern (nicht default)
   --single-pool=...     : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
