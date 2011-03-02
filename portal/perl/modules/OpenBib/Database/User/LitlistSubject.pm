package OpenBib::Database::User::LitlistSubject;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("litlist2subject");
__PACKAGE__->add_columns(
  "litlistid",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 11 },
  "subjectid",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 11 },
);

1;
