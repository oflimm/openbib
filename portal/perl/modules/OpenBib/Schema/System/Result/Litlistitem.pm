use utf8;
package OpenBib::Schema::System::Result::Litlistitem;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Litlistitem

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<litlistitem>

=cut

__PACKAGE__->table("litlistitem");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'litlistitem_id_seq'

=head2 litlistid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 dbname

  data_type: 'text'
  is_nullable: 1

=head2 titleid

  data_type: 'text'
  is_nullable: 1

=head2 titleisbn

  data_type: 'text'
  is_nullable: 1

=head2 comment

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 1

=head2 titlecache

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "litlistitem_id_seq",
  },
  "litlistid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "dbname",
  { data_type => "text", is_nullable => 1 },
  "titleid",
  { data_type => "text", is_nullable => 1 },
  "titleisbn",
  { data_type => "text", is_nullable => 1 },
  "comment",
  { data_type => "text", default_value => "", is_nullable => 1 },
  "titlecache",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 litlistid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Litlist>

=cut

__PACKAGE__->belongs_to(
  "litlistid",
  "OpenBib::Schema::System::Result::Litlist",
  { id => "litlistid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 08:22:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Uuap1p9veJq6NR5sDKP8sg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
