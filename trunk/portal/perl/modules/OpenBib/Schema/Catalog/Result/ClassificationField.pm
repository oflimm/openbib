package OpenBib::Schema::Catalog::Result::ClassificationField;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Catalog::Result::ClassificationField

=cut

__PACKAGE__->table("classification_fields");

=head1 ACCESSORS

=head2 classificationid

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 255

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

=head2 content_norm

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "classificationid",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 255 },
  "field",
  { data_type => "smallint", is_nullable => 0 },
  "mult",
  { data_type => "smallint", is_nullable => 1 },
  "subfield",
  { data_type => "varchar", is_nullable => 1, size => 2 },
  "content",
  { data_type => "text", is_nullable => 0 },
  "content_norm",
  { data_type => "text", is_nullable => 1 },
);

=head1 RELATIONS

=head2 classificationid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Classification>

=cut

__PACKAGE__->belongs_to(
  "classificationid",
  "OpenBib::Schema::Catalog::Result::Classification",
  { id => "classificationid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-07-12 11:41:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:NwJELxX7rbx96bi8ZrHlCg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
