use utf8;
package OpenBib::Schema::System::Result::Collectionitem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Collectionitem

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<collectionitem>

=cut

__PACKAGE__->table("collectionitem");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'collectionitem_id_seq'

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 dbname

  data_type: 'text'
  is_nullable: 1

=head2 titleid

  data_type: 'text'
  is_nullable: 1

=head2 titlecache

  data_type: 'text'
  is_nullable: 1

=head2 comment

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "collectionitem_id_seq",
  },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "dbname",
  { data_type => "text", is_nullable => 1 },
  "titleid",
  { data_type => "text", is_nullable => 1 },
  "titlecache",
  { data_type => "text", is_nullable => 1 },
  "comment",
  { data_type => "text", default_value => "", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 session_collectionitems

Type: has_many

Related object: L<OpenBib::Schema::System::Result::SessionCollectionitem>

=cut

__PACKAGE__->has_many(
  "session_collectionitems",
  "OpenBib::Schema::System::Result::SessionCollectionitem",
  { "foreign.collectionitemid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_collectionitems

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserCollectionitem>

=cut

__PACKAGE__->has_many(
  "user_collectionitems",
  "OpenBib::Schema::System::Result::UserCollectionitem",
  { "foreign.collectionitemid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2012-11-30 14:59:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:z2XdPmYuUOQi2RpO9nMC7Q


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
