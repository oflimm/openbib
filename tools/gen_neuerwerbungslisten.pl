#!/usr/bin/perl

#####################################################################
#
#  gen_neuerwerbungslisten.pl
#
#  Aufbau der Neuerwerbungslisten fuer ein Institut. Dabei Zugriff
#  auf Sybase-DBMS via DBD::Proxy fuer Erwerbungsinformationen und
#  lokal auf zugehoerige bibliogr. Daten via OpenBib::Record::Title
#
#  Dieses File ist (C) 2011-2015 Oliver Flimm <flimm@openbib.org>
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

use strict;
use warnings;

use Getopt::Long;
use OpenBib::Common::Util;
use OpenBib::Config;
use OpenBib::Config::DatabaseInfoTable;
use OpenBib::L10N;
use OpenBib::Record::Person;
use OpenBib::Record::CorporateBody;
use OpenBib::Record::Subject;
use OpenBib::Record::Classification;
use OpenBib::RecordList::Title;
use OpenBib::Search::Util;
use OpenBib::Template::Provider;

use Date::Calc qw(Days_in_Month check_date);
use DBI;
use Encode qw/decode_utf8 encode decode/;
use Log::Log4perl qw(get_logger :levels);
use Template;
use URI::Escape;
use YAML::Syck;

if ($#ARGV < 0){
    print_help();
}

our ($help,$configfile,$logfile,$month,$year);

&GetOptions(
	    "help"         => \$help,
	    "configfile=s" => \$configfile,
            "logfile=s"    => \$logfile,
            "month=s"      => \$month,
            "year=s"       => \$year,
	    );

$month   = sprintf "%02d", $month;

if ($help){
    print_help();
}


if (!$configfile || ! -e $configfile){
  print "Konfigurationsdatei nicht vorhanden.\n";
  exit;
}

if (!$month || !$year){
  print "Angebe von Jahr und Monat nicht vorhanden.\n";
  exit;
}

our $config      = OpenBib::Config->new;
our $dbinfotable = OpenBib::Config::DatabaseInfoTable->new;

$logfile=($logfile)?$logfile:"/var/log/openbib/gen_neuerwerbungslisten.log";

my $log4Perl_config = << "L4PCONF";
log4perl.rootLogger=INFO, LOGFILE, Screen
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

# Message Katalog laden
our $msg = OpenBib::L10N->get_handle('de') || $logger->error("L10N-Fehler");
$msg->fail_with( \&OpenBib::L10N::failure_handler );

our $acq_config = YAML::LoadFile($configfile);

my $dsn = sprintf "dbi:Proxy:%s;dsn=%s",$acq_config->{proxy}, $acq_config->{dsn_at_proxy};

our $dbh = DBI->connect($dsn, $acq_config->{dbuser}, $acq_config->{dbpasswd}) or $logger->error_die($DBI::errstr);

# Daten bestimmen

our $exclude_ref = {};

my $sql="select * from acq_fach order by fachbez";
my $request=$dbh->prepare($sql) or $logger->error($DBI::errstr);

$request->execute() or $logger->error($DBI::errstr);;

our $type_desc_ref = {};
our $types_ordered_ref = [];

while (my $result=$request->fetchrow_hashref()){
    my $type = $result->{'fachnr'};

    next unless ($acq_config->{valid_type}{$type});
    $type   = sprintf "%02d", $type;

    push @{$types_ordered_ref}, $type;
    
    $type_desc_ref->{"$type"}{$result->{'sprache'}}=decode_utf8($result->{'fachbez'});
}

print_startpage();

print_typepage();

#print_yearpage();

print_collection($month,$year);

print_indexpages('00'); # fuer Branch 00

sub print_startpage {

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $templatename = $config->{tt_acquisition_tname};

    $logger->debug("Template is $templatename");
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $acq_config->{dbname},
        templatename => $templatename,
    });

    $logger->debug("Using database/view specific Template $templatename");


    my $outputpath = $acq_config->{document_root_path}.$acq_config->{this_uri};
    my $outputbasename = "index.html";
    my $outputfile = "$outputpath/$outputbasename";

    $logger->debug("Output: Path: $outputpath - File: $outputbasename");
    
    if (! -d $outputpath){
        system("mkdir -p $outputpath");
    }
    
    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
#        OUTPUT_PATH   => $outputpath,
#        OUTPUT        => $outputbasename,
        RECURSION     => 1,
    });
    
    my $ttdata = {
	uri_escape => sub {
	    my $string = shift;
	    return uri_escape_utf8($string);
	},
        branch     => '00',
        dbinfo     => $dbinfotable,
        acq_config => $acq_config,
        config     => $config,
        msg        => $msg,
    };
    
    $template->process($templatename, $ttdata, $outputfile, binmode => ':utf8') || do {
        $logger->error("Template error:".$template->error());
    };
}

