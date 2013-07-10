#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    # Bildung einer Zeitspanne in 0425 aus 042[67[
    if (defined $title_ref->{fields}{'0426'} && defined $title_ref->{fields}{'0427'}){
        my $from = $title_ref->{fields}{'0426'}[0]{content};
        my $to   = $title_ref->{fields}{'0427'}[0]{content};
        
        push @{$title_ref->{fields}{'0425'}}, {
            content => "$from - $to",
            subfield => "",
            mult => 1,
        };
    }

    my $hst = "";
    # Bildung eines HST in 0331
    if (defined $title_ref->{fields}{'0700'}){
        $hst = $title_ref->{fields}{'0700'}[0]{content};
    }
    if (defined $title_ref->{fields}{'0710'}){
        $hst .= " in ".$title_ref->{fields}{'0710'}[0]{content};
    }
    if (defined $title_ref->{fields}{'0100'}){
        $hst .= " unter ".$title_ref->{fields}{'0100'}[0]{content};
    }

    push @{$title_ref->{fields}{'0331'}}, {
        content => $hst,
        subfield => "",
        mult => 1,
    };

    # Interne Verlinkungen
    if (defined $title_ref->{fields}{'0333'}){
        foreach my $item_ref (@{$title_ref->{fields}{'0333'}}){
            if ($item_ref->{content} =~m/^(\w+)\s+\[\[(\w+)\]\]/){
                $item_ref->{content} = "<a href=\"/portal/muenzen/databases/id/muenzen/titles/id/$2\">$1</a>";
            }
        }
    }
    if (defined $title_ref->{fields}{'0336'}){
        foreach my $item_ref (@{$title_ref->{fields}{'0336'}}){
            if ($item_ref->{content} =~m/^(\w+)\s+\[\[(\w+)\]\]/){
                $item_ref->{content} = "<a href=\"/portal/muenzen/databases/id/muenzen/titles/id/$2\">$1</a>";
            }
        }
    }
    
    print encode_json $title_ref, "\n";
}
