use utf8;
package OpenBib::Schema::System::Result::LocationinfoOccupancy;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::LocationinfoOccupancy

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<locationinfo_occupancy>

=cut

__PACKAGE__->table("locationinfo_occupancy");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'locationinfo_occupancy_id_seq'

=head2 locationid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 num_entries

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 num_exits

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=head2 num_occupancy

  data_type: 'integer'
  default_value: 0
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "locationinfo_occupancy_id_seq",
  },
  "locationid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "num_entries",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "num_exits",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
  "num_occupancy",
  { data_type => "integer", default_value => 0, is_nullable => 1 },
);

=head1 RELATIONS

=head2 locationid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Locationinfo>

=cut

__PACKAGE__->belongs_to(
  "locationid",
  "OpenBib::Schema::System::Result::Locationinfo",
  { id => "locationid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-09-04 12:44:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:VwtVyOH774KXMhv0cpXlDA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
