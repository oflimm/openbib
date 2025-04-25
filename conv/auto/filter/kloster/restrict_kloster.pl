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
	'16246584-1' => 1, # Augustinerkloster Köln
	    '1331108772' => 1, # Augustinerinnenkloster Zum Kleinen Lämmchen, Köln
	    '16248828-2' => 1, # Kapuzinerkloster Köln 
	    '3072615-3' => 1, # Kloster der Beschuhten Karmeliter Köln
	    '129480037X' => 1, # Kloster der Unbeschuhten Karmeliter Köln
	    '4275651-0' => 1, # Kölner Kartause 
	    '6507074-4' => 1, # Franziskanerkloster zu den Oliven Köln
	    '16245368-1' => 1, # Kloster Groß Sankt Martin Köln 
	    '6102582-3' => 1, # Dominikanerkloster Heilig Kreuz Köln 
	    '7562565-9' => 1, # Johanniter, Kommende Köln
	    '1156561094' => 1, # Kölner Kreuzbrüder 
	    '16245592-6' => 1, # Minoritenkloster Köln
	    '4337111-5' => 1, # Kloster Marienspiegel Köln
	    '4378125-1' => 1, # Stift Sankt Aposteln Köln
	    '4253823-3' => 1, # Abtei Brauweiler 
	    '1704954-4' => 1, # Kloster St. Pantaleon Köln
	    '1363747274' => 1, # Collegium Norbertinum, Köln
	    '16277855-7' => 1, # Benediktinerabtei Sankt Vitus, Gladbach    
	    '7764949-7' => 1, # Fraterhaus St. Michael am Weidenbach  
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
