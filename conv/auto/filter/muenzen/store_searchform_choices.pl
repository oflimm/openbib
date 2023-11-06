#!/usr/bin/perl

use OpenBib::Config;
use OpenBib::Statistics;
use OpenBib::Catalog::Factory;

my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => 'muenzen' });

my $result_store = {};

# Regenten

my $regenten = $catalog->get_schema->resultset('PersonField')->search(
    {
        'field' => 800
    },
    {
        order_by => ['content ASC'],
        select => ['content'],
    }
);

while (my $regent = $regenten->next()){
    my $regent_content = $regent->content;
    $regent_content =~s/"/\%22/g;
    push @{$result_store->{regent}}, $regent_content;
}       


# Regionen

my $regionen = $catalog->get_schema->resultset('SubjectField')->search(
    {
        'field' => 800
    },
    {
        order_by => ['content ASC'],
        select => ['content'],
    }
);

while (my $region = $regionen->next()){
    my $region_content = $region->content;
    $region_content =~s/"/\%22/g;
    push @{$result_store->{region}}, $region_content;
}       

# Staedte

my $staedte = $catalog->get_schema->resultset('ClassificationField')->search(
    {
        'field' => 800
    },
    {
        order_by => ['content ASC'],
        select => ['content'],
    }
);

while (my $stadt = $staedte->next()){
    my $stadt_content = $stadt->content;
    $stadt_content =~s/"/\%22/g;
    push @{$result_store->{stadt}}, $stadt_content;
}       

# Nominale

my $nominale = $catalog->get_schema->resultset('TitleField')->search(
    {
        'field' => 338
    },
    {
        group_by => ['content'],
        order_by => ['content ASC'],
        select => ['content'],
    }
);

while (my $nominal = $nominale->next()){
    my $nominal_content = $nominal->content;
    $nominal_content =~s/"/\%22/g;
    push @{$result_store->{nominal}}, $nominal_content;
}       

# Politischer Bereich

my $areas = $catalog->get_schema->resultset('TitleField')->search(
    {
        'field' => 410
    },
    {
        group_by => ['content'],
        order_by => ['content ASC'],
        select => ['content'],
    }
);

while (my $area = $areas->next()){
    my $area_content = $area->content;
    $area_content =~s/"/\%22/g;
    push @{$result_store->{area}}, $area_content;
}       

# Magistrat

my $magistrates = $catalog->get_schema->resultset('TitleField')->search(
    {
        'field' => 533
    },
    {
        group_by => ['content'],
        order_by => ['content ASC'],
        select => ['content'],
    }
);

while (my $magistrate = $magistrates->next()){
    my $magistrate_content = $magistrate->content;
    $magistrate_content =~s/"/\%22/g;
    push @{$result_store->{magistrate}}, $magistrate_content;
}       

# Herrscherfamilie

my $ruling_families = $catalog->get_schema->resultset('TitleField')->search(
    {
        'field' => 531
    },
    {
        group_by => ['content'],
        order_by => ['content ASC'],
        select => ['content'],
    }
);

while (my $ruling_family = $ruling_families->next()){
    my $ruling_family_content = $ruling_family->content;
    $ruling_family_content =~s/"/\%22/g;
    push @{$result_store->{ruling_family}}, $ruling_family_content;
}       

# Material

my $materials = $catalog->get_schema->resultset('TitleField')->search(
    {
        'field' => 800
    },
    {
        group_by => ['content'],
        order_by => ['content ASC'],
        select => ['content'],
    }
);

while (my $material = $materials->next()){
    my $material_content = $material->content;
    $material_content =~s/"/\%22/g;
    push @{$result_store->{material}}, $material_content;
}       

my $config = new OpenBib::Config;

$config->set_datacache(
    {
        id => 'muenzen_searchform_choices',
        type => 1,
        data => $result_store,
    }
);

