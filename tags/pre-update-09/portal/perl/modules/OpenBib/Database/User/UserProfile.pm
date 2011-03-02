package OpenBib::Database::User::UserProfile;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("userdbprofile");
__PACKAGE__->add_columns(
  "profilid",
  { data_type => "BIGINT", default_value => undef, is_nullable => 0, size => 20 },
  "profilename",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "userid",
  { data_type => "BIGINT", default_value => 0, is_nullable => 0, size => 20 },
);
__PACKAGE__->set_primary_key("profilid");

1;