sub print_yearpage {

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $templatename = $config->{tt_acquisition_year_by_type_tname};

    $logger->debug("Template is $templatename");
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $acq_config->{dbname},
        templatename => $templatename,
    });

    $logger->debug("Using database/view specific Template $templatename");


    my $outputpath = $acq_config->{document_root_path}.$acq_config->{this_uri};
    my $outputbasename = "index.html";
    my $outputfile = "$outputpath/$outputbasename";
    
    $logger->debug("Output: Path: $outputpath - File: $outputbasename");
    
    if (! -d $outputpath){
        system("mkdir -p $outputpath");
    }
    
    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
#        OUTPUT_PATH   => $outputpath,
#        OUTPUT        => $outputbasename,
        RECURSION     => 1,
    });
    
    my $ttdata = {
	uri_escape => sub {
	    my $string = shift;
	    return uri_escape_utf8($string);
	},
        dbinfo     => $dbinfotable,
        acq_config => $acq_config,
        config     => $config,
        msg        => $msg,
    };
    
    $template->process($templatename, $ttdata, $outputfile, binmode => ':utf8') || do {
        $logger->error("Template error:".$template->error());
    };
}

sub print_typepage {

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $templatename = $config->{tt_acquisition_types_tname};

    $logger->debug("Template is $templatename");
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $acq_config->{dbname},
        templatename => $templatename,
    });

    $logger->debug("Using database/view specific Template $templatename");


    my $outputpath = $acq_config->{document_root_path}.$acq_config->{this_uri}."/00";
    my $outputbasename = "index.html";
    my $outputfile = "$outputpath/$outputbasename";
    
    $logger->debug("Output: Path: $outputpath - File: $outputbasename");
    
    if (! -d $outputpath){
        system("mkdir -p $outputpath");
    }
    
    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
#        OUTPUT_PATH   => $outputpath,
#        OUTPUT        => $outputbasename,
        RECURSION     => 1,
    });
    
    my $ttdata = {
	uri_escape => sub {
	    my $string = shift;
	    return uri_escape_utf8($string);
	},
        type_desc     => $type_desc_ref,
        types_ordered => $types_ordered_ref,
        dbinfo        => $dbinfotable,
        acq_config    => $acq_config,
        config        => $config,
        msg           => $msg,
    };
    
    $template->process($templatename, $ttdata, $outputfile, binmode => ':utf8') || do {
        $logger->error("Template error:".$template->error());
    };

}

