use utf8;
package OpenBib::Schema::System::Result::UserCollectionitem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::UserCollectionitem

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<user_collectionitem>

=cut

__PACKAGE__->table("user_collectionitem");

=head1 ACCESSORS

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 collectionitemid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'user_collectionitem_id_seq'

=cut

__PACKAGE__->add_columns(
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "collectionitemid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "user_collectionitem_id_seq",
  },
);

=head1 RELATIONS

=head2 collectionitemid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Collectionitem>

=cut

__PACKAGE__->belongs_to(
  "collectionitemid",
  "OpenBib::Schema::System::Result::Collectionitem",
  { id => "collectionitemid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

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


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2012-11-30 14:59:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:IWrnWtFTWcIwqpSSAEG1fg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
