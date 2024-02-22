use utf8;
package OpenBib::Schema::Catalog::Result::TitlePerson;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Catalog::Result::TitlePerson

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<title_person>

=cut

__PACKAGE__->table("title_person");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'title_person_id_seq'

=head2 field

  data_type: 'smallint'
  is_nullable: 1

=head2 mult

  data_type: 'smallint'
  is_nullable: 1

=head2 titleid

  data_type: 'text'
  is_foreign_key: 1
  is_nullable: 0

=head2 personid

  data_type: 'text'
  is_foreign_key: 1
  is_nullable: 0

=head2 supplement

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "title_person_id_seq",
  },
  "field",
  { data_type => "smallint", is_nullable => 1 },
  "mult",
  { data_type => "smallint", is_nullable => 1 },
  "titleid",
  { data_type => "text", is_foreign_key => 1, is_nullable => 0 },
  "personid",
  { data_type => "text", is_foreign_key => 1, is_nullable => 0 },
  "supplement",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 personid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Person>

=cut

__PACKAGE__->belongs_to(
  "personid",
  "OpenBib::Schema::Catalog::Result::Person",
  { id => "personid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);

=head2 titleid

Type: belongs_to

Related object: L<OpenBib::Schema::Catalog::Result::Title>

=cut

__PACKAGE__->belongs_to(
  "titleid",
  "OpenBib::Schema::Catalog::Result::Title",
  { id => "titleid" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2024-02-16 11:26:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:M+5II4TQ41iDrvBxx5ID2w


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
