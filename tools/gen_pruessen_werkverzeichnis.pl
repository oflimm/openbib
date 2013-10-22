#!/usr/bin/perl

#####################################################################
#
#  gen_pruessen_werkverzeichnis.pl
#
#  Generierung des Werkverzeichnisses der Sammlung Pruessen in der USB
#
#  Dieses File ist (C) 2013 Oliver Flimm <flimm@openbib.org>
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

#####################################################################
# Einladen der benoetigten Perl-Module 
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
use YAML;

if ($#ARGV < 0){
    print_help();
}

my ($help,$sigel,$showall,$mode);

&GetOptions(
	    "help"    => \$help,
	    "sigel=s" => \$sigel,
	    "mode=s"  => \$mode,
	    "showall" => \$showall,
	    );

if ($help){
    print_help();
}

if (!$mode){
  $mode="tex";
}

if ($mode ne "tex" && $mode ne "pdf"){
  print "Mode muss enweder tex oder pdf sein.\n";
  exit;
}

my $logfile='/var/log/openbib/gen_pruessen_werkverzeichnis.log';

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

my $config      = OpenBib::Config->instance;
my $dbinfotable = OpenBib::Config::DatabaseInfoTable->instance;

my $catalog = OpenBib::Catalog::Factory->create_catalog({database => 'pruessen' });

# IDN's der Exemplardaten und daran haengender Titel anhand von Signaturanfaengen bestimmen

# Teilbestand Buchillustrationen

my $buchillustrationen_recordlist_by_year_ref = ();
my @buchillustrationen_available_years           = ();
my $buchillustrationen_year_max               = 0;
my $buchillustrationen_year_min               = 9999;

