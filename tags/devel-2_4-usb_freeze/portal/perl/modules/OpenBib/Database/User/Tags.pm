package OpenBib::Database::User::Tags;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("tags");
__PACKAGE__->add_columns(
  "id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 11 },
  "tag",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 255 },
);

1;
