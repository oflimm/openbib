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


# Created by DBIx::Class::Schema::Loader v0.07025 @ 2012-11-28 15:24:29
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:m5B1G+6zuQPLDJbfDO8uNw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
