#!/usr/bin/perl

#####################################################################
#
#  wikipedia2enrich.pl
#
#  Extrahierung relevanter Artikel und der darin genannten Literatur
#  fuer eine Anreicherung per ISBN
#
#  Dieses File ist (C) 2008-2022 Oliver Flimm <flimm@openbib.org>
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

#use warnings;
#use strict;

use utf8;
use Encode;

use Business::ISBN;
use Encode qw/decode_utf8/;
use Getopt::Long;
use IO::File;
use IO::Uncompress::Gunzip;
use IO::Uncompress::Bunzip2;
use JSON::XS;
use Log::Log4perl qw(get_logger :levels);
use URI::Escape;
use XML::Twig;
use YAML;

use OpenBib::Config;
use OpenBib::Enrichment;
use OpenBib::Common::Util;

use vars qw($isbn_ref);
use vars qw($article_isbn_ref);
use vars qw($count);

# Autoflush
$|=1;

my ($help,$init,$import,$inputfile,$jsonfile,$related,$lang,$logfile,$loglevel);

my $lang2article_cat_ref = {
    'de' => '4200',
    'en' => '4201',
    'fr' => '4202',
};

my $lang2isbn_origin_ref = {
    'de' => '1',
    'en' => '2',
    'fr' => '3',
};

&GetOptions("help"        => \$help,
            "init"        => \$init,
            "import"      => \$import,
            "related"     => \$related,
            "lang=s"      => \$lang,
	    "inputfile=s" => \$inputfile,
	    "jsonfile=s"  => \$jsonfile,
	    "relatedfile=s"  => \$relatedfile,
            "loglevel=s"   => \$loglevel,
            "logfile=s"   => \$logfile,
	    );


if (!$lang || !$inputfile || !exists $lang2article_cat_ref->{$lang}){
   print_help();
}

my $config = new OpenBib::Config;

$logfile=($logfile)?$logfile:"/var/log/openbib/wikipedia-enrichmnt-$lang.log";
$loglevel=($loglevel)?$loglevel:"INFO";
$jsonfile=($jsonfile)?$jsonfile:"$inputfile.json";

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

# Verbindung zur SQL-Datenbank herstellen
my $enrichment = new OpenBib::Enrichment;

# Zuerst alle Anreicherungen loeschen
# Origin 30 = Wikipedia

my $origin = 30;

$logger->debug("Origin: $origin");

my $input_io;

if ($inputfile =~/\.gz$/){
    $input_io = IO::Uncompress::Gunzip->new($inputfile);
}
elsif ($inputfile =~/\.bz2$/){
    $input_io = IO::Uncompress::Bunzip2->new($inputfile);
}
else {
    $input_io = IO::File->new($inputfile);
}


$article_isbn_ref = {};

my $twig= XML::Twig->new(
    TwigHandlers => {
	"/mediawiki/siteinfo" => \&parse_siteinfo,
        "/mediawiki/page"     => \&parse_page,
    },
    );


if ($init){
    $logger->info("Loeschen der bisherigen Daten");
    
    $enrichment->init_enriched_content({ field => $lang2article_cat_ref->{$lang}, origin => $origin });
    $enrichment->get_schema->resultset('RelatedTitleByIsbn')->search_rs({ origin => $lang2isbn_origin_ref->{$lang} })->delete if ($related);

}

our $count=1;

our $article_tuple_count = 1;

our $enrich_data_by_isbn_ref = [];

$isbn_ref = {};

if ($importjson){
    if (! -e $jsonfile){
        $logger->error("JSON-Datei $jsonfile existiert nicht");
        exit;
    }
    open(JSON,$jsonfile);

    $logger->info("Einlesen und -laden der neuen Daten");

    while (<JSON>){
        my $item_ref = decode_json($_);

        push @{$enrich_data_by_isbn_ref},   $item_ref if (defined $item_ref->{isbn});
        $subject_tuple_count++;
        
        if ($count % 1000 == 0){
            $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
            $enrich_data_by_isbn_ref   = [];
        }
        $count++;
    }

    $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
    
    $logger->info("$subject_tuple_count Schlagwort-Tupel eingefuegt");

    if ($jsonfile){
        close(JSON);
    }
    
}
else {
    if ($jsonfile){
        open(JSON,">$jsonfile");
    }

    $logger->info("Einlesen und speichern der neuen Daten");

    $twig->safe_parse($input_io);
    
    $logger->info("$count done");
    
    if ($jsonfile){
        close(JSON);
    }

}

$logger->info("Ende und aus");

sub parse_page {
    my($t, $page)= @_;

    $logger->debug("Parsing page");
    
    my $id       = $page->first_child('id')->text() if ($page->first_child('id')->text());
    my $title    = $page->first_child('title')->text() if ($page->first_child('title')->text());

    return if $title =~m/^Wikipedia/;
    
    my $revision = $page->first_child('revision') if ($page->first_child('revision'));

    my $content  = $revision->first_child('text')->text() if ($revision->first_child('text')->text());

    my @isbns = ();

    # Zuerst 10-Stellige ISBN's
    while ($content=~m/ISBN\|?\s?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?(\d)-?([0-9xX])/g){
        my @result= ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);
        my $isbn=join('',@result);

        my $isbn10 = Business::ISBN->new($isbn);

        if (defined $isbn10 && $isbn10->is_valid){
           $isbn = $isbn10->as_isbn13->as_string;

        }
        else {
            next;
        }

        $isbn = OpenBib::Common::Util::normalize({
            field => 'T0540',
            content  => $isbn,
        });

	# Merken fuer Related
        $article_isbn_ref->{"$title"}{"$isbn"}=1;

	push @isbns, $isbn;
    }

    # Dann 13-Stellige ISBN's
    while ($content=~m/ISBN\|?\s?(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*(\d)-*([0-9xX])/g){
        my @result= ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);
        my $isbn=join('',@result);

        my $isbn13 = Business::ISBN->new($isbn);

        if (defined $isbn13 && $isbn13->is_valid){
           $isbn = $isbn13->as_isbn13->as_string;

        }
        else {
            next;
        }

        $isbn = OpenBib::Common::Util::normalize({
            field    => 'T0540',
            content  => $isbn,
        });

	# Merken fuer Related
        $article_isbn_ref->{"$title"}{"$isbn"}=1;

	push @isbns, $isbn;
    }

    if (@isbns){
	my @unique_isbns    = grep { ! $seen_terms{$_} ++ } @isbns;

	# Merken fuer Related
	foreach my $isbn (@unique_isbns){
	    push @{$isbn_ref->{"$isbn"}}, $title;	    
	}

	foreach my $isbn (@unique_isbns){
	    my $item_ref = {
		isbn     => $isbn,
		origin   => $origin,
		field    => $lang2article_cat_ref->{$lang},
		subfield => '',
		content  => $title,
	    };
	    
	    print JSON encode_json($item_ref),"\n" if ($jsonfile);
	    
	    push @{$enrich_data_by_isbn_ref}, $item_ref;
	    $article_tuple_count++;	    
	}	
    }

    if ($count % 1000 == 0){
	$logger->info("$count done");
	if ($import){
	    $enrichment->add_enriched_content({ matchkey => 'isbn',   content => $enrich_data_by_isbn_ref }) if (@$enrich_data_by_isbn_ref);
	    $enrich_data_by_isbn_ref   = [];
	}
    }
        
    $count++;
    
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
       
   --inputfile=...       : Dateiname des wikipedia-Dumps im XML-Format
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
