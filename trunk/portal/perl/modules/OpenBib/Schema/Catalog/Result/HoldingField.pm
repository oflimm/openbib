package OpenBib::Schema::Catalog::Result::HoldingField;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Catalog::Result::HoldingField

=cut

__PACKAGE__->table("holding_fields");

=head1 ACCESSORS

=head2 holdingid

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

=cut

__PACKAGE__->add_columns(
  "holdingid",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 255 },
  "field",
  { data_type => "smallint", is_nullable => 0 },
  "mult",
  { data_type => "smallint", is_nullable => 1 },
  "subfield",
  { data_type => "varchar", is_nullable => 1, size => 2 },
  "content",
  { data_type => "text", is_nullable => 0 },
);

=head1 RELATIONS

=head2 holdingid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Holding>

=cut

__PACKAGE__->belongs_to(
  "holdingid",
  "OpenBib::Schema::Catalog::Result::Holding",
  { id => "holdingid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-21 12:51:30
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Xt2BeObbdOENoSjMjyLDfQ


# You can replace this text with custom content, and it will be preserved on regeneration
1;
