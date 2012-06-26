package OpenBib::Database::Catalog::Result::CorporatebodyField;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Catalog::Result::CorporatebodyField

=cut

__PACKAGE__->table("corporatebody_fields");

=head1 ACCESSORS

=head2 corporatebodyid

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
  "corporatebodyid",
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

=head2 corporatebodyid

Type: belongs_to

Related object: L<OpenBib::Database::Catalog::Result::Corporatebody>

=cut

__PACKAGE__->belongs_to(
  "corporatebodyid",
  "OpenBib::Database::Catalog::Result::Corporatebody",
  { id => "corporatebodyid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-06-26 12:52:47
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:nKgYVeft9mZmi6w0Uj9A/g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
