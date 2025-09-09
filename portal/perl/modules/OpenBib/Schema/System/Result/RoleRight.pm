use utf8;
package OpenBib::Schema::System::Result::RoleRight;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::RoleRight

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<role_right>

=cut

__PACKAGE__->table("role_right");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'role_right_id_seq'

=head2 roleid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 scope

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 1

=head2 right_create

  data_type: 'boolean'
  default_value: false
  is_nullable: 1

=head2 right_read

  data_type: 'boolean'
  default_value: false
  is_nullable: 1

=head2 right_update

  data_type: 'boolean'
  default_value: false
  is_nullable: 1

=head2 right_delete

  data_type: 'boolean'
  default_value: false
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "role_right_id_seq",
  },
  "roleid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "scope",
  { data_type => "text", default_value => "", is_nullable => 1 },
  "right_create",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "right_read",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "right_update",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
  "right_delete",
  { data_type => "boolean", default_value => \"false", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 roleid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Roleinfo>

=cut

__PACKAGE__->belongs_to(
  "roleid",
  "OpenBib::Schema::System::Result::Roleinfo",
  { id => "roleid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-09-04 12:44:52
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:gxU5k/erYPxnnye5uAjZgg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
