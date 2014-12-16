#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use JSON::XS;
use Encode;
use YAML;

my $normdata_ref = [
    {
        type => 'person',
        in   => 'unload.PER.gz',
        out  => 'meta.person.gz',
        mapping => {
            '0001' => '0800',
        }
    },
    {
        type => 'corporatebody',
        in   => 'unload.KOE.gz',
        out  => 'meta.corporatebody.gz',
        mapping => {
            '0001' => '0800',
        }
    },
    {
        type => 'subject',
        in   => 'unload.SWD.gz',
        out  => 'meta.subject.gz',
        mapping => {
            '0001' => '0800',
        }
    },
    {
        type => 'classification',
        in   => 'unload.SYS.gz',
        out  => 'meta.classification.gz',
        mapping => {
            '0001' => '0800',
        }
    },
    {
        type => 'holding',
        in   => 'unload.MEX.gz',
        out  => 'meta.holding.gz',
    },
    {
        type => 'title',
        in   => 'unload.TIT.gz',
        out  => 'meta.title.gz',
    },
];


my ($id);

my $mult_value = {};
my $item_ref;
my $ignore_record = 0;

foreach my $thisdata_ref (@$normdata_ref){

    print STDERR "Converting $thisdata_ref->{type}\n";
    open(IN,  "zcat $thisdata_ref->{in} |");
    open(OUT, "| gzip > $thisdata_ref->{out}");

    my $have_title_ref = {};
    
    while (<IN>){
        if (/^0000:(.*)$/){
            $id = $1;

            if (defined $have_title_ref->{$id}){
                print STDERR "Record $id doppelt\n";
                $ignore_record = 1;
                next;
            }
            $have_title_ref->{$id} = 1;
            
            $mult_value = {};
            $item_ref = {};
            $item_ref->{id} = $id;
            $item_ref->{fields} = {};
        }
        elsif (/^(\d\d\d\d)\.(\d\d\d):IDN: (\d+) ; (.+)$/) {
            next if ($ignore_record);
            
            my $field = $1;
            my $mult = $2;
            my $verwid = $3;
            my $supplement = $4;

            if (defined $thisdata_ref->{mapping}{$field}){
                $field = $thisdata_ref->{mapping}{$field};
            }
            push @{$item_ref->{fields}{$field}}, {
                id    => $verwid,
                mult => $mult,
                subfield => '',
                supplement => $supplement,
            };
        }
        elsif (/^(\d\d\d\d):IDN: (\d+) ; (.+)$/) {
            next if ($ignore_record);
            my $field = $1;
            my $verwid = $2;
            my $mult = ++$mult_value->{$field};
            my $supplement = $3;

            if (defined $thisdata_ref->{mapping}{$field}){
                $field = $thisdata_ref->{mapping}{$field};
            }
            
            push @{$item_ref->{fields}{$field}}, {
                id    => $verwid,
                mult => $mult,
                subfield => '',
                supplement => $supplement,
            };
        }
        elsif (/^(\d\d\d\d)\.(\d\d\d):IDN: (\d+) (\[.+\])$/) {
            next if ($ignore_record);
            my $field = $1;
            my $mult = $2;
            my $verwid = $3;
            my $supplement = $4;

            if (defined $thisdata_ref->{mapping}{$field}){
                $field = $thisdata_ref->{mapping}{$field};
            }
            push @{$item_ref->{fields}{$field}}, {
                id    => $verwid,
                mult => $mult,
                subfield => '',
                supplement => $supplement,
            };
        }
        elsif (/^(\d\d\d\d):IDN: (\d+) (\[.+\])$/) {
            next if ($ignore_record);
            my $field = $1;
            my $verwid = $2;
            my $mult = ++$mult_value->{$field};
            my $supplement = $3;

            if (defined $thisdata_ref->{mapping}{$field}){
                $field = $thisdata_ref->{mapping}{$field};
            }
            
            push @{$item_ref->{fields}{$field}}, {
                id    => $verwid,
                mult => $mult,
                subfield => '',
                supplement => $supplement,
            };
        }
        elsif (/^(\d\d\d\d)\.(\d\d\d):IDN: (\d+)$/) {
            next if ($ignore_record);
            my $field = $1;
            my $mult = $2;
            my $verwid = $3;
            my $supplement = $4;

            if (defined $thisdata_ref->{mapping}{$field}){
                $field = $thisdata_ref->{mapping}{$field};
            }
            
            push @{$item_ref->{fields}{$field}}, {
                id    => $verwid,
                mult => $mult,
                subfield => '',
                supplement => $supplement,
            };
        }
        elsif (/^(\d\d\d\d):IDN: (\d+)$/) {
            next if ($ignore_record);
            my $field = $1;
            my $verwid = $2;
            my $mult = ++$mult_value->{$field};

            my $supplement = '';

            if (defined $thisdata_ref->{mapping}{$field}){
                $field = $thisdata_ref->{mapping}{$field};
            }
            push @{$item_ref->{fields}{$field}}, {
                id    => $verwid,
                mult => $mult,
                subfield => '',
                supplement => $supplement,
            };
        }
        elsif (/^(\d\d\d\d)\.(\d\d\d):(.+)$/) {
            next if ($ignore_record);
            my $field = $1;
            my $mult = $2;
            my $content = $3;

            if (defined $thisdata_ref->{mapping}{$field}){
                $field = $thisdata_ref->{mapping}{$field};
            }
            push @{$item_ref->{fields}{$field}}, {
                mult => $mult,
                subfield => '',
                content => $content,
            };
        }
        elsif (/^(\d\d\d\d):(.+)$/) {
            next if ($ignore_record);
            my $field = $1;
            my $content = $2;

            if (defined $thisdata_ref->{mapping}{$field}){
                $field = $thisdata_ref->{mapping}{$field};
            }

            my @parts = ();
            if ($field eq "0425"){
                @parts = split('\s+;\s+',$content);

                foreach my $part (@parts){
                    my $mult = ++$mult_value->{$field};
                    
                    push @{$item_ref->{fields}{$field}}, {
                        mult => $mult,
                        subfield => '',
                        content => $part,
                    };
                }
            }
            else {
                my $mult = ++$mult_value->{$field};
                
                push @{$item_ref->{fields}{$field}}, {
                    mult => $mult,
                    subfield => '',
                    content => $content,
                };
            }

        }
        elsif (/^9999/){
            print OUT JSON::XS->new->encode ($item_ref), "\n";
            $ignore_record = 0;
        }

    }

    close(IN);
    close(OUT);
}
