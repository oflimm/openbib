package OpenBib::Schema::Catalog::Result::TitleSubject;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Catalog::Result::TitleSubject

=cut

__PACKAGE__->table("title_subject");

=head1 ACCESSORS

=head2 field

  data_type: 'smallint'
  is_nullable: 1

=head2 titleid

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 255

=head2 subjectid

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
  "titleid",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 255 },
  "subjectid",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 255 },
  "supplement",
  { data_type => "text", is_nullable => 1 },
);

=head1 RELATIONS

=head2 subjectid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Subject>

=cut

__PACKAGE__->belongs_to(
  "subjectid",
  "OpenBib::Schema::Catalog::Result::Subject",
  { id => "subjectid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 titleid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Title>

=cut

__PACKAGE__->belongs_to(
  "titleid",
  "OpenBib::Schema::Catalog::Result::Title",
  { id => "titleid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-21 12:51:30
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:raVgKH0gXKDMOlr+EdTIlw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
