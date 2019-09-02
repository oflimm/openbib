#!/usr/bin/perl

use strict;
use warnings;

use JSON::XS;

while (<>){
    my $record_ref = decode_json $_;

    my $holdings_ref = [];

    # Zuerst der Erscheinungsverlauf
    if (defined $record_ref->{fields}{'1204'}){
	push @$holdings_ref, $record_ref->{fields}{'1204'}[0]{content};

    }
    else {
	if (defined $record_ref->{fields}{'1200'}){
	    push @$holdings_ref, $record_ref->{fields}{'1200'}[0]{content};
	    delete $record_ref->{fields}{'1200'};
	}
	
	if (defined $record_ref->{fields}{'1201'}){
	    push @$holdings_ref, $record_ref->{fields}{'1201'}[0]{content};
	    delete $record_ref->{fields}{'1201'};
	}
    }

    # Dann ggf. die Bemerkung in Klammern dahinter
    if (defined $record_ref->{fields}{'1202'}){
        push @$holdings_ref, "(".$record_ref->{fields}{'1202'}[0]{content}.")";
        delete $record_ref->{fields}{'1202'};
    }

    if (@$holdings_ref){
        $record_ref->{fields}{'1204'} = [ {
            content  => join (" ",@$holdings_ref),
            subfield => '',
            mult     => 1,
        }];
    }

    print encode_json $record_ref, "\n";
}

