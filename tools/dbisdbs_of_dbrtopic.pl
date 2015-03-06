#!/usr/bin/perl

use OpenBib::Config;
use YAML;

my $dbrtopic = $ARGV[0];

my $config = OpenBib::Config->new;

my $databases_ref = $config->get_dbisdbs_of_dbrtopic($dbrtopic);

print YAML::Dump($databases_ref),"\n";
