#!/usr/bin/perl

my $is_first = 1;
while (<>){
    if ($is_first){
	print "ID,$_";
	$is_first=0;
    }
    else {
	my ($id)=$_=~m/\&docid=(.+?)\&/;
	if ($id){
	    print "\"$id\",$_";
	}
    }    
}
