#!/usr/bin/perl
####################################################################
#
#  openbib_aufsatz2sikis.pl
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

use utf8;

use warnings;
use strict;

use Getopt::Long;
use OpenBib::Catalog::Subset;
use OpenBib::Common::Stopwords;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Template::Provider;

use DBIx::Class::ResultClass::HashRefInflator;
use Encode qw/decode_utf8 encode decode/;
use Log::Log4perl qw(get_logger :levels);
use Template;
use JSON::XS;
use Encode qw/encode_utf8 decode_utf8/;
use YAML;

if ($#ARGV < 0){
    print_help();
}

our ($help,$database,$location);

&GetOptions(
    "help"       => \$help,
    "database=s" => \$database,
    "location=s" => \$location,
);

if ($help){
    print_help();
}

our $title_non_mult_fields_ref = {
    '0002' => 1,
    '0003' => 1,
    '0027' => 1,
    '0028' => 1,
    '0034' => 1,
    '0034' => 1,
    '0034' => 1,
    '0801' => 1,
    '0802' => 1,
    '0807' => 1,
    '0809' => 1,
    '0810' => 1,
    '1679' => 1,
    '5589' => 1,
};

our $title_blacklisted_fields_ref = {
    '0000' => 1,
    '0960' => 1,
    '0004' => 1,
    '5001' => 1,
    '5003' => 1,
    '5005' => 1,
    '5050' => 1,
    '5051' => 1,
    '4301' => 1,
    '4400' => 1,
    '4410' => 1,
};

my $logfile='/var/log/openbib/export_aufsatz2sikis.pl';

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=ERROR, LOGFILE, Screen
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

open(OUTTITLE,         ">:utf8","$database-unload.TIT");
open(OUTPERSON,        ">:utf8","$database-unload.PER");
open(OUTCORPORATEBODY, ">:utf8","$database-unload.KOE");
open(OUTCLASSIFICATION,">:utf8","$database-unload.SYS");
open(OUTSUBJECT,       ">:utf8","$database-unload.SWD");

my $config      = OpenBib::Config->new;

my $catalog = OpenBib::Catalog::Factory->create_catalog({database => $database });

my $titles_with_articles = $catalog->get_schema->resultset('Title')->search(
    {
        'title_fields.field' => '590',
    },
    {
        group_by => ['me.id','title_fields.titleid','title_fields.mult','title_fields.subfield','title_fields.content'],
        columns => ['me.id'],
        join => ['title_fields'],
    }
);

while (my $title = $titles_with_articles->next()){

    process_title($title->id);

}

close(OUTTITLE);
close(OUTPERSON);
close(OUTCORPORATEBODY);
close(OUTCLASSIFICATION);
close(OUTSUBJECT);

sub process_title {
    my $titleid = shift;

    my $record = OpenBib::Record::Title->new({ database => $database, id => $titleid})->load_full_record;

    print OUTTITLE "0000:$titleid\n";

    my $fields_ref = $record->get_fields;

    # Mit Informationen der Ueberordnung anreichern
    
    if (defined $fields_ref->{T5005}){
        foreach my $supertit_item_ref (@{$fields_ref->{T5005}}){
            eval {
                my $supertit_ref = decode_json encode_utf8($supertit_item_ref->{content});
                
                my $supertit_fields_ref = $supertit_ref->{fields};
                
                if (defined $supertit_fields_ref->{T0540}){
                    $fields_ref->{T0589} = $supertit_fields_ref->{T0540};
                    
                    $logger->info("ISBN angereichert");
                }
                if (defined $supertit_fields_ref->{T0553}){
                    $fields_ref->{T0589} = $supertit_fields_ref->{T0553};
                    
                    $logger->info("ISBN angereichert");
                }
                if (defined $supertit_fields_ref->{T0543}){
                    $fields_ref->{T0599} = $supertit_fields_ref->{T0543};
                    
                    $logger->info("ISSN angereichert");
                }
                
                # Soll der HST der Ueberordnung in einer Kategorie fuer die Verfuegbarkeitsrecherche gerettet werden?
                # Aber: Beisst sich mit der 'alten' 590
                if (defined $supertit_fields_ref->{T0331}){
                    $fields_ref->{T0599} = $supertit_fields_ref->{T0543};
                    
                    $logger->info("ISSN angereichert");
                }
            };
            
            if ($@){
                $logger->error($@);
            }
            
        }
    }

    # Standorte fuer jede Signatur setzen
    if (defined $fields_ref->{T0014}){
        $fields_ref->{T0016} = [];
        foreach my $mark_ref (@{$fields_ref->{T0014}}){
            my $location_ref = {
                content => $location,
                mult    => $mark_ref->{mult},
            };
            push @{$fields_ref->{T0016}}, $location_ref;
        }
    }
    
    # Felder ausgeben
    foreach my $field (sort keys %{$fields_ref}){
        my ($fieldno) = $field =~m/(\d\d\d\d)/;

        next if ($title_blacklisted_fields_ref->{$fieldno});
        
        foreach my $field_ref (@{$fields_ref->{$field}}){
#            print YAML::Dump($field_ref),"\n";

            $field_ref->{mult} = 1 unless $field_ref->{mult};
            
            my $field_string = sprintf "%04d.%03d:%s",$fieldno,$field_ref->{mult},konv($field_ref->{content});

            if ($title_non_mult_fields_ref->{$fieldno}){
                $field_string = sprintf "%04d:%s",$fieldno,konv($field_ref->{content});
            }
            
            if ($field_ref->{supplement}){
                $field_string.=" ".$field_ref->{supplement};
            }

            print OUTTITLE $field_string,"\n";
        }
    }

    print OUTTITLE "9999:\n";
    
}

sub konv {
    my $content = shift;

    $content =~s/\&gt;/>/g;
    $content =~s/\&lt;/</g;
    $content =~s/\&amp;/>\&/g;
    
    return $content;
}       

sub print_help {
    print "openbib_aufsatz2sikis.pl - Export von Aufsätze eines OpenBib-Katalogs im Sikis-Importformat\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n";
    print "  --database=             : Katalogname\n";
    
    exit;
}


