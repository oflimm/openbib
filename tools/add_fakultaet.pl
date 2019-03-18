#!/usr/bin/perl

use OpenBib::Config;
use YAML;

my $prefix_map = {
    'DE-38-0' => 'ungeb',
    'DE-38-1' => 'wiso',
    'DE-38-2' => 'jura',
    'DE-38-3' => 'human',
    'DE-38-4' => 'phil',
    'DE-38-5' => 'matnat',
};

my $config = new OpenBib::Config;


foreach my $identifier_regexp (keys %$prefix_map){
    my $faculty = $prefix_map->{$identifier_regexp};

    print STDERR "Checking $identifier\n";
    
    my $locations = $config->get_schema->resultset('Locationinfo')->search(
	{ 
	    identifier => { '~' => "$identifier_regexp"},
	},
	{
	    column => ['id','identifier']
	}
	);

    if ($locations){
        my $update_fields_ref = [];
	
	foreach my $location ($locations->all){
	    my $id         = $location->get_column(id);
	    my $identifier = $location->get_column(identifier);
	    
	    my $thisfield = {
		locationid => $id,
		field      => 15,
		subfield   => 'a',
		mult       => '001',
		content    => $faculty,
	    };

	    push @$update_fields_ref, $thisfield;

	    print YAML::Dump($thisfield);

	    my $location = $config->get_schema->resultset('LocationinfoField')->search(
	{ 
	    locationid  => $id,
	    field => 15,
	})->delete;

	    
	    if ($config->{memc}){
		$config->memc_cleanup_locationinfo($identifier);
	    }
	}

	if (@$update_fields_ref){
            $config->get_schema->resultset('LocationinfoField')->populate($update_fields_ref);

        }

    }
    else {
	print STDERR "No ids found for identifier $identifier\n";
    }
}
