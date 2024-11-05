#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};
use OpenBib::Config;
use YAML;

my $config = new OpenBib::Config;

my $cls = $config->load_yaml('/opt/openbib/conf/usblbs.yml');

# Umorganisierung der Systematik fuer einfacheren Lookup

my $lookup_ref = {};

foreach my $base (keys %$cls){
    foreach my $group (keys %{$cls->{$base}{sub}}){
	$lookup_ref->{$group} = 1;
    }
}

my $title_group_ref = {};

print STDERR "### lesesaal Markierung der Titel mit Systematik-Gruppen bestimmen\n";

open(HOLDING,"meta.holding");

while (<HOLDING>){
    my $holding_ref = decode_json $_;

    my $titleid  = $holding_ref->{fields}{'0004'}[0]{content};
    my $signatur = $holding_ref->{fields}{'0014'}[0]{content};

    next unless ($titleid && $signatur);

    if ($signatur =~m/^([A-Z][A-Z])\d+?[a-z]*\#$/){
	my $group = $1;
	if (defined $lookup_ref->{$group} && $lookup_ref->{$group}){
	    $title_group_ref->{$titleid} = $group;

	}
    }
}

close(HOLDING);

print STDERR "### usblbs Anreicherung der Titel mit Systematik-Gruppen\n";

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    next unless ($titleid);

    # Gruppenmarkierung vorhanden? Dann setzen
    if (defined $title_group_ref->{$titleid}){
       $title_ref->{fields}{'1002'} = [ {
	    content  => $title_group_ref->{$titleid},
	    mult     => 1,
	    subfield => 'a',
	} ];
    }

    print encode_json $title_ref, "\n";
}

