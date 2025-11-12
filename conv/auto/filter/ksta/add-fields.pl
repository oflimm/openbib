#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    if (defined $title_ref->{fields}{'0425'}[0]{content} && defined $title_ref->{fields}{'0089'}[0]{content}){
	my $year   = $title_ref->{fields}{'0425'}[0]{content};
	my $number = $title_ref->{fields}{'0089'}[0]{content};
	$title_ref->{fields}{'0503'} = [
            {
                mult     => 1,
                subfield => '',
                content  => $year.".".$number,
            },
        ];

    }

    if (defined $title_ref->{fields}{'0750'}[0]{content}){
	my $fulltext = $title_ref->{fields}{'0750'}[0]{content};

	my ($teaser) = $fulltext =~m{<P>(.*?)</P>}i;
	
	$title_ref->{fields}{'0517'} = [
            {
                mult     => 1,
                subfield => '',
                content  => $teaser,
            },
	    ] if ($teaser);

    }
    
    print encode_json $title_ref, "\n";
}
