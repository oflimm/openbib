#!/usr/bin/perl

while (<>){
    if (/^0700/){
        s/^0700/0710/;
    }
    elsif (/^0710/){
        s/^0710/0700/;
    }
    print;
}
