#!/usr/bin/perl

use JSON::XS;
use utf8;

my $commentfile = "/opt/openbib/autoconv/pools/inst417karten/comments.dat";

open(COMMENTIN,'<:encoding(UTF-8)',$commentfile);

my $comments_ref = {};

while (<COMMENTIN>){
    my ($id,$comment)=split("\t",$_);

    chomp($comment);

    # HTML entfernen
    $comment=~s/<.+?>//g;
    
    $comments_ref->{$id} = $comment;
}

close(COMMENTIN);

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    if (defined $comments_ref->{$titleid}){
	$title_ref->{fields}{'0403'} = [
	    {
		mult     => 1,
		subfield => '',
		content  => $comments_ref->{$titleid},
	    },
	];
    }
   
    print encode_json $title_ref, "\n";
}

