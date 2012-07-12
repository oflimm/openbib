package OpenBib::Schema::System::Result::UserRole;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::UserRole

=cut

__PACKAGE__->table("user_role");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'user_role_id_seq'

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 roleid

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
    sequence          => "user_role_id_seq",
  },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "roleid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 userid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Userinfo>

=cut

__PACKAGE__->belongs_to(
  "userid",
  "OpenBib::Schema::System::Result::Userinfo",
  { id => "userid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 roleid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Role>

=cut

__PACKAGE__->belongs_to(
  "roleid",
  "OpenBib::Schema::System::Result::Role",
  { id => "roleid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-12 11:30:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ZA1s3CtXtyK6H5glLHFv9g


# You can replace this text with custom content, and it will be preserved on regeneration
1;
