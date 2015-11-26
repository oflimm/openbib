package OpenBib::Schema::System::Result::RoleView;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::RoleView

=cut

__PACKAGE__->table("role_view");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'role_view_id_seq'

=head2 roleid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 viewid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "role_view_id_seq",
  },
  "roleid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "viewid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 viewid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Viewinfo>

=cut

__PACKAGE__->belongs_to(
  "viewid",
  "OpenBib::Schema::System::Result::Viewinfo",
  { id => "viewid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 roleid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Roleinfo>

=cut

__PACKAGE__->belongs_to(
  "roleid",
  "OpenBib::Schema::System::Result::Roleinfo",
  { id => "roleid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2015-11-17 15:09:24
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Ay4F2M+Ukp0li+OothwWSg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
