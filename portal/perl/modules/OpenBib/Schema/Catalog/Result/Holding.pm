package OpenBib::Database::Catalog::Result::Holding;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';


=head1 NAME

OpenBib::Database::Catalog::Result::Holding

=cut

__PACKAGE__->table("holding");

=head1 ACCESSORS

=head2 id

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "varchar", is_nullable => 0, size => 255 },
);
__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 holding_fields

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::HoldingField>

=cut

__PACKAGE__->has_many(
  "holding_fields",
  "OpenBib::Database::Catalog::Result::HoldingField",
  { "foreign.holdingid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title_holdings

Type: has_many

Related object: L<OpenBib::Database::Catalog::Result::TitleHolding>

=cut

__PACKAGE__->has_many(
  "title_holdings",
  "OpenBib::Database::Catalog::Result::TitleHolding",
  { "foreign.holdingid" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2012-06-26 12:52:47
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:JWwl1RBiv2q2yMQ7poC2jA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
