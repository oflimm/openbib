package OpenBib::Database::Enrichment::AllIsbn;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("all_isbn");
__PACKAGE__->add_columns(
  "isbn",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 33,
  },
  "dbname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 25,
  },
  "id",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 255,
  },
  "tstamp",
  {
    data_type => "DATETIME",
    default_value => undef,
    is_nullable => 1,
    size => 19,
  },
);

1;
