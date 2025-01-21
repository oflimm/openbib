use utf8;
package OpenBib::Schema::System::Result::TitTag;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::TitTag

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<tit_tag>

=cut

__PACKAGE__->table("tit_tag");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'tit_tag_id_seq'

=head2 tagid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 userid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 dbname

  data_type: 'text'
  is_nullable: 0

=head2 titleid

  data_type: 'text'
  is_nullable: 0

=head2 titleisbn

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 titlecache

  data_type: 'text'
  is_nullable: 1

=head2 type

  data_type: 'smallint'
  default_value: 1
  is_nullable: 0

=head2 srt_title

  data_type: 'text'
  is_nullable: 1

=head2 srt_year

  data_type: 'text'
  is_nullable: 1

=head2 srt_person

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "tit_tag_id_seq",
  },
  "tagid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "userid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "dbname",
  { data_type => "text", is_nullable => 0 },
  "titleid",
  { data_type => "text", is_nullable => 0 },
  "titleisbn",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "titlecache",
  { data_type => "text", is_nullable => 1 },
  "type",
  { data_type => "smallint", default_value => 1, is_nullable => 0 },
  "srt_title",
  { data_type => "text", is_nullable => 1 },
  "srt_year",
  { data_type => "text", is_nullable => 1 },
  "srt_person",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 tagid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Tag>

=cut

__PACKAGE__->belongs_to(
  "tagid",
  "OpenBib::Schema::System::Result::Tag",
  { id => "tagid" },
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


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-01-20 13:11:41
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:VKtkv75Mz2ScuGp/nAfFcg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
