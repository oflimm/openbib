use utf8;
package OpenBib::Schema::System::Result::Classificationshierarchy;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::System::Result::Classificationshierarchy

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<classificationshierarchy>

=cut

__PACKAGE__->table("classificationshierarchy");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'classificationshierarchy_id_seq'

=head2 tstamp

  data_type: 'timestamp'
  is_nullable: 1

=head2 type

  data_type: 'text'
  is_nullable: 1

=head2 name

  data_type: 'text'
  is_nullable: 1

=head2 number

  data_type: 'integer'
  is_nullable: 1

=head2 subname

  data_type: 'text'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "classificationshierarchy_id_seq",
  },
  "tstamp",
  { data_type => "timestamp", is_nullable => 1 },
  "type",
  { data_type => "text", is_nullable => 1 },
  "name",
  { data_type => "text", is_nullable => 1 },
  "number",
  { data_type => "integer", is_nullable => 1 },
  "subname",
  { data_type => "text", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07051 @ 2025-02-14 12:30:55
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:G1pdlBDIRZ+Zlph7L308iA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
