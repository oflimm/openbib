package OpenBib::Database::Session::Eventlog;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("eventlog");
__PACKAGE__->add_columns(
  "sessionid",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 255,
  },
  "tstamp",
  {
    data_type => "DATETIME",
    default_value => undef,
    is_nullable => 1,
    size => 19,
  },
  "type",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 11 },
  "content",
  {
    data_type => "MEDIUMBLOB",
    default_value => undef,
    is_nullable => 1,
    size => 16777215,
  },
);

1;
