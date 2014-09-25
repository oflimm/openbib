use utf8;
package OpenBib::Schema::System::Result::UserView;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::UserView

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<user_view>

=cut

__PACKAGE__->table("user_view");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'user_view_id_seq'

=head2 userid

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
    sequence          => "user_view_id_seq",
  },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "viewid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

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
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

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


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2014-09-25 11:06:58
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:7/BsSriDusx39WSCmU7nhQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
