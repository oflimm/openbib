#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};
use OpenBib::Config;
use YAML;

my $config = new OpenBib::Config;

my $cls = $config->load_yaml('/opt/openbib/conf/usbls.yml');

# Umorganisierung der Systematik fuer einfacheren Lookup

my $lookup_ref = {};

foreach my $base (keys %$cls){
    foreach my $group (keys %{$cls->{$base}{sub}}){
	push @{$lookup_ref->{$base}}, {
	    start => $cls->{$base}{sub}{$group}{start},
	    end   => $cls->{$base}{sub}{$group}{end},
	    group => $group,
	};
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

    if ($signatur =~m{LS/([A-Za-z]+)(\d+)$}){
	my $base   = $1;
	my $number = $2;

	if (defined $lookup_ref->{$base}){
	    foreach my $rule_ref (@{$lookup_ref->{$base}}){
		if ($number >= $rule_ref->{start} && $number <= $rule_ref->{end}){
		    $title_group_ref->{$titleid} = $rule_ref->{group};
		    last;
		}
	    }
	}
    }
}

close(HOLDING);

print STDERR "### lesesaal Anreicherung der Titel mit Systematik-Gruppen\n";

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    next unless ($titleid);

    # Gruppenmarkierung vorhanden? Dann setzen
    if (defined $title_group_ref->{$titleid}){
       $title_ref->{fields}{'0351'} = [ {
	    content  => $title_group_ref->{$titleid},
	    mult     => 1,
	    subfield => '',
	} ];
    }

    print encode_json $title_ref, "\n";
}

