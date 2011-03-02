package OpenBib::Database::User::Collection;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("treffer");
__PACKAGE__->add_columns(
  "userid",
  { data_type => "BIGINT", default_value => 0, is_nullable => 0, size => 20 },
  "dbname",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "singleidn",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 255,
  },
  "titcache",
  {
    data_type => "BLOB",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
);

1;
