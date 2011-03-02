package OpenBib::Database::Config::DatabaseInfo;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("databaseinfo");
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
  "host",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "protocol",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "remotepath",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "remoteuser",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "remotepassword",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "titlefile",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "personfile",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "corporatebodyfile",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "subjectfile",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "classificationfile",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "holdingsfile",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "autoconvert",
  {
      data_type => "TINYINT",
      default_value => undef,
      is_nullable => 1,
      size => 1
  },
  "circ",
  {
      data_type => "TINYINT",
      default_value => undef,
      is_nullable => 1,
      size => 1
  },
  "circurl",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "circwsurl",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "circdb",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  
);
__PACKAGE__->set_primary_key("dbname");

__PACKAGE__->has_many(
    'titcount' => 'OpenBib::Database::Config::Titcount',
    { 'foreign.dbname' => 'self.dbname' }
);

__PACKAGE__->has_many(
    'libraryinfo' => 'OpenBib::Database::Config::LibraryInfo',
    { 'foreign.dbname' => 'self.dbname' }
);

__PACKAGE__->has_many(
    'profiledbs' => 'OpenBib::Database::Config::ProfileDB',
    { 'foreign.dbname' => 'self.dbname' }
);

__PACKAGE__->has_many(
    'viewdbs' => 'OpenBib::Database::Config::ViewDB',
    { 'foreign.dbname' => 'self.dbname' }
);

__PACKAGE__->has_many(
    'rssfeeds' => 'OpenBib::Database::Config::RSSFeeds',
    { 'foreign.dbname' => 'self.dbname' }
);

__PACKAGE__->has_many(
    'rsscache' => 'OpenBib::Database::Config::RSSCache',
    { 'foreign.dbname' => 'self.dbname' }
);

1;
