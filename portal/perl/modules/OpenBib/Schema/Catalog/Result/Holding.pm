use utf8;
package OpenBib::Schema::Catalog::Result::Holding;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

OpenBib::Schema::Catalog::Result::Holding

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<holding>

=cut

__PACKAGE__->table("holding");

=head1 ACCESSORS

=head2 id

  data_type: 'text'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'holding_id_seq'

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
    sequence          => "holding_id_seq",
  },
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

=head2 holding_fields

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::HoldingField>

=cut

__PACKAGE__->has_many(
  "holding_fields",
  "OpenBib::Schema::Catalog::Result::HoldingField",
  { "foreign.holdingid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_holdings

Type: has_many

Related object: L<OpenBib::Schema::Catalog::Result::TitleHolding>

=cut

__PACKAGE__->has_many(
  "title_holdings",
  "OpenBib::Schema::Catalog::Result::TitleHolding",
  { "foreign.holdingid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2024-02-16 11:26:22
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:qketnzRL037zY/9RoJHrxA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
