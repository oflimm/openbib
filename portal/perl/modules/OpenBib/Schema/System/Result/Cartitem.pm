use utf8;
package OpenBib::Schema::System::Result::Cartitem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Cartitem

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<cartitem>

=cut

__PACKAGE__->table("cartitem");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'cartitem_id_seq'

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
    sequence          => "cartitem_id_seq",
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

=head2 session_cartitems

Type: has_many

Related object: L<OpenBib::Schema::System::Result::SessionCartitem>

=cut

__PACKAGE__->has_many(
  "session_cartitems",
  "OpenBib::Schema::System::Result::SessionCartitem",
  { "foreign.cartitemid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_cartitems

Type: has_many

Related object: L<OpenBib::Schema::System::Result::UserCartitem>

=cut

__PACKAGE__->has_many(
  "user_cartitems",
  "OpenBib::Schema::System::Result::UserCartitem",
  { "foreign.cartitemid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-14 12:30:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:l4hyW4md3zRJUFddHrtbnw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
