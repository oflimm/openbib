package OpenBib::Schema::Catalog::Result::TitlePerson;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::Catalog::Result::TitlePerson

=cut

__PACKAGE__->table("title_person");

=head1 ACCESSORS

=head2 field

  data_type: 'smallint'
  is_nullable: 1

=head2 titleid

  data_type: 'varchar'
  is_foreign_key: 1
  is_nullable: 0
  size: 255

=head2 personid

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
  "personid",
  { data_type => "varchar", is_foreign_key => 1, is_nullable => 0, size => 255 },
  "supplement",
  { data_type => "text", is_nullable => 1 },
);

=head1 RELATIONS

=head2 titleid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Title>

=cut

__PACKAGE__->belongs_to(
  "titleid",
  "OpenBib::Schema::Catalog::Result::Title",
  { id => "titleid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 personid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Person>

=cut

__PACKAGE__->belongs_to(
  "personid",
  "OpenBib::Schema::Catalog::Result::Person",
  { id => "personid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-07-12 11:41:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:YX7G7wpVtkWchmxF9mUkXw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
