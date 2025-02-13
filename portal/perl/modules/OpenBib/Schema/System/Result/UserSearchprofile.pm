use utf8;
package OpenBib::Schema::System::Result::UserSearchprofile;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::UserSearchprofile

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<user_searchprofile>

=cut

__PACKAGE__->table("user_searchprofile");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'user_searchprofile_id_seq'

=head2 searchprofileid

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
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "user_searchprofile_id_seq",
  },
  "searchprofileid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "profilename",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 searchprofileid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Searchprofile>

=cut

__PACKAGE__->belongs_to(
  "searchprofileid",
  "OpenBib::Schema::System::Result::Searchprofile",
  { id => "searchprofileid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 userid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Userinfo>

=cut

__PACKAGE__->belongs_to(
  "userid",
  "OpenBib::Schema::System::Result::Userinfo",
  { id => "userid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 08:22:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:TeC9pelTShoRXI7rYxQ36Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
