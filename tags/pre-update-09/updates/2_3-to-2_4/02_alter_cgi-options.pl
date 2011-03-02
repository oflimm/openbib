#!/usr/bin/perl

use OpenBib::Config;
use File::Find;
use File::Slurp;
use Encode qw(decode_utf8 encode_utf8);

my $config=new OpenBib::Config;

#my $templatepath=$config->{tt_include_path}."/";
my $templatepath="/opt/cvs/templates_backup/2/";

sub process_file {
    print $File::Find::name,"\n";
    
    return unless (-f $File::Find::name);

    return if ($File::Find::name=~/CVS/);
    
    my $slurped_file = decode_utf8(read_file($File::Find::name));

#    return if ($slurped_file=~/base_loc/);
    
    # sb-Parameter entfernen ()
    $slurped_file=~s/\?sb=\w+;/?/g;
    $slurped_file=~s/\?sb=\w+/?/g;
    $slurped_file=~s/;sb=\w+//g;

    $slurped_file=~s/\?sb=\w+;/?/g;
    $slurped_file=~s/\?sb=\w+/?/g;
    $slurped_file=~s/;sb=\w+//g;
    $slurped_file=~s/<input\s*type="hidden"\s*name="sb"\s*value="\w+"\s*\/>//g;

    # Database-Parameter aendern
    $slurped_file=~s/\?database=(\w+);/?db=$1/g;
    $slurped_file=~s/\?database=(\w+)/?db=$1/g;
    $slurped_file=~s/;database=(\w+)/db=$1/g;

    $slurped_file=~s/\?database=(\w+);/?db=$1/g;
    $slurped_file=~s/\?database=(\w+)/?db=$1/g;
    $slurped_file=~s/;database=(\w+)/db=$1/g;
    $slurped_file=~s/\%]database=\[\%/\%]db=\[\%/g;

    # Autoplus entfernen
    $slurped_file=~s/<input\s*type="hidden"\s*name="autoplus"\s*value="\w+"\s*\/>//g;
    
    $slurped_file=~s/sb=xapian;drilldown=1;dd_categorized=1;/dd=1;/g;
    $slurped_file=~s/hitrange/num/g;
    $slurped_file=~s/sorttype/srt/g;
    $slurped_file=~s/sortorder/srto/g;
    $slurped_file=~s/drilldown=1/dd=1/g;
    $slurped_file=~s/drilldown_categorized=1//g;
    $slurped_file=~s/drilldown_cloud=1//g;
    $slurped_file=~s/\[\%-?\s+IF\s+config.get\('drilldown_option'\).cloud\s+-?\%]dd_cloud=1;\[\%-?\s+END\s+-?\%]//smg;
    $slurped_file=~s/\[\%-?\s+IF\s+config.get\('drilldown_option'\).categorized\s+-?\%]dd_categorized=1;\[\%-?\s+END\s+-?\%]//smg;

    $slurped_file=~s/\[\%-?\s+IF\s+config.get\('drilldown_option'\).cloud\s+-?\%]\s*^<input\s*type="hidden"\s*name="dd_cloud"\s*value="\w+"\s*\/>\s*^\[\%-?\s+END\s+-?\%]//smg;

    $slurped_file=~s/\[\%-?\s+IF\s+config.get\('drilldown_option'\).categorized\s+-?\%]\s*^<input\s*type="hidden"\s*name="dd_categorized"\s*value="\w+"\s*\/>\s*^\[\%-?\s+END\s+-?\%]//smg;

    $slurped_file=~s/type="hidden"\s*name="drilldown"/type="hidden" name="dd"/g;
    $slurped_file=~s/type="hidden"\s*name="database"/type="hidden" name="db"/g;

    open (OUT,">:utf8",$File::Find::name);
    print OUT $slurped_file;
    close(OUT);
}

find(\&process_file, $templatepath);





