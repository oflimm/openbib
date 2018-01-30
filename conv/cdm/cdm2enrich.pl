#!/usr/bin/perl

#####################################################################
#
#  cdm2enrich.pl
#
#  Konvertierung und Import aus CDM in die Anreicherungs-DB
#
#  Dieses File ist (C) 2018 Oliver Flimm <flimm@openbib.org>
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

use Encode 'decode';
use Getopt::Long;
use Log::Log4perl qw(get_logger :levels);
use JSON::XS;
use XML::Twig;
use XML::Simple;

use YAML::Syck;

use OpenBib::Config;
use OpenBib::Conv::Common::Util;
use OpenBib::Enrichment;
use OpenBib::Catalog::Factory;

# Autoflush
$|=1;

my ($logfile,$loglevel,$database,$inputfile,$configfile);

&GetOptions(
    "inputfile=s"          => \$inputfile,
    "configfile=s"         => \$configfile,
    "database=s"           => \$database,
    "logfile=s"            => \$logfile,
    "loglevel=s"           => \$loglevel,
	    );

if (!$inputfile && !$configfile && !$origin && !$database){
    print << "HELP";
cdm2enrich.pl - Aufrufsyntax

    cdm2enrich.pl --inputfile=xxx --configfile=yyy.yml

      --inputfile=                 : Name der Eingabedatei
      --configfile=                : Name der Parametrisierungsdaei

      --database=                  : Name der Katalogdatenbank
      --origin=                    : Ursprungsid

HELP
exit;
}

$logfile=($logfile)?$logfile:'/var/log/openbib/cdm2enrich.log';
$loglevel=($loglevel)?$loglevel:'INFO';

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

# Ininitalisierung mit Config-Parametern
my $convconfig = YAML::Syck::LoadFile($configfile);

my $origin = $convconfig->{origin};

our $enrichment = new OpenBib::Enrichment;

$logger->info("Loeschen der bisherigen Daten mit Origin $origin");

$enrichment->init_enriched_content({ origin => $origin });

my $twig= XML::Twig->new(
   TwigHandlers => {
     "/metadata/record" => \&parse_titset
   }
 );


$twig->safe_parsefile($inputfile);

sub parse_titset {
    my($t, $titset)= @_;

    my $titleid;

    if(defined $titset->first_child($convconfig->{idfield}) && $titset->first_child($convconfig->{idfield})->text()){
	$titleid = $titset->first_child($convconfig->{idfield})->text()
    }

    my $enrich_ref = [
    ];

    foreach my $kateg (keys %{$convconfig->{mapping}}){
        my $mult = 1;

        if(defined $titset->first_child($kateg) && $titset->first_child($kateg)->text()){
            my $content = konv($titset->first_child($kateg)->text());
            
            if ($content){
		push @{$enrich_ref},{
		    titleid  => $titleid,
		    dbname   => $database,
                    origin   => $origin,
                    field    => $convconfig->{mapping}{$kateg},
		    subfield => 'e',
		    content  => $content,
		};
            }
        }
    }

    # Speichern in Enrichment-DB

    if ($logger->is_debug){
	$logger->debug("Adding ".YAML::Dump($enrich_ref));
    }
    
    $enrichment->add_enriched_content({ matchkey => "title", content => $enrich_ref });
    
    # Release memory of processed tree
    # up to here
    $t->purge();
}

sub konv {
    my ($content)=@_;

#    $content=~s/\&/&amp;/g;
    $content=~s/>/&gt;/g;
    $content=~s/</&lt;/g;

    return $content;
}

