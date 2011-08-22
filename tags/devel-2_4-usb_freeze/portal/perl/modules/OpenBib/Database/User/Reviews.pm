package OpenBib::Database::User::Reviews;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("reviews");
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
  "titid",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 255,
  },
  "titisbn",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 14 },
  "titdb",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 25 },
  "loginname",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "nickname",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 30 },
  "title",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 100 },
  "review",
  {
    data_type => "MEDIUMTEXT",
    default_value => undef,
    is_nullable => 0,
    size => 16777215,
  },
  "rating",
  { data_type => "INT", default_value => 0, is_nullable => 0, size => 3 },
);
__PACKAGE__->set_primary_key("id");

1;
