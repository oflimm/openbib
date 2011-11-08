package OpenBib::Database::System::Result::ClassificationSubject;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::ClassificationSubject

=cut

__PACKAGE__->table("classification_subject");

=head1 ACCESSORS

=head2 classification

  data_type: 'varchar'
  is_nullable: 0
  size: 20

=head2 subjectid

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 type

  data_type: 'varchar'
  is_nullable: 0
  size: 5

=cut

__PACKAGE__->add_columns(
  "classification",
  { data_type => "varchar", is_nullable => 0, size => 20 },
  "subjectid",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "type",
  { data_type => "varchar", is_nullable => 0, size => 5 },
);

=head1 RELATIONS

=head2 subjectid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Subject>

=cut

__PACKAGE__->belongs_to(
  "subjectid",
  "OpenBib::Database::System::Result::Subject",
  { id => "subjectid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-11-08 11:23:44
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:akZYNp75+HAK6+wC4R44lA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
