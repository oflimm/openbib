package OpenBib::Schema::System::Result::Roleinfo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Roleinfo

=cut

__PACKAGE__->table("roleinfo");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  default_value: nextval(('public.roleinfo_id_seq'::text)::regclass)
  is_nullable: 0

=head2 rolename

  data_type: 'text'
  is_nullable: 0

=head2 description

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type     => "bigint",
    default_value => \"nextval(('public.roleinfo_id_seq'::text)::regclass)",
    is_nullable   => 0,
  },
  "rolename",
  { data_type => "text", is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 role_rights

Type: has_many

Related object: L<OpenBib::Schema::System::Result::RoleRight>

=cut

__PACKAGE__->has_many(
  "role_rights",
  "OpenBib::Schema::System::Result::RoleRight",
  { "foreign.roleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 role_views

Type: has_many

Related object: L<OpenBib::Schema::System::Result::RoleView>

=cut

__PACKAGE__->has_many(
  "role_views",
  "OpenBib::Schema::System::Result::RoleView",
  { "foreign.roleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_roles

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserRole>

=cut

__PACKAGE__->has_many(
  "user_roles",
  "OpenBib::Schema::System::Result::UserRole",
  { "foreign.roleid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2016-01-22 11:29:37
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:475brsSQ+nbpZtSmded31A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
