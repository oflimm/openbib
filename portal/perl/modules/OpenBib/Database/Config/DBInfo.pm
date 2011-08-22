package OpenBib::Database::Config::DBInfo;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("dbinfo");
__PACKAGE__->add_columns(
  "description",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "shortdesc",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "system",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "dbname",
  {
      data_type => "VARCHAR",
      default_value => "",
      is_nullable => 0,
      size => 25
  },
  "sigel",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 20,
  },
  "url",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "use_libinfo",
  {
      data_type => "TINYINT",
      default_value => undef,
      is_nullable => 1,
      size => 1
  },
  "active",
  {
      data_type => "TINYINT",
      default_value => undef,
      is_nullable => 1,
      size => 1
  },
);
__PACKAGE__->set_primary_key("dbname");

__PACKAGE__->has_one(
    'dboptions' => 'OpenBib::Database::Config::DBOptions',
    { 'foreign.dbname' => 'self.dbname' }
);


1;
