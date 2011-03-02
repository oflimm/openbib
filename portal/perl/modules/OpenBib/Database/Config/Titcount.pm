package OpenBib::Database::Config::Titcount;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("titcount");
__PACKAGE__->add_columns(
  "dbname",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "count",
  {
      data_type => "BIGINT",
      default_value => undef,
      is_nullable => 1,
      size => 20
  },
  "type",
  {
      data_type => "TINYINT",
      default_value => undef,
      is_nullable => 1,
      size => 4
  },
);

__PACKAGE__->belongs_to(
    'databaseinfo' => 'OpenBib::Database::Config::DatabaseInfo',
    { 'foreign.dbname' => 'self.dbname' }
);

1;
