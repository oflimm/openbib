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
  is_nullable: 0

=head2 collectionitemid

  data_type: 'bigint'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "sid",
  { data_type => "bigint", is_nullable => 0 },
  "collectionitemid",
  { data_type => "bigint", is_nullable => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2012-11-28 15:24:29
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:JwyDIGUSbJSeGnxChtmKGw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
