package OpenBib::Database::System::Result::UserSearchprofile;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::UserSearchprofile

=cut

__PACKAGE__->table("user_searchprofile");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0

=head2 profileid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 profilename

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_auto_increment => 1, is_nullable => 0 },
  "profileid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "profilename",
  { data_type => "text", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 userid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Userinfo>

=cut

__PACKAGE__->belongs_to(
  "userid",
  "OpenBib::Database::System::Result::Userinfo",
  { id => "userid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 profileid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Searchprofile>

=cut

__PACKAGE__->belongs_to(
  "profileid",
  "OpenBib::Database::System::Result::Searchprofile",
  { id => "profileid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-11-18 10:20:39
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:kOsTXq7tB9QFep1qLqjJVg


# You can replace this text with custom content, and it will be preserved on regeneration
1;
