package OpenBib::Database::User::ProfileDB;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("profildb");
__PACKAGE__->add_columns(
  "profilid",
  { data_type => "BIGINT", default_value => 0, is_nullable => 0, size => 20 },
  "dbname",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
);

1;