{
    my %buchillustrationen_available_years_map        = ();
    my %buchillustrationen_titidns = ();
    
    my $titles = $catalog->{schema}->resultset('TitleHolding')->search_rs(
        {
            'holding_fields.field' => 14,
            'holding_fields.content' => { '~' => '^PrüssenB-' },
        },
        {
            select   => ['titleid.id'],
            as       => ['thistitleid'],
            join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
            group_by => ['titleid.id'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    
    while (my $item = $titles->next){
        my $titleid = $item->{thistitleid};
        $buchillustrationen_titidns{$titleid}=1;    
    }
    
    foreach my $titidn (keys %buchillustrationen_titidns){
        my $record = new OpenBib::Record::Title({database => 'pruessen', id => $titidn})->load_full_record();
        
        my $normset = $record->get_fields;
        
        my ($year) = $normset->{T0425}[0]{content} =~m/(\d\d\d\d)/;
        
        next if ($normset->{T5001}[0]{content});
        
        #    print STDERR "Jahr: $year\n";
        #    print STDERR YAML::Dump($record),"\n";
        
        if ($year && $year > $buchillustrationen_year_max){
            $buchillustrationen_year_max = $year;
        }
        
        if ($year && $year < $buchillustrationen_year_min){
            $buchillustrationen_year_min = $year;
        }
        
        $buchillustrationen_available_years_map{$year} = 1;
        
        push @{$buchillustrationen_recordlist_by_year_ref->{$year}}, $record;
    }
    
    #print STDERR YAML::Dump($buchillustrationen_recordlist_by_year_ref),"\n";
    
    # Sortierung nach Titel innerhalb eines Jahres
    
    foreach my $year (sort keys %buchillustrationen_available_years_map){
        push @buchillustrationen_available_years, $year;

        my @recordlist = @{$buchillustrationen_recordlist_by_year_ref->{$year}};
        my @sorted_recordlist = sort by_title @recordlist;    
        $buchillustrationen_recordlist_by_year_ref->{$year} = \@sorted_recordlist;
    }
}

# Teilbestand Presseillustrationen

my $presseillustrationen_recordlist_by_year_ref = ();
my @presseillustrationen_available_years           = ();
my $presseillustrationen_year_max               = 0;
my $presseillustrationen_year_min               = 9999;

{
    my %presseillustrationen_available_years_map        = ();
    my %presseillustrationen_titidns = ();
    
    my $titles = $catalog->{schema}->resultset('TitleHolding')->search_rs(
        {
            'holding_fields.field' => 14,
            'holding_fields.content' => { '~' => '^PrüssenZ' },
        },
        {
            select   => ['titleid.id'],
            as       => ['thistitleid'],
            join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
            group_by => ['titleid.id'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    
    while (my $item = $titles->next){
        my $titleid = $item->{thistitleid};
        $presseillustrationen_titidns{$titleid}=1;    
    }
    
    foreach my $titidn (keys %presseillustrationen_titidns){
        my $record = new OpenBib::Record::Title({database => 'pruessen', id => $titidn})->load_full_record();
        
        my $normset = $record->get_fields;
        
        my ($year) = $normset->{T0425}[0]{content} =~m/(\d\d\d\d)/;
        
        next if ($normset->{T5001}[0]{content});
        
        #    print STDERR "Jahr: $year\n";
        #    print STDERR YAML::Dump($record),"\n";
        
        if ($year && $year > $presseillustrationen_year_max){
            $presseillustrationen_year_max = $year;
        }
        
        if ($year && $year < $presseillustrationen_year_min){
            $presseillustrationen_year_min = $year;
        }
        
        $presseillustrationen_available_years_map{$year} = 1;
        
        push @{$presseillustrationen_recordlist_by_year_ref->{$year}}, $record;
    }
    
    #print STDERR YAML::Dump($presseillustrationen_recordlist_by_year_ref),"\n";
    
    # Sortierung nach Titel innerhalb eines Jahres
    
    foreach my $year (sort keys %presseillustrationen_available_years_map){
        push @presseillustrationen_available_years, $year;

        my @recordlist = @{$presseillustrationen_recordlist_by_year_ref->{$year}};
        my @sorted_recordlist = sort by_title @recordlist;    
        $presseillustrationen_recordlist_by_year_ref->{$year} = \@sorted_recordlist;
    }
}


# Teilbestand Plakate

my $plakate_recordlist_by_year_ref = ();
my @plakate_available_years        = ();    
my $plakate_year_max               = 0;
my $plakate_year_min               = 9999;

{
    my %plakate_available_years_map        = ();
    my %plakate_titidns = ();
    
    my $titles = $catalog->{schema}->resultset('TitleHolding')->search_rs(
        {
            'holding_fields.field' => 14,
            'holding_fields.content' => { '~' => '^PrüssenP-' },
        },
        {
            select   => ['titleid.id'],
            as       => ['thistitleid'],
            join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
            group_by => ['titleid.id'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    
    while (my $item = $titles->next){
        my $titleid = $item->{thistitleid};
        $plakate_titidns{$titleid}=1;    
    }
    
    foreach my $titidn (keys %plakate_titidns){
        my $record = new OpenBib::Record::Title({database => 'pruessen', id => $titidn})->load_full_record();
        
        my $normset = $record->get_fields;
        
        my ($year) = $normset->{T0425}[0]{content} =~m/(\d\d\d\d)/;
        
        next if ($normset->{T5001}[0]{content});
        
        #    print STDERR "Jahr: $year\n";
        #    print STDERR YAML::Dump($record),"\n";
        
        if ($year && $year > $plakate_year_max){
            $plakate_year_max = $year;
        }
        
        if ($year && $year < $plakate_year_min){
            $plakate_year_min = $year;
        }
        
        $plakate_available_years_map{$year} = 1;
        
        push @{$plakate_recordlist_by_year_ref->{$year}}, $record;
    }
    
    #print STDERR YAML::Dump($plakate_recordlist_by_year_ref),"\n";
    
    # Sortierung nach Titel innerhalb eines Jahres
    
    foreach my $year (sort keys %plakate_available_years_map){
        push @plakate_available_years, $year;

        my @recordlist = @{$plakate_recordlist_by_year_ref->{$year}};
        my @sorted_recordlist = sort by_title @recordlist;    
        $plakate_recordlist_by_year_ref->{$year} = \@sorted_recordlist;
    }
}

# Teilbestand Werbe-Illustrationen

my $werbeillustrationen_recordlist_by_year_ref = {};
my @werbeillustrationen_available_years = ();
my $werbeillustrationen_year_max = 0;
my $werbeillustrationen_year_min = 9999;

{
    my %werbeillustrationen_available_years_map = ();
    my %werbeillustrationen_titidns = ();
    
    my $titles = $catalog->{schema}->resultset('TitleHolding')->search_rs(
        {
            'holding_fields.field' => 14,
            'holding_fields.content' => { '~' => '^PrüssenW-' },
        },
        {
            select   => ['titleid.id'],
            as       => ['thistitleid'],
            join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
            group_by => ['titleid.id'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    
    while (my $item = $titles->next){
        my $titleid = $item->{thistitleid};
        $werbeillustrationen_titidns{$titleid}=1;    
    }
    
    
    foreach my $titidn (keys %werbeillustrationen_titidns){
        my $record = new OpenBib::Record::Title({database => 'pruessen', id => $titidn})->load_full_record();
        
        my $normset = $record->get_fields;
        
        next if ($normset->{T5001}[0]{content});
        
        my ($year) = $normset->{T0425}[0]{content} =~m/(\d\d\d\d)/;
        
        if ($year && $year > $werbeillustrationen_year_max){
            $werbeillustrationen_year_max = $year
        }
        
        if ($year && $year < $werbeillustrationen_year_min){
            $werbeillustrationen_year_min = $year
        }
        
        $werbeillustrationen_available_years_map{$year} = 1;
        
        push @{$werbeillustrationen_recordlist_by_year_ref->{$year}}, $record;
    }
    
    # Sortierung nach Titel innerhalb eines Jahres
    
    foreach my $year (sort keys %werbeillustrationen_available_years_map){
        push @werbeillustrationen_available_years, $year;
        
        my @recordlist = @{$werbeillustrationen_recordlist_by_year_ref->{$year}};
        
        #    print STDERR YAML::Dump($plakate_recordlist_by_year_ref->{$year}),"\n";
        #    print STDERR YAML::Dump(\@recordlist),"\n";
        
        my @sorted_recordlist = sort by_title @recordlist;    
        $werbeillustrationen_recordlist_by_year_ref->{$year} = \@sorted_recordlist;
    }
}

# Teilbestand ExLibris

my $exlibris_recordlist_by_year_ref = {};
my @exlibris_available_years = ();
my $exlibris_year_max = 0;
my $exlibris_year_min = 9999;

{
    my %exlibris_available_years_map = ();
    my %exlibris_titidns = ();
    
    my $titles = $catalog->{schema}->resultset('TitleHolding')->search_rs(
        {
            'holding_fields.field' => 14,
            'holding_fields.content' => { '~' => '^PrüssenExl-' },
        },
        {
            select   => ['titleid.id'],
            as       => ['thistitleid'],
            join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
            group_by => ['titleid.id'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    
    while (my $item = $titles->next){
        my $titleid = $item->{thistitleid};
        $exlibris_titidns{$titleid}=1;    
    }
    
    foreach my $titidn (keys %exlibris_titidns){
        my $record = new OpenBib::Record::Title({database => 'pruessen', id => $titidn})->load_full_record();
        
        my $normset = $record->get_fields;
        
        next if ($normset->{T5001}[0]{content});
        
        my ($year) = $normset->{T0425}[0]{content} =~m/(\d\d\d\d)/;
        
        if ($year && $year > $exlibris_year_max){
            $exlibris_year_max = $year
        }
        
        if ($year && $year < $exlibris_year_min){
            $exlibris_year_min = $year
        }
        
        $exlibris_available_years_map{$year} = 1;
        
        push @{$exlibris_recordlist_by_year_ref->{$year}}, $record;
    }
    
    # Sortierung nach Titel innerhalb eines Jahres
    
    foreach my $year (sort keys %exlibris_available_years_map){
        push @exlibris_available_years, $year;

        my @recordlist = @{$exlibris_recordlist_by_year_ref->{$year}};
        
        #    print STDERR YAML::Dump($plakate_recordlist_by_year_ref->{$year}),"\n";
        #    print STDERR YAML::Dump(\@recordlist),"\n";
        
        my @sorted_recordlist = sort by_title @recordlist;    
        $exlibris_recordlist_by_year_ref->{$year} = \@sorted_recordlist;
    }
}

# Teilbestand Donkeypress etc.

my $donkeypress_recordlist_by_year_ref = {};
my @donkeypress_available_years = ();
my $donkeypress_year_max = 0;
my $donkeypress_year_min = 9999;

{
    my %donkeypress_available_years_map = ();
    my %donkeypress_titidns = ();
    
    my $titles = $catalog->{schema}->resultset('TitleHolding')->search_rs(
        {
            'holding_fields.field' => 14,
            'holding_fields.content' => { '~' => '^PrüssenPress-' },
        },
        {
            select   => ['titleid.id'],
            as       => ['thistitleid'],
            join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
            group_by => ['titleid.id'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    
    while (my $item = $titles->next){
        my $titleid = $item->{thistitleid};
        $donkeypress_titidns{$titleid}=1;    
    }
    
    foreach my $titidn (keys %donkeypress_titidns){
        my $record = new OpenBib::Record::Title({database => 'pruessen', id => $titidn})->load_full_record();
        
        my $normset = $record->get_fields;
        
        next if ($normset->{T5001}[0]{content});
        
        my ($year) = $normset->{T0425}[0]{content} =~m/(\d\d\d\d)/;
        
        if ($year && $year > $donkeypress_year_max){
            $donkeypress_year_max = $year
        }
        
        if ($year && $year < $donkeypress_year_min){
            $donkeypress_year_min = $year
        }
        
        $donkeypress_available_years_map{$year} = 1;
        
        push @{$donkeypress_recordlist_by_year_ref->{$year}}, $record;
    }
    
    # Sortierung nach Titel innerhalb eines Jahres
    
    foreach my $year (sort keys %donkeypress_available_years_map){
        push @donkeypress_available_years, $year;

        my @recordlist = @{$donkeypress_recordlist_by_year_ref->{$year}};
        
        #    print STDERR YAML::Dump($plakate_recordlist_by_year_ref->{$year}),"\n";
        #    print STDERR YAML::Dump(\@recordlist),"\n";
        
        my @sorted_recordlist = sort by_title @recordlist;    
        $donkeypress_recordlist_by_year_ref->{$year} = \@sorted_recordlist;
    }
}

# Teilbestand Bergisch Gladbach

my $gladbach_recordlist_by_year_ref = {};
my @gladbach_available_years = ();
my $gladbach_year_max = 0;
my $gladbach_year_min = 9999;

{
    my %gladbach_available_years_map = ();
    my %gladbach_titidns = ();
    
    my $titles = $catalog->{schema}->resultset('TitleHolding')->search_rs(
        {
            'holding_fields.field' => 14,
            'holding_fields.content' => { '~' => '^PrüssenBG-' },
        },
        {
            select   => ['titleid.id'],
            as       => ['thistitleid'],
            join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
            group_by => ['titleid.id'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    
    while (my $item = $titles->next){
        my $titleid = $item->{thistitleid};
        $gladbach_titidns{$titleid}=1;    
    }
    
    foreach my $titidn (keys %gladbach_titidns){
        my $record = new OpenBib::Record::Title({database => 'pruessen', id => $titidn})->load_full_record();
        
        my $normset = $record->get_fields;
        
        next if ($normset->{T5001}[0]{content});
        
        my ($year) = $normset->{T0425}[0]{content} =~m/(\d\d\d\d)/;
        
        if ($year && $year > $gladbach_year_max){
            $gladbach_year_max = $year
        }
        
        if ($year && $year < $gladbach_year_min){
            $gladbach_year_min = $year
        }
        
        $gladbach_available_years_map{$year} = 1;
        
        push @{$gladbach_recordlist_by_year_ref->{$year}}, $record;
    }
    
    # Sortierung nach Titel innerhalb eines Jahres
    
    foreach my $year (sort keys %gladbach_available_years_map){
        push @gladbach_available_years, $year;

        my @recordlist = @{$gladbach_recordlist_by_year_ref->{$year}};
        
        #    print STDERR YAML::Dump($plakate_recordlist_by_year_ref->{$year}),"\n";
        #    print STDERR YAML::Dump(\@recordlist),"\n";
        
        my @sorted_recordlist = sort by_title @recordlist;    
        $gladbach_recordlist_by_year_ref->{$year} = \@sorted_recordlist;
    }
}

# Teilbestand Verschiedenes

my $misc_recordlist_by_year_ref = {};
my @misc_available_years = ();
my $misc_year_max = 0;
my $misc_year_min = 9999;

{
    my %misc_available_years_map = ();
    my %misc_titidns = ();
    
    my $titles = $catalog->{schema}->resultset('TitleHolding')->search_rs(
        {
            'holding_fields.field' => 14,
            'holding_fields.content' => { '~' => '^PrüssenV-' },
        },
        {
            select   => ['titleid.id'],
            as       => ['thistitleid'],
            join     => ['titleid','holdingid', {'holdingid' => 'holding_fields' }],
            group_by => ['titleid.id'],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );
    
    
    while (my $item = $titles->next){
        my $titleid = $item->{thistitleid};
        $misc_titidns{$titleid}=1;    
    }
    
    foreach my $titidn (keys %misc_titidns){
        my $record = new OpenBib::Record::Title({database => 'pruessen', id => $titidn})->load_full_record();
        
        my $normset = $record->get_fields;
        
        next if ($normset->{T5001}[0]{content});
        
        my ($year) = $normset->{T0425}[0]{content} =~m/(\d\d\d\d)/;
        
        if ($year && $year > $misc_year_max){
            $misc_year_max = $year
        }
        
        if ($year && $year < $misc_year_min){
            $misc_year_min = $year
        }
        
        $misc_available_years_map{$year} = 1;
        
        push @{$misc_recordlist_by_year_ref->{$year}}, $record;
    }
    
    # Sortierung nach Titel innerhalb eines Jahres
    
    foreach my $year (sort keys %misc_available_years_map){
        push @misc_available_years, $year;

        my @recordlist = @{$misc_recordlist_by_year_ref->{$year}};
        
        #    print STDERR YAML::Dump($plakate_recordlist_by_year_ref->{$year}),"\n";
        #    print STDERR YAML::Dump(\@recordlist),"\n";
        
        my @sorted_recordlist = sort by_title @recordlist;    
        $misc_recordlist_by_year_ref->{$year} = \@sorted_recordlist;
    }    
}

my $outputbasename="pruessen-werkverzeichnis";

my $template = Template->new({
    LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
        INCLUDE_PATH   => $config->{tt_include_path},
        ABSOLUTE       => 1,
    }) ],
    #        INCLUDE_PATH   => $config->{tt_include_path},
    #        ABSOLUTE       => 1,
    OUTPUT_PATH   => '/var/www/',
    OUTPUT        => "$outputbasename.$mode",
});


#print STDERR YAML::Dump($plakate_recordlist_by_year_ref),"\n";

my $ttdata = {
    buchillustrationen_recordlist        => $buchillustrationen_recordlist_by_year_ref,
    buchillustrationen_available_years   => \@buchillustrationen_available_years,
    buchillustrationen_year_max          => $buchillustrationen_year_max,
    buchillustrationen_year_min          => $buchillustrationen_year_min,

    presseillustrationen_recordlist        => $presseillustrationen_recordlist_by_year_ref,
    presseillustrationen_available_years   => \@presseillustrationen_available_years,
    presseillustrationen_year_max          => $presseillustrationen_year_max,
    presseillustrationen_year_min          => $presseillustrationen_year_min,
    
    plakate_recordlist        => $plakate_recordlist_by_year_ref,
    plakate_available_years   => \@plakate_available_years,
    plakate_year_max          => $plakate_year_max,
    plakate_year_min          => $plakate_year_min,

    werbeillustrationen_recordlist      => $werbeillustrationen_recordlist_by_year_ref,
    werbeillustrationen_available_years => \@werbeillustrationen_available_years,
    werbeillustrationen_year_max        => $werbeillustrationen_year_max,
    werbeillustrationen_year_min        => $werbeillustrationen_year_min,

    exlibris_recordlist      => $exlibris_recordlist_by_year_ref,
    exlibris_available_years => \@exlibris_available_years,
    exlibris_year_max        => $exlibris_year_max,
    exlibris_year_min        => $exlibris_year_min,

    donkeypress_recordlist      => $donkeypress_recordlist_by_year_ref,
    donkeypress_available_years => \@donkeypress_available_years,
    donkeypress_year_max        => $donkeypress_year_max,
    donkeypress_year_min        => $donkeypress_year_min,

    misc_recordlist      => $misc_recordlist_by_year_ref,
    misc_available_years => \@misc_available_years,
    misc_year_max        => $misc_year_max,
    misc_year_min        => $misc_year_min,
    
    gladbach_recordlist      => $gladbach_recordlist_by_year_ref,
    gladbach_available_years => \@gladbach_available_years,
    gladbach_year_max        => $gladbach_year_max,
    gladbach_year_min        => $gladbach_year_min,

    new_record                    => sub {
        my $database = shift;
        my $id = shift;

        return OpenBib::Record::Title->new({database => $database, id => $id});
    },
    
    filterchars  => \&filterchars,
};

$template->process("pruessen_werkverzeichnis_$mode", $ttdata) || do { 
    print $template->error();
};

sub print_help {
    print "gen_pruessen_werkverzeichnis.pl - Generierung Band 2 des Werkverzeichnisses der Sammlung Pruessen in der USB\n";
    print "Optionen: \n";
    print "  -help                   : Diese Informationsseite\n";
    print "  --mode=[pdf|tex]        : Typ des Ausgabedokumentes\n";
    
    exit;
}

sub filterchars {
  my ($content)=@_;

  $content=~s///g;
  $content=~s/\$/\\\$/g;
  $content=~s/\&gt\;/\$>\$/g;
  $content=~s/\&lt\;/\$<\$/g;
  $content=~s/\{/\\\{/g;
  $content=~s/\}/\\\}/g;
  $content=~s/#/\\\#/g;

  # Entfernen
  $content=~s/đ//g;
  $content=~s/±//g;
  $content=~s/÷//g;
  $content=~s/·//g;
  $content=~s/×//g;
  $content=~s/¾//g;
  $content=~s/¬//g;
  $content=~s/¹//g;
  $content=~s/_//g;
  $content=~s/¸//g;
  $content=~s/þ//g;
  $content=~s/Ð//g;
  $content=~s/\^/\\\^\{\}/g;
  $content=~s/µ/\$µ\$/g;
  $content=~s/\&amp\;/\\&/g;
  $content=~s/\"/\'\'/g;
  $content=~s/\%/\\\%/g;
  $content=~s/ð/d/g;      # eth

  $content=~s/\x{02b9}//g;      #
  $content=~s/\x{02ba}//g;      #
  $content=~s/\x{02bb}//g;      #
  $content=~s/\x{02bc}//g;      #
  $content=~s/\x{0332}//g;      #
  $content=~s/\x{02b9}//g;      #

  $content = encode("utf8",$content);

  $content=~s/\x{cc}\x{8a}//g;  
  $content=~s/\x{cc}\x{81}//g;
  $content=~s/\x{cc}\x{82}//g;
  $content=~s/\x{cc}\x{84}//g;
  $content=~s/\x{cc}\x{85}//g;
  $content=~s/\x{cc}\x{86}//g;
  $content=~s/\x{cc}\x{87}//g;  
  $content=~s/\x{cc}\x{a7}//g;
  $content=~s/\x{c4}\x{99}/e/g;
  $content=~s/\x{c4}\x{90}/D/g;
  $content=~s/\x{c4}\x{85}/\\c{a}/g;
  $content=~s/\x{c5}\x{b3}/u/g;
  $content=~s/c\x{cc}\x{a8}/\\c{c}/g;

  # Umlaute
  #$content=~s/\&uuml\;/ü/g;
  #$content=~s/\&auml\;/ä/g;
  #$content=~s/\&Auml\;/Ä/g;
  #$content=~s/\&Uuml\;/Ü/g;
  #$content=~s/\&ouml\;/ö/g;
  #$content=~s/\&Ouml\;/Ö/g;
  #$content=~s/\&szlig\;/ß/g;

  # Caron
  #$content=~s/\&#353\;/\\v\{s\}/g; # s hacek
  #$content=~s/\&#352\;/\\v\{S\}/g; # S hacek
  #$content=~s/\&#269\;/\\v\{c\}/g; # c hacek
  #$content=~s/\&#268\;/\\v\{C\}/g; # C hacek
  #$content=~s/\&#271\;/\\v\{d\}/g; # d hacek
  #$content=~s/\&#270\;/\\v\{D\}/g; # D hacek
  #$content=~s/\&#283\;/\\v\{e\}/g; # d hacek
  #$content=~s/\&#282\;/\\v\{E\}/g; # D hacek
  #$content=~s/\&#318\;/\\v\{l\}/g; # l hacek
  #$content=~s/\&#317\;/\\v\{L\}/g; # L hacek
  #$content=~s/\&#328\;/\\v\{n\}/g; # n hacek
  #$content=~s/\&#327\;/\\v\{N\}/g; # N hacek
  #$content=~s/\&#345\;/\\v\{r\}/g; # r hacek
  #$content=~s/\&#344\;/\\v\{R\}/g; # R hacek
  #$content=~s/\&#357\;/\\v\{t\}/g; # t hacek
  #$content=~s/\&#356\;/\\v\{T\}/g; # T hacek
  #$content=~s/\&#382\;/\\v\{z\}/g; # n hacek
  #$content=~s/\&#381\;/\\v\{Z\}/g; # N hacek

  # Macron
  #$content=~s/\&#275\;/\\=\{e\}/g; # e oberstrich
  #$content=~s/\&#274\;/\\=\{E\}/g; # e oberstrich
  #$content=~s/\&#257\;/\\=\{a\}/g; # a oberstrich
  #$content=~s/\&#256\;/\\=\{A\}/g; # A oberstrich
  #$content=~s/\&#299\;/\\=\{i\}/g; # i oberstrich
  #$content=~s/\&#298\;/\\=\{I\}/g; # I oberstrich
  #$content=~s/\&#333\;/\\=\{o\}/g; # o oberstrich
  #$content=~s/\&#332\;/\\=\{O\}/g; # O oberstrich
  #$content=~s/\&#363\;/\\=\{u\}/g; # u oberstrich
  #$content=~s/\&#362\;/\\=\{U\}/g; # U oberstrich

  return $content;
}

# sub by_signature {
#     my %line1=%$a;
#     my %line2=%$b;

#     # Sortierung anhand erster Signatur
#     my $line1=(exists $line1{X0014}[0]{content} && defined $line1{X0014}[0]{content})?cleanrl($line1{X0014}[0]{content}):"0";
#     my $line2=(exists $line2{X0014}[0]{content} && defined $line2{X0014}[0]{content})?cleanrl($line2{X0014}[0]{content}):"0";

#     $line1 cmp $line2;
# }

sub by_title {
    my %line1=%{$a->get_fields()};
    my %line2=%{$b->get_fields()};

    my $line1=(exists $line1{T0331}[0]{content} && defined $line1{T0331}[0]{content})?cleanrl($line1{T0331}[0]{content}):"";
    my $line2=(exists $line2{T0331}[0]{content} && defined $line2{T0331}[0]{content})?cleanrl($line2{T0331}[0]{content}):"";

    $line1=OpenBib::Common::Stopwords::strip_first_stopword($line1);
    $line2=OpenBib::Common::Stopwords::strip_first_stopword($line2);
    
    $line1 cmp $line2;
}

sub cleanrl {
    my ($line)=@_;

    $line=~s/Ü/Ue/g;
    $line=~s/Ä/Ae/g;
    $line=~s/Ö/Oe/g;
    $line=lc($line);
    $line=~s/&(.)uml;/$1e/g;
    $line=~s/^ +//g;
    $line=~s/^¬//g;
    $line=~s/^"//g;
    $line=~s/^'//g;

    return $line;
}
