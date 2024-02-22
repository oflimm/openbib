use utf8;
package OpenBib::Schema::Catalog::Result::Person;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Catalog::Result::Person

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<person>

=cut

__PACKAGE__->table("person");

=head1 ACCESSORS

=head2 id

  data_type: 'text'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'person_id_seq'

=head2 tstamp_create

  data_type: 'timestamp'
  is_nullable: 1

=head2 tstamp_update

  data_type: 'timestamp'
  is_nullable: 1

=head2 import_hash

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "text",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "person_id_seq",
  },
  "tstamp_create",
  { data_type => "timestamp", is_nullable => 1 },
  "tstamp_update",
  { data_type => "timestamp", is_nullable => 1 },
  "import_hash",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 person_fields

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::PersonField>

=cut

__PACKAGE__->has_many(
  "person_fields",
  "OpenBib::Schema::Catalog::Result::PersonField",
  { "foreign.personid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_people

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitlePerson>

=cut

__PACKAGE__->has_many(
  "title_people",
  "OpenBib::Schema::Catalog::Result::TitlePerson",
  { "foreign.personid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2024-02-16 11:26:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ifajKw9Bb6E1rRWaM2xYNA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
