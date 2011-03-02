package OpenBib::Database::Config::ViewInfo;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("viewinfo");
__PACKAGE__->add_columns(
  "viewname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 20,
  },
  "description",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "rssfeed",
  { data_type => "BIGINT", default_value => undef, is_nullable => 1, size => 20 },
  "start_loc",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "start_stid",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "profilename",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 20,
  },
  "active",
  { data_type => "TINYINT", default_value => undef, is_nullable => 1, size => 1 },
);

__PACKAGE__->set_primary_key("viewname");

__PACKAGE__->belongs_to(
    'profileinfo' => 'OpenBib::Database::Config::ProfileInfo',
    { 'foreign.profilename' => 'self.profilename' }
);

__PACKAGE__->has_many(
    'profiledbs' => 'OpenBib::Database::Config::ProfileDB',
    { 'foreign.profilename' => 'self.profilename' }
);

__PACKAGE__->has_many(
    'viewdbs' => 'OpenBib::Database::Config::ViewDB',
    { 'foreign.viewname' => 'self.viewname' }
);

__PACKAGE__->has_many(
    'viewrssfeeds' => 'OpenBib::Database::Config::ViewRSSFeeds',
    { 'foreign.viewname' => 'self.viewname' }
);

1;
