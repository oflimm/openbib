package OpenBib::Database::User::Spelling;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("spelling");
__PACKAGE__->add_columns(
  "userid",
  { data_type => "BIGINT", default_value => undef, is_nullable => 0, size => 20 },
  "as_you_type",
  { data_type => "TINYINT", default_value => undef, is_nullable => 1, size => 1 },
  "resultlist",
  { data_type => "TINYINT", default_value => undef, is_nullable => 1, size => 1 },
);

1;
