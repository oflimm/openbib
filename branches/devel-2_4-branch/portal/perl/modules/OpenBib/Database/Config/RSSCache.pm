package OpenBib::Database::Config::RSSCache;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("rsscache");
__PACKAGE__->add_columns(
  "dbname",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 255 },
  "tstamp",
  {
    data_type => "TIMESTAMP",
    default_value => "CURRENT_TIMESTAMP",
    is_nullable => 0,
    size => 14,
  },
  "type",
  { data_type => "TINYINT", default_value => 0, is_nullable => 0, size => 4 },
  "subtype",
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
    is_nullable => 1,
    size => 65535,
  },
);

1;
