package OpenBib::Database::Enrichment::Normdata;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("normdata");
__PACKAGE__->add_columns(
  "isbn",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 14 },
  "origin",
  {
    data_type => "SMALLINT",
    default_value => undef,
    is_nullable => 1,
    size => 6,
  },
  "category",
  { data_type => "SMALLINT", default_value => 0, is_nullable => 0, size => 6 },
  "indicator",
  {
    data_type => "SMALLINT",
    default_value => undef,
    is_nullable => 1,
    size => 6,
  },
  "content",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 0,
    size => 65535,
  },
);

1;
