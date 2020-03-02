#!/usr/bin/perl
#####################################################################
#
#  find_parents_of_volumes_without_zbkunst.pl
#
#  Gesamttitel aufspueren, die selbst eine Markierung zb-kunst haben, deren
#  Baende aber ueber keine solche Markierung verfuegen.
#
#  Dieses File ist (C) 2020 Oliver Flimm <flimm@openbib.org>
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
no warnings 'redefine';
use utf8;

use Encode 'decode_utf8';
use Log::Log4perl qw(get_logger :levels);
use Benchmark ':hireswallclock';
use DBI;
use DBIx::Class::ResultClass::HashRefInflator;
use Getopt::Long;
use JSON::XS qw/encode_json/;
use YAML;
use POSIX qw/strftime/;

use OpenBib::Config;
use OpenBib::Catalog::Factory;
use OpenBib::Common::Util;
use OpenBib::Statistics;
use OpenBib::Search::Util;

my $config     = OpenBib::Config->new;

my ($database,$help,$logfile,$filename);

&GetOptions("database=s"      => \$database,
            "logfile=s"       => \$logfile,
            "filename=s"      => \$filename,
	    "help"            => \$help
	    );

if ($help || (!$database && !$filename)){
    print_help();
}

$logfile=($logfile)?$logfile:"/var/log/openbib/find_parents_of_volumes_without_zbkunst_${database}.log";
$filename=($filename)?$filename:"parent_katkeys_without_zbkunst_$database.txt";
my $yaml_filename="parents_katkeys_info_$database.yml";

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

my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => $database});

open(OUT,">$filename");
open(YAMLOUT,">$yaml_filename");

my $title_tree_ref = {};

my $title_zbkunst = $catalog->get_schema->resultset('TitleField')->search(
    {
        'field'  => 4723,
	'content' => 'zb-kunst',
    },
    {
        select   => ['titleid'],
        as       => ['thistitleid'],
        group_by => ['titleid'],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
);

# my $title_with_children = $catalog->get_schema->resultset('TitleField')->search(
#     {
# 	'content' => { -in => $title_zbkunst->as_query},
#         'field'  => 4,
#     },
#     {
#         select   => ['titleid','content'],
#         as       => ['thistitleid','parenttitleid'],
#         group_by => ['titleid','parenttitleid'],
#         result_class => 'DBIx::Class::ResultClass::HashRefInflator',
#     }
# );

my $title_with_children = $catalog->get_schema->resultset('TitleTitle')->search(
    {
	'target_titleid' => { -in => $title_zbkunst->as_query},
    },
    {
        select   => ['target_titleid','source_titleid'],
        as       => ['parenttitleid','childtitleid'],
        group_by => ['target_titleid','source_titleid'],
        result_class => 'DBIx::Class::ResultClass::HashRefInflator',
    }
);

my $idx = 1;

foreach my $title ($title_with_children->all){
    my $childid     = $title->{childtitleid};
    my $parentid    = $title->{parenttitleid};

    my $child_zbkunst = $catalog->get_schema->resultset('TitleField')->search(
	{
	    'titleid' => $childid,
	    'field'  => 4723,
	    'content' => 'zb-kunst',
	},
	{
	    select   => ['titleid'],
	    as       => ['thistitleid'],
	    group_by => ['titleid'],
	    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
	}
	);

    my $has_zbkunst = 0;
    
    foreach my $title_child_zbkunst ($child_zbkunst->all){
	my $titleid_zbkunst = $title_child_zbkunst->{thistitleid};

	$has_zbkunst = 1;
    }

    if ($has_zbkunst){
	push @{$title_tree_ref->{$parentid}{zbkunst}}, $childid;
    }
    else {
	push @{$title_tree_ref->{$parentid}{no_zbkunst}}, $childid;
    }

    if ($idx % 1000 == 0){
	$logger->info("$idx Hierarchieinformationen bearbeitet")
    }

    $idx++;
}

print YAMLOUT YAML::Dump($title_tree_ref),"\n";

foreach my $parentid (keys %$title_tree_ref){
    if (! defined $title_tree_ref->{$parentid}{zbkunst}){
	print OUT $parentid,"\n";
    }    
}

close(OUT);
close(YAMLOUT);

sub print_help {
    print << "ENDHELP";
find_parents_of_volumes_without_zbkunst.pl - Finde Gesamttitel mit zb-kunst Markierung, deren Baende keine Markierung besitzen


   Optionen:
   -help                 : Diese Informationsseite
       
   --database=inst001    : Datenbankname (USB=inst001)


ENDHELP
    exit;
}

