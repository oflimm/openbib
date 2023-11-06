#!/usr/bin/perl

use OpenBib::Config;
use OpenBib::Statistics;
use OpenBib::Catalog::Factory;

my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => 'muenzen' });

my $result_store = {};


# Staedte

my $cities = $catalog->get_schema->resultset('Classification');

while (my $city = $cities->next()){
    my $thiscity = new OpenBib::Record::Classification({ database => 'muenzen', id => $city->id})->load_full_record;

    if ($thiscity->has_field('N0200')){
	my $name = $thiscity->get_field({ field => 'N0800', mult => 1});
	my $geo = $thiscity->get_field({ field => 'N0200', mult => 1});

	push @{$result_store->{$geo}},$name;
    }
}       

my $config = new OpenBib::Config;

$config->set_datacache(
    {
        id => 'muenzen_city_map',
        type => 1,
        data => $result_store,
    }
);

