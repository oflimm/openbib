#!/usr/bin/perl

# Process linked provenances from 0984/0985 -> 4306ff

use JSON::XS;
use YAML;
use utf8;

use warnings;
use strict;

while (<>){
    my $record_ref = decode_json $_;
    
    my $fields_ref = $record_ref->{fields};

    if (defined $fields_ref->{'0984'} && defined $fields_ref->{'0985'}){

	my $field_scheme_ref = {};
	
	my $field_mult_ref = {};
	
	foreach my $fieldname ('0984','0985'){
	    my $tmp_scheme_ref = {};

	    # print YAML::Dump($fields_ref->{$fieldname});
	    foreach my $item_ref (@{$fields_ref->{$fieldname}}){
		$item_ref->{subfield} = "" unless (defined $item_ref->{subfield});
		unless ($item_ref->{mult}){
		    $item_ref->{mult} = (defined $field_mult_ref->{$fieldname})?$field_mult_ref->{$fieldname}++:1;
		}

		$tmp_scheme_ref->{$item_ref->{mult}}{"ind"} = $item_ref->{ind};
		
		$tmp_scheme_ref->{$item_ref->{mult}}{$item_ref->{subfield}} = $item_ref->{content} if (defined $item_ref->{mult} && defined $item_ref->{subfield} && $item_ref->{content});
	    }

	    # print YAML::Dump($tmp_scheme_ref);
	    
	    foreach my $mult (sort keys %$tmp_scheme_ref){
		my $tmp2_scheme_ref = {
		    mult => $mult,
		};
		foreach my $subfield (keys %{$tmp_scheme_ref->{$mult}}){	    
		    $tmp2_scheme_ref->{$subfield} = $tmp_scheme_ref->{$mult}{$subfield};
		}
		
		push @{$field_scheme_ref->{$fieldname}}, $tmp2_scheme_ref;
	    }
	}

	# Erzeugen der Felder 4306ff

	my $new_fields_ref = [];
	foreach my $item_ref (@{$field_scheme_ref->{'0984'}}){
	    my ($mult) = $item_ref->{'8'} =~m/(\d+)/;	    
	    my $gnd    = $item_ref->{'0'} || '';
	    my $name   = $item_ref->{'a'};	    

	    $gnd =~s/^\(DE-588\)//;
	    
	    # Person
	    if ($item_ref->{'ind'} =~m/1/){
		push @{$fields_ref->{'4308'}}, {
		    subfield => 'a',
		    mult     => $mult,
		    content  => $name
		} if ($name);

		push @{$fields_ref->{'4308'}}, {
		    subfield => 'g',
		    mult     => $mult,
		    content  => $gnd,
		} if ($gnd);		
	    }
	    # Corporate body
	    elsif ($item_ref->{'ind'} =~m/2/){
		push @{$fields_ref->{'4307'}}, {
		    subfield => 'a',
		    mult     => $mult,
		    content  => $name,
		} if ($name);

		push @{$fields_ref->{'4307'}}, {
		    subfield => 'g',
		    mult     => $mult,
		    content  => $gnd,
		} if ($gnd);
	    }
	    # Collections
	    elsif ($item_ref->{'ind'} =~m/3/){
		push @{$fields_ref->{'4306'}}, {
		    subfield => 'a',
		    mult     => $mult,
		    content  => $name,
		} if ($name);

		push @{$fields_ref->{'4306'}}, {
		    subfield => 'g',
		    mult     => $mult,
		    content  => $gnd,
		} if ($gnd);
	    }
	}
	
	foreach my $item_ref (@{$field_scheme_ref->{'0985'}}){
	    my ($mult)           = $item_ref->{'8'} =~m/(\d+)/;
	    my $medianumber      = $item_ref->{'f'};
	    my $tpro_description = $item_ref->{'o'};
	    my $sigel            = $item_ref->{'g'};
	    my $incomplete       = $item_ref->{'p'};
	    my $reference        = $item_ref->{'q'};
	    my $scan_id          = $item_ref->{'u'};
	    my $former_mark      = $item_ref->{'j'};
	    my $entry_year       = $item_ref->{'i'};
	    my $remark           = $item_ref->{'r'};

	    push @{$fields_ref->{'4309'}}, {
		subfield => 'a',
		mult     => $mult,
		content  => $medianumber,
	    } if ($medianumber);

	    push @{$fields_ref->{'4310'}}, {
		subfield => 'a',
		mult     => $mult,
		content  => $tpro_description,
	    } if ($tpro_description);

	    push @{$fields_ref->{'4311'}}, {
		subfield => 'a',
		mult     => $mult,
		content  => $sigel,
	    } if ($sigel);

	    push @{$fields_ref->{'4312'}}, {
		subfield => 'a',
		mult     => $mult,
		content  => $incomplete,
	    } if ($incomplete);

	    push @{$fields_ref->{'4313'}}, {
		subfield => 'a',
		mult     => $mult,
		content  => $reference,
	    } if ($reference);

	    push @{$fields_ref->{'4314'}}, {
		subfield => 'a',
		mult     => $mult,
		content  => $former_mark,
	    } if ($former_mark);

	    push @{$fields_ref->{'4315'}}, {
		subfield => 'a',
		mult     => $mult,
		content  => $scan_id,
	    } if ($scan_id);

	    push @{$fields_ref->{'4316'}}, {
		subfield => 'a',
		mult     => $mult,
		content  => $entry_year,
	    } if ($entry_year);

	    push @{$fields_ref->{'4317'}}, {
		subfield => 'a',
		mult     => $mult,
		content  => $remark,
	    } if ($remark);
	}
	

	# print YAML::Dump($field_scheme_ref);
	
    }

    print encode_json $record_ref, "\n";
}
