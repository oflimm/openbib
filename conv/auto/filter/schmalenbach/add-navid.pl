#!/usr/bin/perl

use warnings;
use strict;

use JSON::XS;
use List::MoreUtils qw{uniq};

print STDERR "### uni Erweiterung Exemplardaten um navid\n";

print STDERR "### uni Einladen navid Mappings\n";

my $navid_ranges_ref = {};

open(NAVIDS,"/opt/openbib/conf/sab-navids.csv");

while (<NAVIDS>){
    my ($navid, $start, $end)=split /,/;
    my ($start_base, $start_count)=split('\s+',$start);
    my ($end_base, $end_count)=split('\s+',$end);

    next unless ($start_count && $end_count && $start_count =~m/^\d+$/ && $end_count =~m/^\d+$/);
    
    $navid_ranges_ref->{$start_base}{'start'}{$start_count} = $navid;
    $navid_ranges_ref->{$start_base}{'end'}{$start_count} = $navid;
}

close(NAVIDS);

while (<>){
    my $holding_ref = decode_json $_;

    eval {
	my $fields_ref = $holding_ref->{fields};
	
	my $is_sab = 0;
	
	if (defined $fields_ref->{'0016'} && $fields_ref->{'0016'}[0]{'content'} eq "38-SAB"){
	    $is_sab = 1;
	}
	
	if ($is_sab){       
	    my $mark = ""; 
	    if (defined $fields_ref->{'0014'} && $fields_ref->{'0014'}[0]{'content'}){
		$mark = $fields_ref->{'0014'}[0]{'content'};	    
	    }
	    
	    if ($mark){
		my ($base,$count) = $mark =~m/^(\d+A)(\d+)/;

		if ($base && $count){
		    # Bestimme navid und reichere in "0050" an		
		    my $navid = "";
		    
		    if (defined $navid_ranges_ref->{$base}{start}){
			foreach my $this_start (sort keys %{$navid_ranges_ref->{$base}{start}}){
#			    print STDERR "$base - $count - $this_start";
			    if ($count >= $this_start){
				$navid = $navid_ranges_ref->{$base}{start}{$this_start}
			    }
			}
		    }
		    
		    if ($navid){
			$fields_ref->{'0050'} = [
			    {
				content => $navid,
				mult => 1,
				subfield => "",
			    }
			    ];
		    }
		}
	    }
	}
    };
    
    print encode_json $holding_ref, "\n";
}
