#!/usr/bin/perl

use OpenBib::Index::Factory;
use YAML;

my $indexname = $ARGV[0];
my $new_alias = $ARGV[1];

my $index = OpenBib::Index::Factory->create_indexer({ sb => 'elasticsearch', database => $indexname});
$index->create_alias($indexname,$new_alias);

my $result = $index->get_aliased_index($new_alias);

print $result,"\n";
