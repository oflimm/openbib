package OpenBib::Database::Catalog::Result::TitleTitle;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Catalog::Result::TitleTitle

=cut

__PACKAGE__->table("title_title");

=head1 ACCESSORS

=head2 field

  data_type: 'smallint'
  is_nullable: 1

=head2 source_titleid

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 255

=head2 target_titleid

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 255

=head2 supplement

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "field",
  { data_type => "smallint", is_nullable => 1 },
  "source_titleid",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 255 },
  "target_titleid",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 255 },
  "supplement",
  { data_type => "text", is_nullable => 1 },
);

=head1 RELATIONS

=head2 source_titleid

Type: belongs_to

Related object: L<OpenBib::Database::Catalog::Result::Title>

=cut

__PACKAGE__->belongs_to(
  "source_titleid",
  "OpenBib::Database::Catalog::Result::Title",
  { id => "source_titleid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 target_titleid

Type: belongs_to

Related object: L<OpenBib::Database::Catalog::Result::Title>

=cut

__PACKAGE__->belongs_to(
  "target_titleid",
  "OpenBib::Database::Catalog::Result::Title",
  { id => "target_titleid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2012-05-28 20:52:49
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:TbEo5+0iqr++u5oTEIb1zg


# You can replace this text with custom content, and it will be preserved on regeneration
1;
