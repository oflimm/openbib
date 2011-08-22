package OpenBib::Database::Config::LibraryInfo;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("libraryinfo");
__PACKAGE__->add_columns(
  "dbname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 255,
  },
  "category",
  {
    data_type => "SMALLINT",
    default_value => undef,
    is_nullable => 0,
    size => 6,
  },
  "indicator",
  {
    data_type => "SMALLINT",
    default_value => undef,
    is_nullable => 1,
    size => 6,
  },
  "content",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 0,
    size => 65535,
  },
);

__PACKAGE__->belongs_to(
    'databaseinfo' => 'OpenBib::Database::Config::DatabaseInfo',
    { 'foreign.dbname' => 'self.dbname' }
);

1;
