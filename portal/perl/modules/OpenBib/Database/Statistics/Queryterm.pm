package OpenBib::Database::Statistics::Queryterm;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("queryterm");
__PACKAGE__->add_columns(
  "tstamp",
  {
    data_type => "DATETIME",
    default_value => undef,
    is_nullable => 1,
    size => 19,
  },
  "viewname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 20,
  },
  "type",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 11 },
  "content",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 40,
  },
);

1;
