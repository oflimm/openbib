package OpenBib::Database::Catalog::Result::Subject;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Catalog::Result::Subject

=cut

__PACKAGE__->table("subject");

=head1 ACCESSORS

=head2 id

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 tstamp_create

  data_type: 'bigint'
  is_nullable: 1

=head2 tstamp_update

  data_type: 'bigint'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "tstamp_create",
  { data_type => "bigint", is_nullable => 1 },
  "tstamp_update",
  { data_type => "bigint", is_nullable => 1 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 subject_fields

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::SubjectField>

=cut

__PACKAGE__->has_many(
  "subject_fields",
  "OpenBib::Database::Catalog::Result::SubjectField",
  { "foreign.subjectid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_subjects

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitleSubject>

=cut

__PACKAGE__->has_many(
  "title_subjects",
  "OpenBib::Database::Catalog::Result::TitleSubject",
  { "foreign.subjectid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-06-26 12:52:47
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:k0F0FBzDooey72UnYfF1rw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
