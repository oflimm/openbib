#!/usr/bin/perl

use JSON::XS;
use utf8;

while (<>){
    my $title_ref = decode_json $_;

    my $titleid = $title_ref->{id};

    $title_ref->{fields}{'0331'} = [
	{
	    mult     => 1,
	    subfield => '',
	    content  => $titleid,
	},
	];
    
    if (defined $title_ref->{fields}{'0750'}){

	# Duplizieren in 0751
	$title_ref->{fields}{'0751'} = [{
	    mult => 1,
	    subfield => '',
	    content => "$title_ref->{fields}{'0750'}[0]{content}",
	}];

	# Dann bearbeiten
        foreach my $item (@{$title_ref->{fields}{'0750'}}){
            my $ocrtext = $item->{content};

	    # Wort-Trennungen zusammenfuehren
	    $ocrtext=~s/(\w)-\n\n(\w)/$1$2/g;
	    $ocrtext=~s/(\w)-$\n(\w)/$1$2/mg;

	    # Nicht-Wort-Zeichen ausfiltern
	    $ocrtext=~s/[^\p{Alnum}]/ /g;

	    # # Generelles Cleanup
	    # $ocrtext=~s/\n/ /g;
	    # $ocrtext=~s/\./ /g;
	    # $ocrtext=~s/,/ /g;
	    # $ocrtext=~s/  / /g;

	    # Fehlende Leerzeichen
	    $ocrtext=~s/([a-z])([A-Z])/$1 $2/mg;
	    
	    $item->{content} = $ocrtext;
        }
    }
   
    print encode_json $title_ref, "\n";
}
#close(CHANGED);
