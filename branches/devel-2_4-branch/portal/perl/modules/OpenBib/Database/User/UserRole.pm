package OpenBib::Database::User::UserRole;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("userrole");
__PACKAGE__->add_columns(
  "userid",
  { data_type => "BIGINT", default_value => undef, is_nullable => 0, size => 20 },
  "roleid",
  { data_type => "BIGINT", default_value => undef, is_nullable => 0, size => 20 },
);

1;
