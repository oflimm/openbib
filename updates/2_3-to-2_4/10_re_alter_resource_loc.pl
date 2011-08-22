#!/usr/bin/perl

use OpenBib::Config;
use File::Find;
use File::Slurp;
use Encode qw(decode_utf8 encode_utf8);

my $config=new OpenBib::Config;

my $templatepath=$config->{tt_include_path}."/";
my $modulepath="/opt/cvs/openbib-current/portal/perl/modules/";

sub process_file {
    return unless (-f $File::Find::name);

    return if ($File::Find::name=~/CVS/);

    print $File::Find::name,"\n";
    
    my $slurped_file = decode_utf8(read_file($File::Find::name));

    return if (!$slurped_file=~/resource/);
    
    $slurped_file=~s/resource_([a-z_]+?_loc)/$1/g;
    $slurped_file=~s/resource_//g;

#    print $slurped_file."-------------------------\n";
    
    open (OUT,">:utf8",$File::Find::name);
    print OUT $slurped_file;
    close(OUT);
}

find(\&process_file, $templatepath);

find(\&process_file, $modulepath);




