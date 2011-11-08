package OpenBib::Database::System::Result::Subject;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::Subject

=cut

__PACKAGE__->table("subject");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'text'
  is_nullable: 0

=head2 description

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "text", is_nullable => 0 },
  "description",
  { data_type => "text", is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 classification_subjects

Type: has_many

Related object: L<OpenBib::Database::System::Result::ClassificationSubject>

=cut

__PACKAGE__->has_many(
  "classification_subjects",
  "OpenBib::Database::System::Result::ClassificationSubject",
  { "foreign.subjectid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 litlist_subjects

Type: has_many

Related object: L<OpenBib::Database::System::Result::LitlistSubject>

=cut

__PACKAGE__->has_many(
  "litlist_subjects",
  "OpenBib::Database::System::Result::LitlistSubject",
  { "foreign.subjectid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-11-08 11:23:44
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:pgPHNfJeUlWdbVlvhEt25w


# You can replace this text with custom content, and it will be preserved on regeneration
1;
