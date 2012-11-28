use utf8;
package OpenBib::Schema::System::Result::SessionCollectionitem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::SessionCollectionitem

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<session_collectionitem>

=cut

__PACKAGE__->table("session_collectionitem");

=head1 ACCESSORS

=head2 sid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 collectionitemid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "collectionitemid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
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

=head2 sid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Sessioninfo>

=cut

__PACKAGE__->belongs_to(
  "sid",
  "OpenBib::Schema::System::Result::Sessioninfo",
  { id => "sid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2012-11-28 16:13:04
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:DOIKc6o+WolFrvqyp9pKPg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
