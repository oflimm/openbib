#!/usr/bin/perl

use utf8;

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    my $is_article = 0;

    if (defined $title_ref->{fields}{'0800'}){
      foreach my $item_ref (@{$title_ref->{fields}{'0800'}}){
          if ($item_ref->{content} =~/Aufsatz/i){
              $is_article = 1;
          }
      }
    }

    next if ($is_article);

    print encode_json $title_ref, "\n";
}
