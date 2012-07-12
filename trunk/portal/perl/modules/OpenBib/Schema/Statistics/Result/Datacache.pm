package OpenBib::Schema::Statistics::Result::Datacache;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Statistics::Result::Datacache

=cut

__PACKAGE__->table("datacache");

=head1 ACCESSORS

=head2 id

  data_type: 'varchar'
  is_nullable: 1
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
  { data_type => "varchar", is_nullable => 1, size => 100 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "type",
  { data_type => "integer", is_nullable => 1 },
  "subkey",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "data",
  { data_type => "text", is_nullable => 1 },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-12 11:29:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:cEFI48KEz0kZ0SuPXeJQYQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
