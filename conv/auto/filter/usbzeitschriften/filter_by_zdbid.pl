#!/usr/bin/perl

use utf8;

use JSON::XS;


open(HOLDING,"meta.holding");

my $is_usbmagazin_ref = {};

while (<HOLDING>){
    my $holding_ref = decode_json $_;

    my $is_usbmagazin = 0;
    
    foreach my $item_ref (@{$holding_ref->{fields}{'0016'}}){
	if ($item_ref->{content} =~m{Hauptabteilung / Magazin} && defined $holding_ref->{fields}{'0004'}){
	    $is_usbmagazin = 1;
	}
    }

    if ($is_usbmagazin){
	$is_usbmagazin_ref->{$holding_ref->{fields}{'0004'}[0]{content}} = 1;
    }
    
}

close(HOLDING);

while (<>){
    my $title_ref = decode_json $_;

    next unless (defined $is_usbmagazin_ref->{$title_ref->{id}} && $is_usbmagazin_ref->{$title_ref->{id}});
    
    my $is_journal = 0;

    if (defined $title_ref->{fields}{'0572'}){
	$is_journal = 1;
    }
    
    next unless ($is_journal);

    print encode_json $title_ref, "\n";
}
