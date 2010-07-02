#!/usr/bin/perl

my @buffer  = ();
my $id      = 0;
my $localid = 0;

while (<>){
       
    if (/^0000:(\d+)/){
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
            $buffer[0]="0000:$id\n";
            print STDOUT join("",@buffer);
        }
        #else {
        #    print STDERR join("",@buffer);
        #}
    }
        
}
