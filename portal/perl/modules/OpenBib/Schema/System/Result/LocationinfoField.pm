use utf8;
package OpenBib::Schema::System::Result::LocationinfoField;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::LocationinfoField

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<locationinfo_fields>

=cut

__PACKAGE__->table("locationinfo_fields");

=head1 ACCESSORS

=head2 locationid

  data_type: 'bigint'
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

=head2 content_norm

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "locationid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
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

=head2 locationid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Locationinfo>

=cut

__PACKAGE__->belongs_to(
  "locationid",
  "OpenBib::Schema::System::Result::Locationinfo",
  { id => "locationid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-13 08:22:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:UCuaRui7a8LWHNEOBPhlaA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
