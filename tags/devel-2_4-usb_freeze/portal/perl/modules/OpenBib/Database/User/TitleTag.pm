package OpenBib::Database::User::TitleTag;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("tittag");
__PACKAGE__->add_columns(
  "ttid",
  {
      data_type => "INT",
      default_value => undef,
      is_nullable => 0,
      size => 11
  },
  "tagid",
  {
      data_type => "INT",
      default_value => 0,
      is_nullable => 0,
      size => 11
  },
  "titid",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 255,
  },
  "titisbn",
  {
      data_type => "VARCHAR",
      default_value => "",
      is_nullable => 0,
      size => 14
  },
  "titdb",
  {
      data_type => "VARCHAR",
      default_value => "",
      is_nullable => 0,
      size => 25
  },
  "titcache",
  {
    data_type => "BLOB",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "loginname",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "type",
  {
      data_type => "INT",
      default_value => 1,
      is_nullable => 0,
      size => 3
  },
);
__PACKAGE__->set_primary_key("ttid");

1;
