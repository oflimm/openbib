package OpenBib::Database::Config::ViewRSSFeeds;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("viewrssfeeds");
__PACKAGE__->add_columns(
  "viewname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 20,
  },
  "rssfeed",
  { data_type => "BIGINT", default_value => 0, is_nullable => 0, size => 20 },
);

1;
