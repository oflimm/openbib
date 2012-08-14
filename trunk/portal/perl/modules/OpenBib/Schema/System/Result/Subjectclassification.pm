package OpenBib::Schema::System::Result::Subjectclassification;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::Subjectclassification

=cut

__PACKAGE__->table("subjectclassification");

=head1 ACCESSORS

=head2 subjectid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 classification

  data_type: 'text'
  is_nullable: 0

=head2 type

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "subjectid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "classification",
  { data_type => "text", is_nullable => 0 },
  "type",
  { data_type => "text", is_nullable => 0 },
);

=head1 RELATIONS

=head2 subjectid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Subject>

=cut

__PACKAGE__->belongs_to(
  "subjectid",
  "OpenBib::Schema::System::Result::Subject",
  { id => "subjectid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-08-14 08:42:28
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:0O2eutgnpBmBLl1J9XxaAg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
