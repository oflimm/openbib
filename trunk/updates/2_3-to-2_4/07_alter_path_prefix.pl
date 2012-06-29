#!/usr/bin/perl

use OpenBib::Config;
use File::Find;
use File::Slurp;
use Encode qw(decode_utf8 encode_utf8);

my $config=new OpenBib::Config;

my $templatepath=$config->{tt_include_path}."/";

sub process_file {
    return unless (-f $File::Find::name);

    return if ($File::Find::name=~/CVS/);

    print $File::Find::name,"\n";    

    my $slurped_file = decode_utf8(read_file($File::Find::name));

    $slurped_file=~s/\[\%\s*config.get\('base_loc'\)\s*\%]\/\[\% view \%]/\[% path_prefix %]/g;
    $slurped_file=~s/\${config.get\('base_loc'\)}\/\${view}/\${path_prefix}/g;

    open (OUT,">:utf8",$File::Find::name);
    print OUT $slurped_file;
    close(OUT);
}

find(\&process_file, $templatepath);





