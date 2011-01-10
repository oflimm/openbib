package OpenBib::Database::Config::ViewDB;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("viewdbs");
__PACKAGE__->add_columns(
  "viewname",
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
    'viewinfo' => 'OpenBib::Database::Config::ViewInfo',
    { 'foreign.viewname' => 'self.viewname' }
);

__PACKAGE__->belongs_to(
    'databaseinfo' => 'OpenBib::Database::Config::DatabaseInfo',
    { 'foreign.dbname' => 'self.dbname' }
);

1;
