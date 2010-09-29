package OpenBib::Database::User::ClassificationSubject;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("classification2subject");
__PACKAGE__->add_columns(
  "classification",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 0,
    size => 20,
  },
  "subjectid",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 11 },
  "type",
  { data_type => "VARCHAR", default_value => undef, is_nullable => 0, size => 5 },
);

1;
