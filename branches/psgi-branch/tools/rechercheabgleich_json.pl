#!/usr/bin/perl

#####################################################################
#
#  rechercheabgleich.pl
#
#  Abgleich des Bestandes eines Katalogs anhand von Suchkriterien
#  in einer CSV-Datei und Ausgabe bibliogr. Titelinformationen in
#  eine CSV-Datei
#
#  Dieses File ist (C) 2014 Oliver Flimm <flimm@openbib.org>
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

use LWP::UserAgent;
use HTTP::Request;

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use Getopt::Long;
use Text::CSV_XS;
use JSON::XS;
use YAML::Syck;

my ($database,$help,$logfile,$loglevel,$configfile,$inputfile,$outputfile);

&GetOptions("database=s"       => \$database,
            "logfile=s"        => \$logfile,
            "loglevel=s"       => \$loglevel,
            "configfile=s"     => \$configfile,
            "inputfilen=s"     => \$inputfile,
            "outputfile=s"     => \$outputfile,
	    "help"             => \$help
        );

if ($help || !$database || !$inputfile || !$outputfile){
    print_help();
}

$logfile=($logfile)?$logfile:'/var/log/openbib/rechercheabgleich.log';
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
our $convconfig = YAML::Syck::LoadFile($configfile);

my $client  = LWP::UserAgent->new;            # HTTP client

# Einlesen und Reorganisieren
my $outputencoding = ($convconfig->{outputencoding})?$convconfig->{outputencoding}:'utf8';
my $inputencoding  = ($convconfig->{encoding})?$convconfig->{encoding}:'utf8';

my $inputcsv = Text::CSV_XS->new ({
    'eol'         => $convconfig->{csv}{eol},
    'sep_char'    => $convconfig->{csv}{sep_char},
    'quote_char'  => $convconfig->{csv}{quote_char},
    'escape_char' => $convconfig->{csv}{escape_char},
});

my $outputcsv = Text::CSV_XS->new ({
    'eol'         => "\n",
    'sep_char'    => ";",
});

open my $in,   "<:encoding($inputencoding)",$inputfile;

my @cols = @{$inputcsv->getline ($in)};
my $row = {};
$inputcsv->bind_columns (\@{$row}{@cols});

my $out;

open $out, ">:encoding(utf8)", $outputfile;

my $out_ref = [];

# Input-CSV bildet Basis der Ausgabe
push @{$out_ref}, @cols;

# Folgende Informationen werden zusaetzlich ausgegeben

push @{$out_ref}, ('Treffer','Person','Titel','Zusatz','Jahr','Umfang','HSSVermerk','Bestand');

$outputcsv->print($out,$out_ref);

my $count = 0;
my $success_count = 0;

while ($inputcsv->getline ($in)){
    my $searchfields_ref = {};

    # Suchbegriffe entsprechend Konfiguration einlesen
    foreach my $col (@cols){
        my $searchfield        = $convconfig->{searchfield}{$col};

        next unless ($searchfield);
        
        my $searchfieldcontent = $row->{$col};
        push @{$searchfields_ref->{$searchfield}}, $searchfieldcontent; 
    }

    my $url_args = searchfields2args({ searchfields => $searchfields_ref });

    my $url = $convconfig->{searchurl_base}."?".$url_args;

    $logger->debug("$url");
    
    my $request = HTTP::Request->new(GET => $url);
    $request->content_type('application/json');
    
    my $response = $client->request($request);

    my $content_ref = decode_json($response->content);

    my $out_ref = [
    ];

    # Input-CSV-Werte hinzufuegen
    foreach my $col (@cols){
        push @$out_ref, $row->{$col};
    }

    # Treffer hinzufuegen

    push @$out_ref, $content_ref->{meta}{hits};
    
    if ($content_ref->{meta}{hits}){
        # Nur den ersten Treffer nehmen
        my $id = $content_ref->{records}[0]{id};

        if (!$id){
            $logger->error("No ID");
        }
        
        my $recordurl = $convconfig->{recordurl_base}."$id.json";
        
        my $recordrequest = HTTP::Request->new(GET => $recordurl);
        $recordrequest->content_type('application/json');
        
        my $recordresponse = $client->request($recordrequest);
        
        my $record_ref = decode_json($recordresponse->content);

        my @persons = ();
        my @titles = ();
        my @years = ();
        my @supplements = ();
        my @collations = ();
        my @hsss = ();
        my @holdings = ();

        foreach my $person (@{$record_ref->{fields}{'T0100'}}){
            push @persons, $person->{content};
        }

        foreach my $title (@{$record_ref->{fields}{'T0331'}}){
            push @titles, $title->{content};
        }

        foreach my $supplement (@{$record_ref->{fields}{'T0335'}}){
            push @supplements, $supplement->{content};
        }
        
        foreach my $year (@{$record_ref->{fields}{'T0425'}}){
            push @years, $year->{content};
        }

        foreach my $collation (@{$record_ref->{fields}{'T0433'}}){
            push @collations, $collation->{content};
        }

        foreach my $hss (@{$record_ref->{fields}{'T0519'}}){
            push @hsss, $hss->{content};
        }
        
        foreach my $item (@{$record_ref->{items}}){
            push @holdings, $item->{'X0014'}{content}." (".$item->{'X0016'}{content}.")";
        }

        push @$out_ref, (join(' ; ',@persons),join(' ; ',@titles),join(' ; ',@supplements),join(' ; ',@years),join(' ; ',@collations),join(' ; ',@hsss),join(' ; ',@holdings));
            
        $success_count++;
    }
    else {
        push @$out_ref, (' ',' ',' ',' ',' ',' ',' ');
                    
    }

    $outputcsv->print($out,$out_ref);

    $count++;
}

close $out;

$logger->info("$success_count von $count Titeln konnten gefunden werden.");

sub print_help {
    print << "HELP";
rechercheabgleich.pl - Abgleich eines Katalog-Bestandes anhand von Suchbegriffen in einer CSV-Datei und
                       Ausgabe der bibliogr. Titeldaten in eine csv-Datei

    rechercheabgleich.pl --database=dissertationen --inputfile=input.csv --outputfile=output.csv --configfile=config.yml
HELP
exit;
}

sub searchfields2args {
    my $args_ref = shift;

    my $searchfields_ref = $args_ref->{searchfields};

    my @url_args = ();

    foreach my $searchfield (keys %$searchfields_ref){
        next unless ($searchfield);        

        if (defined $convconfig->{filter}{$searchfield}{year_as_range}){
            push @url_args, $searchfield."_from=".($searchfields_ref->{$searchfield}[0] -  $convconfig->{filter}{year}{year_as_range}{range_before});
            push @url_args, $searchfield."_to=".($searchfields_ref->{$searchfield}[0] +  $convconfig->{filter}{year}{year_as_range}{range_after});
        }
        else {
            push @url_args, $searchfield."=".join(" ",@{$searchfields_ref->{$searchfield}});
        }
    }
        
    return join(";", @url_args);
}
