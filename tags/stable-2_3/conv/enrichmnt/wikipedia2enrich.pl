#!/usr/bin/perl

#####################################################################
#
#  wikipedia2enrich.pl
#
#  Extrahierung relevanter Artikel fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2008 Oliver Flimm <flimm@openbib.org>
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
use Encode;

use Business::ISBN;
use Encode qw/decode_utf8/;
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use URI::Escape;
use XML::Twig;
use YAML;

use OpenBib::Config;
use OpenBib::Common::Util;

use vars qw($isbn_ref);
use vars qw($counter);

# Autoflush
$|=1;

my ($help,$importyml,$lang,$filename,$logfile);

my $lang2cat_ref = {
    'de' => '4200',
    'en' => '4201',
    'fr' => '4202',
};

&GetOptions("help"       => \$help,
            "import-yml" => \$importyml,
            "lang=s"     => \$lang,
	    "filename=s" => \$filename,
            "logfile=s"  => \$logfile,
	    );


if (!$lang || !$filename || !exists $lang2cat_ref->{$lang}){
   print_help();
}

my $config = OpenBib::Config->instance;

$logfile=($logfile)?$logfile:"/var/log/openbib/wikipedia-enrichmnt-$lang.log";

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

# Verbindung zur SQL-Datenbank herstellen
my $enrichdbh
    = DBI->connect("DBI:$config->{dbimodule}:dbname=$config->{enrichmntdbname};host=$config->{enrichmntdbhost};port=$config->{enrichmntdbport}", $config->{enrichmntdbuser}, $config->{enrichmntdbpasswd})
    or $logger->error_die($DBI::errstr);

# Zuerst alle Anreicherungen loeschen
# Origin 30 = Wikipedia
my $deleterequest = $enrichdbh->prepare("delete from normdata where category = ? and origin=30");
$deleterequest->execute($lang2cat_ref->{$lang});
my $insertrequest = $enrichdbh->prepare("insert into normdata values (?,30,?,?,?)");

$isbn_ref = {};

if ($importyml){
    $logger->info("Einladen der Daten aus YAML-Datei $filename");
    $isbn_ref = YAML::LoadFile($filename);
}
else {

   my $twig= XML::Twig->new(
      TwigHandlers => {
        "/mediawiki/siteinfo" => \&parse_siteinfo,
        "/mediawiki/page"     => \&parse_page,
      },
    );


   $counter  = 1;

   $logger->info("Datei $filename einlesen");

   $twig->safe_parsefile($filename);
   #$twig->parsefile($filename);

   $logger->info("In yml-Datei speichern");

   YAML::DumpFile("wikipedia-isbn-$lang.yml",$isbn_ref);
}

$logger->info("In Datenbank speichern");

foreach my $isbn (keys %$isbn_ref){
    my $indicator=1;
    my @sorted_articles = sort @{$isbn_ref->{$isbn}};
    foreach my $articlename (@sorted_articles){
        $insertrequest->execute($isbn,$lang2cat_ref->{$lang},$indicator,$articlename);
        $indicator++;
    }
}


$logger->info("Ende und aus");

sub parse_page {
    my($t, $page)= @_;

    my $id       = $page->first_child('id')->text() if ($page->first_child('id')->text());
    my $title    = $page->first_child('title')->text() if ($page->first_child('title')->text());

    my $revision = $page->first_child('revision') if ($page->first_child('revision'));

    my $content  = $revision->first_child('text')->text() if ($revision->first_child('text')->text());

    my $article_isbn_ref = {};
    # Zuerst 10-Stellige ISBN's
    while ($content=~m/(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/g){
        my @result= ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);
        my $isbn=join('',@result);

        my $isbn10 = Business::ISBN->new($isbn);

        if (defined $isbn10 && $isbn10->is_valid){
           $isbn = $isbn10->as_isbn13->as_string;

        }
        else {
            next;
        }

        $isbn = OpenBib::Common::Util::grundform({
            category => '0540',
            content  => $isbn,
        });

        $article_isbn_ref->{"$isbn"}=1;

    }

    # Dann 13-Stellige ISBN's
    while ($content=~m/(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/g){
        my @result= ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);
        my $isbn=join('',@result);

        my $isbn13 = Business::ISBN->new($isbn);

        if (defined $isbn13 && $isbn13->is_valid){
           $isbn = $isbn13->as_isbn13->as_string;

        }
        else {
            next;
        }

        $isbn = OpenBib::Common::Util::grundform({
            category => '0540',
            content  => $isbn,
        });

        $article_isbn_ref->{"$isbn"}=1;
    }

    foreach my $isbn (keys %$article_isbn_ref){
       push @{$isbn_ref->{"$isbn"}}, $title;
    }


    if ($counter % 1000 == 0){
        $logger->info("$counter done");
    }

    $counter++;
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}

sub parse_siteinfo {
    my($t, $siteinfo)= @_;

    my $sitename  = $siteinfo->first_child('sitename')->text() if ($siteinfo->first_child('sitename')->text());

    my $base      = $siteinfo->first_child('base')->text() if ($siteinfo->first_child('base')->text());

    $logger->info("Metadata: $sitename $base");

    # Release memory of processed tree
    # up to here
    $t->purge();
}

sub print_help {
    print << "ENDHELP";
wikipedia2enrich.pl - Einspielen von Wikipedia-Artikeln in Anreicherungs-DB

   Optionen:
   -help                 : Diese Informationsseite

   -import-yml           : Import der YAML-Datei
   --filename=...        : Dateiname des wikipedia-Dumps im XML-Format bzw.
                           der YAML-Datei mit den bereits verarbeiteten Daten
   --logfile=...         : Name der Log-Datei
   --lang=\[de\|en\|fr\]     : Sprache

       
Bsp:
  1) Analyse eines Wikipedia Dumps

     wikipedia2enrich.pl --filename=frwiki-20080305-pages-articles.xml --lang=fr

  2) Einladen der generierten

     wikipedia2enrich.pl -import-yml --filename=wikipedia-isbn-fr.yml --lang=fr
ENDHELP
    exit;
}