sub print_collection {
    my ($month,$year) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $sql="select katkey from titel_exclude";
    my $request=$dbh->prepare($sql) or $logger->error($DBI::errstr);
    
    $request->execute() or $logger->error($DBI::errstr);;
    
    while (my $result=$request->fetchrow_hashref()){
        $exclude_ref->{$result->{'katkey'}}=1;
    }
    
    my $last_day_in_month = sprintf "%02d", Days_in_Month( $year, $month );
    
    my $date_from = "01.$month.$year";
    my $date_to   = "$last_day_in_month.$month.$year";

    my $valid_type_string = join(", ",keys %{$acq_config->{valid_type}});
    
    $sql = << "SQL1";
select distinct katkey,fach,zweig
from rechkopf,rechbuch,acq_band,bestellung
where rechkopf.rnr = rechbuch.rnr
and rechbuch.bnr = acq_band.bnr
and rechbuch.band = acq_band.band
and rechbuch.bnr = bestellung.bnr
and not (verarbcode = 2)
and ivdatum >= convert(datetime,'$date_from',104)
and ivdatum <= convert(datetime,'$date_to',104)
and acq_band.fach in ($valid_type_string)
SQL1

    $request=$dbh->prepare($sql);
    
    $request->execute();
    
    my $recordlist_ref = {};

    while (my $result=$request->fetchrow_hashref()){
        my $katkey = $result->{katkey};
        my $type   = $result->{fach};
        my $branch = $result->{zweig};

        $branch = sprintf "%02d", $branch;
        $type   = sprintf "%02d", $type;

        next if ($exclude_ref->{$katkey});
        
        my $record = new OpenBib::Record::Title({database => $acq_config->{dbname}, id => $katkey, config => $config})->load_brief_record;
        
#        print YAML::Dump($record);

        push @{$recordlist_ref->{$branch}{$type}}, $record if ($record->record_exists);

        $logger->debug("Katkey: $katkey - Fach: $type - Zweigstelle: $branch");
    }
    
    my $templatename = $config->{tt_acquisition_collection_tname};

    $logger->debug("Template is $templatename");
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $acq_config->{dbname},
        templatename => $templatename,
    });

    $logger->debug("Using database/view specific Template $templatename");

    foreach my $branch (keys %{$recordlist_ref}){

        my $recordlist_all_types = new OpenBib::RecordList::Title;

        $logger->info("Processing branch $branch");
        
        foreach my $type (keys %{$recordlist_ref->{$branch}}){

            $logger->info("Processing type $type in branch $branch");

            my $recordlist = new OpenBib::RecordList::Title;
            
            foreach my $record (@{$recordlist_ref->{$branch}{$type}}){
                $recordlist->add($record);
                $recordlist_all_types->add($record);
            }

#            $recordlist->load_brief_records;
            
#            $logger->debug("Recordlist ".YAML::Dump($recordlist));
            $recordlist->sort({ type => "title", order => "asc"})  if ($recordlist_all_types->get_size() > 1);
            
            my $outputpath = $acq_config->{document_root_path}.$acq_config->{this_uri}."/$branch/$type/$year/$month/";
            my $outputbasename = "index.html";
            my $outputfile = "$outputpath/$outputbasename";
            
            $logger->debug("Output: Path: $outputpath - File: $outputbasename");
            
            if (! -d $outputpath){
                system("mkdir -p $outputpath");
            }
            
            my $template = Template->new({
                LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                    INCLUDE_PATH   => $config->{tt_include_path},
                    ABSOLUTE       => 1,
                }) ],
#                OUTPUT_PATH   => $outputpath,
#                OUTPUT        => $outputbasename,
                RECURSION     => 1,
            });

            my $ttdata = {
		uri_escape => sub {
		    my $string = shift;
		    return uri_escape_utf8($string);
		},
                month      => $month,
                year       => $year,
                branch     => $branch,
                type       => $type,
                type_desc  => $type_desc_ref,
                dbinfo     => $dbinfotable,
                acq_config => $acq_config,
                config     => $config,
                recordlist => $recordlist,
                msg        => $msg,
            };

            $template->process($templatename, $ttdata, $outputfile, binmode => ':utf8') || do {
                $logger->error("Template error:".$template->error());
            };


            # Indexinformation schreiben

            my $count = $recordlist->get_size();
            my $indexfile = $acq_config->{document_root_path}.$acq_config->{this_uri}."/$branch/$type/".$year."_".$month;
            system("rm ".$indexfile."_*.idx");
            system("touch ".$indexfile."_".$count.".idx");
        }
        
        # Faecheruebergreifend
        my $outputpath = $acq_config->{document_root_path}.$acq_config->{this_uri}."/$branch/00/$year/$month/";
        my $outputbasename = "index.html";
        my $outputfile = "$outputpath/$outputbasename";

        $logger->debug("Output: Path: $outputpath - File: $outputbasename");
        
        if (! -d $outputpath){
            system("mkdir -p $outputpath");
        }

#        $recordlist_all_types->load_brief_records;
        
        $recordlist_all_types->sort({ type => "title", order => "asc"}) if ($recordlist_all_types->get_size() > 1);
        
        my $template = Template->new({
            LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
                INCLUDE_PATH   => $config->{tt_include_path},
                ABSOLUTE       => 1,
            }) ],
#            OUTPUT_PATH    => $outputpath,
#            OUTPUT         => $outputbasename,
            RECURSION      => 1,
        });

        my $ttdata = {
	    uri_escape => sub {
		my $string = shift;
		return uri_escape_utf8($string);
	    },
            month      => $month,
            year       => $year,
            branch     => $branch,
            type       => '00',
            type_desc  => $type_desc_ref,
            dbinfo     => $dbinfotable,
            config     => $config,
            acq_config => $acq_config,
            recordlist => $recordlist_all_types,
            msg        => $msg,
        };
        
        $template->process($templatename, $ttdata, $outputfile, binmode => ':utf8') || do {
            $logger->error("Template error:".$template->error());
        };

        # Indexinformation schreiben
        
        my $count = $recordlist_all_types->get_size();
        my $indexfile = $acq_config->{document_root_path}.$acq_config->{this_uri}."/$branch/".$year."_".$month;
        system("rm ".$indexfile."_*.idx");
        system("touch ".$indexfile."_".$count.".idx");

    }

    return;
}

