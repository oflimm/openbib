package OpenBib::Database::User::Livesearch;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("livesearch");
__PACKAGE__->add_columns(
  "userid",
  { data_type => "BIGINT", default_value => undef, is_nullable => 0, size => 20 },
  "fs",
  { data_type => "TINYINT", default_value => undef, is_nullable => 1, size => 1 },
  "verf",
  { data_type => "TINYINT", default_value => undef, is_nullable => 1, size => 1 },
  "swt",
  { data_type => "TINYINT", default_value => undef, is_nullable => 1, size => 1 },
  "exact",
  { data_type => "TINYINT", default_value => undef, is_nullable => 1, size => 1 },
);

1;
