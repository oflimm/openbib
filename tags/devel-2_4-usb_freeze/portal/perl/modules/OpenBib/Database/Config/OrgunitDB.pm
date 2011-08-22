package OpenBib::Database::Config::OrgunitDB;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("orgunitdbs");
__PACKAGE__->add_columns(
  "profilename",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 20,
  },
  "orgunitname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 20,
  },
  "dbname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
);

__PACKAGE__->belongs_to(
    'orgunitinfo' => 'OpenBib::Database::Config::OrgunitInfo',
    { 'foreign.orgunitname' => 'self.orgunitname' }
);

__PACKAGE__->belongs_to(
    'profileinfo' => 'OpenBib::Database::Config::ProfileInfo',
    { 'foreign.profilename' => 'self.profilename' }
);

__PACKAGE__->belongs_to(
    'databaseinfo' => 'OpenBib::Database::Config::DatabaseInfo',
    { 'foreign.dbname' => 'self.dbname' }
);

1;