sub print_indexpages {
    my ($branch) = @_;

    # Log4perl logger erzeugen
    my $logger = get_logger();

    my $templatename = $config->{tt_acquisition_index_tname};

    $logger->debug("Template is $templatename");
    
    $templatename = OpenBib::Common::Util::get_cascaded_templatepath({
        database     => $acq_config->{dbname},
        templatename => $templatename,
    });

    $logger->debug("Using database/view specific Template $templatename");

    
    # Zuerst fachuebergreifend
    
    my $all_type_files = $acq_config->{document_root_path}.$acq_config->{this_uri}."/$branch/*.idx";
    
    my @all_types = glob "$all_type_files";

    my $index_info_ref = [];
    foreach my $indexfile (reverse sort @all_types) {
        $logger->debug("Indexfile $indexfile");
        my ($year,$month,$count) = $indexfile =~m/(\d\d\d\d)_(\d\d)_(\d+).idx$/;

        push @{$index_info_ref}, {
            year      => $year,
            month     => $month,
            itemcount => $count,
        };        
    }

    my $outputpath = $acq_config->{document_root_path}.$acq_config->{this_uri}."/$branch/00";
    my $outputbasename = "index.html";
    my $outputfile = "$outputpath/$outputbasename";
    
    $logger->debug("Output: Path: $outputpath - File: $outputbasename");
    
    if (! -d $outputpath){
        system("mkdir -p $outputpath");
    }

    my $template = Template->new({
        LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
            INCLUDE_PATH   => $config->{tt_include_path},
            ABSOLUTE       => 1,
        }) ],
#        OUTPUT_PATH    => $outputpath,
#        OUTPUT         => $outputbasename,
        RECURSION      => 1,
    });
    
    my $ttdata = {
	uri_escape => sub {
	    my $string = shift;
	    return uri_escape_utf8($string);
	},
        branch     => $branch,
        index_info => $index_info_ref,
        type       => '00',
        type_desc  => $type_desc_ref,
        dbinfo     => $dbinfotable,
        config     => $config,
        acq_config => $acq_config,
        msg        => $msg,
    };
    
    $template->process($templatename, $ttdata, $outputfile, binmode => ':utf8') || do {
        $logger->error("Template error:".$template->error());
    };
    
    
    # dann pro Fach

    foreach my $type (keys %{$acq_config->{valid_type}}){
        $type = sprintf "%02d", $type;

        my $this_type_files = $acq_config->{document_root_path}.$acq_config->{this_uri}."/$branch/$type/*.idx";
    
        my @this_type = glob "$this_type_files";

        my $index_info_ref = [];
        foreach my $indexfile (reverse sort @this_type) {
           $logger->debug("Indexfile $indexfile");
           my ($year,$month,$count) = $indexfile =~m/(\d\d\d\d)_(\d\d)_(\d+).idx$/;

           push @{$index_info_ref}, {
               year      => $year,
               month     => $month,
               itemcount => $count,
           };        
       }

       my $outputpath = $acq_config->{document_root_path}.$acq_config->{this_uri}."/$branch/$type";
       my $outputbasename = "index.html";
       my $outputfile = "$outputpath/$outputbasename";
    
       $logger->debug("Output: Path: $outputpath - File: $outputbasename");
    
       if (! -d $outputpath){
           system("mkdir -p $outputpath");
       }

       my $template = Template->new({
           LOAD_TEMPLATES => [ OpenBib::Template::Provider->new({
               INCLUDE_PATH   => $config->{tt_include_path},
               ABSOLUTE       => 1,
           }) ],
#           OUTPUT_PATH    => $outputpath,
#           OUTPUT         => $outputbasename,
           RECURSION      => 1,
       });
    
       my $ttdata = {
	   uri_escape => sub {
	       my $string = shift;
	       return uri_escape_utf8($string);
	   },
           branch     => $branch,
           index_info => $index_info_ref,
           type       => $type,
           type_desc  => $type_desc_ref,
           dbinfo     => $dbinfotable,
           config     => $config,
           acq_config => $acq_config,
           msg        => $msg,
       };
    
       $template->process($templatename, $ttdata, $outputfile, binmode => ':utf8') || do {
           $logger->error("Template error:".$template->error());
       };
   }
}

sub print_help {
    print "gen-neuerwerbungslisten.pl - Erzeugen von Neuerwerbungslisten fuer einen Katalog\n\n";
    print "Optionen: \n";
    print "  -help                    : Diese Informationsseite\n";
    print "  --configfile=inst431.yml : Sigel der Bibliothek\n";
    
    exit;
}
