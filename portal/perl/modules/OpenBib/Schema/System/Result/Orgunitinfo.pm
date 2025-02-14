use utf8;
package OpenBib::Schema::System::Result::Orgunitinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Orgunitinfo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<orgunitinfo>

=cut

__PACKAGE__->table("orgunitinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'orgunitinfo_id_seq'

=head2 profileid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 orgunitname

  data_type: 'text'
  is_nullable: 0

=head2 description

  data_type: 'text'
  is_nullable: 1

=head2 nr

  data_type: 'integer'
  is_nullable: 1

=head2 own_index

  data_type: 'boolean'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "orgunitinfo_id_seq",
  },
  "profileid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "orgunitname",
  { data_type => "text", is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 1 },
  "nr",
  { data_type => "integer", is_nullable => 1 },
  "own_index",
  { data_type => "boolean", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 orgunit_dbs

Type: has_many

Related object: L<OpenBib::Schema::System::Result::OrgunitDb>

=cut

__PACKAGE__->has_many(
  "orgunit_dbs",
  "OpenBib::Schema::System::Result::OrgunitDb",
  { "foreign.orgunitid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 profileid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Profileinfo>

=cut

__PACKAGE__->belongs_to(
  "profileid",
  "OpenBib::Schema::System::Result::Profileinfo",
  { id => "profileid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-14 12:30:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/7a7XX/rGwEKaykLY4JPDg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
