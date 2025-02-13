use utf8;
package OpenBib::Schema::System::Result::Tag;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Tag

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<tag>

=cut

__PACKAGE__->table("tag");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'tag_id_seq'

=head2 name

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "tag_id_seq",
  },
  "name",
  { data_type => "text", default_value => "", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 tit_tags

Type: has_many

Related object: L<OpenBib::Schema::System::Result::TitTag>

=cut

__PACKAGE__->has_many(
  "tit_tags",
  "OpenBib::Schema::System::Result::TitTag",
  { "foreign.tagid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 08:22:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ujRlYDdFcNX/ua/XBpYqrA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
