use utf8;
package OpenBib::Schema::Catalog::Result::ClassificationField;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Catalog::Result::ClassificationField

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<classification_fields>

=cut

__PACKAGE__->table("classification_fields");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'classification_fields_id_seq'

=head2 classificationid

  data_type: 'text'
  is_foreign_key: 1
  is_nullable: 0

=head2 field

  data_type: 'smallint'
  is_nullable: 0

=head2 mult

  data_type: 'smallint'
  is_nullable: 1

=head2 subfield

  data_type: 'varchar'
  is_nullable: 1
  size: 2

=head2 content

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "classification_fields_id_seq",
  },
  "classificationid",
  { data_type => "text", is_foreign_key => 1, is_nullable => 0 },
  "field",
  { data_type => "smallint", is_nullable => 0 },
  "mult",
  { data_type => "smallint", is_nullable => 1 },
  "subfield",
  { data_type => "varchar", is_nullable => 1, size => 2 },
  "content",
  { data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 classificationid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Classification>

=cut

__PACKAGE__->belongs_to(
  "classificationid",
  "OpenBib::Schema::Catalog::Result::Classification",
  { id => "classificationid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2024-02-16 11:26:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:KtSuEwWdyui9NsKiPy5MTQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
