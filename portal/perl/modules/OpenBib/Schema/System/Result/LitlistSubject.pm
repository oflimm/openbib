package OpenBib::Schema::System::Result::LitlistSubject;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Schema::System::Result::LitlistSubject

=cut

__PACKAGE__->table("litlist_subject");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'litlist_subject_id_seq'

=head2 litlistid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=head2 subjectid

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "litlist_subject_id_seq",
  },
  "litlistid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "subjectid",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 subjectid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Subject>

=cut

__PACKAGE__->belongs_to(
  "subjectid",
  "OpenBib::Schema::System::Result::Subject",
  { id => "subjectid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);

=head2 litlistid

Type: belongs_to

Related object: L<OpenBib::Schema::System::Result::Litlist>

=cut

__PACKAGE__->belongs_to(
  "litlistid",
  "OpenBib::Schema::System::Result::Litlist",
  { id => "litlistid" },
  { on_delete => "CASCADE", on_update => "CASCADE" },
);


# Created by DBIx::Class::Schema::Loader v0.07000 @ 2012-07-12 11:30:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:e5PMO9oQmBIIVdffF9S+DA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
