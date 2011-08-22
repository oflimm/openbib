package OpenBib::Database::Statistics::Relevance;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("relevance");
__PACKAGE__->add_columns(
  "tstamp",
  {
    data_type => "TIMESTAMP",
    default_value => "CURRENT_TIMESTAMP",
    is_nullable => 0,
    size => 14,
  },
  "id",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 100,
  },
  "isbn",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 15,
  },
  "dbname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 25,
  },
  "katkey",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 11 },
  "origin",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 11 },
);

1;
