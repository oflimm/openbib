#!/usr/bin/perl

use OpenBib::Config;
use File::Find;
use File::Slurp;
use Encode qw(decode_utf8 encode_utf8);

my $config=new OpenBib::Config;

my $templatepath=$config->{tt_include_path}."/";

sub process_file {
    print $File::Find::name,"\n";
    
    return unless (-f $File::Find::name);

    return if ($File::Find::name=~/CVS/);
    
    my $slurped_file = decode_utf8(read_file($File::Find::name));

    #$slurped_file=~s/searchmask_loc/searchform_loc/g;
    $slurped_file=~s/searchmask/searchform/g;

    open (OUT,">:utf8",$File::Find::name);
    print OUT $slurped_file;
    close(OUT);
    #print $File::Find::name,"\n";
    #print $slurped_file;
}

find(\&process_file, $templatepath);





