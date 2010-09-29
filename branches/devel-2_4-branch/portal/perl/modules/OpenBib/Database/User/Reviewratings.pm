package OpenBib::Database::User::Reviewratings;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("reviewratings");
__PACKAGE__->add_columns(
  "id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 11 },
  "tstamp",
  {
    data_type => "TIMESTAMP",
    default_value => "CURRENT_TIMESTAMP",
    is_nullable => 0,
    size => 14,
  },
  "reviewid",
  { data_type => "INT", default_value => 0, is_nullable => 0, size => 11 },
  "loginname",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "rating",
  { data_type => "INT", default_value => 0, is_nullable => 0, size => 3 },
);
__PACKAGE__->set_primary_key("id");

1;
