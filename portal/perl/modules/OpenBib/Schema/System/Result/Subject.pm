package OpenBib::Schema::System::Result::Subject;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Subject

=cut

__PACKAGE__->table("subject");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'subject_id_seq'

=head2 name

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=head2 description

  data_type: 'text'
  default_value: (empty string)
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "subject_id_seq",
  },
  "name",
  { data_type => "text", default_value => "", is_nullable => 0 },
  "description",
  { data_type => "text", default_value => "", is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 litlist_subjects

Type: has_many

Related object: L<OpenBib::Schema::System::Result::LitlistSubject>

=cut

__PACKAGE__->has_many(
  "litlist_subjects",
  "OpenBib::Schema::System::Result::LitlistSubject",
  { "foreign.subjectid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 subjectclassifications

Type: has_many

Related object: L<OpenBib::Schema::System::Result::Subjectclassification>

=cut

__PACKAGE__->has_many(
  "subjectclassifications",
  "OpenBib::Schema::System::Result::Subjectclassification",
  { "foreign.subjectid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-08-09 15:06:23
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:RuRrH+bxRWX4yDQl1MCKww


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
