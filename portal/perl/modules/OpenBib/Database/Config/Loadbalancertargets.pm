package OpenBib::Database::Config::Loadbalancertargets;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("loadbalancertargets");
__PACKAGE__->add_columns(
  "id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 11 },
  "host",
  {
    data_type => "TEXT",
    default_value => undef,
    is_nullable => 1,
    size => 65535,
  },
  "active",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 1 },
);

__PACKAGE__->set_primary_key("id");

1;
