package OpenBib::Database::Statistics::Result::Datacache;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Statistics::Result::Datacache

=cut

__PACKAGE__->table("datacache");

=head1 ACCESSORS

=head2 id

  data_type: 'varchar'
  is_nullable: 0
  size: 100

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 type

  data_type: 'integer'
  is_nullable: 1

=head2 subkey

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 data

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "varchar", is_nullable => 0, size => 100 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "type",
  { data_type => "integer", is_nullable => 1 },
  "subkey",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "data",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-06-27 14:32:47
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:dGYCtKfmjjftve9z8gLsNw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
