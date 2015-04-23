#!/usr/bin/perl

use OpenBib::Config;
use OpenBib::Statistics;
use OpenBib::Catalog::Factory;

my $catalog = OpenBib::Catalog::Factory->create_catalog({ database => 'muenzen' });

my $result_store = {};

# Regenten

my $regenten = $catalog->{schema}->resultset('PersonField')->search(
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

my $regionen = $catalog->{schema}->resultset('SubjectField')->search(
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

my $staedte = $catalog->{schema}->resultset('ClassificationField')->search(
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

my $nominale = $catalog->{schema}->resultset('TitleField')->search(
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

my $areas = $catalog->{schema}->resultset('TitleField')->search(
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

# Material

my $materials = $catalog->{schema}->resultset('TitleField')->search(
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

my $statistics = new OpenBib::Statistics;

$statistics->cache_data(
    {
        id => 'muenzen_searchform_choices',
        type => 1,
        data => $result_store,
    }
);

