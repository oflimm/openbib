package OpenBib::Database::Session::Searchresults;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("searchresults");
__PACKAGE__->add_columns(
  "sessionid",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 255,
  },
  "dbname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 255,
  },
  "offset",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 11 },
  "hitrange",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 11 },
  "searchresult",
  {
    data_type => "LONGTEXT",
    default_value => undef,
    is_nullable => 1,
    size => 4294967295,
  },
  "hits",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 11 },
  "queryid",
  { data_type => "BIGINT", default_value => undef, is_nullable => 1, size => 20 },
);

1;
