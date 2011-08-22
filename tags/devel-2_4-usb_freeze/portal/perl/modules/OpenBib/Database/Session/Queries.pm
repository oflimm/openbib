package OpenBib::Database::Session::Queries;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("queries");
__PACKAGE__->add_columns(
  "queryid",
  { data_type => "BIGINT", default_value => undef, is_nullable => 0, size => 20 },
  "sessionid",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 255,
  },
  "query",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "hitrange",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 11 },
  "hits",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 11 },
  "dbases",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
);
__PACKAGE__->set_primary_key("queryid");

1;
