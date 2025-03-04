use utf8;
package OpenBib::Schema::System::Result::Locationinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Locationinfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<locationinfo>

=cut

__PACKAGE__->table("locationinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'locationinfo_id_seq'

=head2 identifier

  data_type: 'text'
  is_nullable: 1

=head2 type

  data_type: 'text'
  is_nullable: 1

=head2 description

  data_type: 'text'
  is_nullable: 1

=head2 tstamp_create

  data_type: 'timestamp'
  is_nullable: 1

=head2 tstamp_update

  data_type: 'timestamp'
  is_nullable: 1

=head2 shortdesc

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "locationinfo_id_seq",
  },
  "identifier",
  { data_type => "text", is_nullable => 1 },
  "type",
  { data_type => "text", is_nullable => 1 },
  "description",
  { data_type => "text", is_nullable => 1 },
  "tstamp_create",
  { data_type => "timestamp", is_nullable => 1 },
  "tstamp_update",
  { data_type => "timestamp", is_nullable => 1 },
  "shortdesc",
  { data_type => "text", default_value => "", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<uq_locationinfo_identifier>

=over 4

=item * L</identifier>

=back

=cut

__PACKAGE__->add_unique_constraint("uq_locationinfo_identifier", ["identifier"]);

=head1 RELATIONS

=head2 databaseinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Databaseinfo>

=cut

__PACKAGE__->has_many(
  "databaseinfos",
  "OpenBib::Schema::System::Result::Databaseinfo",
  { "foreign.locationid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 locationinfo_fields

Type: has_many

Related object: L<OpenBib::Schema::System::Result::LocationinfoField>

=cut

__PACKAGE__->has_many(
  "locationinfo_fields",
  "OpenBib::Schema::System::Result::LocationinfoField",
  { "foreign.locationid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 locationinfo_occupancies

Type: has_many

Related object: L<OpenBib::Schema::System::Result::LocationinfoOccupancy>

=cut

__PACKAGE__->has_many(
  "locationinfo_occupancies",
  "OpenBib::Schema::System::Result::LocationinfoOccupancy",
  { "foreign.locationid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_searchlocations

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserSearchlocation>

=cut

__PACKAGE__->has_many(
  "user_searchlocations",
  "OpenBib::Schema::System::Result::UserSearchlocation",
  { "foreign.locationid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 userinfos

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Userinfo>

=cut

__PACKAGE__->has_many(
  "userinfos",
  "OpenBib::Schema::System::Result::Userinfo",
  { "foreign.locationid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 view_locations

Type: has_many

Related object: L<OpenBib::Schema::System::Result::ViewLocation>

=cut

__PACKAGE__->has_many(
  "view_locations",
  "OpenBib::Schema::System::Result::ViewLocation",
  { "foreign.locationid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-14 12:30:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:rgvXUGvb0s398xgQoEL0EA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
