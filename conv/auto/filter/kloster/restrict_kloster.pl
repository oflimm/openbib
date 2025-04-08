#!/usr/bin/perl

use JSON::XS;
use utf8;

use MLDBM qw(DB_File Storable);
use Storable ();
use DB_File;
use List::MoreUtils qw/ uniq /;
use YAML;

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    my $allowed_gnd_ref  = {
	'4275651-0' => 1, # Kloster Sankt Barbara Köln
	    '3072615-3' => 1, # Karmeliterkloster Köln
	    '4253823-3' => 1, # Kloster Brauweiler
	    '6102582-3' => 1, # Kloster Heilig Kreuz Köln
	    '1704954-4' => 1, # Kloster St. Pantaleon Köln
	    '16278243-3' => 1, # Benediktinerkloster Groß Sankt Martin
    };
    
    my $allowed_mark_ref = {};
    my $allowed_mult_ref = {};

    # Erlaubte Mult fuer GND bestimmen
    if (defined $title_ref->{fields}{'4307'}){
	foreach my $item_ref (@{$title_ref->{fields}{'4307'}}){
	    my $content  = $item_ref->{'content'};
	    my $subfield = $item_ref->{'subfield'};
	    my $mult     = $item_ref->{'mult'};

	    if ($subfield eq "g" && defined $allowed_gnd_ref->{$content} && $allowed_gnd_ref->{$content}){
		$allowed_mult_ref->{$mult} = 1;
	    }
	}
    }    

    # Signaturen merken
    if (defined $title_ref->{fields}{'4309'}){
	foreach my $item_ref (@{$title_ref->{fields}{'4307'}}){
	    my $content  = $item_ref->{'content'};
	    my $subfield = $item_ref->{'subfield'};
	    my $mult     = $item_ref->{'mult'};

	    if ($subfield eq "a" && defined $allowed_mult_ref->{$mult} && $allowed_mult_ref->{$mult}){
		$allowed_mark_ref->{$content} = 1;
	    }
	}
    }    

    # Erlaubte Mult ggf. mit erlaubten Signaturen erweitern, d.h. mit anderen Provenienzen am gleichen Exemplar
    if (defined $title_ref->{fields}{'4309'}){
	foreach my $item_ref (@{$title_ref->{fields}{'4309'}}){
	    my $content  = $item_ref->{'content'};
	    my $subfield = $item_ref->{'subfield'};
	    my $mult     = $item_ref->{'mult'};

	    if ($subfield eq "a" && defined $allowed_mark_ref->{$content} && $allowed_mark_ref->{$content}){
		$allowed_mult_ref->{$mult} = 1;
	    }
	}
    }    

    # Alles bis auf erlaubte mult entfernen
    foreach my $field ('4306','4307','4308','4309','4310','4311','4312','4313','4314','4315','4316','4317'){
	if (defined $title_ref->{fields}{$field}){
	    my $allowed_field_ref = [];
		
	    foreach my $item_ref (@{$title_ref->{fields}{$field}}){
		my $mult     = $item_ref->{'mult'};

		push @{$allowed_field_ref}, $item_ref if (defined $allowed_mult_ref->{$mult} && $allowed_mult_ref->{$mult});
	    }

	    if (@$allowed_field_ref){
		$title_ref->{fields}{$field} = $allowed_field_ref;
	    }
	    else {
		$title_ref->{fields}{$field} = [];
		delete $title_ref->{fields}{$field};
	    }
	}
    }
    
    
    print encode_json $title_ref, "\n";
}
