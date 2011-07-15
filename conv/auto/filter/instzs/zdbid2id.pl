#!/usr/bin/perl

use YAML::Syck;

my @buffer  = ();
my $id      = 0;
my $localid = 0;

my %id2zdbid = ();

while (<>){
       
    if (/^0000:(.+)/){
        $localid=$1;
        $id = 0;
        @buffer=($_);
    }
    else {
        push @buffer,$_;

        if (/^0572\.\d\d\d:(.*)$/){
            $id = $1;
        }
    }
    
    if (/^9999/){
        if ($id){
            $id2zdbid{$localid}=$id;
            
            $buffer[0]="0000:$id\n";

            push @buffer,"0010:$localid\n";
            
            print STDOUT join("",@buffer);
        }
        #else {
        #    print STDERR join("",@buffer);
        #}
    }
        
}

unlink "/tmp/instzs-id2zdbid.yml";
DumpFile("/tmp/instzs-id2zdbid.yml",\%id2zdbid);
