#!/usr/bin/perl

my $is_first = 1;
while (<>){
    if ($is_first){
	print "ID\t$_";
	$is_first=0;
    }
    else {
	my ($id)=$_=~m{product-document/(.+?)\t};
	if ($id){
	    print "\"$id\"\t$_";
	}
    }    
}
