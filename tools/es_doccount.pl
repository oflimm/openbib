#!/usr/bin/perl

use OpenBib::Index::Factory;
use YAML;

my $database = $ARGV[0];

my $index = OpenBib::Index::Factory->create_indexer({ sb => 'elasticsearch', database => $database});
my $count = $index->get_doccount;

print $count,"\n";
