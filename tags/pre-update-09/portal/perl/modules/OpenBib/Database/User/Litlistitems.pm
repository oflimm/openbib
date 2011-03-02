package OpenBib::Database::User::Litlistitems;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("litlistitems");
__PACKAGE__->add_columns(
  "litlistid",
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
  { data_type => "CHAR", default_value => "", is_nullable => 0, size => 14 },
  "titdb",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 25,
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
