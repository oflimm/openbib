#!/usr/bin/perl

use JSON::XS;

while (<>){
    my $title_ref = decode_json $_;

    if (defined $title_ref->{fields}{'0800'}[0]{content}){
        if ($title_ref->{fields}{'0800'}[0]{content} eq "Briefe von Gentz"){
            if (defined $title_ref->{fields}{'0425'}[0]{content}){
                $title_ref->{fields}{'0426'} = [
                    {
                        mult     => 1,
                        subfield => '',
                        content  => $title_ref->{fields}{'0425'}[0]{content},
                    },
                ];
            }
            else {
                $title_ref->{fields}{'0425'} = [
                    {
                        mult     => 1,
                        subfield => '',
                        content  => 'ohne Jahr',
                    },
                ];
                $title_ref->{fields}{'0426'} = [
                    {
                        mult     => 1,
                        subfield => '',
                        content  => 'ohne Jahr',
                    },
                ];
            }
        }
        elsif ($title_ref->{fields}{'0800'}[0]{content} eq "Briefe an Gentz"){
            if (defined $title_ref->{fields}{'0425'}[0]{content}){
                $title_ref->{fields}{'0427'} = [
                    {
                        mult     => 1,
                        subfield => '',
                        content  => $title_ref->{fields}{'0425'}[0]{content},
                    },
                ];
            }
            else {
                $title_ref->{fields}{'0425'} = [
                    {
                        mult     => 1,
                        subfield => '',
                        content  => 'ohne Jahr',
                    },
                ];
                $title_ref->{fields}{'0427'} = [
                    {
                        mult     => 1,
                        subfield => '',
                        content  => 'ohne Jahr',
                    },
                ];
            }
        }
        elsif ($title_ref->{fields}{'0800'}[0]{content} eq "Briefe Dritter"){
            if (defined $title_ref->{fields}{'0425'}[0]{content}){
                $title_ref->{fields}{'0428'} = [
                    {
                        mult     => 1,
                        subfield => '',
                        content  => $title_ref->{fields}{'0425'}[0]{content},
                    },
                ];
            }
            else {
                $title_ref->{fields}{'0425'} = [
                    {
                        mult     => 1,
                        subfield => '',
                        content  => 'ohne Jahr',
                    },
                ];
                $title_ref->{fields}{'0428'} = [
                    {
                        mult     => 1,
                        subfield => '',
                        content  => 'ohne Jahr',
                    },
                ];
            }
        }
        
    }

    print encode_json $title_ref, "\n";
}
