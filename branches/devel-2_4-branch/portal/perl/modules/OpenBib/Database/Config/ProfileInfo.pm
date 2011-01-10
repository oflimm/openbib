package OpenBib::Database::Config::ProfileInfo;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("profileinfo");
__PACKAGE__->add_columns(
  "profilename",
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
);

__PACKAGE__->set_primary_key("profilename");

__PACKAGE__->has_many(
    'profiledbs' => 'OpenBib::Database::Config::ProfileDB',
    { 'foreign.profilename' => 'self.profilename' }
);

__PACKAGE__->has_many(
    'orgunitinfo' => 'OpenBib::Database::Config::OrgunitInfo',
    { 'foreign.profilename' => 'self.profilename' }
);

1;
