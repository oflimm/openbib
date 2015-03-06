#!/usr/bin/perl

use JSON::XS;
use OpenBib::Config;

my $config = OpenBib::Config->new;
my $view   = "muenzen";

my $path_prefix          = $config->get('base_loc');
my $complete_path_prefix = "$path_prefix/$view";

if (! $config->strip_view_from_uri($view)){
    $path_prefix = $complete_path_prefix;
}

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

    push @{$title_ref->{fields}{'0331'}}, {
        content => $hst,
        subfield => "",
        mult => 1,
    };

    # Legende mit verschiedenen Sonderzeichenbehandlungen fuer Register
    #
    # Vorderseite:
    #
    # Variante 1 : 341
    # Variante 2 : 342
    # Variante 3 : 343

    if (defined $title_ref->{fields}{'0332'}){
        my $grundform = $title_ref->{fields}{'0332'}[0]{content};

        my ($variante1,$variante2,$variante3) = ($grundform,$grundform,$grundform);

        $variante1=~s/\[//g;
        $variante1=~s/]//g;
        $variante1=~s/\(.+?\)//g;
        $variante1=~s/&lt;.+?&gt;//g;
        $variante1=~s/\x{0387}//g;
        $variante1=~s/\x{00b7}//g;
        $variante1=~s/\x{ce87}//g;
        $variante1=~s/-//g;
        $variante1=~s/\///g;
        $variante1=~s/\s+/ /g;

        push @{$title_ref->{fields}{'0341'}}, {
            content => $variante1,
            subfield => "",
            mult => 1,
        };

        $variante2=~s/\[//g;
        $variante2=~s/]//g;
        $variante2=~s/\(//g;
        $variante2=~s/\)//g;
        $variante2=~s/&lt;//g;
        $variante2=~s/&gt;//g;
        $variante2=~s/\x{0387}//g;
        $variante2=~s/\x{00b7}//g;
        $variante2=~s/\x{ce87}//g;
        $variante2=~s/\///g;
        $variante2=~s/-//g;
        $variante2=~s/\s+/ /g;

        push @{$title_ref->{fields}{'0342'}}, {
            content => $variante2,
            subfield => "",
            mult => 1,
        };
        
        $variante3=~s/\[//g;
        $variante3=~s/]//g;

        push @{$title_ref->{fields}{'0343'}}, {
            content => $variante3,
            subfield => "",
            mult => 1,
        };
        
    }    
    
    # Rueckseite:
    #
    # Variante 1 : 351
    # Variante 2 : 352
    # Variante 3 : 353
    # 
    
    if (defined $title_ref->{fields}{'0335'}){
        my $grundform = $title_ref->{fields}{'0335'}[0]{content};

        my ($variante1,$variante2,$variante3) = ($grundform,$grundform,$grundform);

        $variante1=~s/\[//g;
        $variante1=~s/]//g;
        $variante1=~s/\(.+?\)//g;
        $variante1=~s/&lt;.+?&gt;//g;
        $variante1=~s/\x{ce87}//g;
        $variante1=~s/\x{00b7}//g;
        $variante1=~s/\x{0387}//g;
        $variante1=~s/\///g;
        $variante1=~s/-//g;
        $variante1=~s/\s+/ /g;

        push @{$title_ref->{fields}{'0351'}}, {
            content => $variante1,
            subfield => "",
            mult => 1,
        };

        $variante2=~s/\[//g;
        $variante2=~s/]//g;
        $variante2=~s/\(//g;
        $variante2=~s/\)//g;
        $variante2=~s/&lt;//g;
        $variante2=~s/&gt;//g;
        $variante2=~s/\x{ce87}//g;
        $variante2=~s/\x{00b7}//g;
        $variante2=~s/\x{0387}//g;
        $variante2=~s/\///g;
        $variante2=~s/-//g;
        $variante2=~s/\s+/ /g;

        push @{$title_ref->{fields}{'0352'}}, {
            content => $variante2,
            subfield => "",
            mult => 1,
        };
        
        $variante3=~s/\[//g;
        $variante3=~s/]//g;

        push @{$title_ref->{fields}{'0353'}}, {
            content => $variante3,
            subfield => "",
            mult => 1,
        };
    }    
    
    # Interne Verlinkungen
    if (defined $title_ref->{fields}{'0333'}){
        foreach my $item_ref (@{$title_ref->{fields}{'0333'}}){
            $item_ref->{content}=~s/(\w+)\s+\[\[(\w+)]]/<a href="$path_prefix\/databases\/id\/muenzen\/titles\/id\/$2">$1<\/a>/g;
        }
    }
    if (defined $title_ref->{fields}{'0336'}){
        foreach my $item_ref (@{$title_ref->{fields}{'0336'}}){
            $item_ref->{content}=~s/(\w+)\s+\[\[(\w+)]]/<a href="$path_prefix\/databases\/id\/muenzen\/titles\/id\/$2">$1<\/a>/g;
        }
    }
    if (defined $title_ref->{fields}{'0508'}){
        foreach my $item_ref (@{$title_ref->{fields}{'0508'}}){
            $item_ref->{content}=~s/(\w+)\s+\[\[(\w+)]]/<a href="$path_prefix\/databases\/id\/muenzen\/titles\/id\/$2">$1<\/a>/g;
        }
    }
    
    print encode_json $title_ref, "\n";
}
