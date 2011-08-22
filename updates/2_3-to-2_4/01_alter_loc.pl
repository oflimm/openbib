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

    return if ($slurped_file=~/base_loc/);
    
    $slurped_file=~s/\[\%\s*config.get\('(\w+_loc)'\)\s*\%]/\[% config.get('base_loc') %]\/\[% view %]\/\[% config.get('handler').$1.name %]/g;
    $slurped_file=~s/\${config.get\('(\w+_loc)'\)}/\${config.get('base_loc')}\/\${view}\/\${config.get('handler').$1.name}/g;

    # View-Parameter entfernen (in URI gewandert)
    $slurped_file=~s/\?view=\[% view %];/?/g;
    $slurped_file=~s/\?view=\[% view %]/?/g;
    $slurped_file=~s/;view=\[% view %]//g;

    $slurped_file=~s/\?view=\${view};/?/g;
    $slurped_file=~s/\?view=\${view}/?/g;
    $slurped_file=~s/;view=\${view}//g;
    $slurped_file=~s/<input\s*type="hidden"\s*name="view"\s*value="\[% view %]"\s*\/>//g;
    
    # sessionID-Parameter entfernen (in Cookie gewandert)
    $slurped_file=~s/\?sessionID=\[%\s*sessionID\s*%];/?/g;
    $slurped_file=~s/\?sessionID=\[%\s*sessionID\s*%]/?/g;
    $slurped_file=~s/;sessionID=\[%\s*sessionID\s*%]//g;
    $slurped_file=~s/\/\[%\s*sessionID\s*%]\//\//g;

    $slurped_file=~s/\/\${sessionID}\//\//g;
    $slurped_file=~s/\?sessionID=\${sessionID};/?/g;
    $slurped_file=~s/\?sessionID=\${sessionID}/?/g;
    $slurped_file=~s/;sessionID=\${sessionID}//g;
    $slurped_file=~s/<input\s*type="hidden"\s*name="sessionID"\s*value="\[%\s*sessionID\s*%]"\s*\/>//g;
    $slurped_file=~s/<input\s*type="hidden"\s*name="sessionID"\s*value="\[%\s*query.param\('sessionID'\)\s*%]"\s*\/>//g;
    $slurped_file=~s/<meta\s*name="sessionID"\s*content="\[% sessionID %]"\s*\/>//g;

    # CSS_loc korrigieren
    $slurped_file=~s/\[% config.get\('base_loc'\) %]\/\[% view %]\/\[% config.get\('handler'\).css_loc.name %]/\[\% config.get('css_loc') \%]/g;
    $slurped_file=~s/\${config.get\('base_loc'\)}\/\${view}\/\${config.get\('handler'\).css_loc.name}/\${config.get('css_loc')}/g;

    open (OUT,">:utf8",$File::Find::name);
    print OUT $slurped_file;
    close(OUT);
}

find(\&process_file, $templatepath);





