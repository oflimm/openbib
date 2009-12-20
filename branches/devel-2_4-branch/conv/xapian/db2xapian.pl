#!/usr/bin/perl

#####################################################################
#
#  db2xapian.pl
#
#  Dieses File ist (C) 2006-2007 Oliver Flimm <flimm@openbib.org>
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
use DBI;
use Encode qw(decode_utf8 encode_utf8);
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use Search::Xapian;
use String::Tokenizer;

use OpenBib::Config;
use OpenBib::Common::Util;

my ($database,$help,$logfile,$withfields);

&GetOptions("database=s"      => \$database,
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
  $logger->fatal("Kein Pool mit --database= ausgewaehlt");
  exit;
}

$logger->info("### POOL $database");

my $dbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$database;host=$config->{dbhost};port=$config->{dbport}", $config->{dbuser}, $config->{dbpasswd})
    or die "$DBI::errstr";


my $dbbasedir=$config->{xapian_index_base_path};

my $thisdbpath="$dbbasedir/$database";
if (! -d "$thisdbpath"){
    mkdir "$thisdbpath";
}

$logger->info("Loeschung des alten Index fuer Datenbank $database");

system("rm -f $thisdbpath/*");

$logger->info("Aufbau eines neuen  Index fuer Datenbank $database");

my $db = Search::Xapian::WritableDatabase->new( $thisdbpath, Search::Xapian::DB_CREATE_OR_OVERWRITE ) || die "Couldn't open/create Xapian DB $!\n";

# my $stopword_ref={};

# my @stopwordfiles=(
# 		  '/opt/openbib/ft/wordlists/de.txt',
# 		  '/opt/openbib/ft/wordlists/en.txt',
# 		  '/opt/openbib/ft/wordlists/fr.txt',
# 		  '/opt/openbib/ft/wordlists/nl.txt',
# 		 );

# foreach my $stopwordfile (@stopwordfiles){
#     open(SW,$stopwordfile);
#     while (my $stopword=<SW>){
#         chomp $stopword ;
#         $stopword = OpenBib::Common::Util::grundform({
#                         content  => $stopword,
#                     });
#
#         $stopword_ref->{$stopword}=1;
#     }
#     close(SW);
# }

my $tokenizer = String::Tokenizer->new();

my $request=$dbh->prepare("select count(b.id) as rowcount from search as a, titlistitem b where a.verwidn=b.id");
$request->execute();

my $res=$request->fetchrow_hashref;

my $rowcount=$res->{rowcount};

$request->finish();

$logger->info("Migration von $rowcount Titelsaetzen");

my $hitrange = 1000;

my $atime = new Benchmark;

for (my $offset=1;$offset<=$rowcount;$offset=$offset+$hitrange){
    my $atime = new Benchmark;

    my $request=$dbh->prepare("select b.id, a.verf, a.hst, a.kor, a.swt, a.notation, a.sign, a.ejahrft, a.isbn, a.issn, b.listitem from search as a, titlistitem b where a.verwidn=b.id limit $offset,$hitrange");
    $request->execute();

    my $count=1;
    while (my $res=$request->fetchrow_hashref) {
        my $id       = decode_utf8($res->{id});
        my $listitem = decode_utf8($res->{listitem});
        my $verf     = lc(decode_utf8($res->{verf}));
        my $hst      = lc(decode_utf8($res->{hst}));
        my $kor      = lc(decode_utf8($res->{kor}));
        my $swt      = lc(decode_utf8($res->{swt}));
        my $notation = lc(decode_utf8($res->{notation}));
        my $ejahr    = lc(decode_utf8($res->{ejahrft}));
        my $sign     = lc(decode_utf8($res->{sign}));
        my $isbn     = lc(decode_utf8($res->{isbn}));
        my $issn     = lc(decode_utf8($res->{issn}));

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
                next if (length($next) < 2 && $next !~ /\d/);
                # Naechstes, wenn schon gesehen 
                next if (exists $seen_token_ref->{$next});
                # Naechstes, wenn Stopwort
                #next if (exists $stopword_ref->{$next});

                $seen_token_ref->{$next}=1;
                
                # Token generell einfuegen
                $doc->add_term($next);

                push @saved_tokens, $next;
            }

            if ($withfields){
                foreach my $token (@saved_tokens) {
                    # Token in Feld einfuegen            
                    my $fieldtoken=$tokinfo_ref->{prefix}.$token;
                    $doc->add_term($fieldtoken);
                }
            }
        }
    
        $doc->set_data(encode_utf8($listitem));
    
        my $docid=$db->add_document($doc);

    }
    my $btime      = new Benchmark;
    my $timeall    = timediff($btime,$atime);
    my $resulttime = timestr($timeall,"nop");
    $resulttime    =~s/(\d+\.\d+) .*/$1/;

    my $sets_indexed = ($offset+$hitrange > $rowcount )?$rowcount-$offset:$offset+$hitrange; 
    $logger->info("$sets_indexed Saetze indexiert in $resulttime Sekunden");
}

my $btime      = new Benchmark;
my $timeall    = timediff($btime,$atime);
my $resulttime = timestr($timeall,"nop");
$resulttime    =~s/(\d+\.\d+) .*/$1/;

$logger->info("Gesamtzeit: $resulttime Sekunden");


sub print_help {
    print << "ENDHELP";
db2xapian.pl - Datenbank-Konnektor zum Aufbau eines Xapian-Index

   Optionen:
   -help                 : Diese Informationsseite
       
   -with-fields          : Aufbau von einzelnen Suchfeldern (nicht default)
   --database=...        : Angegebenen Datenpool verwenden

ENDHELP
    exit;
}
