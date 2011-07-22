package OpenBib::Database::Config::OrgunitInfo;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("orgunitinfo");
__PACKAGE__->add_columns(
  "orgunitname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 20,
  },
  "profilename",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 20,
  },
  "description",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "nr",
  {
      data_type => "INT",
      default_value => undef,
      is_nullable => 1,
      size => 11
  },
);

__PACKAGE__->has_many(
    'orgunitdbs' => 'OpenBib::Database::Config::OrgunitDB',
    { 'foreign.orgunitname' => 'self.orgunitname' }
);

1;
