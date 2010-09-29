package OpenBib::Database::Config::RSSFeeds;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("rssfeeds");
__PACKAGE__->add_columns(
  "id",
  { data_type => "BIGINT", default_value => undef, is_nullable => 0, size => 20 },
  "dbname",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 255 },
  "type",
  {
    data_type => "SMALLINT",
    default_value => undef,
    is_nullable => 1,
    size => 6,
  },
  "subtype",
  {
    data_type => "SMALLINT",
    default_value => undef,
    is_nullable => 1,
    size => 6,
  },
  "subtypedesc",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "active",
  { data_type => "TINYINT", default_value => undef, is_nullable => 1, size => 4 },
);
__PACKAGE__->set_primary_key("id");


1;
