package OpenBib::Database::System::Result::LitlistSubject;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::System::Result::LitlistSubject

=cut

__PACKAGE__->table("litlist_subject");

=head1 ACCESSORS

=head2 litlistid

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 subjectid

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "litlistid",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "subjectid",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 RELATIONS

=head2 litlistid

Type: belongs_to

Related object: L<OpenBib::Database::System::Result::Litlist>

=cut

__PACKAGE__->belongs_to(
  "litlistid",
  "OpenBib::Database::System::Result::Litlist",
  { id => "litlistid" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

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


# Created by DBIx::Class::Schema::Loader v0.07002 @ 2011-11-08 10:59:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:DmtpA0L0Hx7Dlmin6wcyyg


# You can replace this text with custom content, and it will be preserved on regeneration
1;
