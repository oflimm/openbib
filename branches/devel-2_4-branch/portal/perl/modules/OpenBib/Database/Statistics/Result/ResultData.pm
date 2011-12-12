package OpenBib::Database::Statistics::Result::ResultData;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Statistics::Result::ResultData

=cut

__PACKAGE__->table("result_data");

=head1 ACCESSORS

=head2 id

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 100

=head2 tstamp

  data_type: 'timestamp'
  default_value: current_timestamp
  is_nullable: 0

=head2 type

  data_type: 'integer'
  is_nullable: 1

=head2 subkey

  data_type: 'varchar'
  is_nullable: 1
  size: 50

=head2 data

  data_type: 'mediumblob'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 100 },
  "tstamp",
  {
    data_type     => "timestamp",
    default_value => \"current_timestamp",
    is_nullable   => 0,
  },
  "type",
  { data_type => "integer", is_nullable => 1 },
  "subkey",
  { data_type => "varchar", is_nullable => 1, size => 50 },
  "data",
  { data_type => "mediumblob", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2011-12-12 14:26:38
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:E+Exu8w48FocMo/vqp39+Q


# You can replace this text with custom content, and it will be preserved on regeneration
1;
