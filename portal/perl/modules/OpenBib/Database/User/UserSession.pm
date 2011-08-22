package OpenBib::Database::User::UserSession;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("usersession");
__PACKAGE__->add_columns(
  "sessionid",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 255 },
  "userid",
  { data_type => "BIGINT", default_value => 0, is_nullable => 0, size => 20 },
  "targetid",
  { data_type => "BIGINT", default_value => undef, is_nullable => 1, size => 20 },
);

1;
